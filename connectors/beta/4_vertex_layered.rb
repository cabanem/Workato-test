{
  title: 'Vertex AI',
  
  # ============================================
  # CONNECTION & AUTHENTICATION
  # ============================================
  connection: {
    fields: [
      # Authentication type
      { name: 'auth_type', label: 'Authentication type', group: 'Authentication', control_type: 'select', default: 'custom',
        optional: false, extends_schema: true, hint: 'Select the authentication type for connecting to Google Vertex AI.',
        options: [ ['Service account (JWT)', 'custom'], ['OAuth 2.0 (Auth code)', 'oauth2'] ]},
      # Google Cloud Configuration
      { name: 'project', label: 'Project ID', group: 'Google Cloud Platform', optional: false },
      { name: 'region',  label: 'Region',     group: 'Google Cloud Platform', optional: false, control_type: 'select', 
        options: [
          ['Global', 'global'],
          ['US central 1', 'us-central1'],
          ['US east 1', 'us-east1'],
          ['US east 4', 'us-east4'],
          ['US east 5', 'us-east5'],
          ['US west 1', 'us-west1'],
          ['US west 4', 'us-west4'],
          ['US south 1', 'us-south1'],
        ],
        hint: 'Vertex AI region for model execution.',
        toggle_hint: 'Select from list',
        toggle_field: {
          name: 'region',
          label: 'Region',
          type: 'string',
          control_type: 'text',
          optional: false,
          toggle_hint: 'Use custom value',
          hint: "See Vertex AI locations docs for allowed regions."
        }
      },
      { name: 'version', label: 'API version', group: 'Google Cloud Platform', optional: false, default: 'v1', hint: 'e.g. v1beta1' },
      
      # Optional Configurations
      { name: 'vector_search_endpoint', label: 'Vector Search Endpoint', optional: true, hint: 'Public Vector Search domain host for queries' },
      
      # Default Behaviors
      { name: 'default_model', label: 'Default Model', control_type: 'select',
        options: [
          ['Gemini 1.5 Flash', 'gemini-1.5-flash'],
          ['Gemini 1.5 Pro',   'gemini-1.5-pro'],
          ['Text Embedding 004', 'text-embedding-004'],
          ['Text Embedding Gecko', 'textembedding-gecko']
        ],
        optional: true },
      { name: 'optimization_mode', label: 'Optimization Mode', control_type: 'select',
        options: [['Balanced', 'balanced'], ['Cost', 'cost'], ['Performance', 'performance']],
        default: 'balanced' },
      { name: 'enable_caching', label: 'Enable Response Caching', control_type: 'checkbox', default: true },
      { name: 'enable_logging', label: 'Enable Debug Logging', control_type: 'checkbox', default: false }
    ],
    
    authorization: {
      type: 'multi',
      selected: lambda do |connection|
        connection['auth_type'] || 'custom'
      end,
      identity: lambda do |connection|
        selected = connection['auth_type'] || 'custom'

        if selected == 'oauth2'
          # Uses OAuth2 access token added by `apply` to call Google’s standard UserInfo endpoint
          begin
            info = get('https://openidconnect.googleapis.com/v1/userinfo')
                    .after_error_response(/.*/) { |code, _body, _h, msg| error("Failed to fetch user info (#{code}): #{msg}") }
                    .after_response { |_code, body, _h| body || {} }

            email = info['email'] || '(no email)'
            name  = info['name']
            sub   = info['sub']
            [name, email, sub].compact.join(' / ')
          rescue
            'OAuth2 (Google) – identity unavailable'
          end
        else
          # Service account (JWT)
          connection['service_account_email']
        end
      end,
      options: {
        oauth2: {
          type: 'oauth2',
          fields: [
            { name: 'client_id', label: 'Client ID', group: 'OAuth 2.0', optional: false },
            { name: 'client_secret', label: 'Client Secret', group: 'OAuth 2.0', optional: false, control_type: 'password' },
            { name: 'oauth_refresh_token_ttl', label: 'Refresh token TTL (seconds)', group: 'OAuth 2.0', type: 'integer', optional: true,
              hint: 'Used only if Google does not return refresh_token_expires_in; enables background refresh.' }
          ],
          # AUTH URL
          authorization_url: lambda do |connection|
            scopes = [
              'https://www.googleapis.com/auth/cloud-platform',
              'openid', 'email', 'profile' # needed for /userinfo claims
            ].join(' ')

            params = {
              client_id: connection['client_id'],
              response_type: 'code',
              scope: scopes,
              access_type: 'offline',
              include_granted_scopes: 'true',
              prompt: 'consent'
            }.to_param

            "https://accounts.google.com/o/oauth2/v2/auth?#{params}"
          end,
          # ACQUIRE
          acquire: lambda do |connection, auth_code|
            response = post('https://oauth2.googleapis.com/token').
                        payload(
                          client_id: connection['client_id'],
                          client_secret: connection['client_secret'],
                          grant_type: 'authorization_code',
                          code: auth_code,
                          redirect_uri: 'https://www.workato.com/oauth/callback'
                        ).request_format_www_form_urlencoded

            # Pick Google’s TTL if present; else use user-configured fallback when provided
            ttl = response['refresh_token_expires_in'] || connection['oauth_refresh_token_ttl']

            [
              {
                access_token: response['access_token'],
                refresh_token: response['refresh_token'],
                refresh_token_expires_in: ttl # may be nil if neither is present; that’s OK
              },
              nil,               # owner id (optional)
              {}                 # extra connection state (optional)
            ]
          end,
          # REFRESH
          refresh: lambda do |connection, refresh_token|
            response = post('https://oauth2.googleapis.com/token').
                        payload(
                          client_id: connection['client_id'],
                          client_secret: connection['client_secret'],
                          grant_type: 'refresh_token',
                          refresh_token: refresh_token
                        ).request_format_www_form_urlencoded

            {
              access_token: response['access_token'],
              # Google sometimes rotates refresh tokens; include if present
              refresh_token: response['refresh_token'],
              # Prefer Google’s TTL, else use the user-configured fallback if present
              refresh_token_expires_in: response['refresh_token_expires_in'] || connection['oauth_refresh_token_ttl']
            }.compact
          end,
          # APPLY
          apply: lambda do |_connection, access_token|
            headers(Authorization: "Bearer #{access_token}")
          end
        },
        custom: {
          type: 'custom_auth',
          fields: [
            { name: 'service_account_email', label: 'Service Account Email', group: 'Service Account', optional: false },
            { name: 'client_id', label: 'Client ID', group: 'Service Account', optional: false },
            { name: 'private_key_id', label: 'Private Key ID', group: 'Service Account', optional: false },
            { name: 'private_key', label: 'Private Key', group: 'Service Account', optional: false, multiline: true, control_type: 'password' }
          ],
          acquire: lambda do |connection|
            issued_at = Time.now.to_i
            jwt_body_claim = {
              'iat'   => issued_at,
              'exp'   => issued_at + 3600, # 60 minutes
              'aud'   => 'https://oauth2.googleapis.com/token',
              'iss'   => connection['service_account_email'],
              #'sub'   => connection['service_account_email'], # only required for domain-wide delegation
              'scope' => 'https://www.googleapis.com/auth/cloud-platform'
            }
            private_key = connection['private_key'].to_s.gsub('\\n', "\n")
            jwt_token   = workato.jwt_encode(jwt_body_claim, private_key, 'RS256', kid: connection['private_key_id'])

            response    = post('https://oauth2.googleapis.com/token',
                            grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                            assertion: jwt_token). request_format_www_form_urlencoded

            { access_token: response['access_token'], expires_at: (Time.now + response['expires_in'].to_i).iso8601 }
          end,
          refresh_on: [401],
          apply: lambda do |connection|
            headers(Authorization: "Bearer #{connection['access_token']}")
          end
        }
      }
    },
    
    base_uri: lambda do |connection|
      version = (connection['version'].presence || 'v1').to_s
      region  = (connection['region'].presence  || 'us-east4').to_s

      host = (region == 'global') ? 'aiplatform.googleapis.com' : "#{region}-aiplatform.googleapis.com"
      "https://#{host}/#{version}/"
    end
  },
  
  test: lambda do |connection|
    project = connection['project']
    region = connection['region']

    # 1. Validate token + API enablement via global publisher catalog (absolute URL, independent of region, base URI)
    call('list_publisher_models', connection) # raises on non 2xx

    # 2. Validate regional host, prjoect access via cheap GET
    parent = "projects/#{project}/locations/#{region}"
    call('http_request',
      connection,
      method:   'GET',
      url:      "#{parent}/endpoints",
      headers:  call('build_headers', connection))

    true
  rescue => e
    msg = e.message

    if msg.include?('(404)')
      error("Connection failed (404). Regional endpoint or resource not found for region '#{region}'. "\
            "Verify that the specified region is supported for this type of request. Details: #{msg}")
    elsif msg.include?('(403)') || msg =~ /PERMISSION/i
      error("Connection failed (403). Token is valid but lacks permission, OR the Vertex AI API may not be "\
            "enabled for this project. Verify the roles and access available for this service account. "\
            "Details: #{msg}")
    else
      error("Connection failed: #{msg}")
    end
  end,

  # ============================================
  # ACTIONS
  # ============================================
  # Listed alphabetically within each subsection.
  actions: {

    # ------------------------------------------
    # CORE
    # ------------------------------------------
    # Batch Operation Action
    batch_operation: {
      title: 'UNIVERSAL - Batch AI Operation',
      # CONFIG
      config_fields: [
        { name: 'behavior', label: 'Operation Type', control_type: 'select', pick_list: 'batchable_behaviors', optional: false },
        { name: 'batch_strategy', label: 'Batch Strategy', control_type: 'select', default: 'count',
          options: [['By Count', 'count'], ['By Token Limit', 'tokens']] }
      ],
      # INPUT
      input_fields: lambda do |object_definitions|
        [
          { name: 'items', type: 'array', of: 'object', properties: [
              { name: 'text', label: 'Text', optional: false },
              { name: 'task_type', label: 'Task Type', control_type: 'select', pick_list: 'embedding_tasks' }
          ]},
          { name: 'batch_size', type: 'integer', default: 10, hint: 'Items per batch' }
        ]
      end,
      # EXECUTE
      execute: lambda do |connection, input, input_schema, output_schema, config_fields|
        call('execute_batch_behavior', 
          connection, 
          config_fields['behavior'],
          input['items'],
          input['batch_size'],
          config_fields['batch_strategy']
        )
      end,
      # OUTPUT
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
      # SAMPLE
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
    },

    # Universal Action
    vertex_operation: {
      title: 'UNIVERSAL - Vertex AI Operation',
      # CONFIG
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
        { name: 'advanced_config', label: 'Show Advanced Configuration', control_type: 'checkbox', extends_schema: true, optional: true, default: false }
      ],
      # INPUT
      input_fields: lambda do |object_definitions, connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        behavior = cfg['behavior']
        behavior ? call('get_behavior_input_fields', behavior, cfg['advanced_config']) : []
      end,
      # OUTPUT
      output_fields: lambda do |_object_definitions, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
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
        base + (call('get_behavior_output_fields', cfg['behavior']) || [])
      end,
      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        behavior     = config_fields['behavior']
        user_config  = call('extract_user_config', input, config_fields['advanced_config'])
        safe_input   = call('deep_copy', input) # do NOT mutate Workato’s input

        # Leave advanced fields in safe_input; pipeline reads only what it needs
        call('execute_behavior', connection, behavior, safe_input, user_config)
      end,
      # SAMPLE
      sample_output: lambda do |_connection, config_fields|
        behavior = (config_fields.is_a?(Hash) ? config_fields : {})['behavior']
        case behavior
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

    # ------------------------------------------
    # THIN WRAPPERS
    # ------------------------------------------
    
    classify_text: {
      title: 'AI - Classify Text',
      description: 'Classify text into one of the provided categories',

      # CONFIG
      config_fields: [
        { name: 'advanced_config', label: 'Show Advanced Configuration',
          control_type: 'checkbox', extends_schema: true, optional: true, default: false }
      ],

      # INPUT
      input_fields: lambda do |_obj_defs, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        call('get_behavior_input_fields', 'text.classify', cfg['advanced_config'])
      end,

      # OUTPUT
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        call('get_behavior_output_fields', 'text.classify').unshift(
          { name: 'success', type: 'boolean' },
          { name: 'timestamp', type: 'datetime' },
          { name: 'metadata', type: 'object', properties: [{ name: 'operation' }, { name: 'model' }] },
          { name: 'trace', type: 'object', properties: [
            { name: 'correlation_id' }, { name: 'duration_ms', type: 'integer' }, { name: 'attempt', type: 'integer' }
          ]}
        )
      end,

      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        user_cfg = call('extract_user_config', input, config_fields['advanced_config'])
        safe     = call('deep_copy', input) # never mutate Workato’s input
        call('execute_behavior', connection, 'text.classify', safe, user_cfg)
      end,

      # SAMPLE 
      sample_output: lambda do |_connection, _cfg|
        {
          "success"   => true,
          "timestamp" => Time.now.utc.iso8601,
          "metadata"  => { "operation" => "text.classify", "model" => "gemini-1.5-flash-002" },
          "trace"     => { "correlation_id" => "abc", "duration_ms" => 42, "attempt" => 1 },
          "category"  => "Support",
          "confidence"=> 0.98
        }
      end
    },

    find_neighbors: {
      title: 'VECTOR SEARCH - Find nearest neighbors',
      description: 'Query a deployed Vector Search index',
      input_fields: lambda do |_obj_defs, _connection, _cfg|
        call('get_behavior_input_fields', 'vector.find_neighbors', true)
      end,
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        call('get_behavior_output_fields', 'vector.find_neighbors').unshift(
          { name: 'success', type: 'boolean' },
          { name: 'timestamp', type: 'datetime' },
          { name: 'metadata', type: 'object', properties: [{ name: 'operation' }, { name: 'model' }] },
          { name: 'trace', type: 'object', properties: [
            { name: 'correlation_id' }, { name: 'duration_ms', type: 'integer' }, { name: 'attempt', type: 'integer' }
          ]}
        )
      end,
      execute: lambda do |connection, input, _in_schema, _out_schema, _cfg|
        call('execute_behavior', connection, 'vector.find_neighbors', call('deep_copy', input))
      end
    },

    generate_embeddings: {
      title: 'VECTOR SEARCH - Generate embeddings',
      description: 'Create dense embeddings for text',
      # CONFIG
      config_fields: [
        { name: 'advanced_config', label: 'Show Advanced Configuration', control_type: 'checkbox', extends_schema: true, optional: true, default: false }
      ],
      # INPUT
      input_fields: lambda do |_obj_defs, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        base = [
          { name: 'texts', label: 'Texts', type: 'array', of: 'string', optional: false },
          { name: 'task_type', label: 'Task type', control_type: 'select', pick_list: 'embedding_tasks', optional: true },
          { name: 'output_dimensionality', label: 'Output dimensionality', type: 'integer', optional: true, hint: 'Truncate vector length' },
          { name: 'auto_truncate', label: 'Auto-truncate long inputs', control_type: 'checkbox', optional: true }
        ]
        if cfg['advanced_config']
          base += [
            { name: 'model_override', label: 'Override Model', control_type: 'select',
              pick_list: 'models_dynamic_for_behavior', pick_list_params: { behavior: 'text.embed' }, optional: true },
            { name: 'cache_ttl', label: 'Cache TTL (seconds)', type: 'integer', default: 300 }
          ]
        end
        base
      end,
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        [
          { name: 'success', type: 'boolean' }, { name: 'timestamp', type: 'datetime' },
          { name: 'metadata', type: 'object', properties: [{ name: 'operation' }, { name: 'model' }] },
          { name: 'trace', type: 'object', properties: [
            { name: 'correlation_id' }, { name: 'duration_ms', type: 'integer' }, { name: 'attempt', type: 'integer' }
          ]},
          { name: 'embeddings', type: 'array', of: 'array' }
        ]
      end,
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        user_cfg = call('extract_user_config', input, config_fields['advanced_config'])
        safe     = call('deep_copy', input)
        call('execute_behavior', connection, 'text.embed', safe, user_cfg)
      end
    },
    
    generate_text: {
      title: 'AI - Generate Text',
      description: 'Gemini text generation',

      # CONFIG
      config_fields: [
        { name: 'advanced_config', label: 'Show Advanced Configuration', control_type: 'checkbox', extends_schema: true, optional: true, default: false }
      ],
      # INPUT
      input_fields: lambda do |_obj_defs, _connection, config_fields|
        cfg = config_fields.is_a?(Hash) ? config_fields : {}
        call('get_behavior_input_fields', 'text.generate', cfg['advanced_config'])
      end,
      # OUTPUT
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        call('get_behavior_output_fields', 'text.generate').unshift(
          { name: 'success', type: 'boolean' },
          { name: 'timestamp', type: 'datetime' },
          { name: 'metadata', type: 'object', properties: [{ name: 'operation' }, { name: 'model' }] },
          { name: 'trace', type: 'object', properties: [
            { name: 'correlation_id' }, { name: 'duration_ms', type: 'integer' }, { name: 'attempt', type: 'integer' } ]}
        )
      end,
      # EXECUTE
      execute: lambda do |connection, input, _in_schema, _out_schema, config_fields|
        user_cfg = call('extract_user_config', input, config_fields['advanced_config'])
        safe_input = call('deep_copy', input)
        call('execute_behavior', connection, 'text.generate', safe_input, user_cfg)
      end,
      # SAMPLE OUT
      sample_output: lambda do |_connection, _cfg|
        {
          "success" => true, "timestamp" => Time.now.utc.iso8601,
          "metadata" => { "operation" => "text.generate", "model" => "gemini-1.5-flash-002" },
          "trace" => { "correlation_id" => "abc", "duration_ms" => 42, "attempt" => 1 },
          "result" => "Hello world."
        }
      end
    },

    upsert_index_datapoints: {
      title: 'VECTOR SEARCH - Upsert index datapoints',
      description: 'Add or update datapoints in a Vector Search index',
      input_fields: lambda do |_obj_defs, _connection, _cfg|
        call('get_behavior_input_fields', 'vector.upsert_datapoints', true)
      end,
      output_fields: lambda do |_obj_defs, _connection, _cfg|
        call('get_behavior_output_fields', 'vector.upsert_datapoints').unshift(
          { name: 'success', type: 'boolean' },
          { name: 'timestamp', type: 'datetime' },
          { name: 'metadata', type: 'object', properties: [{ name: 'operation' }, { name: 'model' }] },
          { name: 'trace', type: 'object', properties: [
            { name: 'correlation_id' }, { name: 'duration_ms', type: 'integer' }, { name: 'attempt', type: 'integer' }
          ]}
        )
      end,
      execute: lambda do |connection, input, _in_schema, _out_schema, _cfg|
        call('execute_behavior', connection, 'vector.upsert_datapoints', call('deep_copy', input))
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
      
      # Direct
      when 'direct'
        variables
      
      # Template
      when 'template'
        result = template.dup
        variables.each { |k, v| result = result.gsub("{#{k}}", v.to_s) }
        result
      
      # Vertex prompt
      when 'vertex_prompt'
        payload = {
          'contents' => [{
            'role' => 'user',
            'parts' => [{ 'text' => call('apply_template', template, variables) }]
          }],
          'generationConfig' => call('build_generation_config', variables)
        }.compact

        # Always honor system instructions if provided (Vertex v1 supports this)
        if variables['system'].present?
          payload['systemInstruction'] = { 'parts' => [{ 'text' => variables['system'] }] }
        end

        # Optional governance knobs
        payload['safetySettings'] = variables['safety_settings'] if variables['safety_settings']
        payload['labels']         = variables['labels'] if variables['labels'] # for billing/reporting
        payload

      # Embedding
      when 'embedding'
        body = {
          'instances' => variables['texts'].map { |text|
            {
              'content'   => text,
              'task_type' => variables['task_type'] || 'RETRIEVAL_DOCUMENT',
              'title'     => variables['title']
            }.compact
          }
        }
        params = {}
        params['autoTruncate']          = variables['auto_truncate'] unless variables['auto_truncate'].nil?
        params['outputDimensionality']  = variables['output_dimensionality'] if variables['output_dimensionality']
        body['parameters'] = params unless params.empty? 
        body

      when 'find_neighbors'
        queries = Array(variables['queries']).map do |q|
          dp =
            if q['feature_vector']
              { 'feature_vector' => Array(q['feature_vector']).map(&:to_f) }
            elsif q['vector'] # alias
              { 'feature_vector' => Array(q['vector']).map(&:to_f) }
            elsif q['datapoint_id']
              { 'datapoint_id' => q['datapoint_id'] }
            else
              {}
            end
          {
            'datapoint'        => dp,
            'neighbor_count'   => (q['neighbor_count'] || variables['neighbor_count'] || 10).to_i,
            'restricts'        => q['restricts'],
            'numeric_restricts'=> q['numeric_restricts']
          }.compact
        end

        {
          'deployed_index_id'     => variables['deployed_index_id'],
          'queries'               => queries,
          'return_full_datapoint' => variables['return_full_datapoint']
        }.compact

      when 'upsert_datapoints'
        {
          'datapoints' => Array(variables['datapoints']).map do |d|
            {
              'datapointId'      => d['datapoint_id'] || d['id'],
              'featureVector'    => Array(d['feature_vector'] || d['vector']).map(&:to_f),
              'sparseEmbedding'  => d['sparse_embedding'],
              'restricts'        => d['restricts'],
              'numericRestricts' => d['numeric_restricts'],
              'crowdingTag'      => d['crowding_tag'],
              'embeddingMetadata'=> d['embedding_metadata']
            }.compact
          end
        }

      # Multimodal
      when 'multimodal'
        parts = []
        parts << { 'text' => variables['text'] } if variables['text']
        
        if variables['images']
          variables['images'].each do |img|
            parts << {
              'inLineData' => {
              'mimeType' => img['mime_type'] || 'image/jpeg',
              'data' => img['data']
              }
            }
          end
        end
        
        {
          'contents' => [{ 'role' => 'user', 'parts' => parts }],
          'generationConfig' => call('build_generation_config', variables)
        }
      else
        variables
      end
    end,
    
    # Response Enrichment
    enrich_response: lambda do |response:, metadata: {}|
      base  = response.is_a?(Hash) ? JSON.parse(JSON.dump(response)) : { 'result' => response }
      trace = base.delete('_trace')
      http  = base.delete('_http') # preserved, not exposed by default

      base.merge(
        'success'   => true,
        'timestamp' => Time.now.iso8601,
        'metadata'  => metadata,
        'trace'     => trace
      ).compact
    end,

    # Response Extraction
    extract_response: lambda do |data:, path: nil, format: 'raw'|
      case format
      # Raw data
      when 'raw' then data
      # Json field
      when 'json_field'
        return data unless path
        path.split('.').reduce(data) { |acc, seg| acc.is_a?(Array) && seg =~ /^\d+$/ ? acc[seg.to_i] : (acc || {})[seg] }
      # Vertex text
      when 'vertex_text'
        parts = data.dig('candidates', 0, 'content', 'parts') || []
        text  = parts.select { |p| p['text'] }.map { |p| p['text'] }.join
        text.empty? ? data.dig('predictions', 0, 'content').to_s : text
      # Vertex-flavored json
      when 'vertex_json'
        raw = (data.dig('candidates', 0, 'content', 'parts') || []).map { |p| p['text'] }.compact.join
        return {} if raw.nil? || raw.empty?
        m = raw.match(/```(?:json)?\s*(\{.*?\})\s*```/m) || raw.match(/\{.*\}/m)
        m ? (JSON.parse(m[1] || m[0]) rescue {}) : {}
      # Embeddings
      when 'embeddings'
        # text-embedding APIs return embeddings under predictions[].embeddings.values
        arr = (data['predictions'] || []).map { |p| p.dig('embeddings', 'values') || p['values'] }.compact
        arr
      else data
      end
    end,

    # HTTP Request Execution
    http_request: lambda do |connection, method:, url:, payload: nil, headers: {}, retry_config: {}|
      max_retries = (retry_config['max_retries'] || retry_config['max_attempts'] || 3).to_i
      backoff     = (retry_config['backoff'] || 1.0).to_f

      (1..max_retries).each do |attempt|
        begin
          hdrs = (headers || {}).dup
          corr = hdrs['X-Correlation-Id'] ||= "#{Time.now.utc.to_i}-#{SecureRandom.hex(6)}"
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          req = case method.to_s.upcase
                when 'GET'    then get(url)
                when 'POST'   then post(url, payload)
                when 'PUT'    then put(url, payload)
                when 'DELETE' then delete(url)
                else error("Unsupported HTTP method: #{method}")
                end

          response =
            req.headers(hdrs)
              .after_error_response(/.*/) { |code, body, rheaders, message|
                # normalize errors for observability
                error("#{message} (#{code}): #{body}")
              }
              .after_response { |code, body, rheaders|
                # keep response body as hash and enrich with http metadata
                body ||= {}
                body['_http'] = { 'status' => code, 'headers' => rheaders }
              }

          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          body = response.is_a?(Hash) ? response.dup : { 'raw' => response }
          body['_trace'] = { 'correlation_id' => corr, 'duration_ms' => duration_ms, 'attempt' => attempt }
          return body
        rescue => e
          raise e if attempt >= max_retries
          sleep(backoff * (2 ** (attempt - 1)))
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
    with_resilience: lambda do |operation:, config: {}, task: {}, connection: nil|
      # Rate limiting (per-job)
      if config['rate_limit']
        call('check_rate_limit', operation, config['rate_limit'])
      end

      circuit_key   = "circuit_#{operation}"
      circuit_state = call('memo_get', circuit_key) || { 'failures' => 0 }
      error("Circuit breaker open for #{operation}. Too many recent failures.") if circuit_state['failures'] >= 5

      begin
        # Validate task envelope
        error('with_resilience requires a task hash with url/method') unless task.is_a?(Hash) && task['url']

        result = call('http_request',
          connection,
          method:       (task['method'] || 'GET'),
          url:          task['url'],
          payload:      task['payload'],
          headers:      (task['headers'] || {}),
          retry_config: (task['retry_config'] || {})
        )

        # Reset circuit on success
        call('memo_put', circuit_key, { 'failures' => 0 }, 300)
        result

      rescue => e
        circuit_state['failures'] += 1
        call('memo_put', circuit_key, circuit_state, 300)

        if e.message.match?(/rate limit|quota/i)
          sleep(60)          # keep simple; consider multi‑step + reinvoke_after later
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
          if local[field]
            local[field] = call('transform_data',
              input:        local[field],
              from_format:  transform['from'],
              to_format:    transform['to']
            )
          end
        end
      end

      # -- Ensure selected model from ops config is visible to URL builder
      local['model'] ||= config['model']

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
        config:     (config['resilience'] || {}),
        task: {
          'method'       => endpoint['method'] || 'POST',
          'url'          => url,
          'payload'      => payload,
          'headers'      => call('build_headers', connection),
          'retry_config' => (config.dig('resilience', 'retry') || {})
        },
        connection: connection
      ) do
        call('http_request',
          connection,
          method:       endpoint['method'] || 'POST',
          url:          url,
          payload:      payload,
          headers:      call('build_headers', connection),
          retry_config: (config.dig('resilience', 'retry') || {})
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
        },
        
        # Vector Operations
        'vector.upsert_datapoints' => {
          description: 'Upsert datapoints into a Vector Search index',
          capability: 'vector',
          supported_models: [], # not model-driven
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'index',      'required' => true },
                { 'name' => 'datapoints', 'required' => true }
              ]
            },
            'payload'  => { 'format' => 'upsert_datapoints' },
            'endpoint' => {
              'family' => 'vector_indexes',
              'path'   => ':upsertDatapoints',
              'method' => 'POST'
            },
            'extract'  => { 'format' => 'raw' }, # empty body on success
            'post_process' => 'add_upsert_ack'
          }
        },

        'vector.find_neighbors' => {
          description: 'Find nearest neighbors from a deployed index',
          capability: 'vector',
          supported_models: [], # not model-driven
          config_template: {
            'validate' => {
              'schema' => [
                { 'name' => 'index_endpoint',    'required' => true },
                { 'name' => 'deployed_index_id', 'required' => true },
                { 'name' => 'queries',           'required' => true }
              ]
            },
            'payload'  => { 'format' => 'find_neighbors' },
            'endpoint' => {
              'family' => 'vector_index_endpoints',
              'path'   => ':findNeighbors',
              'method' => 'POST'
            },
            'extract'  => { 'format' => 'raw' },
            'post_process' => 'normalize_find_neighbors'
          }
        }        
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
      behavior_def = call('behavior_registry')[behavior] or error("Unknown behavior: #{behavior}")

      # Work on a local copy only
      local_input = call('deep_copy', input)

      # Apply defaults without side effects
      if behavior_def[:defaults]
        behavior_def[:defaults].each do |k, v|
          local_input[k] = local_input.key?(k) ? local_input[k] : v
        end
      end

      cfg = call('configuration_registry', connection, user_config)

      # Build op config from template (avoid rails-only deep_dup)
      operation_config = JSON.parse(JSON.dump(behavior_def[:config_template] || {}))

      # Bring generation settings into the local input (don’t mutate cfg)
      if cfg[:generation]
        cfg[:generation].each { |k, v| local_input[k] = v unless v.nil? }
      end

      operation_config['model']     = call('select_model', behavior_def, cfg, local_input)
      operation_config['resilience'] = cfg[:execution]

      # Caching key is derived from local_input
      if cfg[:features][:caching][:enabled]
        cache_key = "vertex_#{behavior}_#{local_input.to_json.hash}"
        if (hit = call('memo_get', cache_key))
          return hit
        end
      end

      result = call('execute_pipeline', connection, behavior, local_input, operation_config)

      if cfg[:features][:caching][:enabled]
        call('memo_put', cache_key, result, cfg[:features][:caching][:ttl] || 300)
      end

      result
    end,
    
    # ============================================
    # HELPER METHODS
    # ============================================
    
    # Post-processing methods
    add_upsert_ack: lambda do |response, input|
      # response is empty on success; return a useful ack
      {
        'ack'         => 'upserted',
        'count'       => Array(input['datapoints']).size,
        'index'       => input['index'],
        'empty_body'  => (response.nil? || response == {})
      }
    end,

    add_word_count: lambda do |response, input|
      if response.is_a?(String)
        { 
          'result' => response,
          'word_count' => response.split.size
        }
      else
        {
          'result' => response,
          'word_count' => response.to_s.split.size
        }
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
      api_version = connection['version'].presence || 'v1'
      region = connection['region']
      base_regional = "https://#{region}-aiplatform.googleapis.com/#{api_version}"

      family = endpoint_config['family']

      case family
      when 'vector_indexes' # admin/data-plane ops on Index resources
        index = call('qualify_resource', connection, 'index', input['index'] || endpoint_config['index'])
        "#{base_regional}/#{index}#{endpoint_config['path']}" # e.g., ':upsertDatapoints'

      when 'vector_index_endpoints' # query via MatchService (vbd host)
        base  = call('vector_search_base', connection, input)
        ie    = call('qualify_resource', connection, 'index_endpoint',
                      input['index_endpoint'] || endpoint_config['index_endpoint'])
        "#{base}/#{ie}#{endpoint_config['path']}" # e.g., ':findNeighbors'

      else
        # model/publisher logic and custom path
        base_url = "https://#{connection['region']}-aiplatform.googleapis.com/#{api_version}"
        # Prefer model on input (propogated by execution_pipeline); else use connection default
        model = input['model'] || connection['default_model'] || 'gemini-1.5-flash'

        # Resolve short alias to newest -NNN version using publisher catalog
        model_id  = if model.match?(/-\d{3,}$/) then model
                    else
                      call('resolve_model_version', connection, model)
                    end
        
        model_path = "projects/#{connection['project']}/locations/#{connection['region']}/publishers/google/models/#{model_id}"
        # If the user supplies a custom path, replace the the critical elements with those from the connection
        if endpoint_config['custom_path']
          endpoint_config['custom_path']
            .gsub('{project}',  connection['project'])
            .gsub('{region}',   connection['region'])
            .gsub('{endpoint}', connection['vector_search_endpoint'] || '')
        else
          "#{base_url}/#{model_path}#{endpoint_config['path'] || ':generateContent'}"
        end
      end
    end,
    
    build_generation_config: lambda do |vars|
      {
        'temperature'     => vars['temperature'] || 0.7,
        'maxOutputTokens' => vars['max_tokens']  || 2048,
        'topP'            => vars['top_p']       || 0.95,
        'topK'            => vars['top_k']       || 40,
        'stopSequences'   => vars['stop_sequences']
      }.compact
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
      key   = "rate_#{operation}_#{Time.now.to_i / 60}"
      count = call('memo_get', key) || 0
      error("Rate limit exceeded for #{operation}. Please wait before retrying.") if count >= limits['rpm']
      call('memo_put', key, count + 1, 60)
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
      show_advanced = !!show_advanced

      behavior_def = call('behavior_registry')[behavior]
      return [] unless behavior_def
      
      # Map behavior to input fields
      fields = case behavior
      when 'text.generate'
        fields =[
          { name: 'prompt', label: 'Prompt', control_type: 'text-area', optional: false }
        ]
        if show_advanced
          fields += [
            { name: 'system', label: 'System instruction', control_type: 'text-area', optional: true, group: 'Advanced',
              hint: 'Optional system prompt to guide the model' }
          ]
        end
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
          { name: 'texts', label: 'Texts to Embed', type: 'array', of: 'string', optional: false },
          { name: 'task_type', label: 'Task Type', control_type: 'select', pick_list: 'embedding_tasks' }
        ]
      when 'vector.upsert_datapoints'
        [
          { name: 'index', label: 'Index', hint: 'Index resource or ID (e.g. projects/.../indexes/IDX or IDX)', optional: false },
          { name: 'datapoints', label: 'Datapoints', type: 'array', of: 'object', properties: [
            { name: 'datapoint_id', label: 'Datapoint ID', optional: false },
            { name: 'feature_vector', label: 'Feature vector', type: 'array', of: 'number', optional: false },
            { name: 'restricts', type: 'array', of: 'object', properties: [
              { name: 'namespace' }, { name: 'allowList', type: 'array', of: 'string' }, { name: 'denyList', type: 'array', of: 'string' }
            ]},
            { name: 'numeric_restricts', type: 'array', of: 'object', properties: [
              { name: 'namespace' }, { name: 'op' }, { name: 'valueInt' }, { name: 'valueFloat', type: 'number' }, { name: 'valueDouble', type: 'number' }
            ]},
            { name: 'crowding_tag', type: 'object', properties: [{ name: 'crowdingAttribute' }] },
            { name: 'embedding_metadata', type: 'object' }
          ]}
        ]
      when 'vector.find_neighbors'
        [
          { name: 'endpoint_host', label: 'Public endpoint host (vdb)', hint: 'Overrides connection host just for this call (e.g. 123...vdb.vertexai.goog)', optional: true },
          { name: 'index_endpoint', label: 'Index Endpoint', hint: 'Resource or ID (e.g. projects/.../indexEndpoints/IEP or IEP)', optional: false },
          { name: 'deployed_index_id', label: 'Deployed Index ID', optional: false },
          { name: 'neighbor_count', label: 'Neighbors per query', type: 'integer', default: 10 },
          { name: 'return_full_datapoint', label: 'Return full datapoint', control_type: 'checkbox' },
          { name: 'queries', label: 'Queries', type: 'array', of: 'object', properties: [
            { name: 'datapoint_id', label: 'Query datapoint ID' },
            { name: 'feature_vector', label: 'Query vector', type: 'array', of: 'number', hint: 'Use either vector or datapoint_id' },
            { name: 'neighbor_count', label: 'Override neighbors for this query', type: 'integer' },
            { name: 'restricts', type: 'array', of: 'object', properties: [
              { name: 'namespace' }, { name: 'allowList', type: 'array', of: 'string' }, { name: 'denyList', type: 'array', of: 'string' }
            ]},
            { name: 'numeric_restricts', type: 'array', of: 'object', properties: [
              { name: 'namespace' }, { name: 'op' }, { name: 'valueInt' }, { name: 'valueFloat', type: 'number' }, { name: 'valueDouble', type: 'number' }
            ]}
          ]}
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
          { name: 'model_override', label: 'Override Model', control_type: 'select', group: 'Advanced',
            pick_list: 'models_dynamic_for_behavior', pick_list_params: { behavior: behavior }, optional: true },
          { name: 'temperature', label: 'Temperature', type: 'number', group: 'Advanced', hint: '0.0 to 1.0' },
          { name: 'max_tokens', label: 'Max Tokens', type: 'integer', group: 'Advanced' },
          { name: 'cache_ttl', label: 'Cache TTL (seconds)', type: 'integer', group: 'Advanced',default: 300 }
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
      when 'vector.upsert_datapoints'
        [
          { name: 'ack' }, { name: 'count', type: 'integer' }, { name: 'index' }, { name: 'empty_body', type: 'boolean' }
        ]
      when 'vector.find_neighbors'
        [
          { name: 'groups', type: 'array', of: 'object', properties: [
            { name: 'query_id' },
            { name: 'neighbors', type: 'array', of: 'object', properties: [
              { name: 'datapoint_id' }, { name: 'distance', type: 'number' }, { name: 'score', type: 'number' },
              { name: 'datapoint', type: 'object' }
            ]}
          ]}
        ]

      when 'multimodal.analyze'
        [{ name: 'result', label: 'Analysis' }]
      else
        [{ name: 'result' }]
      end
    end,

    # List Google publisher models (v1beta1)
    list_publisher_models: lambda do |connection, publisher: 'google'|
      # Uses the global aiplatform endpoint so it works regardless of region
      cache_key = "pub_models:#{publisher}"
      if (cached = call('memo_get', cache_key))
        return cached
      end

      # absolute URL to avoid base_uri region coupling
      resp = get("https://aiplatform.googleapis.com/v1beta1/publishers/#{publisher}/models")
              .headers(call('build_headers', connection))
              .after_error_response(/.*/) { |code, body, _h, msg| error("#{msg} (#{code}): #{body}") }
              .after_response { |_code, body, _h| body || {} }

      models = (resp['publisherModels'] || [])
      call('memo_put', cache_key, models, 3600) # 60m
      models
    end,

    memo_store: lambda { @__memo ||= {} },

    memo_get: lambda do |key|
      item = call('memo_store')[key]
      return nil unless item
      exp = item['exp']
      return nil if exp && Time.now.to_i > exp
      item['val']
    end,

    memo_put: lambda do |key, val, ttl=nil|
      call('memo_store')[key] = { 'val' => val, 'exp' => (ttl ? Time.now.to_i + ttl.to_i : nil) }
      val
    end,

    # Normalize FindNeighbors response into a stable, recipe-friendly shape
    normalize_find_neighbors: lambda do |resp, _input|
      # Expected: { "nearestNeighbors": [ { "id": "...?", "neighbors": [ { "datapoint": {...}, "distance": n } ] } ] }
      groups = (resp['nearestNeighbors'] || []).map do |nn|
        {
          'query_id' => nn['id'],
          'neighbors' => (nn['neighbors'] || []).map do |n|
            did  = n.dig('datapoint', 'datapointId')
            dist = n['distance']
            {
              'datapoint_id' => did,
              'distance'     => dist,
              'score'        => call('transform_data', input: dist, from_format: 'distance', to_format: 'similarity'),
              'datapoint'    => n['datapoint']
            }.compact
          end
        }
      end
      { 'groups' => groups }
    end,

    # Resolve full resource names from short IDs, without mutating caller input
    qualify_resource: lambda do |connection, type, value|
      return value if value.to_s.start_with?('projects/')
      project = connection['project']
      region  = connection['region']
      case type.to_s
      when 'index'          then "projects/#{project}/locations/#{region}/indexes/#{value}"
      when 'index_endpoint' then "projects/#{project}/locations/#{region}/indexEndpoints/#{value}"
      else value
      end
    end,

    # Resolve an alias to the latest version available
    resolve_model_version: lambda do |connection, short|
      # If versioned properly, keep it
      return short if short.to_s.match?(/-\d{3,}$/)

      cache_key = "model_resolve:#{short}"
      cached = call('memo_get', cache_key)
      return cached if cached

      # Find all models that start with "#{short}-"
      ids = call('list_publisher_models', connection)
              .map { |m| (m['name'] || '').split('/').last }
              .select { |id| id.start_with?("#{short}-") }

      error("No versioned model found for alias '#{short}'") if ids.empty?
        
      latest = ids.max_by { |id| id[/-(\d+)$/, 1].to_i } # highest numeric suffix
      call('memo_put', cache_key, latest, 3600)
      latest
    end,

    # Model selection logic
    select_model: lambda do |behavior_def, config, input|
      # 1) explicit model in input wins (respect override)
      chosen = input['model']
      return chosen if chosen.present?

      # 2) otherwise take configured default (connection/user config)
      chosen = config[:models][:default]

      # 3) accept if either exact match OR alias root matches (strip -NNN)
      aliases = Array(behavior_def[:supported_models]).compact
      root = chosen.to_s.sub(/-\d+$/, '')
      if aliases.include?(chosen) || aliases.include?(root)
        chosen
      else
        # 4) last resort: first declared supported alias
        aliases.first
      end
    end,

    # Build base for vector *query* calls. Prefer the public vdb host when provided.
    vector_search_base: lambda do |connection, input|
      host = (input['endpoint_host'] || connection['vector_search_endpoint']).to_s.strip
      version = connection['version'].presence || 'v1'
      if host.empty?
        # Fallback to regional API host (works for admin ops; query should use public vdb host)
        "https://#{connection['region']}-aiplatform.googleapis.com/#{version}"
      elsif host.include?('vdb.vertexai.goog')
        "https://#{host}/#{version}"
      else
        # Allow passing a full https://... custom host
        host = host.sub(%r{\Ahttps?://}i, '')
        "https://#{host}/#{version}"
      end
    end

  },

  # ============================================
  # PICK LISTS
  # ============================================
  pick_lists: {

    all_models: lambda do |connection|
      [
        ['Gemini 1.5 Flash', 'gemini-1.5-flash'],
        ['Gemini 1.5 Pro', 'gemini-1.5-pro'],
        ['Gemini Embedding 001',  'gemini-embedding-001'],
        ['Text Embedding 005',    'text-embedding-005'],
        ['Text Embedding 004',    'text-embedding-004'],
        ['Text Embedding Gecko', 'textembedding-gecko']
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
    
    embedding_tasks: lambda do |connection|
      [
        ['Document Retrieval', 'RETRIEVAL_DOCUMENT'],
        ['Query Retrieval', 'RETRIEVAL_QUERY'],
        ['Semantic Similarity', 'SEMANTIC_SIMILARITY'],
        ['Classification', 'CLASSIFICATION'],
        ['Clustering', 'CLUSTERING']
      ]
    end,

    gcp_regions: lambda do |connection|
      [
        ['US Central 1', 'us-central1'],
        ['US East 1', 'us-east1'],
        ['US East 4', 'us-east4'],
        ['US West 1', 'us-west1'],
        ['US West 4', 'us-west4']
      ]
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

    models_for_behavior: lambda do |connection, input = {}|
      behavior = input['behavior']
      defn = call('behavior_registry')[behavior]
      next [] unless defn && defn[:supported_models]

      defn[:supported_models].map do |model|
        [model.split('-').map!(&:capitalize).join(' '), model]
      end
    end,

    models_dynamic_for_behavior: lambda do |connection, input={}|
      behavior = input['behavior'] || 'text.generate'
      # Heuristic prefixes by capability
      prefixes  = case behavior
                  when 'text.embed' then ['text-embedding-', 'textembedding-']
                  else ['gemini-']
                  end
      models = call('list_publisher_models', connection)
                  .map { |m|
                    id = (m['name'] || '').split('/').last
                    display = m['displayName'] || id
                    [display, id]
                  }
                  .select { |label, id| prefixes.any? { |p| id.start_with?(p) } }
                  .uniq
      
      # Sort newest first
      models.sort_by { |_label, id| - (id[/-(\d+)$/, 1].to_i) }
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