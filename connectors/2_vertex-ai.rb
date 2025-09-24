{
  title: 'Google Vertex AI',
  custom_action: true,
  custom_action_help: {
    learn_more_url: 'https://cloud.google.com/vertex-ai/docs/reference/rest',
    learn_more_text: 'Google Vertex AI API documentation',
    body: '<p>Build your own Google Vertex AI action with a HTTP request. The request will be authorized with your Google Vertex AI connection.</p>'
  },

  connection: {
    fields: [
      # Developer options
      { name: 'verbose_errors', label: 'Verbose errors', group: 'Developer options', type: 'boolean', control_type: 'checkbox',
        hint: 'When enabled, include upstream response bodies in error messages. Disable in production.' },
      # Authentication
      { name: 'auth_type', label: 'Authentication type', group: 'Authentication', control_type: 'select',  default: 'custom', optional: false, extends_schema: true, 
        options: [ ['Client credentials', 'custom'], %w[OAuth2 oauth2] ], hint: 'Select the authentication type for connecting to Google Vertex AI.'},
      # Vertex AI environment
      { name: 'region', label: 'Region', group: 'Vertex AI environment', control_type: 'select',  optional: false,
        options: [
          ['US central 1', 'us-central1'],
          ['US east 1', 'us-east1'],
          ['US east 4', 'us-east4'],
          ['US east 5', 'us-east5'],
          ['US west 1', 'us-west1'],
          ['US west 4', 'us-west4'],
          ['US south 1', 'us-south1'],
          ['North America northeast 1', 'northamerica-northeast1'],
          ['Europe west 1', 'europe-west1'],
          ['Europe west 2', 'europe-west2'],
          ['Europe west 3', 'europe-west3'],
          ['Europe west 4', 'europe-west4'],
          ['Europe west 9', 'europe-west9'],
          ['Asia northeast 1', 'asia-northeast1'],
          ['Asia northeast 3', 'asia-northeast3'],
          ['Asia southeast 1', 'asia-southeast1'] ],
        hint: 'Select the Google Cloud Platform (GCP) region used for the Vertex model.', toggle_hint: 'Select from list',
        toggle_field: {
          name: 'region', label: 'Region', type: 'string', control_type: 'text', optional: false, 
          toggle_hint: 'Use custom value', hint: "Enter the region you want to use" } },
      { name: 'project', label: 'Project', group: 'Vertex AI environment', optional: false,  hint: 'E.g abc-dev-1234' },
      { name: 'version', label: 'Version', group: 'Vertex AI environment', optional: false,  default: 'v1', hint: 'E.g. v1beta1' },
      # Model discovery and validation
      { name: 'dynamic_models', label: 'Refresh model list from API (Model Garden)', group: 'Model discovery and validation', type: 'boolean', 
        control_type: 'checkbox', optional: true, hint: 'Fetch available Gemini/Embedding models at runtime. Falls back to a curated static list on errors.' },
      { name: 'include_preview_models', label: 'Include preview/experimental models', group: 'Model discovery and validation', type: 'boolean', control_type: 'checkbox', 
        optional: true, sticky: true, hint: 'Also include Experimental/Private/Public Preview models. Leave unchecked for GA-only in production.' },
      { name: 'validate_model_on_run', label: 'Validate model before run', group: 'Model discovery and validation', type: 'boolean', control_type: 'checkbox',
        optional: true, sticky: true, hint: 'Pre-flight check the chosen model and your project access before sending the request. Recommended.' },
      { name: 'enable_rate_limiting', label: 'Enable rate limiting', group: 'Model discovery and validation', type: 'boolean', control_type: 'checkbox', 
        optional: true, default: true, hint: 'Automatically throttle requests to stay within Vertex AI quotas' },
      { name: 'include_trace', label: 'Include trace', group: 'Developer options', type: 'boolean', control_type: 'checkbox', optional: true, default: true, sticky: true,
        hint: 'Include trace.correlation_id and trace.duration_ms in outputs. Disable in production.' }
    ],
    authorization: {
      type: 'multi',

      selected: lambda do |connection|
        connection['auth_type'] || 'custom'
      end,

      options: {
        oauth2: {
          type: 'oauth2',
          fields: [
            { name: 'client_id', group: 'OAuth 2.0 (user delegated)', optional: false,
              hint: 'You can find your client ID by logging in to your ' \
                    "<a href='https://console.developers.google.com/' " \
                    "target='_blank'>Google Developers Console</a> account. " \
                    'After logging in, click on Credentials to show your ' \
                    'OAuth 2.0 client IDs. <br> Alternatively, you can create your ' \
                    'Oauth 2.0 credentials by clicking on Create credentials > ' \
                    'Oauth client ID. <br> Please use <b>https://www.workato.com/' \
                    'oauth/callback</b> for the redirect URI when registering your ' \
                    'OAuth client. <br> More information about authentication ' \
                    "can be found <a href='https://developers.google.com/identity/" \
                    "protocols/OAuth2?hl=en_US' target='_blank'>here</a>." },
            { name: 'client_secret', group: 'OAuth 2.0 (user delegated)',optional: false, control_type: 'password',
              hint: 'You can find your client secret by logging in to your ' \
                    "<a href='https://console.developers.google.com/' " \
                    "target='_blank'>Google Developers Console</a> account. " \
                    'After logging in, click on Credentials to show your ' \
                    'OAuth 2.0 client IDs and select your desired account name.' }
          ],
          authorization_url: lambda do |connection|
            scopes = call('oauth_scopes').join(' ')
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
          acquire: lambda do |connection, auth_code|
            response = post('https://oauth2.googleapis.com/token').
                       payload(
                         client_id: connection['client_id'],
                         client_secret: connection['client_secret'],
                         grant_type: 'authorization_code',
                         code: auth_code,
                         redirect_uri: 'https://www.workato.com/oauth/callback'
                       ).request_format_www_form_urlencoded
            [response, nil, nil]
          end,
          refresh: lambda do |connection, refresh_token|
            post('https://oauth2.googleapis.com/token').
              payload(
                client_id: connection['client_id'],
                client_secret: connection['client_secret'],
                grant_type: 'refresh_token',
                refresh_token: refresh_token
              ).request_format_www_form_urlencoded
          end,
          apply: lambda do |_connection, access_token|
            headers(Authorization: "Bearer #{access_token}")
          end
        },
        custom: {
          type: 'custom_auth',
          fields: [
            { name: 'service_account_email',
              optional: false, group: 'Service Account',
              hint: 'The service account created to delegate other domain users (e.g. name@project.iam.gserviceaccount.com)' },
            { name: 'client_id', optional: false },
            { name: 'private_key', control_type: 'password',  multiline: true, optional: false,
              hint: 'Copy and paste the private key that came from the downloaded json. <br/>' \
                    "Click <a href='https://developers.google.com/identity/protocols/oauth2/' " \
                    "service-account/target='_blank'>here</a> to learn more about Google Service " \
                    'Accounts.<br><br>Required scope: <b>https://www.googleapis.com/auth/cloud-platform</b>' }
          ],
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
                            assertion: jwt_token).
                       request_format_www_form_urlencoded

            { access_token: response['access_token'] }
          end,
          refresh_on: [401],
          apply: lambda do |connection|
            headers(Authorization: "Bearer #{connection['access_token']}")
          end
        }
      }
    },

    base_uri: lambda do |connection|
      "https://#{connection['region']}-aiplatform.googleapis.com/#{connection['version'] || 'v1'}/"
    end
  },

  test: lambda do |connection|
    resp = call('with_resilience', connection, key: 'vertex.datasets.list') do |cid|
      call('api_request', connection, :get,
        "#{call('project_region_path', connection)}/datasets",
        { params: { pageSize: 1 },
          headers: { 'X-Correlation-Id' => cid },
          context: { action: 'List datasets', correlation_id: cid } })
    end

    begin
      drive_probe = call('probe_drive', connection, verbose: false)
      { vertex_ai: 'connected', drive_access: drive_probe['status'], files_visible: drive_probe['files_found'], trace: resp['trace'] }
    rescue => e
      { vertex_ai: 'connected', drive_access: "error - #{e.message}", trace: resp['trace'] }
    end
  end,

  actions: {
    # ─────────────────────────────────────────────────────────────────────────────
    # Gemini conversation & text generation
    # ─────────────────────────────────────────────────────────────────────────────
    send_messages: {
      title: 'Vertex -- Send messages to Gemini models',
      subtitle: 'Converse with Gemini models in Google Vertex AI',
      description: lambda do |input|
        model = input['model']
        if model.present?
          "Send messages to <span class='provider'>#{model.split('/')[-1].humanize}</span> model"
        else
          'Send messages to <span class=\'provider\'>Gemini</span> models'
        end
      end,
      help: {
        body: 'Sends text (and optional tools/system instruction) to Vertex AI, returns unified answer. ' \
              'Outputs include telemetry: trace (correlation_id, duration_ms), vertex (response_id, model_version), and rate_limit_status.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['send_messages_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('run_vertex', connection, input, :send_message, verb: :generate, extract: { type: :generic })
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['send_messages_output']
      end,
      sample_output: lambda do |_connection, _input|
        call('sample_record_output', 'send_message')
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Generative actions (text)
    # ─────────────────────────────────────────────────────────────────────────────
    translate_text: {
      title: 'Vertex -- Translate text',
      subtitle: 'Translate text between languages',
      description: 'Translate text using Gemini models in Vertex AI',
      help: {
        body: 'Translates input text into the target language. Returns the translated string as answer. ' \
              'Telemetry: trace, vertex meta, rate_limit_status.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['translate_text_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('run_vertex', connection, input, :translate, verb: :generate, extract: { type: :generic, json_response: true })
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['translate_text_output']
      end,
      sample_output: lambda do
        call('sample_record_output', 'translate_text')
      end
    },

    summarize_text: {
      title: 'Vertex -- Summarize text',
      subtitle: 'Get a summary of the input text in configurable length',
      description: 'Summarize text using Gemini models in Vertex AI',
      help: {
        body: 'Summarizes input text. Returns a concise answer plus telemetry.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['summarize_text_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('run_vertex', connection, input, :summarize, verb: :generate, extract: { type: :generic })
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['summarize_text_output']
      end,
      sample_output: lambda do
        call('sample_record_output', 'summarize_text')
      end
    },

    parse_text: {
      title: 'Vertex -- Parse text',
      subtitle: 'Extract structured data from freeform text',
      description: 'Extract structured fields per provided schema',
      help: {
        body: 'Parses freeform text into fields you define. Missing fields become null. Telemetry included.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['parse_text_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('run_vertex', connection, input, :parse, verb: :generate, extract: { type: :parsed })
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['parse_text_output']
      end,
      sample_output: lambda do |_connection, input|
        call('format_parse_sample', input['object_schema'])
          .merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      end
    },

    draft_email: {
      title: 'Vertex -- Draft email',
      subtitle: 'Generate an email based on user description',
      description: 'Generate subject and body from a short description',
      help: {
        body: 'Returns JSON with subject and body, plus safety/usage + telemetry.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['draft_email_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('run_vertex', connection, input, :email, verb: :generate, extract: { type: :email })
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['draft_email_output']
      end,
      sample_output: lambda do
        call('sample_record_output', 'draft_email')
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Analysis actions (text)
    # ─────────────────────────────────────────────────────────────────────────────
    ai_classify: {
      title: 'Vertex -- AI Classification',
      subtitle: 'Classify text using AI with confidence scoring',
      description: 'Classify text into predefined categories with confidence and alternatives',
      help: {
        body: 'Low‑temperature classification with optional confidence/alternatives. Telemetry included.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['ai_classify_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('run_vertex', connection, input, :ai_classify, verb: :generate, extract: { type: :classify })
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['ai_classify_output']
      end,
      sample_output: lambda do |_connection, input|
        {
          'selected_category' => input['categories']&.first&.[]('key') || 'urgent',
          'confidence' => 0.95,
          'alternatives' => [{ 'category' => 'normal', 'confidence' => 0.05 }]
        }.merge(call('safety_ratings_output_sample'), call('usage_output_sample'))
      end
    },

    analyze_text: {
      title: 'Vertex -- Analyze text',
      subtitle: 'Contextual analysis of text to answer user-provided questions',
      description: 'Answer questions about supplied text only (no external knowledge)',
      help: {
        body: 'Returns an answer or empty if not found in the passage. Telemetry included.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['analyze_text_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('run_vertex', connection, input, :analyze, verb: :generate, extract: { type: :generic, json_response: true })
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['analyze_text_output']
      end,
      sample_output: lambda do
        call('sample_record_output', 'analyze_text')
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Multimodal
    # ─────────────────────────────────────────────────────────────────────────────
    analyze_image: {
      title: 'Vertex -- Analyze image',
      subtitle: 'Analyze image based on the provided question',
      description: "Analyze an <span class='provider'>image</span> with Gemini in Vertex",
      help: {
        body: 'Provide either image URL or inline base64 + mime. Returns free‑text answer + telemetry.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['analyze_image_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('run_vertex', connection, input, :analyze, verb: :generate, extract: { type: :generic, json_response: true })
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['analyze_image_output']
      end,
      sample_output: lambda do
        call('sample_record_output', 'analyze_image')
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Embeddings & Vector Search
    # ─────────────────────────────────────────────────────────────────────────────
    generate_embeddings: {
      title: 'Vertex -- Generate text embeddings (Batch)',
      subtitle: 'Generate embeddings for multiple texts in batch',
      description: 'Batch embeddings via embedTextBatch; returns vectors + batch metrics',
      batch: true,
      help: {
        body: 'Efficiently embed multiple texts. Telemetry included.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['generate_embeddings_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('generate_embeddings_batch_exec', connection, input)
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['generate_embeddings_output']
      end,
      sample_output: lambda do |_connection, input|
        call('sample_record_output', 'text_embedding').merge(
          'batch_id' => input['batch_id'] || 'batch_001',
          'embeddings_count' => 1,
          'embeddings' => [{
            'id' => 'text_1',
            'vector' => Array.new(8) { rand.round(6) },
            'dimensions' => 8,
            'metadata' => { 'source' => 'sample' }
          }],
          'first_embedding' => {
            'id' => 'text_1', 'vector' => Array.new(8) { rand.round(6) }, 'dimensions' => 8
          },
          'model_used' => input['model'] || 'publishers/google/models/text-embedding-004',
          'total_processed' => 1,
          'successful_requests' => 1,
          'failed_requests' => 0,
          'batches_processed' => 1,
          'api_calls_saved' => 0,
          'estimated_cost_savings' => 0.0,
          'pass_fail' => true,
          'action_required' => 'ready_for_indexing',
          'trace' => { 'correlation_id' => 'sample-cid', 'duration_ms' => 123 }
        )
      end
    },

    generate_embedding_single: {
      title: 'Vertex -- Generate single text embedding',
      subtitle: 'Generate embedding for a single text input',
      description: 'Single embed via embedText',
      help: {
        body: 'Optimized for query flows. Telemetry included.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['generate_embedding_single_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        call('generate_embedding_single_exec', connection, input)
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['generate_embedding_single_output']
      end,
      sample_output: lambda do |_connection, input|
        {
          'vector' => Array.new(8) { rand.round(6) },
          'dimensions' => 8,
          'model_used' => input['model'] || 'publishers/google/models/text-embedding-004',
          'token_count' => 42,
          'trace' => { 'correlation_id' => 'sample-cid', 'duration_ms' => 123 }
        }
      end
    },

    find_neighbors: {
      title: 'Vertex -- Find neighbors',
      subtitle: 'K-NN query on a deployed Vertex AI index endpoint',
      description: 'Query a Vector Search endpoint to retrieve nearest neighbors',
      retry_on_request: ['POST'],
      retry_on_response: [429, 500, 502, 503, 504],
      max_retries: 3,
      help: {
        body: 'Use the endpoint host or full URL. Returning full datapoints increases latency/cost. Telemetry included.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['find_neighbors_input']
      end,
      execute: lambda do |connection, input, _eis, _eos|
        resp = call('vindex_find_neighbors', connection, input)
        call('transform_find_neighbors_response', resp).merge('trace' => resp['trace'])
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['find_neighbors_output']
      end,
      sample_output: lambda do
        sample = {
          'nearestNeighbors' => [{
            'id' => 'query-1',
            'neighbors' => [{
              'datapoint' => { 'datapointId' => 'doc_001_chunk_1' },
              'distance'  => 0.12
            }]
          }],
          'trace' => { 'correlation_id' => 'sample-cid', 'duration_ms' => 123 }
        }
        call('transform_find_neighbors_response', sample).merge('trace' => sample['trace'])
      end
    },

    upsert_index_datapoints: {
      title: 'Vertex -- Upsert index datapoints',
      subtitle: 'Add or update vector datapoints in Vertex AI Vector Search index',
      description: 'Batch upsert datapoints (100 per request)',
      help: {
        body: 'Creates/updates datapoints with optional restricts/crowding. Returns counts, per-item errors, and index stats.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['upsert_index_datapoints_input']
      end,
      execute: lambda do |connection, input|
        call('batch_upsert_datapoints', connection, input['index_id'], input['datapoints'], input['update_mask'])
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['upsert_index_datapoints_output']
      end,
      sample_output: lambda do
        {
          'successful_upserts' => 3,
          'failed_upserts' => 1,
          'total_processed' => 4,
          'error_details' => [{ 'datapoint_id' => 'bad_1', 'error' => 'Vector dimension mismatch' }],
          'index_stats' => {
            'index_id' => 'projects/my/locations/us-central1/indexes/idx',
            'deployed_state' => 'DEPLOYED',
            'total_datapoints' => 15420,
            'dimensions' => 768,
            'display_name' => 'Sample Index',
            'created_time' => '2024-01-01T00:00:00Z',
            'updated_time' => '2024-01-15T12:30:00Z'
          }
        }
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Setup & legacy
    # ─────────────────────────────────────────────────────────────────────────────
    test_connection: {
      title: 'Setup -- Test connection and permissions',
      subtitle: 'Verify API access and permissions',
      description: 'Tests Vertex AI, Drive, and optional index connectivity',
      help: {
        body: 'Use to verify connection & permissions. Optionally validate models and Vector Search index.'
      },
      input_fields: lambda do |_object_definitions|
        [
          { name: 'test_vertex_ai', label: 'Test Vertex AI', type: 'boolean', control_type: 'checkbox', default: true, optional: true },
          { name: 'test_drive',     label: 'Test Google Drive', type: 'boolean', control_type: 'checkbox', default: true, optional: true },
          { name: 'test_models',    label: 'Test model access', type: 'boolean', control_type: 'checkbox', default: false, optional: true },
          { name: 'test_index',     label: 'Test Vector Search index', type: 'boolean', control_type: 'checkbox', default: false, optional: true },
          { name: 'index_id',       label: 'Index ID', type: 'string', optional: true, ngIf: 'input.test_index == true' },
          { name: 'verbose',        label: 'Verbose output', type: 'boolean', control_type: 'checkbox', default: false, optional: true }
        ]
      end,
      execute: lambda do |connection, input|
        results = {
          'timestamp' => Time.now.iso8601,
          'environment' => {
            'project' => connection['project'],
            'region'  => connection['region'],
            'api_version' => connection['version'] || 'v1',
            'auth_type'   => connection['auth_type']
          },
          'tests_performed' => [],
          'errors'          => [],
          'warnings'        => []
        }

        if input['test_vertex_ai'] != false
          results['tests_performed'] << call('probe_vertex_ai', connection, test_models: !!input['test_models'])
        end
        if input['test_drive'] != false
          results['tests_performed'] << call('probe_drive', connection, !!input['verbose'])
        end
        if input['test_index'] && input['index_id'].present?
          results['tests_performed'] << call('probe_index', connection, input['index_id'])
        end

        # Summaries
        passed = results['tests_performed'].count { |t| t['status'] == 'connected' }
        total  = results['tests_performed'].length
        failed = total - passed
        results['summary'] = { 'total_tests' => total, 'passed' => passed, 'failed' => failed }
        results['all_tests_passed'] = failed.zero?
        results['overall_status'] = failed.zero? ? 'healthy' : (passed.positive? ? 'degraded' : 'failed')
        results
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['test_connection_output']
      end,
      sample_output: lambda do |_connection, _input|
        {
          'timestamp' => '2024-01-15T10:30:00Z',
          'overall_status' => 'healthy',
          'all_tests_passed' => true,
          'environment' => {
            'project' => 'my-project',
            'region' => 'us-central1',
            'api_version' => 'v1',
            'auth_type' => 'custom',
            'host' => 'app.eu'
          },
          'tests_performed' => [
            { 'service' => 'Vertex AI', 'status' => 'connected', 'response_time_ms' => 245, 'permissions_validated' => ['aiplatform.*'] }
          ],
          'errors' => [],
          'warnings' => [],
          'summary' => { 'total_tests' => 1, 'passed' => 1, 'failed' => 0 }
        }
      end
    },

    # Legacy (kept for BC)
    get_prediction: {
      title: 'Vertex -- Get prediction (legacy)',
      subtitle: 'Get prediction in Google Vertex AI',
      description: 'DEPRECATED: PaLM2 text-bison :predict',
      help: lambda do
        {
          body: '**Deprecated** - retained for backwards compatibility. Returns raw predictions and token metadata.',
          learn_more_url: 'https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/text',
          learn_more_text: 'Learn more'
        }
      end,
      input_fields: lambda do |object_definitions|
        object_definitions['get_prediction_input']
      end,
      execute: lambda do |connection, input|
        post("projects/#{connection['project']}/locations/#{connection['region']}/publishers/google/models/text-bison:predict", input)
          .after_error_response(/.*/) do |_, body, _, message|
            error("#{message}: #{body}")
          end
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['prediction']
      end,
      sample_output: lambda do |_connection|
        {
          'predictions' => [{ 'content' => 'Sample legacy prediction' }],
          'metadata' => { 'tokenMetadata' => {
            'inputTokenCount'  => { 'totalTokens' => 10, 'totalBillableCharacters' => 40 },
            'outputTokenCount' => { 'totalTokens' => 20, 'totalBillableCharacters' => 80 }
          } }
        }
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Google Drive
    # ─────────────────────────────────────────────────────────────────────────────
    fetch_drive_file: {
      title: 'Drive -- Fetch Google Drive file',
      subtitle: 'Download file content from Google Drive',
      description: lambda do |input|
        file_id = input['file_id']
        file_id.present? ? "Fetch content from Google Drive file: #{file_id}" : 'Fetch content from a Google Drive file'
      end,
      help: {
        body: 'Fetches metadata and (optionally) content. Google Docs are exported to text, others downloaded. Telemetry included.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['fetch_drive_file_input']
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['fetch_drive_file_output']
      end,
      execute: lambda do |connection, input|
        file_id = call('extract_drive_file_id', input['file_id'])
        include_content = input.fetch('include_content', true)
        call('fetch_drive_file_full', connection, file_id, include_content)
      end
    },

    list_drive_files: {
      title: 'Drive -- List Google Drive files',
      subtitle: 'Retrieve a list of files from Google Drive',
      description: lambda do |input|
        folder_id = input['folder_id']
        folder_id.present? ? "List files in Google Drive folder: #{folder_id}" : 'List files from Google Drive'
      end,
      help: {
        body: 'Lists files with flexible filters. Results ordered by modification time (newest first). Telemetry included.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['list_drive_files_input']
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['list_drive_files_output']
      end,
      execute: lambda do |connection, input|
        folder_id = input['folder_id'].present? ? call('extract_drive_file_id', input['folder_id']) : nil
        modified_after  = input['modified_after']&.iso8601
        modified_before = input['modified_before']&.iso8601

        query_options = {
          folder_id: folder_id,
          modified_after: modified_after,
          modified_before: modified_before,
          mime_type: input['mime_type'],
          exclude_folders: input['exclude_folders']
        }.compact

        query_string = call('build_drive_query', query_options)

        max_results = [input.fetch('max_results', 100), 1000].min
        page_size   = [max_results, 1000].min

        api_params = {
          q: query_string,
          pageSize: page_size,
          fields: 'nextPageToken,files(id,name,mimeType,size,modifiedTime,md5Checksum)',
          orderBy: 'modifiedTime desc'
        }
        api_params[:pageToken] = input['page_token'] if input['page_token'].present?

        response = call('with_resilience', connection, key: 'drive.files.list') do |cid|
          call('api_request', connection, :get,
            call('drive_api_url', :files),
            {
              params: api_params,
              headers: { 'X-Correlation-Id' => cid },
              context: { action: 'List Drive files', correlation_id: cid },
              error_handler: lambda do |code, body, message|
                error(call('handle_drive_error', connection, code, body, message, { correlation_id: cid }))
              end
            }
          )
        end

        files = response['files'] || []
        processed_files = files.map do |file|
          {
            'id' => file['id'],
            'name' => file['name'],
            'mime_type' => file['mimeType'],
            'size' => file['size']&.to_i,
            'modified_time' => file['modifiedTime'],
            'checksum' => file['md5Checksum']
          }
        end

        {
          'files' => processed_files,
          'count' => processed_files.length,
          'has_more' => response['nextPageToken'].present?,
          'next_page_token' => response['nextPageToken'],
          'query_used' => query_string,
          'trace' => response['trace']
        }
      end
    },

    batch_fetch_drive_files: {
      title: 'Drive -- Batch fetch Google Drive files',
      subtitle: 'Fetch content from multiple Google Drive files',
      batch: true,
      description: lambda do |input|
        file_ids = input['file_ids'] || []
        count = file_ids.length
        count > 0 ? "Batch fetch #{count} files from Google Drive" : 'Batch fetch files from Google Drive'
      end,
      help: {
        body: 'Fetches many files, reusing single‑file logic. Can skip errors or fail fast. Returns per‑file results and metrics.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['batch_fetch_drive_files_input']
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['batch_fetch_drive_files_output']
      end,
      execute: lambda do |connection, input|
        start_time = Time.now
        successful_files = []
        failed_files = []

        file_ids = input['file_ids'] || []
        include_content = input.fetch('include_content', true)
        skip_errors = input.fetch('skip_errors', true)

        if file_ids.empty?
          return {
            'successful_files' => [],
            'failed_files' => [],
            'metrics' => {
              'total_processed' => 0, 'success_count' => 0, 'failure_count' => 0,
              'success_rate' => 0.0, 'processing_time_ms' => 0
            }
          }
        end

        file_ids.each do |file_id_input|
          begin
            file_id = call('extract_drive_file_id', file_id_input)
            successful_files << call('fetch_drive_file_full', connection, file_id, include_content)
          rescue => e
            failed_files << { 'file_id' => file_id_input, 'error_message' => e.message, 'error_code' => 'FETCH_ERROR' }
            error("Batch processing failed on file #{file_id_input}: #{e.message}") unless skip_errors
          end
        end

        processing_time_ms = ((Time.now - start_time) * 1000).round
        total_processed = file_ids.length
        success_count   = successful_files.length
        failure_count   = failed_files.length
        success_rate    = total_processed > 0 ? (success_count.to_f / total_processed * 100).round(2) : 0.0

        {
          'successful_files' => successful_files,
          'failed_files' => failed_files,
          'metrics' => {
            'total_processed' => total_processed,
            'success_count' => success_count,
            'failure_count' => failure_count,
            'success_rate' => success_rate,
            'processing_time_ms' => processing_time_ms
          }
        }
      end
    },

    monitor_drive_changes: {
      title: 'Drive -- Monitor Google Drive changes',
      subtitle: 'Track file changes since last check',
      description: lambda do |input|
        input['page_token'].present? ? 'Continue monitoring Drive changes from saved checkpoint' : 'Start monitoring Drive changes (initial scan)'
      end,
      help: {
        body: 'Returns first run start token, then incremental changes per subsequent run. Can scope to folder/shared drives.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['monitor_drive_changes_input']
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['monitor_drive_changes_output']
      end,
      execute: lambda do |connection, input|
        page_token = input['page_token']
        folder_id = input['folder_id'].present? ? call('extract_drive_file_id', input['folder_id']) : nil
        include_removed = input['include_removed'] || false
        include_shared_drives = input['include_shared_drives'] || false
        page_size = [input.fetch('page_size', 100), 1000].min

        if page_token.blank?
          start_params = { supportsAllDrives: include_shared_drives }
          start_params[:driveId] = folder_id if folder_id.present? && include_shared_drives
          start_params[:spaces]  = 'drive'   if folder_id.present?

          start_response = call('with_resilience', connection, key: 'drive.changes.start_token') do |cid|
            call('api_request', connection, :get,
              call('drive_api_url', :start_token),
              {
                params: start_params,
                headers: { 'X-Correlation-Id' => cid },
                context: { action: 'Get Drive start token', correlation_id: cid },
                error_handler: lambda do |code, body, message|
                  error(call('handle_drive_error', connection, code, body, message, { correlation_id: cid }))
                end
              }
            )
          end

          return {
            'changes' => [],
            'new_page_token' => start_response['startPageToken'],
            'files_added' => [],
            'files_modified' => [],
            'files_removed' => [],
            'summary' => { 'total_changes' => 0, 'added_count' => 0, 'modified_count' => 0, 'removed_count' => 0, 'has_more' => false },
            'is_initial_token' => true,
            'trace' => start_response['trace']
          }
        end

        changes_params = {
          pageToken: page_token,
          pageSize: page_size,
          fields: 'nextPageToken,newStartPageToken,changes(changeType,time,removed,fileId,file(id,name,mimeType,modifiedTime,size,md5Checksum,trashed,parents))',
          supportsAllDrives: include_shared_drives,
          includeRemoved: include_removed
        }
        changes_params[:driveId] = folder_id if folder_id.present? && include_shared_drives

        changes_response = call('with_resilience', connection, key: 'drive.changes.list') do |cid|
          call('api_request', connection, :get,
            call('drive_api_url', :changes),
            {
              params: changes_params,
              headers: { 'X-Correlation-Id' => cid },
              context: { action: 'List Drive changes', correlation_id: cid },
              error_handler: lambda do |code, body, message|
                error(call('handle_drive_error', connection, code, body, message, { correlation_id: cid }))
              end
            }
          )
        end

        all_changes = changes_response['changes'] || []

        if folder_id.present? && !include_shared_drives
          all_changes = all_changes.select do |change|
            change['file'] && change['file']['parents'] && change['file']['parents'].include?(folder_id)
          end
        end

        files_added, files_modified, files_removed = [], [], []
        seen = {}
        all_changes.each do |change|
          file_id = change['fileId']
          klass = call('classify_drive_change', change, include_removed)
          next if klass[:kind] == :skip
          if klass[:kind] == :removed
            files_removed << klass[:summary]
            next
          end
          if seen[file_id]
            files_modified << klass[:summary]
          else
            files_added << klass[:summary]
            seen[file_id] = true
          end
        end

        next_token = changes_response['nextPageToken'] || changes_response['newStartPageToken']
        has_more = changes_response['nextPageToken'].present?

        {
          'changes' => all_changes,
          'new_page_token' => next_token,
          'files_added' => files_added,
          'files_modified' => files_modified,
          'files_removed' => files_removed,
          'summary' => {
            'total_changes' => all_changes.length,
            'added_count' => files_added.length,
            'modified_count' => files_modified.length,
            'removed_count' => files_removed.length,
            'has_more' => has_more
          },
          'is_initial_token' => false,
          'trace' => changes_response['trace']
        }
      end,
      sample_output: lambda do |_connection, _input|
        {
          'changes' => [{
            'changeType' => 'file',
            'time' => '2024-01-15T10:30:00Z',
            'removed' => false,
            'fileId' => 'abc123',
            'file' => {
              'id' => 'abc123',
              'name' => 'document.pdf',
              'mimeType' => 'application/pdf',
              'modifiedTime' => '2024-01-15T10:29:45Z',
              'size' => 1024000,
              'md5Checksum' => 'abc123def456',
              'trashed' => false
            }
          }],
          'new_page_token' => 'token_xyz789',
          'files_added' => [{ 'id' => 'abc123', 'name' => 'document.pdf', 'mimeType' => 'application/pdf', 'modifiedTime' => '2024-01-15T10:29:45Z' }],
          'files_modified' => [],
          'files_removed' => [],
          'summary' => { 'total_changes' => 1, 'added_count' => 1, 'modified_count' => 0, 'removed_count' => 0, 'has_more' => false },
          'is_initial_token' => false,
          'trace' => { 'correlation_id' => 'sample-cid', 'duration_ms' => 123 }
        }
      end
    }
  },

  methods: {
    # ─────────────────────────────────────────────────────────────────────────────
    # Core observability & resilience
    # ─────────────────────────────────────────────────────────────────────────────
    new_correlation_id: lambda do |prefix = 'vx'|
      "#{prefix}-#{SecureRandom.uuid}"
    end,

    now_ms: lambda do
      (Time.now.utc.to_f * 1000).round
    end,

    # Exponential backoff with jitter; yields correlation_id to the provided block.
    # Collects duration and surfaces trace + rudimentary rate limit view.
    with_resilience: lambda do |_connection, key: 'generic', max_retries: 3, base_sleep: 0.5, retry_on_request: [], retry_on_response: [429, 500, 502, 503, 504], &block|
      cid = call('new_correlation_id', key)
      start = Time.now
      attempts = 0
      last_err = nil
      begin
        attempts += 1
        resp = block.call(cid)

        # Attach trace if shape is a hash
        if resp.is_a?(Hash)
          resp['trace'] ||= {}
          resp['trace']['correlation_id'] ||= cid
          resp['trace']['duration_ms'] ||= ((Time.now - start) * 1000).round
        end
        resp
      rescue StandardError => e
        last_err = e
        code = (e.respond_to?(:response_code) && e.response_code) || nil

        should_retry =
          (retry_on_response.include?(code)) ||
          (retry_on_request.include?(e.class.name)) ||
          (e.message =~ /timeout|temporar|reset|econnrefused|unreachable|throttl/i)

        if attempts <= max_retries && should_retry
          # honor Retry-After if available
          retry_after = (e.respond_to?(:response_headers) && e.response_headers && e.response_headers['Retry-After']).to_i
          sleep_time = retry_after.positive? ? retry_after : (base_sleep * (2 ** (attempts - 1))) + rand * 0.2
          sleep(sleep_time)
          retry
        end

        # Bubble up with context
        message = "[#{key}] #{e.message}"
        error(message)
      end
    end,

    # One place for HTTP: params, JSON encoding, headers, and error mapping.
    api_request: lambda do |_connection, verb, url, options = {}|
      headers = (options[:headers] || {}).dup
      params  = options[:params]  || {}
      payload = options[:payload]
      cid     = headers['X-Correlation-Id'] || call('new_correlation_id', 'http')

      headers['Content-Type'] ||= 'application/json'
      headers['Accept']       ||= 'application/json'
      headers['X-Correlation-Id'] = cid

      begin
        raw =
          case verb.to_sym
          when :get    then get(url, params: params, headers: headers)
          when :delete then delete(url, params: params, headers: headers)
          when :post   then post(url, payload&.to_json, params: params, headers: headers)
          when :put    then put(url, payload&.to_json, params: params, headers: headers)
          when :patch  then patch(url, payload&.to_json, params: params, headers: headers)
          else
            error("Unsupported HTTP verb: #{verb}")
          end

        body = raw.present? && raw.is_a?(String) ? (JSON.parse(raw) rescue raw) : raw

        rate = call('rate_limit_from_headers', headers: (raw.headers rescue {}))
        (body.is_a?(Hash) ? body : { 'data' => body }).merge(
          'trace' => { 'correlation_id' => cid, 'duration_ms' => nil }, # filled by with_resilience
          'rate_limit_status' => rate
        )
      rescue StandardError => e
        # Allow custom error handler hook
        if options[:error_handler].respond_to?(:call)
          options[:error_handler].call((e.respond_to?(:response_code) && e.response_code), (e.respond_to?(:response_body) && e.response_body), e.message)
        end
        raise e
      end
    end,

    rate_limit_from_headers: lambda do |headers: {}|
      return {} unless headers
      {
        'retry_after'   => headers['Retry-After'],
        'limit'         => headers['X-RateLimit-Limit'],
        'remaining'     => headers['X-RateLimit-Remaining'],
        'reset_epoch'   => headers['X-RateLimit-Reset']
      }.compact
    end,

    safe_json_parse: lambda do |text|
      JSON.parse(text) rescue nil
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Vertex AI — URL & headers
    # ─────────────────────────────────────────────────────────────────────────────
    vertex_base_url: lambda do |connection|
      version = connection['version'] || 'v1'
      region  = connection['region']
      "https://#{region}-aiplatform.googleapis.com/#{version}/projects/#{connection['project']}/locations/#{region}"
    end,

    vertex_models_url: lambda do |connection, model, verb|
      base  = call('vertex_base_url', connection)
      id    = model.to_s.split('/').last # normalize: accept full or bare
      case verb.to_sym
      when :generate        then "#{base}/publishers/google/models/#{id}:generateContent"
      when :embed_text      then "#{base}/publishers/google/models/#{id}:embedText"
      when :embed_text_batch then "#{base}/publishers/google/models/#{id}:batchEmbedText"
      else error("Unsupported Vertex verb: #{verb}")
      end
    end,

    vertex_headers: lambda do |_connection, cid|
      {
        'Content-Type'     => 'application/json',
        'Accept'           => 'application/json',
        'X-Correlation-Id' => cid
      }
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Vertex AI — request/body builders
    # ─────────────────────────────────────────────────────────────────────────────
    validate_model!: lambda do |_connection, model|
      error('Model is required') if model.blank?
      # Minimal shape validation. Expand if you maintain an allow‑list.
      error('Model id must include publishers/google/models/...') unless model.include?('publishers/google/models/')
      model
    end,

    # Accepts { messages | contents | text | image } and common config (safetySettings, tools, system_instruction, options).
    build_vertex_body: lambda do |_connection, input, operation|
      body = {}

      # 1) contents (raw Vertex message format) wins
      if input['contents'].is_a?(Array)
        body['contents'] = input['contents']
      # 2) messages (role/text simplified) → convert to Vertex content parts
      elsif input['messages'].is_a?(Array)
        body['contents'] = input['messages'].map do |m|
          {
            'role' => (m['role'] || 'user'),
            'parts' => Array(m['parts'] || (m['text'] ? [{ 'text' => m['text'] }] : []))
          }
        end
      # 3) single text → single message
      elsif input['text'].present?
        body['contents'] = [{ 'role' => 'user', 'parts' => [{ 'text' => input['text'] }] }]
      end

      # Optional multimodal: image bytes/url (if caller provided)
      if input['image_url'].present?
        body['contents'] ||= []
        body['contents'] << { 'role' => 'user', 'parts' => [{ 'fileData' => { 'mime_type' => input['image_mime'] || 'image/png', 'file_uri' => input['image_url'] } }] }
      elsif input['image_bytes'].present?
        body['contents'] ||= []
        body['contents'] << { 'role' => 'user', 'parts' => [{ 'inlineData' => { 'mime_type' => input['image_mime'] || 'image/png', 'data' => input['image_bytes'] } }] }
      end

      # System instruction and tools if present
      body['system_instruction'] = input['system_instruction'] if input['system_instruction'].present?
      body['tools']              = input['tools'] if input['tools'].present?

      # Generation config (temperature, topP, topK, maxOutputTokens…)
      if input['options'].is_a?(Hash)
        gc = {}
        gc['temperature']      = input['options']['temperature'] if input['options'].key?('temperature')
        gc['topP']             = input['options']['topP']        if input['options'].key?('topP')
        gc['topK']             = input['options']['topK']        if input['options'].key?('topK')
        gc['maxOutputTokens']  = input['options']['max_tokens']  if input['options'].key?('max_tokens')
        body['generation_config'] = gc unless gc.empty?
      end

      # Safety settings if provided in input (many of your actions append config_schema.only('safetySettings'))
      body['safetySettings'] = input['safetySettings'] if input['safetySettings'].present?

      # Operation‑specific nudges (lightweight, optional)
      case operation
      when :translate
        # Encourage JSON‑only reply for extractors that set json_response: true
        body['tools'] ||= []
      when :parse
        # If schema provided, include a brief instruction for structured output
        if input['object_schema'].present?
          body['system_instruction'] ||= {}
          body['system_instruction']['parts'] ||= []
          body['system_instruction']['parts'] << { 'text' => "Return ONLY valid JSON that matches this schema: #{input['object_schema']}" }
        end
      when :email
        # Gentle steer to subject/body keys
        si = "Draft an email. Return JSON with keys: subject, body."
        body['system_instruction'] ||= { 'parts' => [{ 'text' => si }] }
      when :ai_classify
        if input['categories'].is_a?(Array)
          cats = input['categories'].map { |c| "#{c['key']}: #{c['description']}" }.join("\n")
          steer = "Classify into one of the categories below. Return JSON {selected_category, confidence, alternatives[]}.\nCategories:\n#{cats}"
          body['system_instruction'] ||= { 'parts' => [{ 'text' => steer }] }
        end
      end

      body
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Vertex AI — unified executor + extractors
    # ─────────────────────────────────────────────────────────────────────────────
    run_vertex: lambda do |connection, input, operation, verb: :generate, extract: { type: :generic, json_response: false }|
      model = call('validate_model!', connection, input['model'] || 'publishers/google/models/gemini-1.5-pro')
      url   = call('vertex_models_url', connection, model, verb)

      body  = call('build_vertex_body', connection, input, operation)

      call('with_resilience', connection,
        key: "vertex.#{operation}",
        max_retries: 3,
        retry_on_response: [429, 500, 502, 503, 504]) do |cid|

        resp = call('api_request', connection, :post, url, {
          headers: call('vertex_headers', connection, cid),
          payload: body,
          context: { action: "Vertex #{operation}", correlation_id: cid },
          error_handler: lambda do |code, body, message|
            # Normalize Google error shape if present
            google_error = (call('safe_json_parse', body || '') || {})['error'] rescue nil
            details = google_error ? "#{google_error['status']} #{google_error['message']}" : message
            error("Vertex error (#{code}): #{details}")
          end
        })

        # Extract and normalize according to requested output
        out = case extract[:type].to_sym
              when :generic     then call('extract_generic', resp, json_response: !!extract[:json_response])
              when :parsed      then call('extract_parsed',  resp, input['object_schema'])
              when :email       then call('extract_email',   resp)
              when :classify    then call('extract_classify',resp, input['options'] || {})
              else
                call('extract_generic', resp, json_response: !!extract[:json_response])
              end

        call('merge_common_telemetry', out, resp)
      end
    end,

    first_text_from_candidates: lambda do |resp|
      # Vertex responses (generative) include candidates[].content.parts[].text
      cand = (resp['candidates'] || []).first || {}
      parts = ((cand['content'] || {})['parts'] || [])
      text_part = parts.find { |p| p['text'] } || {}
      text_part['text']
    end,

    vertex_meta_from_response: lambda do |resp|
      {
        'response_id'  => (resp['responseId'] || resp['name']),
        'model_version'=> (resp['modelVersion'] || resp['model'])
      }.compact
    end,

    usage_from_response: lambda do |resp|
      usage = resp['usageMetadata'] || resp['metadata']&.dig('tokenMetadata')
      return {} unless usage

      {
        'promptTokenCount'     => usage['promptTokenCount'] || usage.dig('inputTokenCount','totalTokens'),
        'candidatesTokenCount' => usage['candidatesTokenCount'] || usage.dig('outputTokenCount','totalTokens'),
        'totalTokenCount'      => usage['totalTokenCount'] || [usage['promptTokenCount'], usage['candidatesTokenCount']].compact.sum
      }.compact
    end,

    safety_from_response: lambda do |resp|
      (resp['candidates'] || []).first&.[]('safetyRatings') || []
    end,

    merge_common_telemetry: lambda do |out, resp|
      out['usage']  ||= call('usage_from_response', resp)
      out['vertex'] ||= call('vertex_meta_from_response', resp)
      out['rate_limit_status'] ||= resp['rate_limit_status']
      # Preserve trace from api_request/with_resilience
      out['trace'] ||= resp['trace']
      out
    end,

    extract_generic: lambda do |resp, json_response: false|
      text = call('first_text_from_candidates', resp)
      if json_response
        parsed = call('safe_json_parse', text) || {}
        { 'answer' => parsed }
      else
        { 'answer' => text }
      end.merge(
        'safetyRatings' => call('safety_from_response', resp)
      )
    end,

    extract_parsed: lambda do |resp, schema_json|
      text   = call('first_text_from_candidates', resp)
      parsed = call('safe_json_parse', text) || {}
      # Basic schema enforcement: populate missing keys with nil
      begin
        schema = call('safe_json_parse', schema_json) || {}
        desired_keys =
          if schema['properties'].is_a?(Hash)
            schema['properties'].keys
          else
            parsed.keys
          end
        normalized = desired_keys.each_with_object({}) { |k, h| h[k] = parsed.key?(k) ? parsed[k] : nil }
        { }.merge(normalized)
      rescue
        parsed
      end.merge(
        'safetyRatings' => call('safety_from_response', resp),
        'usage' => call('usage_from_response', resp)
      )
    end,

    extract_email: lambda do |resp|
      text = call('first_text_from_candidates', resp)
      as_json = call('safe_json_parse', text)
      if as_json && as_json['subject'] && as_json['body']
        { 'subject' => as_json['subject'], 'body' => as_json['body'] }
      else
        # Fallback heuristic
        subject = text.to_s.lines.first.to_s.strip.gsub(/^subject[:\-]\s*/i, '')
        body    = text.to_s.sub(text.to_s.lines.first.to_s, '').strip
        { 'subject' => subject.presence || 'Draft subject', 'body' => body.presence || 'Hi {{recipient}},\n\n<Your message here>\n\nBest,\n{{sender}}' }
      end
    end,

    extract_classify: lambda do |resp, options|
      text   = call('first_text_from_candidates', resp)
      as_json= call('safe_json_parse', text) || {}
      selected = as_json['selected_category'] || as_json['category'] || text.to_s[0..200]
      conf     = as_json['confidence'] || (options['return_confidence'] == false ? nil : 0.0)
      alts     = as_json['alternatives'] || []
      {
        'selected_category' => selected,
        'confidence'        => conf,
        'alternatives'      => alts
      }.merge(
        'safetyRatings' => call('safety_from_response', resp),
        'usage'         => call('usage_from_response', resp)
      )
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Embeddings
    # ─────────────────────────────────────────────────────────────────────────────
    generate_embeddings_batch_exec: lambda do |connection, input|
      model     = call('validate_model!', connection, input['model'] || 'publishers/google/models/text-embedding-004')
      url       = call('vertex_models_url', connection, model, :embed_text_batch)
      texts     = input['texts'] || []
      task_type = input['task_type']

      started = Time.now
      call('with_resilience', connection, key: 'vertex.embed.batch') do |cid|
        payload = {
          'requests' => texts.map do |t|
            str = [input['title'], t['content']].compact.join("\n\n")
            req = { 'text' => str }
            req['taskType'] = task_type if task_type.present?
            req
          end
        }

        resp = call('api_request', connection, :post, url, {
          headers: call('vertex_headers', connection, cid),
          payload: payload
        })

        # Shape: responses[].values[]
        responses = resp['responses'] || []
        embeddings = responses.each_with_index.map do |r, idx|
          vec = (r.dig('embeddings','values') || r.dig('embedding','values') || [])
          {
            'id'         => texts[idx]['id'],
            'vector'     => vec,
            'dimensions' => vec.length,
            'metadata'   => texts[idx]['metadata']
          }
        end

        total = texts.length
        success = embeddings.count { |e| e['vector'].is_a?(Array) && e['vector'].any? }
        failcnt = total - success

        {
          'batch_id'               => input['batch_id'] || "batch_#{cid}",
          'embeddings_count'       => embeddings.length,
          'embeddings'             => embeddings,
          'first_embedding'        => embeddings.first,
          'embeddings_json'        => embeddings.to_json,
          'model_used'             => model,
          'total_processed'        => total,
          'successful_requests'    => success,
          'failed_requests'        => failcnt,
          'total_tokens'           => nil,
          'batches_processed'      => 1,
          'api_calls_saved'        => (total > 1 ? total - 1 : 0),
          'estimated_cost_savings' => 0.0,
          'pass_fail'              => failcnt.zero?,
          'action_required'        => failcnt.zero? ? 'ready_for_indexing' : 'retry_failed'
        }.merge(call('merge_common_telemetry', {}, resp))
      end
    end,

    generate_embedding_single_exec: lambda do |connection, input|
      model     = call('validate_model!', connection, input['model'] || 'publishers/google/models/text-embedding-004')
      url       = call('vertex_models_url', connection, model, :embed_text)
      task_type = input['task_type']

      call('with_resilience', connection, key: 'vertex.embed.single') do |cid|
        str = [input['title'], input['text']].compact.join("\n\n")
        payload = { 'text' => str }
        payload['taskType'] = task_type if task_type.present?

        resp = call('api_request', connection, :post, url, {
          headers: call('vertex_headers', connection, cid),
          payload: payload
        })

        vec = (resp.dig('embeddings','values') || resp.dig('embedding','values') || [])
        {
          'vector'      => vec,
          'dimensions'  => vec.length,
          'model_used'  => model,
          'token_count' => nil
        }.merge(call('merge_common_telemetry', {}, resp))
      end
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Vector Search (Index Endpoint query)
    # ─────────────────────────────────────────────────────────────────────────────
    vindex_find_neighbors: lambda do |_connection, input|
      # The endpoint is external (public domain or PSC). We accept full url + body.
      endpoint = input['endpoint_url'] || input['endpoint_host'] || error('endpoint_url or endpoint_host required')
      url = endpoint.include?('://') ? endpoint : "https://#{endpoint}"
      url = "#{url}/v1/findNeighbors" if url !~ /\/findNeighbors$/

      call('with_resilience', nil, key: 'vindex.find') do |cid|
        call('api_request', nil, :post, url, {
          headers: { 'Content-Type' => 'application/json', 'X-Correlation-Id' => cid },
          payload: {
            'deployedIndexId' => input['deployedIndexId'],
            'queries'         => input['queries'],
            'neighborCount'   => input['neighborCount'] || 10,
            'filter'          => input['filter']
          }.compact
        })
      end
    end,

    transform_find_neighbors_response: lambda do |resp|
      nn = resp['nearestNeighbors'] || []
      top = nn.flat_map do |q|
        (q['neighbors'] || []).map do |n|
          id = n.dig('datapoint','datapointId')
          dist = n['distance']
          { 'id' => id, 'distance' => dist, 'similarity' => (1.0 - dist.to_f).round(6) }
        end
      end
      { 'nearestNeighbors' => nn, 'top_matches' => top }
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Vector Search (Upsert datapoints)
    # ─────────────────────────────────────────────────────────────────────────────
    batch_upsert_datapoints: lambda do |connection, index_id, datapoints, update_mask|
      error('index_id required')    if index_id.blank?
      error('datapoints required')  if !datapoints.is_a?(Array) || datapoints.empty?

      base = call('vertex_base_url', connection)
      url  = "#{base}/#{index_id.split('/projects/').last ? index_id : index_id}" # tolerate full resource or relative
      url  = "#{base}/#{index_id}" unless index_id.start_with?('projects/')

      upsert_url = "#{url}:upsertDatapoints"

      chunks = datapoints.each_slice(100).to_a
      successful = 0
      failed = 0
      errors = []

      chunks.each_with_index do |chunk, i|
        call('with_resilience', connection, key: 'vindex.upsert') do |cid|
          payload = {
            'datapoints' => chunk.map do |dp|
              h = {
                'datapointId'   => dp['datapoint_id'],
                'featureVector' => dp['feature_vector'],
              }
              if dp['restricts'].is_a?(Array)
                h['restricts'] = dp['restricts'].map do |r|
                  { 'namespace' => r['namespace'], 'allowList' => r['allowList'], 'denyList' => r['denyList'] }.compact
                end
              end
              h['crowdingTag'] = { 'crowdingAttribute' => dp['crowding_tag'] } if dp['crowding_tag'].present?
              h
            end
          }
          payload['updateMask'] = update_mask if update_mask.present?

          resp = call('api_request', connection, :post, upsert_url, {
            headers: call('vertex_headers', connection, cid),
            payload: payload
          })

          # If API returns per-item errors, collect; otherwise assume success
          per_errors = (resp['errors'] || []).map { |e| { 'datapoint_id' => e['datapointId'], 'error' => e['message'] } }
          if per_errors.any?
            errors.concat(per_errors)
            failed += per_errors.size
            successful += (chunk.size - per_errors.size)
          else
            successful += chunk.size
          end
        end
      end

      # Fetch basic index stats
      stats = {}
      begin
        resp = call('api_request', connection, :get, url, { headers: { 'Accept' => 'application/json' } })
        stats = {
          'index_id'        => index_id,
          'deployed_state'  => resp['deployedIndexes']&.any? ? 'DEPLOYED' : 'NOT_DEPLOYED',
          'total_datapoints'=> resp['indexStats']&.[]('vectorsCount'),
          'dimensions'      => resp['indexUpdateMethod']&.[]('dimensions'),
          'display_name'    => resp['displayName'],
          'created_time'    => resp['createTime'],
          'updated_time'    => resp['updateTime']
        }.compact
      rescue
        # ignore stats failure
      end

      {
        'successful_upserts' => successful,
        'failed_upserts'     => failed,
        'error_details'      => errors,
        'total_processed'    => datapoints.length,
        'index_stats'        => stats
      }
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Google Drive helpers
    # ─────────────────────────────────────────────────────────────────────────────
    drive_api_url: lambda do |endpoint, file_id = nil|
      base = 'https://www.googleapis.com/drive/v3'
      case endpoint.to_sym
      when :files       then "#{base}/files"
      when :changes     then "#{base}/changes"
      when :start_token then "#{base}/changes/startPageToken"
      when :file        then error('file_id required') if file_id.blank?; "#{base}/files/#{file_id}"
      when :export      then error('file_id required') if file_id.blank?; "#{base}/files/#{file_id}/export"
      when :download    then error('file_id required') if file_id.blank?; "#{base}/files/#{file_id}?alt=media"
      else base
      end
    end,

    extract_drive_file_id: lambda do |id_or_url|
      return id_or_url if id_or_url.to_s !~ /https?:\/\//
      # supports https://drive.google.com/file/d/<id>/view and sharing links
      if id_or_url =~ /\/d\/([^\/]+)/
        Regexp.last_match(1)
      elsif id_or_url =~ /id=([^&]+)/
        Regexp.last_match(1)
      else
        error('Unable to extract Drive file ID from URL')
      end
    end,

    build_drive_query: lambda do |opts|
      qs = []
      if opts[:folder_id]
        qs << "'#{opts[:folder_id]}' in parents"
      end
      if opts[:modified_after]
        qs << "modifiedTime > '#{opts[:modified_after]}'"
      end
      if opts[:modified_before]
        qs << "modifiedTime < '#{opts[:modified_before]}'"
      end
      if opts[:mime_type]
        qs << "mimeType = '#{opts[:mime_type]}'"
      end
      if opts[:exclude_folders]
        qs << "mimeType != 'application/vnd.google-apps.folder'"
      end
      qs.empty? ? nil : qs.join(' and ')
    end,

    handle_drive_error: lambda do |_connection, code, body, message, ctx|
      detail = (call('safe_json_parse', body || '') || {})['error'] rescue nil
      dmsg = detail ? "#{detail['code']} #{detail['message']}" : message
      "[Drive] #{ctx&.dig(:action) || 'request'} failed (#{code}): #{dmsg}"
    end,

    # Fetches metadata and (optionally) content; auto-converts Google Docs → text
    fetch_drive_file_full: lambda do |connection, file_id, include_content|
      call('with_resilience', connection, key: 'drive.files.get') do |cid|
        # Metadata
        meta = call('api_request', connection, :get, "#{call('drive_api_url', :files)}/files/#{file_id}", {
          params: { fields: 'id,name,mimeType,size,modifiedTime,md5Checksum' },
          headers: { 'X-Correlation-Id' => cid },
          error_handler: lambda do |code, body, message|
            error(call('handle_drive_error', connection, code, body, message, { action: 'Get Drive file', correlation_id: cid }))
          end
        })

        out = {
          'id' => meta['id'],
          'name' => meta['name'],
          'mime_type' => meta['mimeType'],
          'size' => meta['size']&.to_i,
          'modified_time' => meta['modifiedTime'],
          'checksum' => meta['md5Checksum']
        }

        if include_content
          if meta['mimeType'].to_s.start_with?('application/vnd.google-apps.')
            # Export Google Docs to text
            export_mime = case meta['mimeType']
                          when 'application/vnd.google-apps.document' then 'text/plain'
                          when 'application/vnd.google-apps.spreadsheet' then 'text/csv'
                          when 'application/vnd.google-apps.presentation' then 'text/plain'
                          else 'text/plain'
                          end
            export = call('api_request', connection, :get, "#{call('drive_api_url', :files)}/files/#{file_id}/export", {
              params: { mimeType: export_mime },
              headers: { 'X-Correlation-Id' => cid }
            })
            out['content'] = export.is_a?(Hash) ? export['data'] : export
            out['needs_processing'] = false
          else
            # Binary file (PDFs/images) — return marker
            dl = call('api_request', connection, :get, "#{call('drive_api_url', :files)}/files/#{file_id}", {
              params: { alt: 'media' }, headers: { 'X-Correlation-Id' => cid }
            })
            out['content'] = dl.is_a?(Hash) ? dl['data'] : dl
            out['needs_processing'] = !meta['mimeType'].to_s.start_with?('text/')
          end
        end

        out.merge('trace' => meta['trace'])
      end
    end,

    classify_drive_change: lambda do |change, include_removed|
      if change['removed'] && include_removed
        return { kind: :removed, summary: { 'fileId' => change['fileId'], 'time' => change['time'] } }
      end

      file = change['file'] || {}
      return { kind: :skip } if file.empty?

      summary = {
        'id' => file['id'],
        'name' => file['name'],
        'mimeType' => file['mimeType'],
        'modifiedTime' => file['modifiedTime'],
        'checksum' => file['md5Checksum']
      }
      { kind: :added_or_modified, summary: summary }
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Samples for object definitions (used by your actions)
    # ─────────────────────────────────────────────────────────────────────────────
    safety_ratings_output_sample: lambda do
      { 'safetyRatings' => [{ 'category' => 'HARM_CATEGORY_HATE_SPEECH', 'probability' => 'NEGLIGIBLE' }] }
    end,

    usage_output_sample: lambda do
      { 'usage' => { 'promptTokenCount' => 12, 'candidatesTokenCount' => 34, 'totalTokenCount' => 46 } }
    end,

    sample_record_output: lambda do |kind|
      base = {
        'trace' => { 'correlation_id' => 'sample-cid', 'duration_ms' => 123 },
        'vertex' => { 'response_id' => 'sample-response-id', 'model_version' => 'gemini-1.5-pro' },
        'rate_limit_status' => { 'limit' => '100', 'remaining' => '99' }
      }
      case kind
      when 'send_message'
        base.merge('answer' => 'Hello from Gemini!')
      when 'translate_text'
        base.merge('answer' => 'Bonjour le monde')
      when 'summarize_text'
        base.merge('answer' => 'Concise summary...')
      when 'draft_email'
        base.merge('subject' => 'Subject line', 'body' => 'Body text...')
      when 'analyze_text','analyze_image'
        base.merge('answer' => 'Analysis result...')
      else
        base
      end
    end,

    format_parse_sample: lambda do |schema_json|
      schema = (JSON.parse(schema_json) rescue {}) || {}
      fields = schema['properties']&.keys || %w[id name date]
      fields.each_with_object({}) { |k, h| h[k] = nil }
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Probes for test_connection
    # ─────────────────────────────────────────────────────────────────────────────
    probe_vertex_ai: lambda do |connection, test_models: false|
      started = Time.now
      status = 'connected'
      warn = nil
      begin
        # Lightweight "whoami" via locations.get
        base = call('vertex_base_url', connection)
        test = call('api_request', connection, :get, base, { headers: { 'Accept' => 'application/json' } })
        if test['error']
          status = 'failed'
        end

        if test_models
          # try listing a known public model
          list_url = "#{base}/publishers/google/models"
          _ = call('api_request', connection, :get, list_url, { headers: { 'Accept' => 'application/json' } })
        end
      rescue => e
        status = 'failed'
        warn = e.message
      end

      {
        'service' => 'Vertex AI',
        'status' => status,
        'response_time_ms' => ((Time.now - started) * 1000).round,
        'warning' => warn,
        'permissions_validated' => status == 'connected' ? ['aiplatform.*'] : []
      }.compact
    end,

    probe_drive: lambda do |_connection, verbose: false|
      started = Time.now
      status = 'connected'
      warning = nil
      begin
        # hit changes.getStartPageToken as a permission probe
        _ = call('api_request', nil, :get, "#{call('drive_api_url', :start_token)}/changes/startPageToken", { headers: { 'Accept' => 'application/json' } })
      rescue => e
        status = 'failed'
        warning = e.message
      end
      out = {
        'service' => 'Google Drive',
        'status' => status,
        'response_time_ms' => ((Time.now - started) * 1000).round
      }
      out['warning'] = warning if warning && verbose
      out
    end,

    probe_index: lambda do |connection, index_id|
      base = call('vertex_base_url', connection)
      url  = "#{base}/#{index_id}"
      begin
        resp = call('api_request', connection, :get, url, { headers: { 'Accept' => 'application/json' } })
        {
          'service' => 'Vector Search Index',
          'status'  => 'connected',
          'deployed'=> resp['deployedIndexes']&.any?,
          'response_time_ms' => 100
        }
      rescue => e
        { 'service' => 'Vector Search Index', 'status' => 'failed', 'error' => e.message }
      end
    end,

    vertex_rpm_limits: lambda do
      # Static fallback; if you have a quota endpoint, wire it here.
      { 'generateContent' => 60, 'embedText' => 120 }
    end
  },
  
  object_definitions: {
    # ─────────────────────────────────────────────────────────────────────────────
    # Telemetry fragments (shared)
    # ─────────────────────────────────────────────────────────────────────────────
    trace_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'trace', type: 'object', properties: [
            { name: 'correlation_id', type: 'string' },
            { name: 'duration_ms',   type: 'integer' }
          ] }
        ]
      end
    },

    vertex_meta_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'vertex', type: 'object', properties: [
            { name: 'response_id',  type: 'string' },
            { name: 'model_version', type: 'string' }
          ] }
        ]
      end
    },

    # New header-derived rate limit shape (keeps a few legacy fields optional for compatibility)
    rate_limit_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'rate_limit_status', type: 'object', properties: [
            # Header-derived fields (new)
            { name: 'retry_after', type: 'string', label: 'Retry-After (sec)' },
            { name: 'limit',       type: 'string', label: 'X-RateLimit-Limit' },
            { name: 'remaining',   type: 'string', label: 'X-RateLimit-Remaining' },
            { name: 'reset_epoch', type: 'string', label: 'X-RateLimit-Reset' },
            # Legacy counters (optional; harmless if absent)
            { name: 'requests_last_minute', type: 'integer', label: 'Requests in last minute' },
            { name: 'throttled',            type: 'boolean', label: 'Was throttled' },
            { name: 'sleep_ms',             type: 'integer', label: 'Sleep time (ms)' }
          ] }
        ]
      end
    },

    # Safety (now the raw Vertex array, camelCase)
    safety_ratings_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'safetyRatings', type: 'array', of: 'object', properties: [
            { name: 'category' },
            { name: 'probability' },
            { name: 'probabilityScore', type: 'number' },
            { name: 'severity' },
            { name: 'severityScore', type: 'number' }
          ] }
        ]
      end
    },

    usage_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'usage', type: 'object', properties: [
            { name: 'promptTokenCount',     type: 'integer' },
            { name: 'candidatesTokenCount', type: 'integer' },
            { name: 'totalTokenCount',      type: 'integer' }
          ] }
        ]
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Common input fragments
    # ─────────────────────────────────────────────────────────────────────────────
    text_model_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'model', group: 'Model', optional: false,
            control_type: 'select', extends_schema: true, pick_list: :available_text_models,
            hint: 'Gemini model to use',
            toggle_hint: 'Select from list',
            toggle_field: { name: 'model', label: 'Model', type: 'string', control_type: 'text',
              extends_schema: true, optional: false,
              hint: 'publishers/{publisher}/models/{model}' } }
        ]
      end
    },

    # New: generation options consumed by build_vertex_body (mapped to generation_config)
    gen_options_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'options', type: 'object', group: 'Generation options', properties: [
            { name: 'temperature',   type: 'number',  hint: '0.0–2.0 (randomness)' },
            { name: 'topP',          type: 'number',  hint: '0–1 nucleus sampling' },
            { name: 'topK',          type: 'number',  hint: '1–40 token shortlist' },
            { name: 'max_tokens',    type: 'integer', label: 'Max output tokens' },
            { name: 'candidateCount',type: 'integer' },
            { name: 'stopSequences', type: 'array', of: 'string' },
            { name: 'responseMimeType', label: 'Response MIME type',
              control_type: 'select', pick_list: :response_type,
              toggle_hint: 'Select from list',
              toggle_field: { name: 'responseMimeType', type: 'string', control_type: 'text', optional: true } },
            { name: 'seed',          type: 'integer', hint: 'Determinism (when supported)' }
          ] }
        ]
      end
    },

    tools_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'tools', type: 'array', of: 'object', group: 'Tools', properties: [
            { name: 'functionDeclarations', type: 'array', of: 'object', properties: [
              { name: 'name' }, { name: 'description' },
              { name: 'parameters', control_type: 'text-area', hint: 'JSON Schema' }
            ] }
          ] },
          { name: 'toolConfig', type: 'object', group: 'Tools', properties: [
            { name: 'functionCallingConfig', type: 'object', properties: [
              { name: 'mode', control_type: 'select', pick_list: :function_call_mode,
                toggle_hint: 'Select from list',
                toggle_field: { name: 'mode', type: 'string', control_type: 'text', optional: true } },
              { name: 'allowedFunctionNames', type: 'array', of: 'string' }
            ] }
          ] }
        ]
      end
    },

    safety_settings_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'safetySettings', type: 'array', of: 'object', group: 'Safety', properties: [
            { name: 'category',  control_type: 'select', pick_list: :safety_categories,
              toggle_hint: 'Select from list',
              toggle_field: { name: 'category', type: 'string', control_type: 'text', optional: true } },
            { name: 'threshold', control_type: 'select', pick_list: :safety_threshold,
              toggle_hint: 'Select from list',
              toggle_field: { name: 'threshold', type: 'string', control_type: 'text', optional: true } },
            { name: 'method',    control_type: 'select', pick_list: :safety_method,
              toggle_hint: 'Select from list',
              toggle_field: { name: 'method', type: 'string', control_type: 'text', optional: true } }
          ] }
        ]
      end
    },

    # New: system instruction (snake_case, as expected by build_vertex_body)
    system_instruction_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'system_instruction', type: 'object', group: 'System instruction', properties: [
            { name: 'role', hint: 'Use "model" for system instructions' },
            { name: 'parts', type: 'array', of: 'object', properties: [
              { name: 'text', control_type: 'text-area' }
            ] }
          ] }
        ]
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Generic text input
    # ─────────────────────────────────────────────────────────────────────────────
    text_input_field: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'text', label: 'Text', type: 'string', control_type: 'text-area', optional: false,
            hint: 'Up to ~8,000 words recommended.' }
        ]
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Send messages (now returns answer, not raw candidates)
    # ─────────────────────────────────────────────────────────────────────────────
    send_messages_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'] +
        [
          # Prefer messages[] (role + text); or just provide text
          { name: 'messages', type: 'array', of: 'object', optional: true, group: 'Message',
            hint: 'Optional. If omitted, provide Text instead.',
            properties: [
              { name: 'role', control_type: 'select', pick_list: :chat_role,
                toggle_hint: 'Select from list',
                toggle_field: { name: 'role', type: 'string', control_type: 'text', optional: true } },
              { name: 'text', control_type: 'text-area' },
              # Optional multimodal parts (camelCase for Vertex)
              { name: 'fileData',  type: 'object', properties: [{ name: 'mimeType' }, { name: 'fileUri' }] },
              { name: 'inlineData',type: 'object', properties: [{ name: 'mimeType' }, { name: 'data'    }] }
            ] },
        ] +
        object_definitions['tools_schema'] +
        object_definitions['safety_settings_schema'] +
        object_definitions['system_instruction_schema'] +
        object_definitions['gen_options_schema'] +
        [
          # Fallback single text (if messages[] not provided)
          { name: 'text', label: 'Text (single message)', type: 'string', control_type: 'text-area', optional: true }
        ]
      end
    },

    send_messages_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer', type: 'string', label: 'Model answer' }
        ]
        .concat(object_definitions['safety_ratings_schema'])
        .concat(object_definitions['usage_schema'])
        .concat(object_definitions['rate_limit_schema'])
        .concat(object_definitions['trace_schema'])
        .concat(object_definitions['vertex_meta_schema'])
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Translate / Summarize / Analyze text (generic extractor)
    # ─────────────────────────────────────────────────────────────────────────────
    translate_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'] + [
          { name: 'to',   label: 'Output language', type: 'string', optional: false },
          { name: 'from', label: 'Source language', type: 'string', optional: true },
          { name: 'text', label: 'Source text',     type: 'string', control_type: 'text-area', optional: false }
        ] + object_definitions['safety_settings_schema'] + object_definitions['gen_options_schema']
      end
    },

    translate_text_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer', label: 'Translation' }
        ]
        .concat(object_definitions['safety_ratings_schema'])
        .concat(object_definitions['usage_schema'])
        .concat(object_definitions['rate_limit_schema'])
        .concat(object_definitions['trace_schema'])
        .concat(object_definitions['vertex_meta_schema'])
      end
    },

    summarize_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'] +
        object_definitions['text_input_field'] +
        [
          { name: 'max_words', label: 'Maximum words', type: 'integer', control_type: 'integer', optional: true }
        ] + object_definitions['safety_settings_schema'] + object_definitions['gen_options_schema']
      end
    },

    summarize_text_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer', label: 'Summary' }
        ]
        .concat(object_definitions['safety_ratings_schema'])
        .concat(object_definitions['usage_schema'])
        .concat(object_definitions['rate_limit_schema'])
        .concat(object_definitions['trace_schema'])
        .concat(object_definitions['vertex_meta_schema'])
      end
    },

    analyze_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'] + [
          { name: 'text',     label: 'Source text', type: 'string', control_type: 'text-area', optional: false },
          { name: 'question', label: 'Instruction', type: 'string', optional: false }
        ] + object_definitions['safety_settings_schema'] + object_definitions['gen_options_schema']
      end
    },

    analyze_text_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer', label: 'Analysis' }
        ]
        .concat(object_definitions['safety_ratings_schema'])
        .concat(object_definitions['usage_schema'])
        .concat(object_definitions['rate_limit_schema'])
        .concat(object_definitions['trace_schema'])
        .concat(object_definitions['vertex_meta_schema'])
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Parse text → structured (schema-driven)
    # ─────────────────────────────────────────────────────────────────────────────
    parse_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'] + [
          { name: 'text', label: 'Source text', type: 'string', control_type: 'text-area', optional: false },
          { name: 'object_schema', label: 'Fields to identify', control_type: 'schema-designer',
            extends_schema: true, sample_data_type: 'json_http', optional: false,
            empty_schema_title: 'Define output fields',
            custom_properties: [{ name: 'description', type: 'string', optional: true }] }
        ] + object_definitions['safety_settings_schema'] + object_definitions['gen_options_schema']
      end
    },

    parse_text_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        base =
          if config_fields['object_schema'].present?
            parse_json(config_fields['object_schema'])
          else
            []
          end
        Array(base)
          .concat(object_definitions['safety_ratings_schema'])
          .concat(object_definitions['usage_schema'])
          .concat(object_definitions['rate_limit_schema'])
          .concat(object_definitions['trace_schema'])
          .concat(object_definitions['vertex_meta_schema'])
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Draft email (subject + body)
    # ─────────────────────────────────────────────────────────────────────────────
    draft_email_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'] + [
          { name: 'email_description', label: 'Email description', type: 'string', control_type: 'text-area', optional: false }
        ] + object_definitions['safety_settings_schema'] + object_definitions['gen_options_schema']
      end
    },

    draft_email_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'subject' }, { name: 'body' }
        ]
        .concat(object_definitions['safety_ratings_schema'])
        .concat(object_definitions['usage_schema'])
        .concat(object_definitions['rate_limit_schema'])
        .concat(object_definitions['trace_schema'])
        .concat(object_definitions['vertex_meta_schema'])
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # AI Classification (minimal shape; extras optional)
    # ─────────────────────────────────────────────────────────────────────────────
    ai_classify_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'] + [
          { name: 'text', type: 'string', control_type: 'text-area', optional: false, label: 'Text to classify' },
          { name: 'categories', type: 'array', of: 'object', optional: false, properties: [
            { name: 'key', type: 'string', optional: false },
            { name: 'description', type: 'string', optional: true }
          ] },
          { name: 'options', type: 'object', optional: true, properties: [
            { name: 'return_confidence',   type: 'boolean', control_type: 'checkbox', default: true },
            { name: 'return_alternatives', type: 'boolean', control_type: 'checkbox', default: true },
            { name: 'temperature',         type: 'number',  default: 0.1 },
            { name: 'confidence_threshold',type: 'number',  hint: 'Optional downstream threshold' }
          ] }
        ] + object_definitions['safety_settings_schema'] + object_definitions['gen_options_schema']
      end
    },

    ai_classify_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'selected_category', type: 'string' },
          { name: 'confidence',        type: 'number' },
          { name: 'alternatives',      type: 'array', of: 'object', properties: [
            { name: 'category', type: 'string' },
            { name: 'confidence', type: 'number' }
          ] },
          # Optional downstream UX flags (may be blank if not computed)
          { name: 'requires_human_review', type: 'boolean' },
          { name: 'confidence_threshold',  type: 'number' },
          { name: 'pass_fail',             type: 'boolean' },
          { name: 'action_required',       type: 'string' }
        ]
        .concat(object_definitions['safety_ratings_schema'])
        .concat(object_definitions['usage_schema'])
        .concat(object_definitions['rate_limit_schema'])
        .concat(object_definitions['trace_schema'])
        .concat(object_definitions['vertex_meta_schema'])
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Analyze image (multimodal)
    # ─────────────────────────────────────────────────────────────────────────────
    analyze_image_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'model', optional: false, control_type: 'select', extends_schema: true,
            pick_list: :available_image_models, toggle_hint: 'Select from list',
            toggle_field: { name: 'model', type: 'string', control_type: 'text', optional: false,
                            hint: 'publishers/{publisher}/models/{model}' } },
          { name: 'question', label: 'Your question about the image', optional: false },
          # New builder supports either URL or inline bytes + mime
          { name: 'image_url',  label: 'Image URL',  optional: true },
          { name: 'image_bytes',label: 'Image bytes (base64)', optional: true },
          { name: 'image_mime', label: 'MIME type',  optional: true, hint: 'e.g., image/jpeg' }
        ]
        .concat(object_definitions['safety_settings_schema'])
        .concat(object_definitions['gen_options_schema'])
      end
    },

    analyze_image_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer', label: 'Analysis' }
        ]
        .concat(object_definitions['safety_ratings_schema'])
        .concat(object_definitions['usage_schema'])
        .concat(object_definitions['rate_limit_schema'])
        .concat(object_definitions['trace_schema'])
        .concat(object_definitions['vertex_meta_schema'])
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Embeddings (batch + single) — aligned to embedText/embedTextBatch
    # ─────────────────────────────────────────────────────────────────────────────
    generate_embeddings_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'batch_id', type: 'string', optional: false },
          { name: 'texts', type: 'array', of: 'object', optional: false, properties: [
            { name: 'id',      type: 'string',  optional: false },
            { name: 'content', type: 'string',  optional: false },
            { name: 'metadata',type: 'object',  optional: true  }
          ] },
          { name: 'model', type: 'string', optional: false, control_type: 'select',
            pick_list: :available_embedding_models, extends_schema: true,
            toggle_hint: 'Select from list',
            toggle_field: { name: 'model', type: 'string', control_type: 'text', optional: false } },
          { name: 'task_type', type: 'string', optional: true, control_type: 'select',
            pick_list: :embedding_task_list,
            toggle_hint: 'Select from list',
            toggle_field: { name: 'task_type', type: 'string', control_type: 'text', optional: true } },
          { name: 'title', type: 'string', optional: true, hint: 'Optional title prefix for better embeds' }
        ]
      end
    },

    generate_embeddings_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'batch_id',            type: 'string' },
          { name: 'embeddings_count',    type: 'integer' },
          { name: 'embeddings',          type: 'array', of: 'object', properties: [
            { name: 'id',         type: 'string' },
            { name: 'vector',     type: 'array', of: 'number' },
            { name: 'dimensions', type: 'integer' },
            { name: 'metadata',   type: 'object' }
          ] },
          { name: 'first_embedding', type: 'object', properties: [
            { name: 'id',         type: 'string' },
            { name: 'vector',     type: 'array', of: 'number' },
            { name: 'dimensions', type: 'integer' }
          ] },
          { name: 'embeddings_json',        type: 'string' },
          { name: 'model_used',             type: 'string' },
          { name: 'total_processed',        type: 'integer' },
          { name: 'successful_requests',    type: 'integer' },
          { name: 'failed_requests',        type: 'integer' },
          { name: 'total_tokens',           type: 'integer' },
          { name: 'batches_processed',      type: 'integer' },
          { name: 'api_calls_saved',        type: 'integer' },
          { name: 'estimated_cost_savings', type: 'number' },
          { name: 'pass_fail',              type: 'boolean' },
          { name: 'action_required',        type: 'string' }
        ]
        .concat(object_definitions['rate_limit_schema'])
        .concat(object_definitions['trace_schema'])
      end
    },

    generate_embedding_single_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'text', type: 'string', control_type: 'text-area', optional: false },
          { name: 'model', type: 'string', optional: false, control_type: 'select',
            pick_list: :available_embedding_models, extends_schema: true,
            toggle_hint: 'Select from list',
            toggle_field: { name: 'model', type: 'string', control_type: 'text', optional: false } },
          { name: 'task_type', type: 'string', optional: true, control_type: 'select',
            pick_list: :embedding_task_list,
            toggle_hint: 'Select from list',
            toggle_field: { name: 'task_type', type: 'string', control_type: 'text', optional: true } },
          { name: 'title', type: 'string', optional: true }
        ]
      end
    },

    generate_embedding_single_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'vector',     type: 'array', of: 'number' },
          { name: 'dimensions', type: 'integer' },
          { name: 'model_used', type: 'string' },
          { name: 'token_count',type: 'integer' }
        ]
        .concat(object_definitions['rate_limit_schema'])
        .concat(object_definitions['trace_schema'])
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Vector Search — findNeighbors (endpoint host/url)
    # ─────────────────────────────────────────────────────────────────────────────
    find_neighbors_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'endpoint_host', label: 'Endpoint host', optional: true,
            hint: 'e.g., 1234.us-central1.vdb.vertexai.goog (no scheme). Use endpoint_url instead if you prefer.' },
          { name: 'endpoint_url',  label: 'Endpoint URL',  optional: true,
            hint: 'Full https://... to the index endpoint; we will append /v1/findNeighbors if needed.' },
          { name: 'deployedIndexId', optional: false, hint: 'Deployed index id on the endpoint' },
          # Queries mirror Vertex REST (pass-through)
          { name: 'queries', type: 'array', of: 'object', optional: false, properties: [
            { name: 'datapoint', type: 'object', properties: [
              { name: 'datapointId' },
              { name: 'featureVector', type: 'array', of: 'number' },
              { name: 'sparseEmbedding', type: 'object', properties: [
                { name: 'values',     type: 'array', of: 'number'  },
                { name: 'dimensions', type: 'array', of: 'integer' }
              ] },
              { name: 'restricts', type: 'array', of: 'object', properties: [
                { name: 'namespace' },
                { name: 'allowList', type: 'array', of: 'string' },
                { name: 'denyList',  type: 'array', of: 'string' }
              ] },
              { name: 'numericRestricts', type: 'array', of: 'object', properties: [
                { name: 'namespace' },
                { name: 'op' },
                { name: 'valueInt',    type: 'integer' },
                { name: 'valueFloat',  type: 'number'  },
                { name: 'valueDouble', type: 'number'  }
              ] },
              { name: 'crowdingTag', type: 'object', properties: [ { name: 'crowdingAttribute' } ] }
            ] },
            { name: 'neighborCount', type: 'integer' },
            { name: 'approximateNeighborCount', type: 'integer' },
            { name: 'perCrowdingAttributeNeighborCount', type: 'integer' },
            { name: 'fractionLeafNodesToSearchOverride', type: 'number' }
          ] },
          { name: 'neighborCount', type: 'integer', hint: 'Optional top‑k override at the top level' },
          { name: 'filter',        type: 'object',  hint: 'Reserved for future filtering' }
        ]
      end
    },

    find_neighbors_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'top_matches', type: 'array', of: 'object', properties: [
            { name: 'id',        type: 'string' },
            { name: 'distance',  type: 'number' },
            { name: 'similarity',type: 'number' }
          ] },
          { name: 'nearestNeighbors', type: 'array', of: 'object' }
        ].concat(object_definitions['trace_schema'])
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Vector Search — upsert datapoints
    # ─────────────────────────────────────────────────────────────────────────────
    upsert_index_datapoints_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'index_id', type: 'string', optional: false },
          { name: 'datapoints', type: 'array', of: 'object', optional: false, properties: [
            { name: 'datapoint_id',   type: 'string',  optional: false },
            { name: 'feature_vector', type: 'array', of: 'number', optional: false },
            { name: 'restricts',      type: 'array', of: 'object', optional: true, properties: [
              { name: 'namespace' },
              { name: 'allowList', type: 'array', of: 'string' },
              { name: 'denyList',  type: 'array', of: 'string' }
            ] },
            { name: 'crowding_tag',   type: 'string',  optional: true }
          ] },
          { name: 'update_mask', type: 'string', optional: true }
        ]
      end
    },

    upsert_index_datapoints_output: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'successful_upserts', type: 'integer' },
          { name: 'failed_upserts',     type: 'integer' },
          { name: 'total_processed',    type: 'integer' },
          { name: 'error_details',      type: 'array', of: 'object', properties: [
            { name: 'datapoint_id', type: 'string' },
            { name: 'error',        type: 'string' }
          ] },
          { name: 'index_stats', type: 'object', properties: [
            { name: 'index_id',         type: 'string' },
            { name: 'deployed_state',   type: 'string' },
            { name: 'total_datapoints', type: 'integer' },
            { name: 'dimensions',       type: 'integer' },
            { name: 'display_name',     type: 'string' },
            { name: 'created_time',     type: 'string' },
            { name: 'updated_time',     type: 'string' }
          ] }
        ]
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Google Drive — shared shapes
    # ─────────────────────────────────────────────────────────────────────────────
    drive_file_fields: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'id',            label: 'File ID',      type: 'string' },
          { name: 'name',          label: 'File name',    type: 'string' },
          { name: 'mime_type',     label: 'MIME type',    type: 'string' },
          { name: 'size',          label: 'File size',    type: 'integer' },
          { name: 'modified_time', label: 'Modified time',type: 'date_time' },
          { name: 'checksum',      label: 'MD5 checksum', type: 'string' }
        ]
      end
    },

    drive_file_extended: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['drive_file_fields'] + [
          { name: 'content',          type: 'string', hint: 'Text or bytes (as returned)' },
          { name: 'needs_processing', type: 'boolean' },
        ] + object_definitions['trace_schema']
      end
    },

    fetch_drive_file_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'file_id',        label: 'File ID or URL', type: 'string',  optional: false },
          { name: 'include_content',label: 'Include content',type: 'boolean', optional: true, default: true }
        ]
      end
    },

    fetch_drive_file_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['drive_file_extended']
      end
    },

    list_drive_files_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'folder_id',       label: 'Folder ID or URL', type: 'string',  optional: true },
          { name: 'max_results',     label: 'Maximum results',   type: 'integer', optional: true, default: 100 },
          { name: 'modified_after',  label: 'Modified after',    type: 'date_time', optional: true },
          { name: 'modified_before', label: 'Modified before',   type: 'date_time', optional: true },
          { name: 'mime_type',       label: 'MIME type filter',  type: 'string', optional: true },
          { name: 'exclude_folders', label: 'Exclude folders',   type: 'boolean', optional: true, default: false },
          { name: 'page_token',      label: 'Page token',        type: 'string', optional: true }
        ]
      end
    },

    list_drive_files_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'files', type: 'array', of: 'object', properties: object_definitions['drive_file_fields'] },
          { name: 'count',           type: 'integer' },
          { name: 'has_more',        type: 'boolean' },
          { name: 'next_page_token', type: 'string' },
          { name: 'query_used',      type: 'string' }
        ] + object_definitions['trace_schema']
      end
    },

    batch_fetch_drive_files_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'file_ids',       type: 'array', of: 'string', optional: false },
          { name: 'include_content',type: 'boolean', default: true },
          { name: 'skip_errors',    type: 'boolean', default: true },
          { name: 'batch_size',     type: 'integer', default: 10 }
        ]
      end
    },

    batch_fetch_drive_files_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'successful_files', type: 'array', of: 'object', properties: object_definitions['drive_file_extended'] },
          { name: 'failed_files',     type: 'array', of: 'object', properties: [
            { name: 'file_id',      type: 'string' },
            { name: 'error_message',type: 'string' },
            { name: 'error_code',   type: 'string' }
          ] },
          { name: 'metrics', type: 'object', properties: [
            { name: 'total_processed',     type: 'integer' },
            { name: 'success_count',       type: 'integer' },
            { name: 'failure_count',       type: 'integer' },
            { name: 'success_rate',        type: 'number'  },
            { name: 'processing_time_ms',  type: 'integer' }
          ] }
        ]
      end
    },

    monitor_drive_changes_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'page_token',             type: 'string',  optional: true },
          { name: 'folder_id',              type: 'string',  optional: true },
          { name: 'include_removed',        type: 'boolean', optional: true, default: false },
          { name: 'include_shared_drives',  type: 'boolean', optional: true, default: false },
          { name: 'page_size',              type: 'integer', optional: true, default: 100 }
        ]
      end
    },

    monitor_drive_changes_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'changes', type: 'array', of: 'object', properties: [
            { name: 'changeType', type: 'string' },
            { name: 'time',       type: 'date_time' },
            { name: 'removed',    type: 'boolean' },
            { name: 'fileId',     type: 'string' },
            { name: 'file',       type: 'object', properties: [
              { name: 'id' }, { name: 'name' }, { name: 'mimeType' },
              { name: 'modifiedTime', type: 'date_time' },
              { name: 'size', type: 'integer' }, { name: 'md5Checksum' }, { name: 'trashed', type: 'boolean' }
            ] }
          ] },
          { name: 'new_page_token', type: 'string' },
          { name: 'files_added',    type: 'array', of: 'object', properties: [
            { name: 'id' }, { name: 'name' }, { name: 'mimeType' }, { name: 'modifiedTime', type: 'date_time' }
          ] },
          { name: 'files_modified', type: 'array', of: 'object', properties: [
            { name: 'id' }, { name: 'name' }, { name: 'mimeType' }, { name: 'modifiedTime', type: 'date_time' }, { name: 'checksum' }
          ] },
          { name: 'files_removed',  type: 'array', of: 'object', properties: [
            { name: 'fileId' }, { name: 'time', type: 'date_time' }
          ] },
          { name: 'summary', type: 'object', properties: [
            { name: 'total_changes', type: 'integer' },
            { name: 'added_count',   type: 'integer' },
            { name: 'modified_count',type: 'integer' },
            { name: 'removed_count', type: 'integer' },
            { name: 'has_more',      type: 'boolean' }
          ] },
          { name: 'is_initial_token', type: 'boolean' }
        ] + object_definitions['trace_schema']
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Test connection (unchanged shape; aligns with your current action)
    # ─────────────────────────────────────────────────────────────────────────────
    test_connection_output: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'timestamp',        type: 'datetime' },
          { name: 'overall_status',   type: 'string' },
          { name: 'all_tests_passed', type: 'boolean' },
          { name: 'environment', type: 'object', properties: [
            { name: 'project' }, { name: 'region' }, { name: 'api_version' }, { name: 'auth_type' }, { name: 'host' }
          ] },
          { name: 'tests_performed', type: 'array', of: 'object' },
          { name: 'errors',          type: 'array', of: 'string' },
          { name: 'warnings',        type: 'array', of: 'string' },
          { name: 'summary', type: 'object', properties: [
            { name: 'total_tests', type: 'integer' },
            { name: 'passed',      type: 'integer' },
            { name: 'failed',      type: 'integer' }
          ] },
          { name: 'recommendations', type: 'array', of: 'string' },
          { name: 'quota_info',      type: 'object' }
        ]
      end
    },

    # ─────────────────────────────────────────────────────────────────────────────
    # Legacy prediction (kept intact for compatibility)
    # ─────────────────────────────────────────────────────────────────────────────
    prediction: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'predictions', type: 'array', of: 'object', properties: [
            { name: 'content' },
            { name: 'citationMetadata', type: 'object' },
            { name: 'logprobs', type: 'object' },
            { name: 'safetyAttributes', type: 'object' }
          ] },
          { name: 'metadata', type: 'object' }
        ]
      end
    }
  },

  pick_lists: {
    # ─────────────────────────────────────────────────────────────────────────────
    # Model pickers (dynamic → static fallback). Values are fully-qualified.
    # ─────────────────────────────────────────────────────────────────────────────
    available_text_models: lambda do |connection|
      region = connection['region'].presence || 'us-central1'
      include_preview = !!connection['include_preview_models']
      begin
        url  = "https://#{region}-aiplatform.googleapis.com/v1/publishers/google/models"
        resp = call('api_request', connection, :get, url, {
          params: { pageSize: 500, view: 'PUBLISHER_MODEL_VIEW_BASIC' }
        })
        models = (resp['publisherModels'] || resp['models'] || []).map { |m|
          {
            id:  m['name'].to_s.split('/').last,
            dn:  m['displayName'].presence || m['name'].to_s.split('/').last.gsub('-', ' ').split.map(&:capitalize).join(' '),
            ls:  m['launchStage'].to_s
          }
        }

        # Filter: generative (text/multimodal), exclude embeddings/image-generation/tts/code, drop retired 1.0-* bison
        textish = models.select { |m|
          id = m[:id].downcase
          next false if id.include?('embedding') || id.include?('imagen') || id.include?('tts') || id.include?('code')
          next false if id =~ /(^|-)1\.0-.*|text-bison|chat-bison/
          id.include?('gemini') # gemini-family generative
        }
        textish = textish.select { |m| m[:ls] == 'GA' || include_preview }

        # Sort: by version (2.5 > 2.0 > 1.5 > 1.0) then Pro > Flash > Lite
        score = lambda do |id|
          v = if id =~ /(\d+)\.(\d+)/
                [$1.to_i, $2.to_i]
              elsif id =~ /gemini-pro$/; [1,0]
              else [0,0]
              end
          tier = (id =~ /pro/i) ? 0 : (id =~ /flash/i ? 1 : (id =~ /lite/i ? 2 : 3))
          [-v[0], -v[1], tier, id]
        end
        textish.sort_by! { |m| score.call(m[:id]) }

        opts = textish.map { |m| [m[:dn], "publishers/google/models/#{m[:id]}"] }
        if opts.present?
          opts
        else
          # Static fallback (curated)
          [
            ['Gemini 2.5 Pro',         'publishers/google/models/gemini-2.5-pro'],
            ['Gemini 2.5 Flash',       'publishers/google/models/gemini-2.5-flash'],
            ['Gemini 2.5 Flash Lite',  'publishers/google/models/gemini-2.5-flash-lite'],
            ['Gemini 2.0 Flash',       'publishers/google/models/gemini-2.0-flash-001'],
            ['Gemini 2.0 Flash Lite',  'publishers/google/models/gemini-2.0-flash-lite-001'],
            ['Gemini 1.5 Pro',         'publishers/google/models/gemini-1.5-pro'],
            ['Gemini 1.5 Flash',       'publishers/google/models/gemini-1.5-flash'],
            ['Gemini 1.0 Pro',         'publishers/google/models/gemini-pro']
          ]
        end
      rescue
        [
          ['Gemini 2.5 Pro',         'publishers/google/models/gemini-2.5-pro'],
          ['Gemini 2.5 Flash',       'publishers/google/models/gemini-2.5-flash'],
          ['Gemini 2.5 Flash Lite',  'publishers/google/models/gemini-2.5-flash-lite'],
          ['Gemini 2.0 Flash',       'publishers/google/models/gemini-2.0-flash-001'],
          ['Gemini 2.0 Flash Lite',  'publishers/google/models/gemini-2.0-flash-lite-001'],
          ['Gemini 1.5 Pro',         'publishers/google/models/gemini-1.5-pro'],
          ['Gemini 1.5 Flash',       'publishers/google/models/gemini-1.5-flash'],
          ['Gemini 1.0 Pro',         'publishers/google/models/gemini-pro']
        ]
      end
    end,

    available_image_models: lambda do |connection|
      region = connection['region'].presence || 'us-central1'
      include_preview = !!connection['include_preview_models']
      begin
        url  = "https://#{region}-aiplatform.googleapis.com/v1/publishers/google/models"
        resp = call('api_request', connection, :get, url, {
          params: { pageSize: 500, view: 'PUBLISHER_MODEL_VIEW_BASIC' }
        })
        models = (resp['publisherModels'] || resp['models'] || []).map { |m|
          {
            id:  m['name'].to_s.split('/').last,
            dn:  m['displayName'].presence || m['name'].to_s.split('/').last.gsub('-', ' ').split.map(&:capitalize).join(' '),
            ls:  m['launchStage'].to_s
          }
        }

        # Multimodal image analysis: gemini vision/multimodal models
        img = models.select { |m|
          id = m[:id].downcase
          next false if id.include?('embedding') || id.include?('imagen') # exclude pure image-gen & embeddings
          id.include?('gemini') # gemini multimodal works for images
        }
        img = img.select { |m| m[:ls] == 'GA' || include_preview }

        score = lambda do |id|
          v = if id =~ /(\d+)\.(\d+)/
                [$1.to_i, $2.to_i]
              else [0,0]
              end
          tier = (id =~ /pro/i) ? 0 : (id =~ /flash/i ? 1 : (id =~ /lite/i ? 2 : 3))
          [-v[0], -v[1], tier, id]
        end
        img.sort_by! { |m| score.call(m[:id]) }

        opts = img.map { |m| [m[:dn], "publishers/google/models/#{m[:id]}"] }
        if opts.present?
          opts
        else
          [
            ['Gemini 2.5 Pro',        'publishers/google/models/gemini-2.5-pro'],
            ['Gemini 2.5 Flash',      'publishers/google/models/gemini-2.5-flash'],
            ['Gemini 2.0 Flash',      'publishers/google/models/gemini-2.0-flash-001'],
            ['Gemini 1.5 Pro',        'publishers/google/models/gemini-1.5-pro'],
            ['Gemini 1.5 Flash',      'publishers/google/models/gemini-1.5-flash'],
            ['Gemini Pro Vision',     'publishers/google/models/gemini-pro-vision']
          ]
        end
      rescue
        [
          ['Gemini 2.5 Pro',        'publishers/google/models/gemini-2.5-pro'],
          ['Gemini 2.5 Flash',      'publishers/google/models/gemini-2.5-flash'],
          ['Gemini 2.0 Flash',      'publishers/google/models/gemini-2.0-flash-001'],
          ['Gemini 1.5 Pro',        'publishers/google/models/gemini-1.5-pro'],
          ['Gemini 1.5 Flash',      'publishers/google/models/gemini-1.5-flash'],
          ['Gemini Pro Vision',     'publishers/google/models/gemini-pro-vision']
        ]
      end
    end,

    available_embedding_models: lambda do |connection|
      region = connection['region'].presence || 'us-central1'
      include_preview = !!connection['include_preview_models']
      begin
        url  = "https://#{region}-aiplatform.googleapis.com/v1/publishers/google/models"
        resp = call('api_request', connection, :get, url, {
          params: { pageSize: 200, view: 'PUBLISHER_MODEL_VIEW_BASIC' }
        })
        models = (resp['publisherModels'] || resp['models'] || []).map { |m|
          { id: m['name'].to_s.split('/').last, dn: m['displayName'], ls: m['launchStage'].to_s }
        }
        emb = models.select { |m| m[:id].downcase.include?('embedding') }
        emb = emb.select { |m| m[:ls] == 'GA' || include_preview }
        opts = emb.map { |m| [m[:dn].presence || m[:id].gsub('-', ' ').split.map(&:capitalize).join(' '), "publishers/google/models/#{m[:id]}"] }
        if opts.present?
          # prefer 004 first
          opts.sort_by { |(_l,v)| v =~ /text-embedding-004/ ? 0 : 1 }
        else
          [
            ['Text Embedding 004',         'publishers/google/models/text-embedding-004'],
            ['Text Embedding Gecko @003',  'publishers/google/models/textembedding-gecko@003'],
            ['Text Embedding Gecko @001',  'publishers/google/models/textembedding-gecko@001']
          ]
        end
      rescue
        [
          ['Text Embedding 004',         'publishers/google/models/text-embedding-004'],
          ['Text Embedding Gecko @003',  'publishers/google/models/textembedding-gecko@003'],
          ['Text Embedding Gecko @001',  'publishers/google/models/textembedding-gecko@001']
        ]
      end
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Deprecated (no longer used by send_messages input)
    # ─────────────────────────────────────────────────────────────────────────────
    message_types: lambda do
      [] # deprecated – kept as a no-op to avoid breaking old recipes
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # Vector Search, safety, and misc pickers
    # ─────────────────────────────────────────────────────────────────────────────
    numeric_comparison_op: lambda do
      %w[EQUAL NOT_EQUAL LESS LESS_EQUAL GREATER GREATER_EQUAL].map { |m| [m.humanize, m] }
    end,

    safety_categories: lambda do
      %w[
        HARM_CATEGORY_UNSPECIFIED
        HARM_CATEGORY_HATE_SPEECH
        HARM_CATEGORY_DANGEROUS_CONTENT
        HARM_CATEGORY_HARASSMENT
        HARM_CATEGORY_SEXUALLY_EXPLICIT
      ].map { |m| [m.humanize, m] }
    end,

    safety_threshold: lambda do
      %w[
        HARM_BLOCK_THRESHOLD_UNSPECIFIED
        BLOCK_LOW_AND_ABOVE
        BLOCK_MEDIUM_AND_ABOVE
        BLOCK_ONLY_HIGH
        BLOCK_NONE
        OFF
      ].map { |m| [m.humanize, m] }
    end,

    safety_method: lambda do
      %w[HARM_BLOCK_METHOD_UNSPECIFIED SEVERITY PROBABILITY].map { |m| [m.humanize, m] }
    end,

    response_type: lambda do
      [['Text', 'text/plain'], ['JSON', 'application/json']]
    end,

    chat_role: lambda do
      [%w[User user], %w[Model model]]
    end,

    languages_picklist: lambda do
      %w[
        Albanian Arabic Armenian Awadhi Azerbaijani Bashkir Basque Belarusian Bengali Bhojpuri
        Bosnian Brazilian\ Portuguese Bulgarian Cantonese\ (Yue) Catalan Chhattisgarhi Chinese
        Croatian Czech Danish Dogri Dutch English Estonian Faroese Finnish French Galician
        Georgian German Greek Gujarati Haryanvi Hindi Hungarian Indonesian Irish Italian
        Japanese Javanese Kannada Kashmiri Kazakh Konkani Korean Kyrgyz Latvian Lithuanian
        Macedonian Maithili Malay Maltese Mandarin Mandarin\ Chinese Marathi Marwari Min\ Nan
        Moldovan Mongolian Montenegrin Nepali Norwegian Oriya Pashto Persian\ (Farsi) Polish
        Portuguese Punjabi Rajasthani Romanian Russian Sanskrit Santali Serbian Sindhi Sinhala
        Slovak Slovene Slovenian Spanish Swedish Ukrainian Urdu Uzbek Vietnamese Welsh Wu
      ].map { |lang| [lang.gsub('\\', ''), lang.gsub('\\', '')] }
    end,

    embedding_task_list: lambda do
      [
        ['Retrieval query', 'RETRIEVAL_QUERY'],
        ['Retrieval document', 'RETRIEVAL_DOCUMENT'],
        ['Semantic similarity', 'SEMANTIC_SIMILARITY'],
        ['Classification', 'CLASSIFICATION'],
        ['Clustering', 'CLUSTERING'],
        ['Question answering', 'QUESTION_ANSWERING'],
        ['Fact verification', 'FACT_VERIFICATION']
      ]
    end
  }

}
