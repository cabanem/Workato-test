#!/usr/bin/env ruby
# frozen_string_literal: true
#
# connector_analyzer.rb
#
# A zero-dependency Ruby tool that:
# 1) Parses a Workato-style Ruby connector (hash DSL),
# 2) Maps each component dependency (actions ⇄ methods ⇄ object definitions ⇄ pick lists),
# 3) Emits:
#    (a) an Intermediate Representation (IR) as JSON,
#    (b) a call graph (edge list + per-action call paths),
# 4) Surfaces design issues (undefined calls, unused methods, direct HTTP calls, template mismatches, etc).
#
# Usage:
#   ruby connector_analyzer.rb path/to/connector.rb [-o out_dir]
#
# Outputs (default out_dir: ./out):
#   out/ir.json
#   out/call_graph.json
#   out/issues.json
#
# Notes:
# - This analyzer is static (no execution).
# - Handles strings and comments; ignores braces inside them.
# - Fallbacks are in place for odd formatting.
#
require 'json'
require 'optparse'
require 'fileutils'
require 'set'

# -------------------------------
# Preprocessing 
# -------------------------------
module Preprocess
  module_function

  # Strip single-line (# ...) comments outside strings, preserving length
  def strip_line_comments_preserve_length(src)
    out = src.dup
    i = 0
    n = src.length
    in_s = false
    in_d = false
    escaped = false
    while i < n
      ch = src[i]
      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        case ch
        when "'"
          in_s = true
          i += 1
          next
        when '"'
          in_d = true
          i += 1
          next
        when '#'
          # Replace to end of line (exclusive)
          j = i
          j += 1 while j < n && src[j] != "\n"
          (i...j).each { |k| out[k] = ' ' }
          i = j
          next
        else
          i += 1
        end
      end
    end
    out
  end

  # Strip block comments (=begin ... =end) preserving length
  def strip_block_comments_preserve_length(src)
    out = src.dup
    # Only matches when =begin / =end start at line-begin (ignoring spaces)
    loop do
      m = out.match(/^[ \t]*=begin.*?\n.*?^[ \t]*=end[ \t]*\n?/m)
      break unless m
      (m.begin(0)...m.end(0)).each { |k| out[k] = ' ' }
    end
    out
  end

  def sanitize(src)
    s = strip_line_comments_preserve_length(src)
    strip_block_comments_preserve_length(s)
  end
end

# -------------------------------
# Small utilities
# -------------------------------
class StringScannerLite
  attr_reader :s, :i, :n
  def initialize(s); @s = s; @i = 0; @n = s.length; end
  def peek; @i < @n ? @s[@i] : nil; end
  def next; c = peek; @i += 1; c; end
  def pos; @i; end
  def eos?; @i >= @n; end
  def skip_ws
    @i += 1 while @i < @n && @s[@i] =~ /\s/
  end
  def scan_regex!(rx)
    m = rx.match(@s, @i)
    return nil unless m && m.begin(0) == @i
    @i = m.end(0)
    m
  end
  def index_of(substr, start=@i)
    @s.index(substr, start)
  end
end

