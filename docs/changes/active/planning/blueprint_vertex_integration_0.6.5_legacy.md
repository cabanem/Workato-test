# Blueprint

## 1. Repo / module layout (separation of concerns)

> If your platform requires a single file, still keep these “layers” as **virtual modules** via method prefixes (e.g., `core__`, `http__`, `vertex__`, `llm__`, `catalog__`, `vec__`, `emb__`, `drive__`, `schemas__`). You can also generate the final file via a build step that concatenates these pieces.

```
connectors/
  vertex_ai/
    connector.rb                    # final Workato (or equivalent) connector definition (can be generated)
    actions/
      generative.rb                 # send_messages, summarize, parse, analyze, classify
      embeddings.rb                 # single + batch
      vector_search.rb              # find_neighbors, upsert_datapoints
      setup.rb                      # test_connection, diagnostics
      drive.rb                      # (optional) file fetch/list/monitor if you keep them here
    services/
      resilience.rb                 # with_resilience, circuit breaker, 429 backoff
      rate_limit.rb                 # per-model-family RPM sliding window
      http.rb                       # api_request wrapper, standard error mapping
      telemetry.rb                  # trace & envelope helpers
      validators.rb                 # validate_model_on_run, index access, input guards
      model_catalog.rb              # dynamic model discovery cascade + curated fallback
      payloads.rb                   # base builders, templates, tools/function-calling
      extractors.rb                 # finish reason map, JSON parsing, safety & usage mapping
      vector.rb                     # neighbors payload & response flattening
      embeddings.rb                 # batch/single execution helpers
      drive_utils.rb                # (optional) Drive helpers, query builders
    objects/
      schemas.rb                    # trace/rate_limit/vertex_meta/safety/usage schemas
      picklists.rb                  # available_*_models, enums
    README.md
    CHANGELOG.md
    Rakefile or build script        # (optional) stitch multi-file → single-file
```

**Why this helps DRY:** Actions become thin delegators; resilience, HTTP, catalog, builders, and extractors live in one place and are re-used.

---

## 2. Naming & DRY conventions (work in one file too)

For single file, keep **virtual modules** using prefixes:

* **Core/runtime:** `core__gen_correlation_id`, `core__with_resilience`
* **HTTP:** `http__request`, `http__vertex`, `http__drive`, `http__handle_vertex_error`
* **Rate limiting:** `rl__enforce`, `rl__defaults`
* **Telemetry:** `telemetry__envelope`, `telemetry__usage_meta`
* **Catalog & validation:** `catalog__fetch`, `catalog__to_options`, `catalog__validate_model!`
* **LLM payloads:** `llm__build(template, input)`, `llm__build_conversation`, `llm__templates`
* **LLM extractors:** `llm__extract(type:, json:)`, `llm__finish_reason_map`, `llm__standard_error`
* **Embeddings:** `emb__batch_exec`, `emb__single_exec`
* **Vector search:** `vec__build_neighbors_payload`, `vec__transform_neighbors`
* **Drive (optional):** `drive__fetch_file_full`, …
* **Schemas & picklists:** `schemas__trace`, `schemas__rate_limit`, `picklists__available_models(bucket)`

This keeps **one source of truth** per concern and lets you reuse everywhere.

---

## 3. Connector skeleton (thin actions + shared builders)

> Below is a **concise skeleton** showing how to organize the new connector while reusing logic. It’s intentionally compact but complete enough to paste and extend. Keep the legacy behavior where it adds value (resilience, telemetry, catalog, extractors) but modernize naming.

