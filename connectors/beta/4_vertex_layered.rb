{
  title: 'Vertex AI',
  
  # ============================================
  # CONNECTION & AUTHENTICATION
  # ============================================
  connection: {
    fields: [
      # Google Cloud Configuration
      { name: 'project', label: 'Project ID', group: 'Google Cloud Platform', optional: false },
      { name: 'region',  label: 'Region',     group: 'Google Cloud Platform', optional: false, control_type: 'select', 
        options: [ 
          ['US central 1', 'us-central1'],
          ['US east 1', 'us-east1'],
          ['US east 4', 'us-east4'],
          ['US east 5', 'us-east5'],
          ['US west 1', 'us-west1'],
          ['US west 4', 'us-west4'],
          ['US south 1', 'us-south1'],
        ]},
      # Service Account Authentication
      { name: 'service_account_email', label: 'Service Account Email', optional: false },
      { name: 'client_id', label: 'Client ID', optional: false },
      { name: 'private_key', label: 'Private Key', control_type: 'password', multiline: true, optional: false },
      
      # Optional Configurations
      { name: 'vector_search_endpoint', label: 'Vector Search Endpoint', optional: true, 
        hint: 'Required only for vector search operations' },
      
      # Default Behaviors
      { name: 'default_model', label: 'Default Model', control_type: 'select', 
        options: ['all_models'], optional: true },
      { name: 'optimization_mode', label: 'Optimization Mode', control_type: 'select',
        options: [['Balanced', 'balanced'], ['Cost', 'cost'], ['Performance', 'performance']],
        default: 'balanced' },
      { name: 'enable_caching', label: 'Enable Response Caching', control_type: 'checkbox', default: true },
      { name: 'enable_logging', label: 'Enable Debug Logging', control_type: 'checkbox', default: false }
    ],
    
    authorization: {
      type: 'custom_auth',
      
      acquire: lambda do |connection|
        jwt_claim = {
          'iat' => now.to_i,
          'exp' => 1.hour.from_now.to_i,
          'aud' => 'https://oauth2.googleapis.com/token',
          'iss' => connection['service_account_email'],
          'sub' => connection['service_account_email'],
          'scope' => 'https://www.googleapis.com/auth/cloud-platform'
        }
        
        private_key = connection['private_key'].gsub('\\n', "\n")
        jwt_token = workato.jwt_encode(jwt_claim, private_key, 'RS256', kid: connection['client_id'])
        
        response = post('https://oauth2.googleapis.com/token',
          grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          assertion: jwt_token
        ).request_format_www_form_urlencoded
        
        { access_token: response['access_token'] }
      end,
      
      refresh_on: [401],
      
      apply: lambda do |connection|
        headers(Authorization: "Bearer #{connection['access_token']}")
      end
    },
    
    base_uri: lambda do |connection|
      "https://#{connection['region']}-aiplatform.googleapis.com/"
    end
  },
  
  test: lambda do |connection|
    get("v1/projects/#{connection['project']}/locations/#{connection['region']}")
    true
  rescue => e
    error("Connection failed: #{e.message}")
  end,

  # ============================================
  # ACTIONS
  # ============================================
  actions: {
    # Primary Universal Action
    vertex_operation: {
      title: 'Vertex AI Operation',
      
      config_fields: [
        {
          name: 'behavior',
          label: 'Operation Type',
          control_type: 'select',
          pick_list: 'available_behaviors',
          optional: false,
          extends_schema: true,
          hint: 'Select the AI operation to perform'
        },
        {
          name: 'advanced_config',
          label: 'Show Advanced Configuration',
          control_type: 'checkbox',
          extends_schema: true
        }
      ],
      
      input_fields: lambda do |object_definitions, connection, config_fields|
        behavior = config_fields['behavior']
        
        # Get behavior-specific fields
        call('get_behavior_input_fields', behavior, config_fields['advanced_config'])
      end,
      
      output_fields: lambda do |_object_definitions, _connection, config_fields|
        base = [
          { name: 'success', type: 'boolean' },
          { name: 'timestamp', type: 'datetime' },
          { name: 'metadata', type: 'object', properties: [
            { name: 'operation' },
            { name: 'model' }
          ]},
          { name: 'trace', type: 'object', properties: [
            { name: 'correlation_id' },
            { name: 'duration_ms', type: 'integer' },
            { name: 'attempt', type: 'integer' }
          ]}
        ]

        behavior_fields = call('get_behavior_output_fields', config_fields['behavior'])
        base + behavior_fields
      end,
      
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        behavior     = config_fields['behavior']
        user_config  = call('extract_user_config', input, config_fields['advanced_config'])
        safe_input   = call('deep_copy', input) # do NOT mutate Workato’s input

        # Leave advanced fields in safe_input; pipeline reads only what it needs
        call('execute_behavior', connection, behavior, safe_input, user_config)
      end,

      sample_output: lambda do |_connection, config_fields|
        case config_fields['behavior']
        when 'text.generate'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.generate", "model"=>"gemini-1.5-flash" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "result"=>"Hello world." }
        when 'text.translate'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.translate", "model"=>"gemini-1.5-flash" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "result"=>"Hola mundo.", "detected_language"=>"en" }
        when 'text.summarize'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.summarize", "model"=>"gemini-1.5-flash" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "result"=>"Concise summary.", "word_count"=>2 }
        when 'text.classify'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.classify", "model"=>"gemini-1.5-flash" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "category"=>"Support", "confidence"=>0.98 }
        when 'text.embed'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"text.embed", "model"=>"text-embedding-004" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "embeddings"=>[[0.01,0.02,0.03]] }
        when 'multimodal.analyze'
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"multimodal.analyze", "model"=>"gemini-1.5-pro" },
            "trace"=>{ "correlation_id"=>"abc", "duration_ms"=>42, "attempt"=>1 },
            "result"=>"The image shows a tabby cat on a desk." }
        else
          { "success"=>true, "timestamp"=>"2025-01-01T00:00:00Z",
            "metadata"=>{ "operation"=>"unknown", "model"=>"gemini-1.5-flash" } }
        end
      end
    },
    
    # Batch Operation Action
    batch_operation: {
      title: 'Batch AI Operation',
      
      config_fields: [
        {
          name: 'behavior',
          label: 'Operation Type',
          control_type: 'select',
          pick_list: 'batchable_behaviors',
          optional: false
        },
        {
          name: 'batch_strategy',
          label: 'Batch Strategy',
          control_type: 'select',
          pick_list: [['By Count', 'count'], ['By Token Limit', 'tokens']],
          default: 'count'
        }
      ],
      
      input_fields: lambda do |object_definitions|
        [
          { name: 'items', type: 'array', of: 'object', properties: 
            call('get_behavior_input_fields', 'text.embed', false)
          },
          { name: 'batch_size', type: 'integer', default: 10, hint: 'Items per batch' }
        ]
      end,
      
      execute: lambda do |connection, input, input_schema, output_schema, config_fields|
        call('execute_batch_behavior', 
          connection, 
          config_fields['behavior'],
          input['items'],
          input['batch_size'],
          config_fields['batch_strategy']
        )
      end,
      output_fields: lambda do |_obj, _conn, _cfg|
        [
          { name: 'success', type: 'boolean' },
          { name: 'results', type: 'array', of: 'object' }, # behavior-shaped items
          { name: 'errors',  type: 'array', of: 'object', properties: [
            { name: 'batch', type: 'array', of: 'object' },
            { name: 'error' }
          ]},
          { name: 'total_processed', type: 'integer' },
          { name: 'total_errors', type: 'integer' }
        ]
      end,
      sample_output: lambda do |_conn, cfg|
        if cfg['behavior'] == 'text.embed'
          {
            "success"=>true,
            "results"=>[
              { "embeddings"=>[[0.01,0.02],[0.03,0.04]] }
            ],
            "errors"=>[],
            "total_processed"=>2,
            "total_errors"=>0
          }
        else
          {
            "success"=>true,
            "results"=>[],
            "errors"=>[],
            "total_processed"=>0,
            "total_errors"=>0
          }
        end
      end
    }
  },

  # ============================================
  # METHODS - LAYERED ARCHITECTURE
  # ============================================
  methods: {
    # ============================================
    # LAYER 1: CORE METHODS (Foundation)
    # ============================================
    
    # Payload Building
    build_payload: lambda do |template:, variables:, format:|
      case format
      when 'direct'
        variables
      when 'template'
        result = template.dup
        variables.each { |k, v| result = result.gsub("{#{k}}", v.to_s) }
        result
      when 'vertex_prompt'
        contents = [{
          'role' => 'user',
          'parts' => [{ 'text' => call('apply_template', template, variables) }]
        }]
        
        # Add system instruction if present
        if variables['system']
          contents.unshift({
            'role' => 'model',
            'parts' => [{ 'text' => variables['system'] }]
          })
        end
        
        {
          'contents' => contents,
          'generationConfig' => {
            'temperature' => variables['temperature'] || 0.7,
            'maxOutputTokens' => variables['max_tokens'] || 2048,
            'topP' => variables['top_p'] || 0.95,
            'topK' => variables['top_k'] || 40
          }.compact
        }
      when 'embedding'
        {
          'instances' => variables['texts'].map { |text|
            {
              'content' => text,
              'task_type' => variables['task_type'] || 'RETRIEVAL_DOCUMENT'
            }
          }
        }
      when 'multimodal'
        parts = []
        parts << { 'text' => variables['text'] } if variables['text']
        
        if variables['images']
          variables['images'].each do |img|
            parts << {
              'inline_data' => {
                'mime_type' => img['mime_type'] || 'image/jpeg',
                'data' => img['data']
              }
            }
          end
        end
        
        {
          'contents' => [{
            'role' => 'user',
            'parts' => parts
          }],
          'generationConfig' => call('build_generation_config', variables)
        }
      else
        variables
      end
    end,
    
    # Response Enrichment
    enrich_response: lambda do |response:, metadata: {}|
      enriched = response.is_a?(Hash) ? response.dup : { 'result' => response }
      
      enriched['success'] = true
      enriched['timestamp'] = Time.now.iso8601
      enriched['metadata'] = metadata
      
      # Add trace if present
      if response.is_a?(Hash) && response['_trace']
        enriched['trace'] = response.delete('_trace')
      end
      
      enriched
    end,

    # Response Extraction
    extract_response: lambda do |data:, path: nil, format: 'raw'|
      case format
      when 'raw'
        data
      when 'json_field'
        return data unless path
        result = data
        path.split('.').each do |segment|
          if segment.match?(/^\d+$/)
            result = result[segment.to_i]
          else
            result = result[segment]
          end
          break unless result
        end
        result
      when 'vertex_text'
        data.dig('candidates', 0, 'content', 'parts', 0, 'text') || 
        data.dig('predictions', 0, 'content')
      when 'vertex_json'
        text = data.dig('candidates', 0, 'content', 'parts', 0, 'text')
        return {} unless text
        
        # Extract JSON from markdown code blocks if present
        json_match = text.match(/```(?:json)?\n?(.*?)\n?```/m) || text.match(/\{.*\}/m)
        return {} unless json_match
        
        JSON.parse(json_match[1] || json_match[0]) rescue {}
      when 'embeddings'
        data['predictions']&.map { |p| p['embeddings'] || p['values'] }&.compact || []
      else
        data
      end
    end,

    # HTTP Request Execution
    http_request: lambda do |connection, method:, url:, payload: nil, headers: {}, retry_config: {}|
      retries = retry_config['max_retries'] || 3
      backoff = retry_config['backoff'] || 1.0
      
      retries.times do |attempt|
        begin
          headers['X-Correlation-Id'] ||= "#{Time.now.to_i}-#{rand(1000)}"
          start_time = Time.now
          
          response = 
            case method.to_s.upcase
            when 'GET'    then get(url).headers(headers)
            when 'POST'   then post(url, payload).headers(headers)
            when 'PUT'    then put(url, payload).headers(headers)
            when 'DELETE' then delete(url).headers(headers)
            # Guard for errors
            else
              error("Unsupported HTTP method: #{method}")
            end
          
          # Add trace metadata and preserve it - don't mutate
          body = resp.is_a?(Hash) ? resp.dup : { 'raw' => resp }
          body['_trace'] = {
            'correlation_id'  => headers['X-Correlation-Id'],
            'duration_ms'     => ((Time.now - start_time) * 1000).round,
            'attempt'         => attempt + 1
          }
          
          return body
        rescue => e
          raise e if attempt >= retries - 1
          sleep(backoff * (2 ** attempt))
        end
      end
    end,

    # Data Transformation
    transform_data: lambda do |input:, from_format:, to_format:|
      case "#{from_format}_to_#{to_format}"
      when 'url_to_base64'
        response = get(input)
        response.body.encode_base64
      when 'base64_to_bytes'
        input.decode_base64
      when 'language_code_to_name'
        languages = { 'en' => 'English', 'es' => 'Spanish', 'fr' => 'French' }
        languages[input] || input
      when 'categories_to_text'
        input.map { |c| "#{c['name']}: #{c['description']}" }.join("\n")
      when 'distance_to_similarity'
        1.0 - (input.to_f / 2.0)
      else
        input
      end
    end,
    
    # Input Validation
    validate_input: lambda do |data:, schema: [], constraints: []|
      errors = []
      
      # Schema validation
      schema.each do |field|
        field_name = field['name']
        field_value = data[field_name]
        
        # Required check
        if field['required'] && (field_value.nil? || field_value.to_s.empty?)
          errors << "#{field_name} is required"
        end
        
        # Length validation
        if field['max_length'] && field_value.to_s.length > field['max_length']
          errors << "#{field_name} exceeds maximum length of #{field['max_length']}"
        end
        
        # Pattern validation
        if field['pattern'] && field_value && !field_value.match?(Regexp.new(field['pattern']))
          errors << "#{field_name} format is invalid"
        end
      end
      
      # Constraint validation
      constraints.each do |constraint|
        case constraint['type']
        when 'min_value'
          value = data[constraint['field']].to_f
          if value < constraint['value']
            errors << "#{constraint['field']} must be at least #{constraint['value']}"
          end
        when 'max_items'
          items = data[constraint['field']] || []
          if items.size > constraint['value']
            errors << "#{constraint['field']} cannot exceed #{constraint['value']} items"
          end
        end
      end
      
      error(errors.join('; ')) if errors.any?
      true
    end,
    
    # Error Recovery
    with_resilience: lambda do |operation:, config: {}, &block|
      # Rate limiting
      if config['rate_limit']
        call('check_rate_limit', operation, config['rate_limit'])
      end
      
      # Circuit breaker
      circuit_key = "circuit_#{operation}"
      circuit_state = workato.cache.get(circuit_key) || { 'failures' => 0 }
      
      if circuit_state['failures'] >= 5
        error("Circuit breaker open for #{operation}. Too many recent failures.")
      end
      
      begin
        result = block.call
        
        # Reset circuit on success
        workato.cache.set(circuit_key, { 'failures' => 0 }, 300)
        result
        
      rescue => e
        # Update circuit breaker
        circuit_state['failures'] += 1
        workato.cache.set(circuit_key, circuit_state, 300)
        
        # Determine if retryable
        if e.message.match?(/rate limit|quota/i)
          sleep(60)
          retry
        elsif e.message.match?(/timeout|unavailable/i) && circuit_state['failures'] < 3
          sleep(5)
          retry
        else
          raise e
        end
      end
    end,

    
    # ============================================
    # LAYER 2: UNIVERSAL PIPELINE
    # ============================================
    
    execute_pipeline: lambda do |connection, operation, input, config|
      # Don't mutate the input
      local = call('deep_copy', input)

      # 1. Validate
      if config['validate']
        call('validate_input',
          data:         local,
          schema:       config['validate']['schema'] || [],
          constraints:  config['validate']['constraints'] || []
        )
      end
      
      # 2. Transform input
      if config['transform_input']
        config['transform_input'].each do |field, transform|
          if input[field]
            local[field] = call('transform_data',
              input:        local[field],
              from_format:  transform['from'],
              to_format:    transform['to']
            )
          end
        end
      end
      
      # 3. Build payload
      payload = if config['payload']
        call('build_payload',
          template:   config['payload']['template'] || '',
          variables:  local.merge('system' => config['payload']['system']),
          format:     config['payload']['format'] || 'direct'
        )
      else
        local
      end
      
      # 4. Build URL
      endpoint  = config['endpoint'] || {}
      url       = call('build_endpoint_url', connection, endpoint, local)
      
      # 5. Execute with resilience
      response = call('with_resilience',
        operation:  operation,
        config:     config['resilience'] || {}
      ) do
        call('http_request',
          connection,
          method:   endpoint['method'] || 'POST',
          url:      url,
          payload:  payload,
          headers:  call('build_headers', connection)
        )
      end
      
      # 6. Extract response
      extracted = if config['extract']
        call('extract_response',
          data:   response,
          path:   config['extract']['path'],
          format: config['extract']['format'] || 'raw'
        )
      else
        response
      end
      
      # 7. Post-process
      if config['post_process']
        extracted = call(config['post_process'], extracted, local)
      end
      
      # 8. Enrich
      call('enrich_response',
        response: extracted,
        metadata: { 'operation' => operation, 'model' => config['model'] || local['model'] }
      )
    end,
    
    # ============================================
    # LAYER 3: BEHAVIOR & CONFIGURATION
    # ============================================
    
    # Behavior Registry - Catalog of capabilities
    behavior_registry: lambda do
      {
        # Text Operations
        'text.generate' => {
          description: 'Generate text from a prompt',
          capability: 'generation',
          supported_models: ['gemini-1.5-flash', 'gemini-1.5-pro'],
          features: ['streaming', 'caching'],
          config_template: {
            'payload' => {
              'format' => 'vertex_prompt',
              'template' => '{prompt}',
              'system' => nil
            },
            'endpoint' => {
              'path' => ':generateContent',
              'method' => 'POST'
            },
            'extract' => {
              'format' => 'vertex_text'
            }
          }
        },
        
        'text.translate' => {
          description: 'Translate text between languages',
          capability: 'generation',
          supported_models: ['gemini-1.5-flash', 'gemini-1.5-pro'],
          features: ['caching', 'batching'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'text', 'required' => true, 'max_length' => 10000 },
                { 'name' => 'target_language', 'required' => true }
              ]
            },
            'transform_input' => {
              'source_language' => { 'from' => 'language_code', 'to' => 'name' },
              'target_language' => { 'from' => 'language_code', 'to' => 'name' }
            },
            'payload' => {
              'format' => 'vertex_prompt',
              'template' => 'Translate the following text from {source_language} to {target_language}. Return only the translation:\n\n{text}',
              'system' => 'You are a professional translator. Maintain tone and context.'
            },
            'endpoint' => {
              'path' => ':generateContent',
              'method' => 'POST'
            },
            'extract' => {
              'format' => 'vertex_text'
            }
          },
          defaults: {
            'temperature' => 0.3,
            'max_tokens' => 2048
          }
        },
        
        'text.summarize' => {
          description: 'Summarize text content',
          capability: 'generation',
          supported_models: ['gemini-1.5-flash', 'gemini-1.5-pro'],
          features: ['caching'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'text', 'required' => true },
                { 'name' => 'max_words', 'required' => false }
              ]
            },
            'payload' => {
              'format' => 'vertex_prompt',
              'template' => 'Summarize the following text in {max_words} words:\n\n{text}',
              'system' => 'You are an expert at creating clear, concise summaries.'
            },
            'endpoint' => {
              'path' => ':generateContent'
            },
            'extract' => {
              'format' => 'vertex_text'
            },
            'post_process' => 'add_word_count'
          },
          defaults: {
            'temperature' => 0.5,
            'max_words' => 200
          }
        },
        
        'text.classify' => {
          description: 'Classify text into categories',
          capability: 'generation',
          supported_models: ['gemini-1.5-flash', 'gemini-1.5-pro'],
          features: ['caching', 'batching'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'text', 'required' => true },
                { 'name' => 'categories', 'required' => true }
              ]
            },
            'transform_input' => {
              'categories' => { 'from' => 'categories', 'to' => 'text' }
            },
            'payload' => {
              'format' => 'vertex_prompt',
              'template' => 'Classify this text into one of these categories:\n{categories}\n\nText: {text}\n\nRespond with JSON: {"category": "name", "confidence": 0.0-1.0}',
              'system' => 'You are a classification expert. Always return valid JSON.'
            },
            'endpoint' => {
              'path' => ':generateContent'
            },
            'extract' => {
              'format' => 'vertex_json'
            }
          },
          defaults: {
            'temperature' => 0.1
          }
        },
        
        # Embedding Operations
        'text.embed' => {
          description: 'Generate text embeddings',
          capability: 'embedding',
          supported_models: ['text-embedding-004', 'textembedding-gecko'],
          features: ['batching', 'caching'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'texts', 'required' => true }
              ],
              'constraints' => [
                { 'type' => 'max_items', 'field' => 'texts', 'value' => 100 }
              ]
            },
            'payload' => {
              'format' => 'embedding'
            },
            'endpoint' => {
              'path' => ':predict',
              'method' => 'POST'
            },
            'extract' => {
              'format' => 'embeddings'
            }
          }
        },
        
        # Multimodal Operations
        'multimodal.analyze' => {
          description: 'Analyze images with text prompts',
          capability: 'generation',
          supported_models: ['gemini-1.5-pro', 'gemini-1.5-flash'],
          features: ['streaming'],
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'prompt', 'required' => true },
                { 'name' => 'images', 'required' => true }
              ]
            },
            'payload' => {
              'format' => 'multimodal'
            },
            'endpoint' => {
              'path' => ':generateContent'
            },
            'extract' => {
              'format' => 'vertex_text'
            }
          }
        }
        
        # Add more behaviors as needed...
      }
    end,
    
    # Configuration Registry - User preferences
    configuration_registry: lambda do |connection, user_config|
      {
        # Model selection
        models: {
          default: user_config['model'] || connection['default_model'] || 'gemini-1.5-flash',
          strategy: connection['optimization_mode'] || 'balanced'
        },
        
        # Generation settings
        generation: {
          temperature: user_config['temperature'],
          max_tokens: user_config['max_tokens'],
          top_p: user_config['top_p'],
          top_k: user_config['top_k']
        }.compact,
        
        # Features
        features: {
          caching: {
            enabled: connection['enable_caching'] != false,
            ttl: user_config['cache_ttl'] || 300
          },
          logging: {
            enabled: connection['enable_logging'] == true
          }
        },
        
        # Execution
        execution: {
          retry: {
            max_attempts: 3,
            backoff: 1.0
          },
          rate_limit: {
            rpm: 60
          }
        }
      }
    end,
    
    # Main execution method combining all layers
    execute_behavior: lambda do |connection, behavior, input, user_config = {}|
      # Get behavior definition
      behavior_def = call('behavior_registry')[behavior]
      unless behavior_def
        error("Unknown behavior: #{behavior}")
      end
      
      # Get user configuration
      config = call('configuration_registry', connection, user_config)
      
      # Build operation configuration
      operation_config = behavior_def[:config_template].deep_dup || {}
      
      # Apply defaults
      if behavior_def[:defaults]
        behavior_def[:defaults].each do |key, value|
          input[key] ||= value
        end
      end
      
      # Apply user configuration
      if config[:generation]
        input.merge!(config[:generation])
      end
      
      # Select model
      operation_config['model'] = call('select_model', 
        behavior_def, 
        config, 
        input
      )
      
      # Add resilience config
      operation_config['resilience'] = config[:execution]
      
      # Cache if enabled
      if config[:features][:caching][:enabled]
        cache_key = "vertex_#{behavior}_#{input.to_json.hash}"
        cached = workato.cache.get(cache_key)
        return cached if cached
      end
      
      # Execute through pipeline
      result = call('execute_pipeline', connection, behavior, input, operation_config)
      
      # Cache result
      if config[:features][:caching][:enabled]
        workato.cache.set(cache_key, result, config[:features][:caching][:ttl])
      end
      
      result
    end,
    
    # ============================================
    # HELPER METHODS
    # ============================================
    
    # Post-processing methods
    add_word_count: lambda do |response, input|
      if response.is_a?(String)
        { 
          'result' => response,
          'word_count' => response.split.size
        }
      else
        response['word_count'] = response['result'].to_s.split.size
        response
      end
    end,
    
    # Template application
    apply_template: lambda do |template, variables|
      return template unless template && variables
      
      result = template.dup
      variables.each do |key, value|
        result = result.gsub("{#{key}}", value.to_s)
      end
      result
    end,

    # Build endpoint URL
    build_endpoint_url: lambda do |connection, endpoint_config, input|
      base_url = "https://#{connection['region']}-aiplatform.googleapis.com/v1"
      
      # Determine model path
      model = input['model'] || 'gemini-1.5-flash'
      model_mappings = {
        'gemini-1.5-flash' => 'gemini-1.5-flash-002',
        'gemini-1.5-pro' => 'gemini-1.5-pro-002',
        'text-embedding-004' => 'text-embedding-004',
        'textembedding-gecko' => 'textembedding-gecko@003'
      }
      
      model_id = model_mappings[model] || model
      model_path = "projects/#{connection['project']}/locations/#{connection['region']}/publishers/google/models/#{model_id}"
      
      # Handle special endpoints
      if endpoint_config['custom_path']
        endpoint_config['custom_path']
          .gsub('{project}', connection['project'])
          .gsub('{region}', connection['region'])
          .gsub('{endpoint}', connection['vector_search_endpoint'] || '')
      else
        "#{base_url}/#{model_path}#{endpoint_config['path'] || ':generateContent'}"
      end
    end,
    
    # Build request headers
    build_headers: lambda do |connection|
      {
        'Content-Type' => 'application/json',
        'X-Goog-User-Project' => connection['project']
      }
    end,

    # Rate limiting
    check_rate_limit: lambda do |operation, limits|
      cache_key = "rate_#{operation}_#{Time.now.to_i / 60}"
      current = workato.cache.get(cache_key) || 0
      
      if current >= limits['rpm']
        error("Rate limit exceeded for #{operation}. Please wait before retrying.")
      end
      
      workato.cache.set(cache_key, current + 1, 60)
    end,

    coerce_kwargs: lambda do |*args, **kwargs| # ::TODO:: implement
      if kwargs.empty? && args.last.is_a?(Hash)
        h = args.pop
        h = h.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
        kwargs = h
      end
      [args, kwargs]
    end,
    
    # Safely duplicate object
    deep_copy: lambda { |obj| JSON.parse(JSON.dump(obj)) },

    # Extract user configuration safely
    extract_user_config: lambda do |input, cfg_enabled|
      return {} unless cfg_enabled
      {
        'model'      => input['model_override'],
        'temperature'=> input['temperature'],
        'max_tokens' => input['max_tokens'],
        'cache_ttl'  => input['cache_ttl']
      }.compact
    end,
  
    # Batch execution
    execute_batch_behavior: lambda do |connection, behavior, items, batch_size, strategy|
      results = []
      errors = []
      
      # Process in batches
      items.each_slice(batch_size) do |batch|
        begin
          # Execute batch based on strategy
          batch_result = if behavior.include?('embed')
            # Embeddings can be truly batched
            call('execute_behavior', connection, behavior, { 'texts' => batch.map { |item| item['text'] } })
          else
            # Other operations need individual processing
            batch.map do |item|
              call('execute_behavior', connection, behavior, item)
            end
          end
          
          results.concat(Array.wrap(batch_result))
        rescue => e
          errors << { 'batch' => batch, 'error' => e.message }
        end
      end
      
      {
        'success' => errors.empty?,
        'results' => results,
        'errors' => errors,
        'total_processed' => results.size,
        'total_errors' => errors.size
      }
    end,
  
    # Get behavior input fields dynamically
    get_behavior_input_fields: lambda do |behavior, show_advanced|
      behavior_def = call('behavior_registry')[behavior]
      return [] unless behavior_def
      
      # Map behavior to input fields
      fields = case behavior
      when 'text.generate'
        [
          { name: 'prompt', label: 'Prompt', control_type: 'text-area', optional: false }
        ]
      when 'text.translate'
        [
          { name: 'text', label: 'Text to Translate', control_type: 'text-area', optional: false },
          { name: 'target_language', label: 'Target Language', control_type: 'select', 
            pick_list: 'languages', optional: false },
          { name: 'source_language', label: 'Source Language', control_type: 'select', 
            pick_list: 'languages', optional: true, hint: 'Leave blank for auto-detection' }
        ]
      when 'text.summarize'
        [
          { name: 'text', label: 'Text to Summarize', control_type: 'text-area', optional: false },
          { name: 'max_words', label: 'Maximum Words', type: 'integer', default: 200 }
        ]
      when 'text.classify'
        [
          { name: 'text', label: 'Text to Classify', control_type: 'text-area', optional: false },
          { name: 'categories', label: 'Categories', type: 'array', of: 'object', properties: [
            { name: 'name', label: 'Category Name' },
            { name: 'description', label: 'Description' }
          ]}
        ]
      when 'text.embed'
        [
          { name: 'texts', label: 'Texts to Embed', type: 'array', of: 'string' },
          { name: 'task_type', label: 'Task Type', control_type: 'select', pick_list: 'embedding_tasks' }
        ]
      when 'multimodal.analyze'
        [
          { name: 'prompt', label: 'Analysis Prompt', control_type: 'text-area', optional: false },
          { name: 'images', label: 'Images', type: 'array', of: 'object', properties: [
            { name: 'data', label: 'Image Data (Base64)', control_type: 'text-area' },
            { name: 'mime_type', label: 'MIME Type', default: 'image/jpeg' }
          ]}
        ]
      else
        []
      end
      
      # Add advanced fields if requested
      if show_advanced
        fields += [
          { name: 'model_override', label: 'Override Model', control_type: 'select', 
            pick_list: 'models_for_behavior', pick_list_params: { behavior: behavior }, optional: true },
          { name: 'temperature', label: 'Temperature', type: 'number', hint: '0.0 to 1.0' },
          { name: 'max_tokens', label: 'Max Tokens', type: 'integer' },
          { name: 'cache_ttl', label: 'Cache TTL (seconds)', type: 'integer', default: 300 }
        ]
      end
      
      fields
    end,
    
    # Get behavior output fields
    get_behavior_output_fields: lambda do |behavior|
      case behavior
      when 'text.generate'
        [{ name: 'result', label: 'Generated Text' }]
      when 'text.translate'
        [
          { name: 'result', label: 'Translated Text' },
          { name: 'detected_language', label: 'Detected Source Language' }
        ]
      when 'text.summarize'
        [
          { name: 'result', label: 'Summary' },
          { name: 'word_count', type: 'integer' }
        ]
      when 'text.classify'
        [
          { name: 'category', label: 'Selected Category' },
          { name: 'confidence', type: 'number' }
        ]
      when 'text.embed'
        [{ name: 'embeddings', type: 'array', of: 'array' }]
      when 'multimodal.analyze'
        [{ name: 'result', label: 'Analysis' }]
      else
        [{ name: 'result' }]
      end
    end,

    # Model selection logic
    select_model: lambda do |behavior_def, config, input|
      # Explicit model in input takes precedence
      return input['model'] if input['model']
      
      # Use configured default
      model = config[:models][:default]
      
      # Ensure model supports the behavior
      unless behavior_def[:supported_models].include?(model)
        model = behavior_def[:supported_models].first
      end
      
      model
    end,
  },

  # ============================================
  # PICK LISTS
  # ============================================
  pick_lists: {
    gcp_regions: lambda do |connection|
      [
        ['US Central 1', 'us-central1'],
        ['US East 1', 'us-east1'],
        ['US East 4', 'us-east4'],
        ['US West 1', 'us-west1'],
        ['US West 4', 'us-west4']
      ]
    end,
    
    available_behaviors: lambda do |connection|
      behaviors = call('behavior_registry')
      behaviors.map do |key, config|
        [config[:description], key]
      end.sort_by { |label, _| label }
    end,
    
    batchable_behaviors: lambda do |connection|
      behaviors = call('behavior_registry')
      behaviors.select { |_, config| 
        config[:features]&.include?('batching') 
      }.map { |key, config|
        [config[:description], key]
      }
    end,
    
    all_models: lambda do |connection|
      [
        ['Gemini 1.5 Flash', 'gemini-1.5-flash'],
        ['Gemini 1.5 Pro', 'gemini-1.5-pro'],
        ['Text Embedding 004', 'text-embedding-004'],
        ['Text Embedding Gecko', 'textembedding-gecko']
      ]
    end,
    
    models_for_behavior: lambda do |connection, input = {}|
      behavior = input['behavior']
      defn = call('behavior_registry')[behavior]
      next [] unless defn && defn[:supported_models]

      defn[:supported_models].map do |model|
        [model.split('-').map!(&:capitalize).join(' '), model]
      end
    end,
    
    languages: lambda do |connection|
      [
        ['Auto-detect', 'auto'],
        ['English', 'en'],
        ['Spanish', 'es'],
        ['French', 'fr'],
        ['German', 'de'],
        ['Italian', 'it'],
        ['Portuguese', 'pt'],
        ['Japanese', 'ja'],
        ['Korean', 'ko'],
        ['Chinese (Simplified)', 'zh-CN'],
        ['Chinese (Traditional)', 'zh-TW']
      ]
    end,
    
    embedding_tasks: lambda do |connection|
      [
        ['Document Retrieval', 'RETRIEVAL_DOCUMENT'],
        ['Query Retrieval', 'RETRIEVAL_QUERY'],
        ['Semantic Similarity', 'SEMANTIC_SIMILARITY'],
        ['Classification', 'CLASSIFICATION'],
        ['Clustering', 'CLUSTERING']
      ]
    end,

    safety_levels: lambda do |_connection|
      [
        ['Block none',   'BLOCK_NONE'],
        ['Block low',    'BLOCK_LOW'],
        ['Block medium', 'BLOCK_MEDIUM'],
        ['Block high',   'BLOCK_HIGH']
      ]
    end

  },

  # ============================================
  # OBJECT DEFINITIONS (Reusable Schemas)
  # ============================================
  object_definitions: {
    generation_config: {
      fields: lambda do |connection|
        [
          { name: 'temperature', type: 'number', hint: 'Controls randomness (0-1)' },
          { name: 'max_tokens', type: 'integer', hint: 'Maximum response length' },
          { name: 'top_p', type: 'number', hint: 'Nucleus sampling' },
          { name: 'top_k', type: 'integer', hint: 'Top-k sampling' },
          { name: 'stop_sequences', type: 'array', of: 'string', hint: 'Stop generation at these sequences' }
        ]
      end
    },
    
    safety_settings: {
      fields: lambda do |connection|
        [
          { name: 'harassment', control_type: 'select', pick_list: 'safety_levels' },
          { name: 'hate_speech', control_type: 'select', pick_list: 'safety_levels' },
          { name: 'sexually_explicit', control_type: 'select', pick_list: 'safety_levels' },
          { name: 'dangerous_content', control_type: 'select', pick_list: 'safety_levels' }
        ]
      end
    }
  },

  # ============================================
  # TRIGGERS (if needed)
  # ============================================
  triggers: {},
  
  # ============================================
  # CUSTOM ACTION SUPPORT
  # ============================================
  custom_action: true,
  custom_action_help: {
    body: 'Create custom Vertex AI operations using the established connection'
  }
}