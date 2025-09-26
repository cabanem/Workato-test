{
  title: 'Vertex AI',

  connection: {
    # Base connection fields; do not use pick_lists here, use "options"
    fields: [
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
      { name: 'service_account_email',  label: 'Service Account Email', group: 'Service Account', optional: false },
      { name: 'client_id',              label: 'Client ID',             group: 'Service Account', optional: false },
      { name: 'private_key',            label: 'Private Key',           group: 'Service Account', optional: false, control_type: 'password', multiline: true },
      { name: 'vector_search_endpoint', label: 'Vector Search Endpoint',group: 'Vector Search',   optional: true }
    ],
    # Enables the display of additional fields based on connection type
    extended_fields: lambda do |connection|
      # Array
    end,
    authorization: {
      type: 'custom_auth',
      acquire: lambda do |connection|
        jwt_body_claim = {
          'iat' => now.to_i,
          'exp' => 1.hour.from_now.to_i,
          'aud' => 'https://oauth2.googleapis.com/token',
          'iss' => connection['service_account_email'],
          'sub' => connection['service_account_email'],
          'scope' => 'https://www.googleapis.com/auth/cloud-platform'
        }
        private_key = connection['private_key'].gsub('\\n', "\n")
        jwt_token =
          workato.jwt_encode(jwt_body_claim,
                              private_key, 'RS256',
                              kid: connection['client_id'])

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
  # Establish connection validity, should emit bool True if connection exists
  test: lambda do |connection|
    # Test with a simple API call to verify authentication
    get("https://#{connection['region']}-aiplatform.googleapis.com/v1/projects/#{connection['project']}/locations/#{connection['region']}")
    true
  rescue => e
    error("Connection failed: #{e.message}")
  end,

  # ---------------------------------------------------------------------------
  # Custom Action
  # Allows user to quickly define custom actions using established connection
  # ---------------------------------------------------------------------------
  custom_action: true, # boolean
  custom_action_help: {
    learn_more_url:   '',
    learn_more_text:  '',
    body:             ''
  },

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------
  actions: {
    ai_operation: {
      title: 'AI Operation',
      
      # Configuration
      config_fields: [
        {
          name: 'operation',
          label: 'Operation Type',
          control_type: 'select',
          pick_list: 'operation_types',
          optional: false,
          extends_schema: true,
          hint: 'Select the AI operation to perform'
        }
      ],
      # Input
      input_fields: lambda do |object_definitions, connection, config_fields|
        # Operation from action configuration
        operation = config_fields['operation']
        
        # Common to all operations
        base_fields = [
          { 
            name: 'model',
            label: 'Model',
            control_type: 'select',
            pick_list: 'model_list',
            default: 'gemini-1.5-flash',
            hint: 'Select the Vertex AI model'
          }
        ]
        
        # Add operation-specific fields
        case operation
        when 'translate'
          base_fields + [
            { name: 'text', label: 'Text to Translate', control_type: 'text-area', optional: false },
            { name: 'source_language', label: 'Source Language', pick_list: 'language_codes', optional: true },
            { name: 'target_language', label: 'Target Language', pick_list: 'language_codes', optional: false }
          ]
        when 'summarize'
          base_fields + [
            { name: 'text', label: 'Text to Summarize', control_type: 'text-area', optional: false },
            { name: 'max_length', label: 'Max Summary Length', type: 'integer', default: 500 },
            { name: 'style', label: 'Summary Style', pick_list: 'summary_styles' }
          ]
        when 'classify'
          base_fields + [
            { name: 'text', label: 'Text to Classify', control_type: 'text-area', optional: false },
            { name: 'categories', label: 'Categories', type: 'array', of: 'object', properties: [
              { name: 'name', label: 'Category Name' },
              { name: 'description', label: 'Description' }
            ]}
          ]
        when 'embed'
          base_fields + [
            { name: 'texts', label: 'Texts to Embed', type: 'array', of: 'string' },
            { name: 'task_type', label: 'Task Type', pick_list: 'embedding_tasks' }
          ]
        else
          base_fields + [
            { name: 'prompt', label: 'Custom Prompt', control_type: 'text-area' }
          ]
        end
      end,
      # Output
      output_fields: lambda do |object_definitions, connection, config_fields|
        operation = config_fields['operation']
        
        # Base output fields
        base_output = [
          { name: 'success', type: 'boolean' },
          { name: 'timestamp', type: 'datetime' }
        ]
        
        # Operation-specific outputs
        case operation
        when 'translate'
          base_output + [
            { name: 'translated_text', label: 'Translated Text' },
            { name: 'detected_language', label: 'Detected Source Language' }
          ]
        when 'summarize'
          base_output + [
            { name: 'summary', label: 'Summary' },
            { name: 'word_count', type: 'integer' }
          ]
        when 'classify'
          base_output + [
            { name: 'category', label: 'Selected Category' },
            { name: 'confidence', type: 'number', label: 'Confidence Score' },
            { name: 'alternatives', type: 'array', of: 'object', properties: [
              { name: 'category' },
              { name: 'confidence', type: 'number' }
            ]}
          ]
        when 'embed'
          base_output + [
            { name: 'embeddings', type: 'array', of: 'array' }
          ]
        else
          base_output + [
            { name: 'response', label: 'AI Response' }
          ]
        end
      end,
      # Execute
      execute: lambda do |connection, input, input_schema, output_schema, config_fields|
        operation = config_fields['operation']
        
        # Execute using the generic method
        result = call('execute_vertex_request', connection, operation, input)
        
        # Add operation-specific post-processing if needed
        case operation
        when 'translate'
          result['word_count'] = result['translated_text'].to_s.split.size
        when 'summarize'
          result['word_count'] = result['summary'].to_s.split.size
        end
        
        result
      rescue => e
        error("Operation failed: #{e.message}")
      end
    },
    test_connection_details: {
      title: 'Test Connection (Debug)',
      
      execute: lambda do |connection|
        {
          project: connection['project'],
          region: connection['region'],
          service_account: connection['service_account_email'],
          auth_test: begin
            get("https://#{connection['region']}-aiplatform.googleapis.com/v1/projects/#{connection['project']}/locations/#{connection['region']}")
            'Success'
          rescue => e
            "Failed: #{e.message}"
          end,
          availabel_models: [
            'gemini-1.5-flash',
            'gemini-1.5-pro'
          ]
        }
      end
    }
  },

  # ---------------------------------------------------------------------------
  # Triggers
  # ---------------------------------------------------------------------------
  triggers: {},

  # ---------------------------------------------------------------------------
  # Object Definitions
  # ---------------------------------------------------------------------------
  object_definitions: {
    # Store reusable field configurations
    text_input: {
      fields: lambda do |connection, config_fields|
        [
          {
            name: 'text',
            control_type: 'text-area',
            optional: false,
            hint: 'Text to process'
          }
        ]
      end
    },
    
    safety_settings: {
      fields: lambda do |connection, config_fields|
        [
          { name: 'category', control_type: 'select', pick_list: 'safety_categories' },
          { name: 'threshold', control_type: 'select', pick_list: 'safety_thresholds' }
        ]
      end
    },
    
    trace_schema: {
      fields: lambda do
        [
          { name: 'correlation_id', type: 'string' },
          { name: 'duration_ms', type: 'integer' }
        ]
      end
    },
    
    # Operation-specific schemas
    translate_schema: {
      fields: lambda do |connection, config_fields|
        call('operation_fields', 'translate')
      end
    }
  },

  # ---------------------------------------------------------------------------
  # Pick Lists
  # ---------------------------------------------------------------------------
  pick_lists: {
    operation_types: lambda do |connection|
      [
        ['Translate Text', 'translate'],
        ['Summarize Text', 'summarize'],
        ['Classify Text', 'classify'],
        ['Generate Embeddings', 'embed'],
        ['Custom Prompt', 'custom']
      ]
    end,
    
    model_list: lambda do |connection|
      [
        ['Gemini 1.5 Flash', 'gemini-1.5-flash'],
        ['Gemini 1.5 Pro', 'gemini-1.5-pro'],
        ['Text Bison', 'text-bison'],
        ['Text Embedding Gecko', 'textembedding-gecko']
      ]
    end,
    
    language_codes: lambda do |connection|
      [
        ['Auto-detect', 'auto'],
        ['English', 'en'],
        ['Spanish', 'es'],
        ['French', 'fr'],
        ['German', 'de'],
        ['Italian', 'it'],
        ['Portuguese', 'pt'],
        ['Japanese', 'ja'],
        ['Chinese (Simplified)', 'zh-CN'],
        ['Korean', 'ko']
      ]
    end,
    
    summary_styles: lambda do |connection|
      [
        ['Concise', 'concise'],
        ['Detailed', 'detailed'],
        ['Bullet Points', 'bullets'],
        ['Executive Summary', 'executive']
      ]
    end,
    
    embedding_tasks: lambda do |connection|
      [
        ['Retrieval Query', 'RETRIEVAL_QUERY'],
        ['Retrieval Document', 'RETRIEVAL_DOCUMENT'],
        ['Semantic Similarity', 'SEMANTIC_SIMILARITY'],
        ['Classification', 'CLASSIFICATION'],
        ['Clustering', 'CLUSTERING']
      ]
    end
  },
  # ---------------------------------------------------------------------------
  # Methods
  # ---------------------------------------------------------------------------
  methods: {
    # ----- FUNDAMENTAL -----
    execute_vertex_request: lambda do |connection, operation, input|
      config = call('get_operation_config', connection, operation)

      # Validate input
      if config['validate']
        call('validate_input', connection, input, config['validate'])
      end

      # Build the url
      model = input['model'] || 'gemini-1.5-flash'

      # Handle variants of model name 
      model_path = input['model'] || 'projects/{project}/locations/{region}/publishers/google/models/gemini-1.5-flash'
      model_path = model_path.gsub('{project}', connection['project'])
                            .gsub('{region}', connection['region'])
      
      url = "https://#{connection['region']}-aiplatform.googleapis.com/v1/#{model_path}#{config.dig('endpoint', 'path')}"

      # Build payload
      payload = call('build_payload', connection, config, input)

      # Execute with resilience
      response = call('http_request', connection, 'POST', url, payload)

      # Extract and enrich
      extracted = call('extract_response', connection, response, config['extract'])
      call('enrich_response', connection, extracted)
    end,
    handle_vertex_error: lambda do |connection, error_response|
      error_data = error_response.is_a?(Hash) ? error_response : {}
      error_code = error_data.dig('error', 'code')
      error_message = error_data.dig('error', 'message') || 'Unknown error'
      
      case error_code
      when 400
        error("Bad Request: #{error_message}")
      when 401
        error("Authentication failed. Check your service account credentials.")
      when 403
        error("Permission denied. Ensure service account has Vertex AI permissions.")
      when 429
        error("Rate limit exceeded. Please retry after some time.")
      when 500..599
        error("Vertex AI service error: #{error_message}")
      else
        error("API Error: #{error_message}")
      end
    end,

    # ----- CORE METHODS -----
    # 1. HTTP Request Execution
    http_request: lambda do |connection, method, url, payload=nil, headers={}, retry_config={}|
      # Universal HTTP handler with built-in resilience
      retries = retry_config['max_retries'] || 3
      backoff = retry_config['backoff'] || 1.0
      
      retries.times do |attempt|
        begin
          # Add correlation ID
          headers['X-Correlation-Id'] ||= "#{Time.now.to_i}-#{rand(1000)}"
          start_time = Time.now
          
          # Execute request
          response = case method.to_s.upcase
          when 'GET'
            get(url).headers(headers)
          when 'POST'  
            post(url, payload).headers(headers)
          when 'PUT'
            put(url, payload).headers(headers)
          when 'DELETE'
            delete(url).headers(headers)
          end
          
          # Add trace metadata
          response['_trace'] = {
            'correlation_id' => headers['X-Correlation-Id'],
            'duration_ms' => ((Time.now - start_time) * 1000).round
          }
          
          return response
        rescue => e
          raise e if attempt >= retries - 1
          sleep(backoff * (2 ** attempt))
        end
      end
    end,
    
    # 2. Payload Building
    build_payload: lambda do |connection, config, input|
      format = config.dig('payload', 'format')
      template_or_lambda = config.dig('payload', 'template')
      system = config.dig('payload', 'system')
      
      case format
      when 'vertex_prompt'
        # Handle lambda templates
        prompt_text = if template_or_lambda.respond_to?(:call)
          template_or_lambda.call(input)
        else
          # String template with substitution
          text = template_or_lambda
          input.each { |k, v| text = text.gsub("{#{k}}", v.to_s) }
          text
        end
        
        {
          'contents' => [{
            'role' => 'user',
            'parts' => [{ 'text' => prompt_text }]
          }],
          'generationConfig' => {
            'temperature' => input['temperature'] || 0.7,
            'maxOutputTokens' => input['max_tokens'] || 2048,
            'topP' => 0.95,
            'topK' => 40
          }
        }
      when 'simple_json'
        input
      when 'batch_array'
        { 'instances' => input['items'] || input['texts'] }
      else
        input
      end
    end,
    
    # 3. Response Extraction
    extract_response: lambda do |connection, data, extract_config|
      return data unless extract_config
      
      format = extract_config['format']
      path = extract_config['path']
      
      case format
      when 'json_field'
        result = data
        path.split('.').each { |key| result = result[key] if result }
        result
      when 'vertex_text'
        data.dig('candidates', 0, 'content', 'parts', 0, 'text')
      when 'vertex_json'
        text = data.dig('candidates', 0, 'content', 'parts', 0, 'text')
        return {} unless text
        json_text = text.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip
        JSON.parse(json_text) rescue {}
      when 'array_map'
        field = extract_config['field']
        (data[path] || []).map { |item| item[field] }
      else
        data
      end
    end,
    
    # 4. Error Recovery
    with_resilience: lambda do |operation:, config: {}, &block|
      # Implements rate limiting, circuit breaker, retries
      
      # Rate limit check
      if config['rate_limit']
        call('check_rate_limit', 
          resource: operation,
          limit: config['rate_limit']['rpm'] || 60
        )
      end
      
      # Circuit breaker check
      circuit_key = "circuit_#{operation}"
      circuit_state = workato.cache.get(circuit_key) || { 'failures' => 0 }
      
      if circuit_state['failures'] >= 5
        error("Circuit breaker open for #{operation}")
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
        raise e
      end
    end,
    
    # 5. Data Transformation
    transform_data: lambda do |input:, from_format:, to_format:|
      case "#{from_format}_to_#{to_format}"
      when 'url_to_id'
        # Extract Google Drive ID from URL
        if match = input.match(/\/d\/([a-zA-Z0-9_-]+)/)
          match[1]
        else
          input
        end
        
      when 'text_to_base64'
        input.encode_base64
        
      when 'distance_to_similarity'
        # Convert distance to similarity score
        1.0 - (input.to_f / 2.0)
        
      when 'categories_to_text'
        # Format categories for prompt
        input.map { |c| "#{c['key']}: #{c['description']}" }.join("\n")
        
      else
        input
      end
    end,
    
    # 6. Input Validation  
    validate_input: lambda do |connection, data, validation_config|
      errors = []
      
      schema = validation_config['schema']
      constraints = validation_config['constraints']
      
      if schema
        schema.each do |field|
          if field['required'] && data[field['name']].nil?
            errors << "#{field['name']} is required"
          end
          
          if field['max_length'] && data[field['name']].to_s.length > field['max_length']
            errors << "#{field['name']} exceeds max length"
          end
        end
      end
      
      if constraints
        constraints.each do |constraint|
          case constraint['type']
          when 'regex'
            unless data[constraint['field']].to_s.match?(Regexp.new(constraint['pattern']))
              errors << constraint['message']
            end
          when 'range'
            value = data[constraint['field']].to_f
            if value < constraint['min'] || value > constraint['max']
              errors << constraint['message']
            end
          end
        end
      end
      
      error(errors.join('; ')) if errors.any?
      true
    end,
    
    # 7. Batch Processing
    process_batch: lambda do |items:, batch_size:, processor:, aggregator: nil|
      results = []
      errors = []
      
      items.each_slice(batch_size) do |batch|
        begin
          batch_result = processor.call(batch)
          results << batch_result
        rescue => e
          errors << { 'batch' => batch, 'error' => e.message }
        end
      end
      
      # Aggregate results if aggregator provided
      if aggregator
        aggregator.call(results, errors)
      else
        { 'results' => results, 'errors' => errors }
      end
    end,
    
    # 8. Metadata Enrichment
    enrich_response: lambda do |connection, response, metadata = {}|
      enriched = response.is_a?(Hash) ? response.dup : { 'result' => response }
      
      enriched['success'] = true
      enriched['timestamp'] = Time.now.iso8601
      
      if response.is_a?(Hash) && response['_trace']
        enriched['trace'] = response.delete('_trace')
      end
      
      metadata.each do |key, value|
        enriched[key] = value unless key == 'success'
      end
      
      enriched
    end,

    # ---- CONFIGURATION REGISTRY -----
    # Operation configurations as data
    get_operation_config: lambda do |connection, operation|
      base_url = "https://#{connection['region']}-aiplatform.googleapis.com/v1"
      project_path = "projects/#{connection['project']}/locations/#{connection['region']}"
      
      configs = {
        'translate' => {
          'endpoint' => { 
            'path' => ':generateContent',
            'method' => 'POST'
          },
          'payload' => {
            'format' => 'vertex_prompt',
            'template' => lambda do |input|
              source = input['source_language'] == 'auto' ? '' : "from #{input['source_language']} "
              "Translate the following text #{source}to #{input['target_language']}. Return ONLY the translation:\n\n#{input['text']}"
            end,
            'system' => 'You are a professional translator. Provide accurate translations while preserving tone and context.'
          }
        },
        
        'summarize' => {
          'endpoint' => { 
            'path' => ':generateContent',
            'method' => 'POST'
          },
          'payload' => {
            'format' => 'vertex_prompt',
            'template' => lambda do |input|
              style_instructions = {
                'concise' => 'in 2-3 sentences',
                'detailed' => 'in a comprehensive paragraph',
                'bullets' => 'as bullet points',
                'executive' => 'as an executive summary'
              }
              
              "Summarize the following text #{style_instructions[input['style'] || 'concise']} (max #{input['max_length']} words):\n\n#{input['text']}"
            end,
            'system' => 'You are an expert at creating clear, accurate summaries.'
          }
        },
        
        'classify' => {
          'endpoint' => {
            'path' => ':generateContent',
            'method' => 'POST'
          },
          'payload' => {
            'format' => 'vertex_prompt',
            'template' => lambda do |input|
              categories_text = input['categories'].map { |c| 
                "- #{c['name']}: #{c['description']}" 
              }.join("\n")
              
              "Classify the following text into one of these categories:\n#{categories_text}\n\nText: #{input['text']}\n\nReturn JSON: {\"category\": \"name\", \"confidence\": 0.0-1.0, \"alternatives\": []}"
            end,
            'system' => 'You are a classification expert. Always return valid JSON.'
          },
          'extract' => {
            'format' => 'vertex_json'
          }
        }
      }
      
      configs[operation] || {}
    end, 
    
    # ----- ENDPOINTS ----
    # Vertex
    # base = region}-aiplatform.googleapis.com	
    # /v1/projects/{p}/locations/{l}/publishers/google/models/{m}:generateContent
    # /v1/projects/{p}/locations/{l}/publishers/google/models/{m}:predict
    # /v1/projects/{p}/locations/{l}/indexes/{i}:upsertDatapoints
    # Query Vector
    # base = custom
    # /v1/projects/{p}/locations/{l}/indexEndpoints/{e}:findNeighbors
  },

  # ---------------------------------------------------------------------------
  # Secure Tunnel
  # ---------------------------------------------------------------------------
  secure_tunnel: false,

  # ---------------------------------------------------------------------------
  # Streams
  # ---------------------------------------------------------------------------
  streams: {}
}