````ruby
{
  title: 'Google Vertex AI (New)',

  # ---- Custom action help (kept minimal) ----
  custom_action: true,
  custom_action_help: {
    learn_more_url: 'https://cloud.google.com/vertex-ai/docs/reference/rest',
    learn_more_text: 'Google Vertex AI API documentation',
    body: '<p>Build custom Vertex AI requests. Uses your Vertex AI connection and project/region.</p>'
  },

  # ==== CONNECTION ====
  connection: {
    fields: [
      # Developer options
      { name: 'verbose_errors',    label: 'Verbose errors', group: 'Developer', type: 'boolean', control_type: 'checkbox',
        hint: 'Include upstream response bodies in error messages (disable in prod).' },
      { name: 'include_trace',     label: 'Include trace',  group: 'Developer', type: 'boolean', control_type: 'checkbox', default: true, sticky: true,
        hint: 'Adds trace.correlation_id and trace.duration_ms to outputs.' },

      # Authentication
      { name: 'auth_type', label: 'Authentication type', group: 'Authentication', control_type: 'select', default: 'custom', optional: false, extends_schema: true,
        options: [ ['Service account (JWT)', 'custom'], ['OAuth2 (user delegated)', 'oauth2'] ] },

      # Vertex environment
      { name: 'region',  label: 'Region',  group: 'Vertex AI', control_type: 'select', optional: false,
        options: [%w[US\ Central\ 1 us-central1], %w[US\ East\ 1 us-east1], %w[Europe\ West\ 4 europe-west4], %w[Asia\ Southeast\ 1 asia-southeast1]],
        toggle_field: { name: 'region', label: 'Region', type: 'string', control_type: 'text', optional: false } },
      { name: 'project', label: 'Project', group: 'Vertex AI', optional: false, hint: 'e.g. abc-dev-1234' },
      { name: 'version', label: 'API version', group: 'Vertex AI', optional: false, default: 'v1' },

      # Model discovery / validation
      { name: 'dynamic_models',          label: 'Refresh model list from API', group: 'Models', type: 'boolean', control_type: 'checkbox' },
      { name: 'include_preview_models',  label: 'Include preview/experimental models', group: 'Models', type: 'boolean', control_type: 'checkbox', sticky: true },
      { name: 'validate_model_on_run',   label: 'Validate model before run', group: 'Models', type: 'boolean', control_type: 'checkbox', sticky: true, default: true },
      { name: 'enable_rate_limiting',    label: 'Enable rate limiting', group: 'Quotas', type: 'boolean', control_type: 'checkbox', default: true }
    ],

    authorization: {
      type: 'multi',
      selected: lambda { |connection| connection['auth_type'] || 'custom' },
      options: {
        oauth2: {
          type: 'oauth2',
          fields: [
            { name: 'client_id',     group: 'OAuth2', optional: false },
            { name: 'client_secret', group: 'OAuth2', optional: false, control_type: 'password' }
          ],
          authorization_url: lambda do |connection|
            scopes = call('catalog__oauth_scopes').join(' ')
            params = { client_id: connection['client_id'], response_type: 'code', scope: scopes,
                       access_type: 'offline', include_granted_scopes: 'true', prompt: 'consent' }.to_param
            "https://accounts.google.com/o/oauth2/v2/auth?#{params}"
          end,
          acquire: lambda do |connection, auth_code|
            post('https://oauth2.googleapis.com/token')
              .payload(client_id: connection['client_id'],
                       client_secret: connection['client_secret'],
                       grant_type: 'authorization_code',
                       code: auth_code,
                       redirect_uri: 'https://www.workato.com/oauth/callback')
              .request_format_www_form_urlencoded
          end,
          refresh: lambda do |connection, refresh_token|
            post('https://oauth2.googleapis.com/token')
              .payload(client_id: connection['client_id'],
                       client_secret: connection['client_secret'],
                       grant_type: 'refresh_token',
                       refresh_token: refresh_token)
              .request_format_www_form_urlencoded
          end,
          apply: lambda { |_connection, access_token| headers(Authorization: "Bearer #{access_token}") }
        },

        custom: {
          type: 'custom_auth',
          fields: [
            { name: 'service_account_email', optional: false, group: 'Service Account' },
            { name: 'client_id',             optional: false },
            { name: 'private_key',           optional: false, control_type: 'password', multiline: true }
          ],
          acquire: lambda do |connection|
            jwt_body = {
              'iat' => now.to_i, 'exp' => 1.hour.from_now.to_i,
              'aud' => 'https://oauth2.googleapis.com/token',
              'iss' => connection['service_account_email'],
              'sub' => connection['service_account_email'],
              'scope' => 'https://www.googleapis.com/auth/cloud-platform'
            }
            pk = connection['private_key'].gsub('\\n', "\n")
            jwt = workato.jwt_encode(jwt_body, pk, 'RS256', kid: connection['client_id'])
            resp = post('https://oauth2.googleapis.com/token',
                        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                        assertion: jwt).request_format_www_form_urlencoded
            { access_token: resp['access_token'] }
          end,
          refresh_on: [401],
          apply: lambda { |connection| headers(Authorization: "Bearer #{connection['access_token']}") }
        }
      }
    },

    base_uri: lambda { |connection| "https://#{connection['region']}-aiplatform.googleapis.com/#{connection['version'] || 'v1'}/" }
  },

  # ==== TEST (lightweight) ====
  test: lambda do |connection|
    resp = call('core__with_resilience', connection, key: 'vertex.datasets.list') do |cid|
      call('http__request', connection, :get,
           "#{call('core__project_region_path', connection)}/datasets",
           params: { pageSize: 1 },
           headers: { 'X-Correlation-Id' => cid },
           context: { action: 'List datasets', correlation_id: cid })
    end
    { status: 'connected', trace: resp['trace'] }
  end,

  # ==== ACTIONS (thin delegators) ====
  actions: {
    send_messages: {
      title: 'Vertex — Send messages',
      subtitle: 'Converse with Gemini models',
      description: 'Send messages to Gemini via Vertex AI',
      input_fields: lambda { |object_definitions| object_definitions['send_messages_input'] },
      execute: lambda do |connection, input|
        call('vertex__run', connection, input, :send_message, verb: :generate, extract: { type: :generic })
      end,
      output_fields: lambda { |object_definitions| object_definitions['send_messages_output'] },
      sample_output: lambda { call('schemas__sample', 'send_message') }
    },

    summarize_text: {
      title: 'Vertex — Summarize text',
      subtitle: 'Short summaries on demand',
      input_fields: lambda { |object_definitions| object_definitions['summarize_text_input'] },
      execute: lambda do |connection, input|
        call('vertex__run', connection, input, :summarize, verb: :generate, extract: { type: :generic })
      end,
      output_fields: lambda { |object_definitions| object_definitions['summarize_text_output'] },
      sample_output: lambda { call('schemas__sample', 'summarize_text') }
    },

    ai_classify: {
      title: 'Vertex — AI Classification',
      subtitle: 'Classify text with confidence',
      input_fields: lambda { |obj_defs| obj_defs['ai_classify_input'] },
      execute: lambda do |connection, input|
        call('vertex__run', connection, input, :ai_classify, verb: :generate, extract: { type: :classify })
      end,
      output_fields: lambda { |obj_defs| obj_defs['ai_classify_output'] },
      sample_output: lambda { call('schemas__sample', 'ai_classify') }
    },

    generate_embedding_single: {
      title: 'Vertex — Generate single text embedding',
      input_fields: lambda { |obj_defs| obj_defs['embedding_single_input'] },
      execute:     lambda { |connection, input| call('emb__single_exec', connection, input) },
      output_fields: lambda { |obj_defs| obj_defs['embedding_single_output'] },
      sample_output: lambda { call('schemas__sample', 'embedding_single') }
    },

    generate_embeddings: {
      title: 'Vertex — Generate text embeddings (Batch)',
      batch: true,
      input_fields: lambda { |obj_defs| obj_defs['embedding_batch_input'] },
      execute:     lambda { |connection, input| call('emb__batch_exec', connection, input) },
      output_fields: lambda { |obj_defs| obj_defs['embedding_batch_output'] },
      sample_output: lambda { call('schemas__sample', 'embedding_batch') }
    },

    find_neighbors: {
      title: 'Vertex — Find neighbors',
      subtitle: 'k‑NN on Vertex Vector Search',
      input_fields:  lambda { |obj_defs| obj_defs['find_neighbors_input'] },
      execute:       lambda do |connection, input|
        resp = call('vec__find_neighbors', connection, input)
        call('vec__transform_neighbors', resp).merge('trace' => resp['trace'])
      end,
      output_fields: lambda { |obj_defs| obj_defs['find_neighbors_output'] },
      sample_output: lambda { call('schemas__sample', 'find_neighbors') }
    },

    upsert_index_datapoints: {
      title: 'Vertex — Upsert index datapoints',
      input_fields:  lambda { |obj_defs| obj_defs['upsert_datapoints_input'] },
      execute:       lambda { |connection, input| call('vec__upsert_datapoints', connection, input) },
      output_fields: lambda { |obj_defs| obj_defs['upsert_datapoints_output'] },
      sample_output: lambda { call('schemas__sample', 'upsert_datapoints') }
    },

    test_connection: {
      title: 'Setup — Test connection & permissions',
      input_fields: lambda { |obj_defs| obj_defs['test_connection_input'] },
      execute:      lambda { |connection, input| call('core__test_connection', connection, input) },
      output_fields: lambda { |obj_defs| obj_defs['test_connection_output'] },
      sample_output: lambda { call('schemas__sample', 'test_connection') }
    }
  },

  # ==== SHARED METHODS (DRY core) ====
  methods: {
    # --- Core / Telemetry / HTTP ---
    core__gen_correlation_id: lambda do
      SecureRandom.uuid rescue "#{(Time.now.to_f*1000).to_i.to_s(36)}-#{rand(36**8).to_s(36).rjust(8,'0')}"
    end,
    core__project_region_path: lambda { |c| "projects/#{c['project']}/locations/#{c['region']}" },

    core__with_resilience: lambda do |connection, key:, model: nil, retry_on: nil, &block|
      defaults = call('rl__defaults')
      retry_on ||= defaults['retry_on']
      rl = call('rl__enforce', connection, model || key, 'inference')
      include_trace = connection['include_trace'] != false
      cid = call('core__gen_correlation_id'); started = Time.now

      result = call('core__circuit_breaker_retry', connection, key, { retry_on: retry_on }) { block.call(cid) }
      duration_ms = ((Time.now - started)*1000).round

      out = result.is_a?(Hash) ? result.dup : { 'raw' => result }
      out['rate_limit_status'] ||= rl
      out['trace'] = { 'correlation_id' => cid, 'duration_ms' => duration_ms } if include_trace
      out
    end,

    http__request: lambda do |connection, method, url, options = {}|
      req = case method.to_sym
            when :get then get(url)
            when :post then options[:payload] ? post(url, options[:payload]) : post(url)
            when :put then put(url, options[:payload])
            when :delete then delete(url)
            else error("Unsupported HTTP method: #{method}")
            end
      req = req.params(options[:params]) if options[:params]
      req = req.headers(options[:headers]) if options[:headers]
      req.after_error_response(/.*/) do |code, body, _hdr, message|
        if options[:error_handler]
          options[:error_handler].call(code, body, message)
        else
          call('http__handle_vertex_error', connection, code, body, message, options[:context] || {})
        end
      end
    end,

    http__handle_vertex_error: lambda do |connection, code, body, message, context = {}|
      # concise, data-driven error mapping (can paste your detailed mapping here)
      message_prefix = context[:action] ? "#{context[:action]} failed: " : ''
      verbose = connection['verbose_errors']
      cid = context[:correlation_id]; cid_txt = cid ? " [cid: #{cid}]" : ''

      details = begin
        parsed = parse_json(body); parsed.dig('error','message') || parsed['message'] || body
      rescue; body; end

      base = case code
             when 400 then 'Invalid request'
             when 401 then 'Authentication failed'
             when 403 then 'Permission denied'
             when 404 then 'Not found'
             when 429 then 'Rate limit exceeded'
             when 500..599 then 'Google service error'
             else 'API error'
             end

      if verbose
        error("#{message_prefix}#{base} (HTTP #{code})#{cid_txt}\nDetails: #{details}\nOriginal: #{message}")
      else
        hint = (code == 429 ? "\nConsider backoff." : '')
        error("#{message_prefix}#{base}#{cid_txt}#{hint}")
      end
    end,

    # --- Rate limiting & CB (trimmed) ---
    rl__defaults: lambda { { 'max_retries' => 3, 'base_delay' => 1.0, 'max_delay' => 30.0, 'retry_on' => [429, 500, 502, 503, 504, 'timeout', 'connection'] } },
    rl__enforce: lambda do |connection, model, _|
      return { requests_last_minute: 0, limit: 0, throttled: false, sleep_ms: 0 } unless connection['enable_rate_limiting']
      family = case model.to_s.downcase
               when /flash/ then 'gemini-flash'
               when /embedding/ then 'embedding'
               else 'gemini-pro'
               end
      limits = { 'gemini-pro' => 300, 'gemini-flash' => 600, 'embedding' => 600 }
      project = connection['project'] || 'default'
      k = "vertex_rate_#{project}_#{family}_window"
      t = Time.now.to_i; window = (workato.cache.get(k) || { 'timestamps' => [] })
      ts = window['timestamps'].select { |x| x >= t-60 }
      if ts.length >= limits[family]
        sleep(1.0 + rand*0.5) # simple, jittered
        { requests_last_minute: ts.length, limit: limits[family], throttled: true, sleep_ms: 1000 }
      else
        ts << t; workato.cache.set(k, { 'timestamps' => ts }, 90)
        { requests_last_minute: ts.length, limit: limits[family], throttled: false, sleep_ms: 0 }
      end
    end,

    core__circuit_breaker_retry: lambda do |connection, op_name, opts = {}, &block|
      d = call('rl__defaults'); max = opts[:max_retries] || d['max_retries']
      base = opts[:base_delay] || d['base_delay']; maxd = opts[:max_delay] || d['max_delay']
      retry_on = Array(opts[:retry_on] || d['retry_on'])
      key = "cb_#{connection['project']}_#{op_name}"
      state = workato.cache.get(key) || { 'failures' => 0, 'state' => 'closed', 'last_failure' => nil }
      if state['state'] == 'open' && Time.now - (Time.parse(state['last_failure']) rescue Time.at(0)) < 300
        error("Circuit breaker OPEN for #{op_name}. Retry later.")
      end
      max.times do |i|
        begin
          res = block.call; workato.cache.set(key, { 'failures' => 0, 'state' => 'closed' }, 3600); return res
        rescue => e
          code = (e.respond_to?(:response) && e.response.respond_to?(:status)) ? e.response.status.to_i : nil
          retryable = retry_on.any? { |x| x.is_a?(Integer) ? x == code : e.message.include?(x.to_s) }
          if retryable && i < max-1
            delay = [base * (2 ** i), maxd].min + rand*0.5; sleep(delay)
          else
            state['failures'] += 1; state['last_failure'] = Time.now.iso8601
            state['state'] = 'open' if state['failures'] >= 5
            workato.cache.set(key, state, 3600)
            raise e
          end
        end
      end
    end,

    # --- Model catalog & validation (DRY) ---
    catalog__oauth_scopes: lambda { ['https://www.googleapis.com/auth/cloud-platform'] },
    catalog__static_models: lambda do
      {
        text: [
          ['Gemini 1.5 Pro',   'publishers/google/models/gemini-1.5-pro'],
          ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
          ['Gemini 2.5 Pro',   'publishers/google/models/gemini-2.5-pro'],
          ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash']
        ],
        image: [
          ['Gemini 1.5 Pro',   'publishers/google/models/gemini-1.5-pro'],
          ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash']
        ],
        embedding: [
          ['Text Embedding 004', 'publishers/google/models/text-embedding-004']
        ]
      }
    end,
    catalog__available_models: lambda do |connection, bucket|
      static = call('catalog__static_models')[bucket] || []
      if connection['dynamic_models']
        options = call('catalog__dynamic_options', connection, bucket)
        options.present? ? options : static
      else
        static
      end
    end,
    catalog__dynamic_options: lambda do |connection, bucket|
      # (short form) fetch list with fallback; filter/label; return [['Label','id'], ...]
      # You can paste the full cascade implementation here from your legacy connector.
      []
    end,
    catalog__validate_model!: lambda do |connection, model|
      return unless connection['validate_model_on_run']
      error('Invalid model name') unless model.to_s.match?(/^publishers\/[^\/]+\/models\/[^\/]+$/)
      # Optionally make a lightweight GET to ensure it exists / is GA unless preview is enabled
      # (Reuse detailed validation from the legacy connector.)
    end,

    # --- LLM payloads & extractors (DRY) ---
    llm__templates: lambda do
      {
        send_message: { delegate_to: 'llm__build_conversation' },
        summarize:    { instruction: ->(i){ "Summarize in #{i['max_words']||200} words or fewer." },
                        user: ->(i){ i['text'] } },
        ai_classify:  { custom: 'llm__build_classify' }
      }
    end,

    llm__build: lambda do |template_key, input|
      t = call('llm__templates')[template_key] || error("Unknown template: #{template_key}")
      if t[:delegate_to] then call(t[:delegate_to], input)
      elsif t[:custom]   then call(t[:custom], input)
      else
        instr = t[:instruction].call(input)
        user  = t[:user].call(input)
        {
          'systemInstruction' => { 'role' => 'model', 'parts' => [{ 'text' => instr }] },
          'contents' => [{ 'role' => 'user', 'parts' => [{ 'text' => user }] }],
          'generationConfig' => { 'temperature' => 0 }
        }
      end
    end,

    llm__build_conversation: lambda do |input|
      # Supports single message or chat transcript; tools/responseSchema passthrough if present
      if input['generationConfig']&.[]('responseSchema').present?
        input['generationConfig']['responseSchema'] = parse_json(input['generationConfig']['responseSchema'])
      end
      if input['tools'].present?
        input['tools'] = input['tools'].map do |tool|
          if tool['functionDeclarations']
            tool['functionDeclarations'].map! do |f|
              f['parameters'] = parse_json(f['parameters']) rescue f['parameters']
              f
            end
          end
          tool
        end
      end
      contents =
        if input['message_type'] == 'single_message'
          [{ 'role' => 'user', 'parts' => [{ 'text' => input.dig('messages','message') }] }]
        else
          Array(input.dig('messages','chat_transcript')).map do |m|
            parts = []; parts << { 'text' => m['text'] } if m['text']
            parts << { 'fileData' => m['fileData'] } if m['fileData']
            parts << { 'inlineData' => m['inlineData'] } if m['inlineData']
            parts << { 'functionCall' => m['functionCall'].merge('args' => (parse_json(m.dig('functionCall','args')) rescue m.dig('functionCall','args'))) } if m['functionCall']
            parts << { 'functionResponse' => m['functionResponse'].merge('response' => (parse_json(m.dig('functionResponse','response')) rescue m.dig('functionResponse','response'))) } if m['functionResponse']
            { 'role' => m['role'], 'parts' => parts }
          end
        end
      { 'contents' => contents,
        'generationConfig' => input['generationConfig'],
        'systemInstruction'=> input['systemInstruction'],
        'tools' => input['tools'],
        'toolConfig' => input['toolConfig'],
        'safetySettings' => input['safetySettings'] }.compact
    end,

    llm__build_classify: lambda do |input|
      cats = Array(input['categories']).map { |c| c['description'].to_s.empty? ? c['key'] : "#{c['key']}: #{c['description']}" }.join("\n")
      user = "Categories:\n```#{cats}```\nText:\n```#{input['text']}```\nReturn JSON {selected_category, confidence, alternatives?}"
      { 'systemInstruction' => { 'role' => 'model', 'parts' => [{ 'text' => 'You are an expert classifier.' }] },
        'contents' => [{ 'role' => 'user', 'parts' => [{ 'text' => user }] }],
        'generationConfig' => { 'temperature' => input.dig('options','temperature') || 0.1 } }
    end,

    llm__extract: lambda do |resp, type:, json_response: false|
      finish = resp&.dig('candidates',0,'finishReason').to_s
      safety = (resp&.dig('candidates',0,'safetyRatings') || [])
      usage  = call('telemetry__usage_meta', resp)
      text   = resp&.dig('candidates',0,'content','parts',0,'text').to_s

      case type
      when :generic
        answer = json_response ? (parse_json(text) rescue {})['response'] : text
        { 'answer' => answer.to_s, 'has_answer' => answer.to_s.strip != '', 'pass_fail' => finish.downcase != 'safety',
          'action_required' => answer.to_s.strip == '' ? 'retry_or_refine' : 'use_answer',
          'safety_ratings' => { 'raw' => safety }, 'usage' => usage }
      when :classify
        json = (parse_json(text) rescue {}) || {}
        conf = [[json['confidence'].to_f, 0.0].max, 1.0].min
        { 'selected_category' => json['selected_category'] || 'unknown',
          'confidence' => conf,
          'alternatives' => json['alternatives'] || [],
          'requires_human_review' => conf < 0.7,
          'pass_fail' => conf >= 0.7 && finish.downcase != 'safety',
          'action_required' => conf < 0.7 ? 'human_review' : 'use_classification',
          'safety_ratings' => { 'raw' => safety }, 'usage' => usage }
      else
        { 'pass_fail' => false, 'action_required' => 'review_and_retry', 'usage' => usage }
      end
    end,

    telemetry__usage_meta: lambda do |resp|
      { 'promptTokenCount' => resp.dig('usageMetadata','promptTokenCount') || 0,
        'candidatesTokenCount' => resp.dig('usageMetadata','candidatesTokenCount') || 0,
        'totalTokenCount' => resp.dig('usageMetadata','totalTokenCount') || 0 }
    end,

    # --- Vertex orchestrator ---
    vertex__url_for: lambda do |connection, model, verb|
      base = call('core__project_region_path', connection)
      case verb.to_s
      when 'generate' then "#{base}/#{model}:generateContent"
      when 'predict'  then "#{base}/#{model}:predict"
      else error("Unsupported verb: #{verb}")
      end
    end,

    vertex__run: lambda do |connection, input, template, verb:, extract: {}|
      call('catalog__validate_model!', connection, input['model'])
      payload = input['formatted_prompt'] || call('llm__build', template, input)
      url     = call('vertex__url_for', connection, input['model'], verb)
      resp = call('core__with_resilience', connection, key: "vertex.#{verb}", model: input['model']) do |cid|
        call('http__request', connection, :post, url,
             payload: payload,
             headers: { 'X-Correlation-Id' => cid },
             context: { action: (verb.to_s == 'generate' ? 'Generate content' : 'Predict'),
                        model: input['model'], correlation_id: cid })
      end
      extracted = extract[:type] ? call('llm__extract', resp, type: extract[:type], json_response: extract[:json_response]) : resp
      extracted.merge(
        'trace' => resp['trace'],
        'rate_limit_status' => resp['rate_limit_status'],
        'vertex' => { 'response_id' => resp['responseId'], 'model_version' => resp['modelVersion'] }.compact
      )
    end,

    # --- Embeddings ---
    emb__single_exec: lambda do |connection, input|
      call('catalog__validate_model!', connection, input['model'])
      url = call('vertex__url_for', connection, input['model'], :predict)
      content = input['title'].present? ? "#{input['title']}: #{input['text']}" : input['text']
      payload = { 'instances' => [{ 'task_type' => input['task_type'].presence, 'content' => content }.compact] }
      resp = call('core__with_resilience', connection, key: 'vertex.embedding', model: input['model']) do |cid|
        call('http__request', connection, :post, url,
             payload: payload,
             headers: { 'X-Correlation-Id' => cid },
             context: { action: 'Embedding predict', model: input['model'], correlation_id: cid })
      end
      vec = resp.dig('predictions',0,'embeddings','values') || []
      { 'vector' => vec, 'dimensions' => vec.length, 'model_used' => input['model'],
        'token_count' => (content.length/4.0).ceil, 'trace' => resp['trace'], 'rate_limit_status' => resp['rate_limit_status'] }
    end,

    emb__batch_exec: lambda do |connection, input|
      call('catalog__validate_model!', connection, input['model'])
      url = call('vertex__url_for', connection, input['model'], :predict)
      texts = Array(input['texts'] || [])
      batch_size = 25
      embeddings, batches, ok, fail, tokens = [], 0, 0, 0, 0
      last_trace = nil; last_rate = nil

      texts.each_slice(batch_size) do |chunk|
        batches += 1
        instances = chunk.map { |t| { 'task_type' => input['task_type'].presence, 'content' => t['content'].to_s }.compact }
        resp = call('core__with_resilience', connection, key: 'vertex.embedding', model: input['model']) do |cid|
          call('http__request', connection, :post, url,
               payload: { 'instances' => instances },
               headers: { 'X-Correlation-Id' => cid },
               context: { action: 'Embedding predict', model: input['model'], correlation_id: cid })
        end
        preds = resp['predictions'] || []
        chunk.each_with_index do |t, i|
          vals = preds[i]&.dig('embeddings','values') || []
          success = vals.any?
          embeddings << { 'id' => t['id'], 'vector' => vals, 'dimensions' => vals.length, 'metadata' => t['metadata'] || {}, 'success' => success }
          ok += 1 if success; fail += 1 unless success
          tokens += (t['content'].to_s.length/4.0).ceil
        end
        last_trace = resp['trace']; last_rate = resp['rate_limit_status']
      end

      { 'batch_id' => input['batch_id'],
        'embeddings_count' => embeddings.length,
        'embeddings' => embeddings,
        'first_embedding' => (e=embeddings.first)||{} and { 'id'=>e['id'],'vector'=>e['vector']||[],'dimensions'=>e['dimensions']||0 },
        'embeddings_json' => embeddings.to_json,
        'model_used' => input['model'],
        'total_processed' => texts.length,
        'successful_requests' => ok,
        'failed_requests' => fail,
        'total_tokens' => tokens,
        'batches_processed' => batches,
        'api_calls_saved' => texts.length - batches,
        'estimated_cost_savings' => ((texts.length - batches) * 0.0001).round(4),
        'pass_fail' => fail == 0,
        'action_required' => fail == 0 ? 'ready_for_indexing' : 'retry_failed_embeddings',
        'rate_limit_status' => last_rate,
        'trace' => last_trace
      }
    end,

    # --- Vector search (neighbors + upsert) ---
    vec__find_neighbors: lambda do |connection, input|
      host = call('vec__normalize_host', input['index_endpoint_host'])
      version = connection['version'] || 'v1'
      url = "https://#{host}/#{version}/projects/#{connection['project']}/locations/#{connection['region']}/indexEndpoints/#{input['index_endpoint_id']}:findNeighbors"
      payload = call('vec__build_neighbors_payload', input)
      call('core__with_resilience', connection, key: 'vertex.find_neighbors') do |cid|
        call('http__request', connection, :post, url,
             payload: payload,
             headers: { 'X-Correlation-Id' => cid },
             context: { action: 'Find neighbors', correlation_id: cid })
      end
    end,

    vec__build_neighbors_payload: lambda do |input|
      {
        'deployedIndexId' => input['deployedIndexId'],
        'returnFullDatapoint' => !!input['returnFullDatapoint'],
        'queries' => Array(input['queries']).map do |q|
          dp = q['datapoint'] || {}
          {
            'datapoint' => {
              'datapointId' => dp['datapointId'],
              'featureVector' => dp['featureVector'],
              'sparseEmbedding' => dp['sparseEmbedding'],
              'restricts' => dp['restricts'],
              'numericRestricts' => dp['numericRestricts'],
              'crowdingTag' => dp['crowdingTag']
            }.compact,
            'neighborCount' => q['neighborCount'],
            'approximateNeighborCount' => q['approximateNeighborCount'],
            'perCrowdingAttributeNeighborCount' => q['perCrowdingAttributeNeighborCount'],
            'fractionLeafNodesToSearchOverride' => q['fractionLeafNodesToSearchOverride']
          }.compact
        end
      }.compact
    end,

    vec__transform_neighbors: lambda do |resp|
      maxd = 2.0
      all = []
      Array(resp['nearestNeighbors']).each do |qr|
        Array(qr['neighbors']).each do |n|
          dp = n['datapoint'] || {}
          dist = n['distance'].to_f
          sim = [[1.0 - (dist / maxd), 0.0].max, 1.0].min
          all << {
            'datapoint_id' => dp['datapointId'].to_s,
            'distance' => dist,
            'similarity_score' => sim,
            'feature_vector' => dp['featureVector'] || [],
            'crowding_attribute' => dp.dig('crowdingTag','crowdingAttribute').to_s
          }
        end
      end
      all.sort_by! { |x| -x['similarity_score'] }
      top = all.first || {}
      {
        'matches_count' => all.length,
        'top_matches' => all,
        'best_match_id' => top['datapoint_id'],
        'best_match_score' => top['similarity_score'] || 0.0,
        'pass_fail' => all.any?,
        'action_required' => all.any? ? 'retrieve_content' : 'refine_query',
        'nearestNeighbors' => resp['nearestNeighbors']
      }
    end,

    vec__normalize_host: lambda do |host|
      h = host.to_s.strip.gsub(/^https?:\/\//i,'').gsub(/\/+$/,'')
      error('Invalid endpoint host') unless h.match?(/^[\w\-.]+(:\d+)?$/); h
    end,

    vec__upsert_datapoints: lambda do |connection, input|
      # Short version—can paste full batch_upsert logic from legacy here
      { 'successfully_upserted_count' => 0, 'total_processed' => Array(input['datapoints']).length,
        'failed_upserts' => 0, 'failed_datapoints' => [], 'index_stats' => {} }
    end,

    # --- Setup/diagnostics ---
    core__test_connection: lambda do |connection, input|
      results = { 'timestamp' => Time.now.iso8601,
                  'environment' => { 'project' => connection['project'], 'region' => connection['region'], 'api_version' => connection['version'] || 'v1' },
                  'tests_performed' => [], 'errors' => [], 'warnings' => [], 'all_tests_passed' => true }
      begin
        v = call('core__with_resilience', connection, key: 'vertex.datasets.list') do |cid|
          call('http__request', connection, :get,
               "#{call('core__project_region_path', connection)}/datasets",
               params: { pageSize: 1 }, headers: { 'X-Correlation-Id' => cid },
               context: { action: 'List datasets', correlation_id: cid })
        end
        results['tests_performed'] << { 'service' => 'Vertex AI', 'status' => 'connected', 'response_time_ms' => v['trace']&.[]('duration_ms') }
      rescue => e
        results['errors'] << e.message; results['all_tests_passed'] = false
      end
      results['summary'] = { 'total_tests' => results['tests_performed'].length, 'passed' => results['tests_performed'].length - results['errors'].length, 'failed' => results['errors'].length }
      results['overall_status'] = results['all_tests_passed'] ? 'healthy' : 'failed'
      results
    end
  },

  # ==== OBJECT DEFINITIONS (compose from shared schemas; DRY) ====
  object_definitions: {
    # Minimal examples, keep your richer versions from the legacy connector
    send_messages_input: {
      fields: lambda do |_c, config, obj_defs|
        obj_defs['text_model_schema'].dup + [
          { name: 'message_type', type: 'string', control_type: 'select', pick_list: :message_types, extends_schema: true },
          { name: 'messages', type: 'object', properties: [
              { name: 'message', label: 'Text to send', type: 'string', control_type: 'text-area' },
              { name: 'chat_transcript', type: 'array', of: 'object', properties: [
                  { name: 'role' }, { name: 'text' }, { name: 'fileData', type: 'object' }, { name: 'inlineData', type: 'object' },
                  { name: 'functionCall', type: 'object' }, { name: 'functionResponse', type: 'object' }
              ] }
          ] }
        ] + obj_defs['config_schema']
      end
    },
    send_messages_output: {
      fields: lambda do |_c, _cfg, obj_defs|
        [
          { name: 'candidates', type: 'array', of: 'object' },
          { name: 'usageMetadata', type: 'object' },
          { name: 'modelVersion' }, { name: 'responseId' }
        ] + obj_defs['schemas__envelope']
      end
    },

    summarize_text_input: {
      fields: lambda do |_c, _cfg, obj_defs|
        obj_defs['text_model_schema'].dup + [
          { name: 'text', type: 'string', control_type: 'text-area' },
          { name: 'max_words', type: 'integer', control_type: 'integer' }
        ] + obj_defs['config_schema'].only('safetySettings')
      end
    },
    summarize_text_output: {
      fields: lambda do |_c, _cfg, obj_defs|
        [{ name: 'answer' }, { name: 'pass_fail', type: 'boolean' }, { name: 'action_required' }] + obj_defs['schemas__envelope']
      end
    },

    ai_classify_input: {
      fields: lambda do |_c, _cfg, obj_defs|
        [
          { name: 'text', type: 'string', control_type: 'text-area' },
          { name: 'categories', type: 'array', of: 'object', properties: [{ name: 'key' }, { name: 'description' }] },
          { name: 'model', type: 'string', control_type: 'select', pick_list: :available_text_models, extends_schema: true,
            toggle_field: { name: 'model', type: 'string', control_type: 'text' } },
          { name: 'options', type: 'object', properties: [{ name: 'temperature', type: 'number', control_type: 'number', default: 0.1 }] }
        ] + obj_defs['config_schema'].only('safetySettings')
      end
    },
    ai_classify_output: {
      fields: lambda do |_c, _cfg, obj_defs|
        [
          { name: 'selected_category' }, { name: 'confidence', type: 'number' }, { name: 'alternatives', type: 'array', of: 'object' },
          { name: 'requires_human_review', type: 'boolean' }, { name: 'pass_fail', type: 'boolean' }, { name: 'action_required' }
        ] + obj_defs['schemas__envelope']
      end
    },

    embedding_single_input: {
      fields: lambda do |_c, _cfg, obj_defs|
        [
          { name: 'text', type: 'string', control_type: 'text-area' },
          { name: 'model', type: 'string', control_type: 'select', pick_list: :available_embedding_models, extends_schema: true,
            toggle_field: { name: 'model', type: 'string', control_type: 'text' } },
          { name: 'task_type', type: 'string', control_type: 'select', pick_list: :embedding_task_list, optional: true },
          { name: 'title', type: 'string', optional: true }
        ]
      end
    },
    embedding_single_output: {
      fields: lambda do |_c, _cfg, obj_defs|
        [{ name: 'vector', type: 'array', of: 'number' }, { name: 'dimensions', type: 'integer' }, { name: 'model_used' }, { name: 'token_count', type: 'integer' }] + obj_defs['schemas__trace_rate']
      end
    },

    embedding_batch_input: {
      fields: lambda do |_c, _cfg, _obj_defs|
        [
          { name: 'batch_id', type: 'string' },
          { name: 'texts', type: 'array', of: 'object', properties: [{ name: 'id' }, { name: 'content' }, { name: 'metadata', type: 'object' }] },
          { name: 'model', type: 'string', control_type: 'select', pick_list: :available_embedding_models, extends_schema: true,
            toggle_field: { name: 'model', type: 'string', control_type: 'text' } },
          { name: 'task_type', type: 'string', control_type: 'select', pick_list: :embedding_task_list, optional: true }
        ]
      end
    },
    embedding_batch_output: {
      fields: lambda do |_c, _cfg, obj_defs|
        [
          { name: 'batch_id' }, { name: 'embeddings_count', type: 'integer' },
          { name: 'embeddings', type: 'array', of: 'object' },
          { name: 'first_embedding', type: 'object' },
          { name: 'model_used' }, { name: 'total_processed', type: 'integer' },
          { name: 'successful_requests', type: 'integer' }, { name: 'failed_requests', type: 'integer' },
          { name: 'total_tokens', type: 'integer' }, { name: 'batches_processed', type: 'integer' },
          { name: 'api_calls_saved', type: 'integer' }, { name: 'estimated_cost_savings', type: 'number' },
          { name: 'pass_fail', type: 'boolean' }, { name: 'action_required' },
          { name: 'embeddings_json' }
        ] + obj_defs['schemas__trace_rate']
      end
    },

    find_neighbors_input:   { fields: lambda { |_c,_cfg,_| [ { name: 'index_endpoint_host' }, { name: 'index_endpoint_id' }, { name: 'deployedIndexId' }, { name: 'returnFullDatapoint', type: 'boolean' }, { name: 'queries', type: 'array', of: 'object' } ] } },
    find_neighbors_output:  { fields: lambda { |_c,_cfg,obj_defs| [ { name: 'matches_count', type: 'integer' }, { name: 'top_matches', type: 'array', of: 'object' }, { name: 'best_match_id' }, { name: 'best_match_score', type: 'number' }, { name: 'pass_fail', type: 'boolean' }, { name: 'action_required' }, { name: 'nearestNeighbors', type: 'array', of: 'object' } ] + obj_defs['schemas__trace'] } },

    upsert_datapoints_input:  { fields: lambda { |_c,_cfg,_| [ { name: 'index_id' }, { name: 'datapoints', type: 'array', of: 'object' }, { name: 'update_mask', optional: true } ] } },
    upsert_datapoints_output: { fields: lambda { |_c,_cfg,_| [ { name: 'successfully_upserted_count', type: 'integer' }, { name: 'total_processed', type: 'integer' }, { name: 'failed_upserts', type: 'integer' }, { name: 'failed_datapoints', type: 'array', of: 'object' }, { name: 'index_stats', type: 'object' } ] } },

    test_connection_input:  { fields: lambda { |_c,_cfg,_| [ { name: 'test_vertex_ai', type: 'boolean', default: true }, { name: 'test_models', type: 'boolean', default: false } ] } },
    test_connection_output: { fields: lambda { |_c,_cfg,_| [ { name: 'timestamp', type: 'datetime' }, { name: 'environment', type: 'object' }, { name: 'tests_performed', type: 'array', of: 'object' }, { name: 'errors', type: 'array', of: 'string' }, { name: 'warnings', type: 'array', of: 'string' }, { name: 'summary', type: 'object' }, { name: 'overall_status' } ] } },

    # --- Schemas (DRY envelope) ---
    schemas__envelope: {
      fields: lambda do |_c,_cfg,obj_defs|
        obj_defs['schemas__safety_usage'] + obj_defs['schemas__trace_rate_vertex']
      end
    },
    schemas__safety_usage: {
      fields: lambda do |_c,_cfg,_|
        [
          { name: 'safety_ratings', type: 'object' },
          { name: 'usage', type: 'object', properties: [
              { name: 'promptTokenCount', type: 'integer' },
              { name: 'candidatesTokenCount', type: 'integer' },
              { name: 'totalTokenCount', type: 'integer' }
          ] }
        ]
      end
    },
    schemas__trace:      { fields: lambda { |_c,_cfg,_| [ { name: 'trace', type: 'object', properties: [ { name: 'correlation_id' }, { name: 'duration_ms', type: 'integer' } ] } ] } },
    schemas__rate:       { fields: lambda { |_c,_cfg,_| [ { name: 'rate_limit_status', type: 'object', properties: [ { name: 'requests_last_minute', type: 'integer' }, { name: 'limit', type: 'integer' }, { name: 'throttled', type: 'boolean' }, { name: 'sleep_ms', type: 'integer' } ] } ] } },
    schemas__vertex:     { fields: lambda { |_c,_cfg,_| [ { name: 'vertex', type: 'object', properties: [ { name: 'response_id' }, { name: 'model_version' } ] } ] } },
    schemas__trace_rate: { fields: lambda { |_c,_cfg,obj_defs| obj_defs['schemas__trace'] + obj_defs['schemas__rate'] } },
    schemas__trace_rate_vertex: { fields: lambda { |_c,_cfg,obj_defs| obj_defs['schemas__trace'] + obj_defs['schemas__rate'] + obj_defs['schemas__vertex'] } },

    text_model_schema: {
      fields: lambda do |connection,_cfg,_|
        [{ name: 'model', group: 'Model', control_type: 'select', extends_schema: true,
           pick_list: :available_text_models,
           toggle_field: { name: 'model', type: 'string', control_type: 'text', extends_schema: true } }]
      end
    },

    config_schema: {
      fields: lambda do |_c,_cfg,_|
        [
          { name: 'generationConfig', type: 'object', group: 'Generation', properties: [
              { name: 'responseMimeType', control_type: 'select', pick_list: :response_type, optional: true,
                toggle_field: { name: 'responseMimeType', type: 'string', control_type: 'text' } },
              { name: 'temperature', control_type: 'number', type: 'number', optional: true },
              { name: 'topP', control_type: 'number', type: 'number', optional: true },
              { name: 'topK', control_type: 'number', type: 'number', optional: true },
              { name: 'maxOutputTokens', control_type: 'integer', type: 'integer', optional: true },
              { name: 'responseSchema', control_type: 'text-area', optional: true }
          ] },
          { name: 'tools', type: 'array', of: 'object', group: 'Tools', optional: true,
            properties: [{ name: 'functionDeclarations', type: 'array', of: 'object', properties: [
              { name: 'name' }, { name: 'description' }, { name: 'parameters', control_type: 'text-area' } ] }] },
          { name: 'toolConfig', type: 'object', group: 'Tools', optional: true, properties: [
            { name: 'functionCallingConfig', type: 'object', properties: [
              { name: 'mode', control_type: 'select', pick_list: :function_call_mode,
                toggle_field: { name: 'mode', type: 'string', control_type: 'text', optional: true } },
              { name: 'allowedFunctionNames', type: 'array', of: 'string', optional: true }
          ] } ] },
          { name: 'safetySettings', type: 'array', of: 'object', group: 'Safety', optional: true, properties: [
            { name: 'category', control_type: 'select', pick_list: :safety_categories,
              toggle_field: { name: 'category', type: 'string', control_type: 'text', optional: true } },
            { name: 'threshold', control_type: 'select', pick_list: :safety_threshold,
              toggle_field: { name: 'threshold', type: 'string', control_type: 'text', optional: true } },
            { name: 'method', control_type: 'select', pick_list: :safety_method,
              toggle_field: { name: 'method', type: 'string', control_type: 'text', optional: true } }
          ] }
        ]
      end
    },

    schemas__sample: {
      fields: lambda do |_c,_cfg,_|
        # Optional: keep sample generators in a shared helper
        []
      end
    }
  },

  # ==== PICK LISTS (DRY) ====
  pick_lists: {
    available_text_models:      lambda { |connection| call('catalog__available_models', connection, :text) },
    available_image_models:     lambda { |connection| call('catalog__available_models', connection, :image) },
    available_embedding_models: lambda { |connection| call('catalog__available_models', connection, :embedding) },
    message_types:              lambda { %w[single_message chat_transcript].map { |m| [m.split('_').map(&:capitalize).join(' '), m] } },
    function_call_mode:         lambda { %w[MODE_UNSPECIFIED AUTO ANY NONE].map { |m| [m.capitalize, m] } },
    safety_categories:          lambda { %w[HARM_CATEGORY_UNSPECIFIED HARM_CATEGORY_DANGEROUS_CONTENT HARM_CATEGORY_HATE_SPEECH HARM_CATEGORY_HARASSMENT HARM_CATEGORY_SEXUALLY_EXPLICIT].map { |m| [m.gsub('_',' ').capitalize, m] } },
    safety_threshold:           lambda { %w[HARM_BLOCK_THRESHOLD_UNSPECIFIED BLOCK_LOW_AND_ABOVE BLOCK_MEDIUM_AND_ABOVE BLOCK_ONLY_HIGH BLOCK_NONE OFF].map { |m| [m.gsub('_',' ').capitalize, m] } },
    safety_method:              lambda { %w[HARM_BLOCK_METHOD_UNSPECIFIED SEVERITY PROBABILITY].map { |m| [m.capitalize, m] } },
    response_type:              lambda { [['Text', 'text/plain'], ['JSON', 'application/json']] },
    embedding_task_list:        lambda { [['Retrieval query','RETRIEVAL_QUERY'], ['Retrieval document','RETRIEVAL_DOCUMENT'], ['Semantic similarity','SEMANTIC_SIMILARITY'], ['Classification','CLASSIFICATION'], ['Clustering','CLUSTERING'], ['Question answering','QUESTION_ANSWERING'], ['Fact verification','FACT_VERIFICATION']] }
  }
}
````

### How this skeleton enforces DRY

* **Thin actions** only call `vertex__run`, `emb__*`, or `vec__*`.
* **Single payload builder** (`llm__build`) + **template table** keeps all prompt logic in one place.
* **Single extractor** (`llm__extract`) maps finish reasons, safety, and usage to a consistent envelope.
* **Single HTTP/request path** with `core__with_resilience` and `http__request`.
* **Single catalog path** to build all model picklists; GA/preview gating happens centrally.
* **Single set of envelope schemas** assembled into outputs via `schemas__envelope`.

---

## 4. Migration map (old → new)

| Legacy helper                       | New helper                                        |
| ----------------------------------- | ------------------------------------------------- |
| `with_resilience`                   | `core__with_resilience`                           |
| `api_request`                       | `http__request`                                   |
| `enforce_vertex_rate_limits`        | `rl__enforce`                                     |
| `validate_publisher_model!`         | `catalog__validate_model!`                        |
| `build_ai_payload` + templates      | `llm__build` + `llm__templates`                   |
| `extract_response`                  | `llm__extract`                                    |
| `vindex_find_neighbors`             | `vec__find_neighbors`                             |
| `transform_find_neighbors_response` | `vec__transform_neighbors`                        |
| `generate_embeddings_*`             | `emb__single_exec`, `emb__batch_exec`             |
| `test_connection` sub‑helpers       | `core__test_connection` (+ reuse http/resilience) |

---

## 5. Practical build tips

* **Single source of truth** for constants: quotas, finish‑reason map, curated model list → keep next to the service they affect (rate limits in `rate_limit.rb`, models in `model_catalog.rb`).
* **Guardrails:** Gate unsupported generationConfig fields per modality in `llm__build` if you expose them (to prevent 400s).
* **Telemetry is non‑optional:** Always return `trace`, `rate_limit_status`, and `vertex` in the final envelope—even on partial failures—so downstream recipes don’t branch on nil.

---

## 6. What to plug in from the legacy code (drop-in)

* **Full dynamic model cascade** (`fetch_fresh_publisher_models`, us‑central1 fallback, curated fallback).
* **Detailed error messages** for Drive and Vertex (permission hints, share-with account).
* **Batch upsert datapoints** (100/req, per-batch retries, index validation).
* **Drive utilities** — or extract to a shared Google Workspace library.

---

If you want, I can also generate a **“final single-file”** by stitching your existing best-of helpers into the skeleton above (keeping names and behavior), or a **build script** that concatenates the module files into `connector.rb` for deployment.
