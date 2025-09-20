#!/usr/bin/env ruby
# run_all_tests.rb
# Purpose: Execute all tests and generate report
# Usage: ruby run_all_tests.rb

require 'json'
require 'time'

class TestRunner
  def initialize
    @results = {}
    @start_time = Time.now
  end
  
  def run_all_tests
    puts "🚀 Starting Workato RAG System Test Suite"
    puts "="*60
    puts "Environment: #{ENV['ENVIRONMENT'] || 'development'}"
    puts "Started at: #{@start_time}"
    puts "="*60
    
    test_suites = [
      { name: "Connection Tests", file: "test_all_connections.rb" },
      { name: "Document Processing", file: "test_document_processing.rb" },
      { name: "Batch Processing", file: "test_batch_processing.rb" },
      { name: "Embeddings", file: "test_embeddings.rb" },
      { name: "Vector Search", file: "test_vector_search.rb" },
      { name: "Email Pipeline", file: "test_email_pipeline.rb" },
      { name: "Performance", file: "test_performance.rb" }
    ]
    
    test_suites.each do |suite|
      puts "\n" + "="*60
      puts "Running: #{suite[:name]}"
      puts "="*60
      
      begin
        result = system("ruby #{suite[:file]}")
        @results[suite[:name]] = {
          passed: result,
          executed_at: Time.now
        }
      rescue => e
        @results[suite[:name]] = {
          passed: false,
          error: e.message,
          executed_at: Time.now
        }
      end
      
      sleep(2) # Prevent rate limiting
    end
    
    generate_report
  end
  
  def generate_report
    total_time = Time.now - @start_time
    passed_count = @results.values.count { |r| r[:passed] }
    failed_count = @results.length - passed_count
    
    puts "\n" + "="*60
    puts "📊 TEST SUITE REPORT"
    puts "="*60
    
    puts "\n📋 Results Summary:"
    @results.each do |name, result|
      status = result[:passed] ? "✅ PASS" : "❌ FAIL"
      puts "   #{status} - #{name}"
      puts "        Error: #{result[:error]}" if result[:error]
    end
    
    puts "\n📈 Statistics:"
    puts "   Total Tests: #{@results.length}"
    puts "   Passed: #{passed_count}"
    puts "   Failed: #{failed_count}"
    puts "   Success Rate: #{(passed_count.to_f / @results.length * 100).round(1)}%"
    puts "   Total Time: #{total_time.round(2)}s"
    
    # Save report to file
    report = {
      timestamp: @start_time.iso8601,
      environment: ENV['ENVIRONMENT'] || 'development',
      results: @results,
      statistics: {
        total: @results.length,
        passed: passed_count,
        failed: failed_count,
        success_rate: (passed_count.to_f / @results.length * 100).round(1),
        duration_seconds: total_time.round(2)
      }
    }
    
    File.write("test_report_#{@start_time.strftime('%Y%m%d_%H%M%S')}.json", JSON.pretty_generate(report))
    puts "\n💾 Report saved to: test_report_#{@start_time.strftime('%Y%m%d_%H%M%S')}.json"
    
    # Exit with appropriate code
    exit(failed_count == 0 ? 0 : 1)
  end
end

# Run tests
TestRunner.new.run_all_tests if __FILE__ == $0