module Balance
  module_function

  # Parse balanced {...} starting at idx pointing at '{'
  def extract_curly_block(src, start_idx)
    raise "Expected '{' at #{start_idx}" unless src[start_idx] == '{'
    i = start_idx
    depth = 0
    in_s = false
    in_d = false
    escaped = false
    while i < src.length
      ch = src[i]

      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        case ch
        when "'"
          in_s = true
        when '"'
          in_d = true
        when '{'
          depth += 1
        when '}'
          depth -= 1
          if depth == 0
            return src[start_idx..i]
          end
        end
      end

      i += 1
    end
    raise "Unbalanced '{' starting at #{start_idx}"
  end

  # Parse balanced [...] starting at '['
  def extract_square_block(src, start_idx)
    raise "Expected '[' at #{start_idx}" unless src[start_idx] == '['
    i = start_idx
    depth = 0
    in_s = false
    in_d = false
    escaped = false
    while i < src.length
      ch = src[i]
      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        case ch
        when "'"
          in_s = true
        when '"'
          in_d = true
        when '['
          depth += 1
        when ']'
          depth -= 1
          if depth == 0
            return src[start_idx..i]
          end
        end
      end
      i += 1
    end
    raise "Unbalanced '[' starting at #{start_idx}"
  end

  # Parse 'lambda { ... }' OR 'lambda do ... end'
  def extract_lambda_block(src, start_idx)
    unless src[start_idx, 6] == 'lambda'
      raise "Expected 'lambda' at #{start_idx}"
    end
    i = start_idx + 6
    while i < src.length && src[i] =~ /\s/
      i += 1
    end
    if src[i, 2] == 'do'
      return extract_do_end(src, start_idx)
    elsif src[i] == '{'
      block = extract_curly_block(src, i)
      return src[start_idx...(i)] + block
    else
      j = i
      j += 1 while j < src.length && src[j] != ',' && src[j] != "\n"
      return src[start_idx...j]
    end
  end

  def extract_do_end(src, start_idx)
    i = start_idx
    in_s = false
    in_d = false
    escaped = false
    depth = 0
    while i < src.length
      ch = src[i]
      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        if ch == "'"
          in_s = true
          i += 1
          next
        elsif ch == '"'
          in_d = true
          i += 1
          next
        end
        if src[i..] =~ /\Ado\b/
          depth += 1
          i += 2
          next
        elsif src[i..] =~ /\Aend\b/
          depth -= 1
          i += 3
          if depth <= 0
            return src[start_idx...i]
          end
          next
        else
          i += 1
        end
      end
    end
    raise "Unbalanced lambda do..end starting at #{start_idx}"
  end
end

# -------------------------------
# Section extractors
# -------------------------------
module Extractor
  module_function

  # Find a top-level section key like "actions:" and extract the following {...} block as string
  def extract_top_hash_section(src, key)
    # Primary strategy: scan with depth tracking (comments already stripped).
    idx = 0
    in_s = false
    in_d = false
    escaped = false
    depth = 0
    while idx < src.length
      ch = src[idx]
      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        idx += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        idx += 1
        next
      else
        case ch
        when "'"
          in_s = true
        when '"'
          in_d = true
        when '{'
          depth += 1
        when '}'
          depth -= 1 if depth > 0
        else
          # no-op
        end

        if depth == 1
          if src[idx..] =~ /\A#{Regexp.escape(key)}\s*:\s*\{/
            m = Regexp.last_match
            start_brace = idx + m[0].rindex('{')
            begin
              return Balance.extract_curly_block(src, start_brace)
            rescue => _
              # Fallback: naive match from first '{' after key, independent of depth location
              if (m2 = src.match(/#{Regexp.escape(key)}\s*:\s*\{/, idx))
                start2 = m2.end(0) - 1
                return Balance.extract_curly_block(src, start2)
              else
                raise
              end
            end
          end
        end
        idx += 1
      end
    end

    # Final fallback: naive search anywhere
    if (m3 = src.match(/#{Regexp.escape(key)}\s*:\s*\{/))
      start3 = m3.end(0) - 1
      return Balance.extract_curly_block(src, start3)
    end
    nil
  end

  # From a { ... } block string, extract pairs of "name: { ... }"
  def extract_named_curly_pairs(block_str)
    inner = block_str.strip
    inner = inner[1..-2] if inner.start_with?('{') && inner.end_with?('}')
    pairs = {}
    i = 0
    in_s = false
    in_d = false
    escaped = false
    while i < inner.length
      ch = inner[i]
      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        if ch == "'"; in_s = true; i += 1; next; end
        if ch == '"'; in_d = true; i += 1; next; end

        if inner[i..] =~ /\A([a-zA-Z_]\w*)\s*:\s*\{/
          m = Regexp.last_match
          name = m[1]
          start_brace = i + m[0].rindex('{')
          block = Balance.extract_curly_block(inner, start_brace)
          pairs[name] = block
          i = start_brace + block.length
          i += 1 while i < inner.length && inner[i] =~ /[\s,]/
          next
        end
        i += 1
      end
    end
    pairs
  end

  # From a { ... } block string, extract pairs of "name: lambda { ... }" or "name: lambda do ... end"
  def extract_named_lambda_pairs(block_str)
    inner = block_str.strip
    inner = inner[1..-2] if inner.start_with?('{') && inner.end_with?('}')
    pairs = {}
    i = 0
    in_s = false
    in_d = false
    escaped = false
    while i < inner.length
      ch = inner[i]
      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        if ch == "'"; in_s = true; i += 1; next; end
        if ch == '"'; in_d = true; i += 1; next; end

        if inner[i..] =~ /\A([a-zA-Z_]\w*[!?]?)\s*:\s*lambda\b/
          m = Regexp.last_match
          name = m[1]
          lambda_start = i + m[0].index('lambda')
          block = Balance.extract_lambda_block(inner, lambda_start)
          pairs[name] = block
          i = lambda_start + block.length
          i += 1 while i < inner.length && inner[i] =~ /[\s,]/
          next
        end
        i += 1
      end
    end
    pairs
  end

  # Extract lambdas inside an action block by their keys
  def extract_action_parts(action_block)
    parts = {}
    %w[input_fields execute output_fields sample_output help description subtitle title].each do |k|
      if action_block =~ /#{k}\s*:\s*lambda\b/
        start = Regexp.last_match.begin(0)
        lambda_pos = action_block.index('lambda', start)
        lb = Balance.extract_lambda_block(action_block, lambda_pos)
        parts[k] = lb
      end
    end
    parts['picklists'] = action_block.scan(/pick_list:\s*:(\w+)/).flatten.uniq
    parts
  end
end

# -------------------------------
# Semantics extractors
# -------------------------------
module Semantics
  module_function

  def find_calls(body)
    body.to_s.scan(/call\(\s*['"]([^'"]+)['"]/).flatten.uniq
  end

  def find_direct_http(body)
    hits = []
    body.to_s.scan(/\b(post|get|put|delete)\s*\(/i) do |m|
      hits << m[0].downcase
    end
    hits.uniq
  end

  def find_object_def_refs(body)
    refs = body.to_s.scan(/object_definitions\[['"]([^'"]+)['"]\]/).flatten
    refs += body.to_s.scan(/object_definitions\[['"]([^'"]+)['"]\]\.only\(/).flatten
    refs.uniq
  end

  def find_picklists(body)
    body.to_s.scan(/pick_list:\s*:(\w+)/).flatten.uniq
  end

  def run_vertex_template_symbol(body)
    m = body.to_s.match(/call\(\s*['"]run_vertex['"][^)]*?,\s*:[\s]*([a-zA-Z_]\w*)/)
    m && m[1]
  end

  def lambda_params(body)
    if body =~ /lambda\s*(do|\{)\s*\|([^|]*)\|/
      Regexp.last_match(2).split(',').map(&:strip)
    else
      []
    end
  end
end

# -------------------------------
# Analyzer
# -------------------------------
class ConnectorAnalyzer
  attr_reader :src, :ir, :graph, :issues

  def initialize(src)
    @src_raw = src
    @src = Preprocess.sanitize(src) # <<< IMPORTANT: sanitize comments
    @ir = {
      'connector' => {},
      'actions' => [],
      'methods' => [],
      'object_definitions' => [],
      'pick_lists' => []
    }
    @graph = {
      'nodes' => [],
      'edges' => [],
      'paths' => {}
    }
    @issues = []
  end

  def analyze!
    parse_topmeta
    parse_sections
    post_process
    self
  end

  def parse_topmeta
    if (m = @src.match(/title\s*:\s*['"]([^'"]+)['"]/))
      @ir['connector']['title'] = m[1]
    end
    auth_modes = []
    auth_modes << 'oauth2' if @src.include?('authorization:') && @src.include?('oauth2:')
    auth_modes << 'custom' if @src.include?('custom_auth')
    @ir['connector']['auth_modes'] = auth_modes.uniq
  end

  def parse_sections
    actions_block = Extractor.extract_top_hash_section(@src, 'actions')
    methods_block = Extractor.extract_top_hash_section(@src, 'methods')
    objdefs_block = Extractor.extract_top_hash_section(@src, 'object_definitions')
    picklists_block = Extractor.extract_top_hash_section(@src, 'pick_lists')
    test_block = @src[/\btest\s*:\s*lambda\b.+/m]

    parse_actions(actions_block) if actions_block
    parse_methods(methods_block) if methods_block
    parse_object_definitions(objdefs_block) if objdefs_block
    parse_picklists(picklists_block) if picklists_block
    parse_top_test(test_block) if test_block
  end

  def parse_actions(block)
    pairs = Extractor.extract_named_curly_pairs(block)
    pairs.each do |action_name, action_block|
      parts = Extractor.extract_action_parts(action_block)
      execute_body = parts['execute'] || ''
      input_body   = parts['input_fields'] || ''
      output_body  = parts['output_fields'] || ''

      action = {
        'name' => action_name,
        'picklists_used' => (parts['picklists'] || []),
        'input_object_defs' => Semantics.find_object_def_refs(input_body),
        'output_object_defs' => Semantics.find_object_def_refs(output_body),
        'execute' => {
          'lambda_params' => Semantics.lambda_params(execute_body),
          'calls' => Semantics.find_calls(execute_body),
          'direct_http' => Semantics.find_direct_http(execute_body),
          'template_symbol' => Semantics.run_vertex_template_symbol(execute_body)
        }
      }
      @ir['actions'] << action

      entry = "execute:#{action_name}"
      add_node(entry)
      action['execute']['calls'].each { |callee| add_edge(entry, callee) }
      action['execute']['direct_http'].each { |verb| add_edge(entry, "HTTP:#{verb.upcase}") }

      if action_name =~ /image/i
        ts = action['execute']['template_symbol']
        if ts && ts != 'analyze_image'
          @issues << {
            'severity' => 'warning',
            'category' => 'template_mismatch',
            'message' => "Action '#{action_name}' uses template :#{ts}. Did you mean :analyze_image?",
            'where' => "actions.#{action_name}.execute"
          }
        end
      end
    end
  end

  def parse_methods(block)
    pairs = Extractor.extract_named_lambda_pairs(block)
    pairs.each do |method_name, lambda_body|
      calls = Semantics.find_calls(lambda_body)
      direct_http = Semantics.find_direct_http(lambda_body)
      m = {
        'name' => method_name,
        'lambda_params' => Semantics.lambda_params(lambda_body),
        'calls' => calls,
        'direct_http' => direct_http
      }
      @ir['methods'] << m
      add_node(method_name)
      calls.each { |callee| add_edge(method_name, callee) }
      direct_http.each { |verb| add_edge(method_name, "HTTP:#{verb.upcase}") }
    end
  end

  def parse_object_definitions(block)
    pairs = Extractor.extract_named_curly_pairs(block)
    pairs.each do |name, od_block|
      picklists = Semantics.find_picklists(od_block)
      refs = Semantics.find_object_def_refs(od_block)
      @ir['object_definitions'] << {
        'name' => name,
        'picklists_used' => picklists,
        'object_defs_referenced' => refs
      }
    end
  end

  def parse_picklists(block)
    pairs = Extractor.extract_named_lambda_pairs(block)
    pairs.each do |name, _lb|
      @ir['pick_lists'] << { 'name' => name }
    end
  end

  def parse_top_test(test_blob)
    if test_blob && (idx = test_blob.index('lambda'))
      lb = Balance.extract_lambda_block(test_blob, idx)
      calls = Semantics.find_calls(lb)
      entry = 'top:test'
      add_node(entry)
      calls.each { |c| add_edge(entry, c) }
    end
  end

  def add_node(n)
    @graph['nodes'] << n unless @graph['nodes'].include?(n)
  end

  def add_edge(from, to)
    add_node(from); add_node(to)
    @graph['edges'] << { 'from' => from, 'to' => to }
  end

  def post_process
    defined_methods = @ir['methods'].map { |m| m['name'] }.to_set

    all_calls = []
    @ir['methods'].each { |m| all_calls.concat(m['calls']) }
    @ir['actions'].each { |a| all_calls.concat(a.dig('execute','calls') || []) }
    all_calls.uniq!
    (all_calls - defined_methods.to_a).each do |undef_name|
      next if undef_name.start_with?('HTTP:')
      @issues << {
        'severity' => 'info',
        'category' => 'undefined_method_reference',
        'message' => "Method '#{undef_name}' is called but not defined under methods:",
        'where' => 'global'
      }
    end

    reachable = compute_reachable_from_entries
    (@ir['methods'].map { |m| m['name'] } - reachable.to_a).each do |unused|
      @issues << {
        'severity' => 'info',
        'category' => 'unused_method',
        'message' => "Method '#{unused}' is not reachable from any action/test entrypoints",
        'where' => 'methods'
      }
    end

    (@ir['methods'] + @ir['actions'].map{|a| {'name'=>"execute:#{a['name']}", 'direct_http'=>a.dig('execute','direct_http')}}).each do |m|
      next unless m['direct_http'] && !m['direct_http'].empty?
      @issues << {
        'severity' => 'warning',
        'category' => 'direct_http',
        'message' => "Direct HTTP calls detected in '#{m['name']}' (#{m['direct_http'].uniq.join(', ')}). Prefer unified api_request wrapper.",
        'where' => "methods.#{m['name']}"
      }
    end

    defined_pl = @ir['pick_lists'].map{|p| p['name']}.to_set
    used_pl = []
    @ir['actions'].each { |a| used_pl.concat(a['picklists_used']) }
    @ir['object_definitions'].each { |o| used_pl.concat(o['picklists_used']) }
    (used_pl.uniq - defined_pl.to_a).each do |pl|
      @issues << {
        'severity' => 'info',
        'category' => 'missing_picklist',
        'message' => "pick_list :#{pl} is referenced but not defined in pick_lists",
        'where' => 'object_definitions/actions'
      }
    end

    build_call_paths!
  end

  def compute_reachable_from_entries
    adj = {}
    @graph['edges'].each do |e|
      (adj[e['from']] ||= []) << e['to']
    end
    entries = (@ir['actions'].map { |a| "execute:#{a['name']}" } + ['top:test']).select { |n| @graph['nodes'].include?(n) }
    seen = Set.new
    stack = entries.dup
    while (n = stack.pop)
      next if seen.include?(n)
      seen << n
      (adj[n] || []).each { |m| stack << m }
    end
    Set.new(seen.select { |n| @ir['methods'].any? { |m| m['name'] == n } })
  end

  def build_call_paths!
    adj = Hash.new { |h,k| h[k] = [] }
    @graph['edges'].each { |e| adj[e['from']] << e['to'] }

    entries = @ir['actions'].map { |a| "execute:#{a['name']}" }.select { |n| @graph['nodes'].include?(n) }

    entries.each do |entry|
      paths = []
      dfs_paths(entry, adj, [], Set.new, paths, 0, 60)
      @graph['paths'][entry.sub('execute:', '')] = paths
    end
  end

  def dfs_paths(node, adj, cur, seen, paths, depth, limit)
    return if depth > limit
    cur << node
    if (adj[node] || []).empty? || seen.include?(node)
      paths << cur.dup
      cur.pop
      return
    end
    seen.add(node)
    adj[node].each do |nxt|
      dfs_paths(nxt, adj, cur, seen, paths, depth+1, limit)
    end
    seen.delete(node)
    cur.pop
  end
end

# -------------------------------
# CLI
# -------------------------------
if __FILE__ == $0
  opts = { out: 'out' }
  OptionParser.new do |o|
    o.banner = "Usage: ruby #{File.basename($0)} path/to/connector.rb [-o out_dir]"
    o.on('-o', '--out DIR', 'Output directory') { |v| opts[:out] = v }
  end.parse!

  abort("Please provide path to connector file") if ARGV.empty?
  path = ARGV[0]
  abort("File not found: #{path}") unless File.file?(path)

  src = File.read(path, encoding: 'UTF-8')
  analyzer = ConnectorAnalyzer.new(src).analyze!

  FileUtils.mkdir_p(opts[:out])

  File.write(File.join(opts[:out], 'ir.json'), JSON.pretty_generate(analyzer.ir))
  File.write(File.join(opts[:out], 'call_graph.json'), JSON.pretty_generate(analyzer.graph))
  File.write(File.join(opts[:out], 'issues.json'), JSON.pretty_generate(analyzer.issues))

  puts "[✓] Wrote: #{opts[:out]}/ir.json, call_graph.json, issues.json"
  puts "Actions: #{analyzer.ir['actions'].size}, Methods: #{analyzer.ir['methods'].size}, ObjectDefs: #{analyzer.ir['object_definitions'].size}, PickLists: #{analyzer.ir['pick_lists'].size}"
  puts "Issues: #{analyzer.issues.size}"
end
