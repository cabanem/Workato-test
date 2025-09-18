{
  title: 'Google Vertex AI',
  custom_action: true,
  custom_action_help: {
    learn_more_url: 'https://cloud.google.com/vertex-ai/docs/reference/rest',
    learn_more_text: 'Google Vertex AI API documentation',
    body: '<p>Build your own Google Vertex AI action with a HTTP request. The request will ' \
          'be authorized with your Google Vertex AI connection.</p>'
  },

  connection: {
    fields: [
      # Developer options
      { # - verbose_errors
        name: 'verbose_errors', label: 'Verbose errors',
        group: 'Developer options',
        type: 'boolean', control_type: 'checkbox',
        hint: 'When enabled, include upstream response bodies in error messages. Disable in production.'
      },
      # Authentication
      { # - auth_type
        name: 'auth_type', label: 'Authentication type', group: 'Authentication',
        control_type: 'select', 
        default: 'custom',
        optional: false, 
        extends_schema: true, 
        hint: 'Select the authentication type for connecting to Google Vertex AI.',
        options: [ ['Client credentials', 'custom'], %w[OAuth2 oauth2] ] 
      },
      # Vertex AI environment
      { # - region
        name: 'region', label: 'Region', group: 'Vertex AI environment',
        control_type: 'select', 
        optional: false,
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
          ['Asia southeast 1', 'asia-southeast1']
        ],
        hint: 'Select the Google Cloud Platform (GCP) region used for the Vertex model.',
        toggle_hint: 'Select from list',
        toggle_field: {
          name: 'region',
          label: 'Region',
          type: 'string',
          control_type: 'text',
          optional: false,
          toggle_hint: 'Use custom value',
          hint: "Enter the region you want to use. See <a href='https://cloud.google." \
                "com/vertex-ai/generative-ai/docs/learn/locations' " \
                "target='_blank'>generative AI on Vertex AI locations</a> for a list " \
                'of regions and model availability.'

        }
        
      },
      { # - project
        name: 'project', label: 'Project', group: 'Vertex AI environment',
        optional: false, 
        hint: 'E.g abc-dev-1234'
      },
      { # - version
        name: 'version', label: 'Version', group: 'Vertex AI environment',
        optional: false, 
        default: 'v1',
        hint: 'E.g. v1beta1'
      },
      # Model discovery and validation
      { # - dynamic_models
        name: 'dynamic_models', label: 'Refresh model list from API (Model Garden)', group: 'Model discovery and validation',
        type: 'boolean',
        control_type: 'checkbox',
        optional: true,
        hint: 'Fetch available Gemini/Embedding models at runtime. Falls back to a curated static list on errors.' 
      },
      { # - include_preview_models
        name: 'include_preview_models', label: 'Include preview/experimental models', group: 'Model discovery and validation',
        type: 'boolean',
        control_type: 'checkbox', 
        optional: true, 
        sticky: true,
        hint: 'Also include Experimental/Private/Public Preview models. Leave unchecked for GA-only in production.' 
      },
      { # - validate_model_on_run
        name: 'validate_model_on_run', label: 'Validate model before run', group: 'Model discovery and validation',
        type: 'boolean', control_type: 'checkbox', optional: true, sticky: true, 
        hint: 'Pre-flight check the chosen model and your project access before sending the request. Recommended.' }

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
            { # - client_id
              name: 'client_id', group: 'OAuth 2.0 (user delegated)',
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
                    "protocols/OAuth2?hl=en_US' target='_blank'>here</a>.",
              optional: false
             },
            { # - client_secret
              name: 'client_secret', group: 'OAuth 2.0 (user delegated)',
              hint: 'You can find your client secret by logging in to your ' \
                    "<a href='https://console.developers.google.com/' " \
                    "target='_blank'>Google Developers Console</a> account. " \
                    'After logging in, click on Credentials to show your ' \
                    'OAuth 2.0 client IDs and select your desired account name.',
              optional: false, 
              control_type: 'password' 
            }
          ],
          authorization_url: lambda do |connection|
            scopes = [
              'https://www.googleapis.com/auth/cloud-platform'
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
              hint: 'The service account created to delegate other domain users. ' \
                    'e.g. name@project.iam.gserviceaccount.com' },
            { name: 'client_id', optional: false },
            { name: 'private_key',
              control_type: 'password',
              hint: 'Copy and paste the private key that came from the downloaded json. <br/>' \
                    "Click <a href='https://developers.google.com/identity/protocols/oauth2/' " \
                    "service-account/target='_blank'>here</a> to learn more about Google Service " \
                    'Accounts.<br><br>Required scope: <b>https://www.googleapis.com/auth/' \
                    'cloud-platform</b>',
              multiline: true,
              optional: false }
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
    get("projects/#{connection['project']}/locations/#{connection['region']}/datasets").
      after_error_response(/.*/) do |code, body, _header, message|
        call('handle_vertex_error', connection, code, body, message)
      end
  end,

  actions: {
    send_messages: {
      title: 'Send messages to Gemini models',
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
        body: 'This action sends a message to Vertex AI, and gathers a response ' \
              'using the selected Gemini Model.'
      },

      input_fields: lambda do |object_definitions|
        object_definitions['send_messages_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Accepts prepared prompts from RAG_Utils
        # Validate model
        call('validate_publisher_model!', connection, input['model'])

        # Build payload - check for prepared input from RAG_Utils
        payload = if input['formatted_prompt'].present?
          # Use prepared prompt directly (from RAG_Utils)
          input['formatted_prompt']
        else
          # Build payload using existing method (backward compatibility)
          call('payload_for_send_message', input)
        end

        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"
        # Make the request
        post(url, payload).
          after_error_response(/.*/) do |code, body, _header, message|
            call('handle_vertex_error', connection, code, body, message)
        end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['send_messages_output']
      end,

      sample_output: lambda do |_connection, _input|
        call('sample_record_output', 'send_message')
      end
    },
    # --- Generative and Analysis actions (text models) ---
    translate_text: {
      title: 'Translate text',
      subtitle: 'Translate text between languages',
      description: "Translate <span class='provider'>text</span> into a different " \
                   "language using Gemini models in <span class='provider'>Google Vertex AI</span>",
      help: {
        body: 'This action translates inputted text into a different language. ' \
              'While other languages may be possible, languages not on the predefined ' \
              'list may not provide reliable translations.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['translate_text_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('payload_for_translate', input)
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"
        # Make the request
        response = post(url, payload).
          after_error_response(/.*/) do |code, body, _header, message|
            call('handle_vertex_error', connection, code, body, message)
          end
        # Extract and return the response
        call('extract_generic_response', response, true)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['translate_text_output']
      end,

      sample_output: lambda do |_connection, _input|
        call('sample_record_output', 'translate_text')
      end
    },
    summarize_text: {
      title: 'Summarize text',
      subtitle: 'Get a summary of the input text in configurable length',
      description: "Summarize <span class='provider'>text</span> " \
                   "using Gemini models in <span class='provider'>Google Vertex AI</span>",
      help: {
        body: 'This action summarizes inputted text into a shorter version. ' \
              'The length of the summary can be configured.'
      },
      input_fields: lambda do |object_definitions|
        object_definitions['summarize_text_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('payload_for_summarize', input)
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"
        # Make the request
        response = post(url, payload).
                  after_error_response(/.*/) do |code, body, _header, message|
                    call('handle_vertex_error', connection, code, body, message)
                  end
        # Extract and return the response
        call('extract_generic_response', response, false)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['summarize_text_output']
      end,

      sample_output: lambda do |_connection, _input|
        call('sample_record_output', 'summarize_text')
      end
    },
    parse_text: {
      title: 'Parse text',
      subtitle: 'Extract structured data from freeform text',
      help: {
        body: 'This action helps process inputted text to find specific information ' \
              'based on defined guidelines. The processed information is then available as datapills.'
      },
      description: "Parse <span class='provider'>text</span> to find specific " \
                   "information using Gemini models in <span class='provider'>" \
                   'Google Vertex AI</span>',

      input_fields: lambda do |object_definitions|
        object_definitions['parse_text_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('payload_for_parse', input)
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
                        "/#{input['model']}:generateContent"
        # Make the request
        response = post(url, payload).
                  after_error_response(/.*/) do |code, body, _header, message|
                    call('handle_vertex_error', connection, code, body, message)
                  end
        # Extract and return the response
        call('extract_parsed_response', response)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['parse_text_output']
      end,

      sample_output: lambda do |_connection, input|
        call('format_parse_sample', parse_json(input['object_schema'])).
          merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      end
    },
    draft_email: {
      title: 'Draft email',
      subtitle: 'Generate an email based on user description',
      description: "Generate draft <span class='provider'>email</span> " \
                   "using Gemini models in <span class='provider'>Google Vertex AI</span>",
      help: {
        body: 'This action generates an email and parses input into datapills ' \
              'containing a subject line and body for easy mapping into future ' \
              'recipe actions. Note that the body contains placeholder text for ' \
              "a salutation if this information isn't present in the email description."
      },

      input_fields: lambda do |object_definitions|
        object_definitions['draft_email_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('payload_for_email', input)
        # Build the url
        url ="projects/#{connection['project']}/locations/#{connection['region']}" \
                        "/#{input['model']}:generateContent"
        response = post(url, payload).
                  after_error_response(/.*/) do |code, body, _header, message|
                    call('handle_vertex_error', connection, code, body, message)
                  end
        # Extract and return the response
        call('extract_generated_email_response', response)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['draft_email_output']
      end,

      sample_output: lambda do
        call('sample_record_output', 'draft_email')
      end
    },

    ai_classify: {
      title: 'AI Classification',
      subtitle: 'Classify text using AI with confidence scoring',
      description: "Classify <span class='provider'>text</span> into predefined categories " \
                   'using Gemini models in ' \
                   "<span class='provider'>Google Vertex AI</span> with confidence scores and alternatives",
      help: {
        body: 'This action uses AI to classify text into one of the provided categories. ' \
              'Returns confidence scores and alternative classifications. Designed to work ' \
              'with text prepared by RAG_Utils prepare_for_ai action.'
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: 'text', label: 'Text to classify', type: 'string',
            optional: false, hint: 'Text content to classify (preferably from RAG_Utils prepare_for_ai)'
          },
          {
            name: 'categories', label: 'Categories', type: 'array', of: 'object',
            optional: false, list_mode_toggle: true,
            properties: [
              { name: 'key', label: 'Category key', type: 'string', optional: false },
              { name: 'description', label: 'Category description', type: 'string', optional: true }
            ],
            hint: 'Array of categories with keys and optional descriptions'
          },
          {
            name: 'model', label: 'Model', type: 'string',
            optional: false, control_type: 'select',
            pick_list: :available_text_models,
            extends_schema: true,
            hint: 'Select the Gemini model to use',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'model', label: 'Model (custom)', type: 'string',
              control_type: 'text', toggle_hint: 'Use custom value',
              hint: 'E.g., publishers/google/models/gemini-pro'
            }
          },
          {
            name: 'options', label: 'Classification options', type: 'object', optional: true,
            properties: [
              { name: 'return_confidence', label: 'Return confidence score', type: 'boolean', control_type: 'checkbox', default: true },
              { name: 'return_alternatives', label: 'Return alternative classifications', type: 'boolean', control_type: 'checkbox', default: true },
              { name: 'temperature', label: 'Temperature', type: 'number', hint: 'Controls randomness (0.0-1.0)', default: 0.1 }
            ]
          }
        ].concat(object_definitions['config_schema'].only('safetySettings'))
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'selected_category', label: 'Selected category', type: 'string' },
          { name: 'confidence', label: 'Confidence score', type: 'number', hint: 'Confidence score (0.0-1.0)' },
          { name: 'alternatives', label: 'Alternative classifications', type: 'array', of: 'object',
            properties: [
              { name: 'category', type: 'string' },
              { name: 'confidence', type: 'number' }
            ]
          },
          { name: 'usage_metrics', label: 'Usage metrics', type: 'object', properties: [
            { name: 'prompt_token_count', type: 'integer' },
            { name: 'candidates_token_count', type: 'integer' },
            { name: 'total_token_count', type: 'integer' }
          ]}
        ].concat(object_definitions['safety_rating_schema'])
      end,

      sample_output: lambda do |_connection, input|
        {
          'selected_category' => input['categories']&.first&.[]('key') || 'urgent',
          'confidence' => 0.95,
          'alternatives' => [
            { 'category' => 'normal', 'confidence' => 0.05 }
          ],
          'usage_metrics' => {
            'prompt_token_count' => 45,
            'candidates_token_count' => 12,
            'total_token_count' => 57
          }
        }.merge(call('safety_ratings_output_sample'))
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])

        # Build payload for AI classification
        payload = call('payload_for_ai_classify', connection, input)

        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
                        "/#{input['model']}:generateContent"

        response = post(url, payload).
                  after_error_response(/.*/) do |code, body, _header, message|
                    call('handle_vertex_error', connection, code, body, message)
                  end

        # Extract and return the response
        call('extract_ai_classify_response', response, input)
      end
    },

    analyze_text: {
      title: 'Analyze text',
      subtitle: 'Contextual analysis of text to answer user-provided questions',
      description: "Analyze <span class='provider'>text</span> to answer user-provided " \
                   "questions using Gemini models in <span class='provider'>" \
                   'Google Vertex AI</span>',
      help: {
        body: 'This action performs a contextual analysis of a text to answer ' \
              "user-provided questions. If the answer isn't found in the text, " \
              'the datapill will be empty.'
      },

      input_fields: lambda do |object_definitions|
        object_definitions['analyze_text_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('payload_for_analyze', input)
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"
        # Make the request
        response = post(url, payload).
                  after_error_response(/.*/) do |code, body, _header, message|
                    call('handle_vertex_error', connection, code, body, message)
                  end
        # Extract and return the response
        call('extract_generic_response', response, true)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['analyze_text_output']
      end,

      sample_output: lambda do
        call('sample_record_output', 'analyze_text')
      end
    },
    # --- Generative and Analysis actions (multimodal models) ---
    analyze_image: {
      title: 'Analyze image',
      subtitle: 'Analyze image based on the provided question',
      description: "Analyses passed <span class='provider'>image</span> using " \
                   "Gemini models in <span class='provider'>Google Vertex AI</span>",
      help: {
        body: 'This action analyses passed image and answers related question.'
      },

      input_fields: lambda do |object_definitions|
        object_definitions['analyze_image_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Validate model
        call('validate_publisher_model!', connection, input['model'])
        # Build payload
        payload = call('payload_for_analyze_image', input)
        # Build the url
        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
              "/#{input['model']}:generateContent"
        # Make the request
        response = post(url, payload).
                  after_error_response(/.*/) do |code, body, _header, message|
                    call('handle_vertex_error', connection, code, body, message)
                  end
        # Extract and return the response
        call('extract_generic_response', response, false)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['analyze_image_output']
      end,

      sample_output: lambda do
        call('sample_record_output', 'analyze_image')
      end
    },
    # --- Embedding and Vector Search actions ---
    generate_embeddings: {
      title: 'Generate text embeddings (Batch)',
      subtitle: 'Generate embeddings for multiple texts in batch',
      description: "Generate text <span class='provider'>embeddings</span> for multiple texts using " \
                   "Google models in <span class='provider'>Google Vertex AI</span>",
      help: {
        body: 'Batch text embedding generates numerical vectors for multiple text inputs efficiently. ' \
              'It processes an array of texts and returns vectors that capture the meaning ' \
              'and context of each text. These vectors can be used for similarity search, ' \
              'clustering, classification, and other natural language processing tasks.'
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: 'batch_id', label: 'Batch ID', type: 'string',
            optional: false, hint: 'Unique identifier for this batch of embeddings'
          },
          {
            name: 'texts', label: 'Text objects', type: 'array', of: 'object',
            optional: false, list_mode_toggle: true,
            properties: [
              { name: 'id', label: 'Text ID', type: 'string', optional: false },
              { name: 'content', label: 'Text content', type: 'string', optional: false,
                hint: 'Input text must not exceed 8192 tokens (approximately 6000 words).' },
              { name: 'metadata', label: 'Metadata', type: 'object', optional: true }
            ],
            hint: 'Array of text objects to generate embeddings for'
          },
          {
            name: 'model', label: 'Model', type: 'string',
            optional: false, control_type: 'select',
            pick_list: :available_embedding_models,
            extends_schema: true,
            hint: 'Select the embedding model to use',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'model', label: 'Model (custom)', type: 'string',
              control_type: 'text', toggle_hint: 'Use custom value',
              hint: 'E.g., publishers/google/models/text-embedding-004'
            }
          },
          {
            name: 'task_type', label: 'Task type', type: 'string',
            optional: true, control_type: 'select',
            pick_list: :embedding_task_list,
            hint: 'Intended downstream application to help the model produce better embeddings',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'task_type', label: 'Task type (custom)', type: 'string',
              control_type: 'text', toggle_hint: 'Use custom value',
              hint: 'E.g., RETRIEVAL_DOCUMENT, RETRIEVAL_QUERY, SEMANTIC_SIMILARITY'
            }
          }
        ]
      end,

      execute: lambda do |connection, input, _eis, _eos|
        call('generate_embeddings_batch_exec', connection, input)
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'batch_id', label: 'Batch ID', type: 'string' },
          { name: 'embeddings', label: 'Generated embeddings', type: 'array', of: 'object',
            properties: [
              { name: 'id', label: 'Text ID', type: 'string' },
              { name: 'vector', label: 'Embedding vector', type: 'array', of: 'number' },
              { name: 'dimensions', label: 'Vector dimensions', type: 'integer' },
              { name: 'metadata', label: 'Original metadata', type: 'object' }
            ]
          },
          { name: 'model_used', label: 'Model used', type: 'string' },
          { name: 'total_processed', label: 'Total texts processed', type: 'integer' },
          { name: 'usage_statistics', label: 'Usage statistics', type: 'object',
            properties: [
              { name: 'total_requests', type: 'integer' },
              { name: 'successful_requests', type: 'integer' },
              { name: 'failed_requests', type: 'integer' },
              { name: 'total_tokens', type: 'integer' }
            ]
          }
        ]
      end,

      sample_output: lambda do |_connection, input|
        {
          'batch_id' => input['batch_id'] || 'batch_001',
          'embeddings' => [
            {
              'id' => 'text_1',
              'vector' => Array.new(768) { rand(-1.0..1.0).round(6) },
              'dimensions' => 768,
              'metadata' => { 'source' => 'sample' }
            }
          ],
          'model_used' => input['model'] || 'publishers/google/models/text-embedding-004',
          'total_processed' => 1,
          'usage_statistics' => {
            'total_requests' => 1,
            'successful_requests' => 1,
            'failed_requests' => 0,
            'total_tokens' => 15
          }
        }
      end
    },
    find_neighbors: {
      title: 'Find neighbors (Vector Search)',
      subtitle: 'K-NN query on a deployed Vertex AI index endpoint',
      description: "Query a <span class='provider'>Vertex AI Vector Search</span> index endpoint "\
                  "to retrieve nearest neighbors.",
      retry_on_request: ['POST'],
      retry_on_response: [429, 500, 502, 503, 504],
      max_retries: 3,
      help: {
        body: "This action queries a deployed Vector Search index endpoint to find nearest neighbors "\
              "(k-NN). IMPORTANT: Use the endpoint's own host (public endpoint domain or PSC DNS). "\
              "Final URL looks like https://{INDEX_ENDPOINT_HOST}/v1/projects/{PROJECT}/locations/{LOCATION}/"\
              "indexEndpoints/{INDEX_ENDPOINT_ID}:findNeighbors. "\
              "Returning full datapoints increases latency and cost."
      },

      input_fields: lambda do |object_definitions|
        object_definitions['find_neighbors_input']
      end,

      execute: lambda do |connection, input, _eis, _eos|
        # Build payload and normalized host
        payload = call('payload_for_find_neighbors', input)
        host = input['index_endpoint_host'].to_s.strip
        # Host normalization
        if host.blank?
          error('Index endpoint host is required')
        end
        
        # Remove protocol if present and trailing slashes
        host = host.gsub(/^https?:\/\//i, '').gsub(/\/+$/, '')
        
        # Validate host format (basic check for valid domain or IP)
        unless host.match?(/^[\w\-\.]+(:\d+)?$/)
          error("Invalid index endpoint host format: #{host}")
        end

        version = connection['version'].presence || 'v1'
        project = connection['project']
        region = connection['region']
        endpoint_id = input['index_endpoint_id']
        
        # Validate required parameters
        error('Project is required') if project.blank?
        error('Region is required') if region.blank?
        error('Index endpoint ID is required') if endpoint_id.blank?
        # Construct the full URL
        url = "https://#{host}/#{version}/projects/#{project}/locations/#{region}/" \
              "indexEndpoints/#{endpoint_id}:findNeighbors"
        # Make the request
        post(url, payload).
          after_error_response(/404/) do |code, body, _headers, message|
            # Use a custom message for 404s since they're often configuration errors
            error("Index endpoint not found. Please verify:\n" \
                  "• Host: #{host}\n" \
                  "• Endpoint ID: #{endpoint_id}\n" \
                  "• Region: #{region}")
          end.
          after_error_response(/.*/) do |code, body, _headers, message|
            # Use the centralized handler for all other errors
            call('handle_vertex_error', connection, code, body, message)
          end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['find_neighbors_output']
      end,

      sample_output: lambda do
        {
          'nearestNeighbors' => [
            {
              'id' => 'query-0',
              'neighbors' => [
                {
                  'distance' => 0.1234,
                  'datapoint' => {
                    'datapointId' => 'dp_123',
                    # Present only when returnFullDatapoint = true
                    'featureVector' => [0.1, -0.2, 0.3],
                    'restricts' => [
                      { 'namespace' => 'color', 'allowList' => ['red'] }
                    ],
                    'numericRestricts' => [
                      { 'namespace' => 'price', 'op' => 'LESS_EQUAL', 'valueFloat' => 9.99 }
                    ],
                    'crowdingTag' => { 'crowdingAttribute' => 'brand_A' },
                    'sparseEmbedding' => {
                      'values' => [0.4, 0.2],
                      'dimensions' => [5, 17]
                    }
                  }
                }
              ]
            }
          ]
        }
      end
    },
    # --- Legacy Text Bison action kept for backward compatibility ---
    get_prediction: {
      title: 'Get prediction',
      subtitle: 'Get prediction in Google Vertex AI',
      description: "Get <span class='provider'>prediction in <span class='provider'>" \
                   'Google Vertex AI</span>',
      help: lambda do
        {
          body: 'This action will retrieve prediction using the PaLM 2 for Text ' \
                '(text-bison) model.',
          learn_more_url: 'https://cloud.google.com/vertex-ai/docs/generative-ai/' \
                          'model-reference/text',
          learn_more_text: 'Learn more'
        }
      end,

      input_fields: lambda do |object_definitions|
        object_definitions['get_prediction_input']
      end,

      execute: lambda do |connection, input|
        post("projects/#{connection['project']}/locations/#{connection['region']}/publishers/" \
             'google/models/text-bison:predict', input).
          after_error_response(/.*/) do |_, body, _, message|
            error("#{message}: #{body}")
          end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['prediction']
      end,

      sample_output: lambda do |connection|
        payload = {
          instances: [
            {
              prompt: 'action'
            }
          ],
          parameters: {
            temperature: 1,
            topK: 2,
            topP: 1,
            maxOutputTokens: 50
          }
        }
        post("projects/#{connection['project']}/locations/#{connection['region']}" \
             '/publishers/google/models/text-bison:predict').
          payload(payload)
      end
    }

  },

  methods: {
    # ─────────────────────────────────────────────────────────────────────────────
    # -- Core error and HTTP utilities
    # ─────────────────────────────────────────────────────────────────────────────
    handle_vertex_error: lambda do |connection, code, body, message, context = {}|
      # Parse the body for structured error information
      error_details = begin
        parsed = parse_json(body)
        # Google APIs often nest the error message
        parsed.dig('error', 'message') || parsed['message'] || body
      rescue
        body
      end
      
      # Build base message based on status code
      base_message = case code
      when 400
        "Invalid request format"
      when 401
        "Authentication failed - please check your credentials"
      when 403
        "Permission denied - verify Vertex AI API is enabled"
      when 404
        "Resource not found"
      when 429
        "Rate limit exceeded - please wait before retrying"
      when 500
        "Google service error - temporary issue"
      when 502, 503, 504
        "Google service temporarily unavailable"
      else
        "API error"
      end
      
      # Add context if provided
      if context[:action].present?
        base_message = "#{context[:action]} failed: #{base_message}"
      end
      
      # Build final message
      if connection['verbose_errors']
        error_message = "#{base_message} (HTTP #{code})"
        error_message += "\nDetails: #{error_details}" if error_details.present?
        error_message += "\nOriginal: #{message}" if message != error_details
        error(error_message)
      else
        hint = case code
        when 401, 403
          "\nEnable verbose errors in connection settings for details"
        when 429
          "\nConsider adding delays between requests"
        when 500..599
          "\nThis is usually temporary - retry in a few moments"
        else
          ""
        end
        error("#{base_message}#{hint}")
      end
    end,
    replace_backticks_with_hash: lambda do |text|
      text&.gsub('```', '####')
    end,
    truthy?: lambda do |val|
      case val
      when TrueClass then true
      when FalseClass then false
      when Integer then val != 0
      else
        %w[true 1 yes y t].include?(val.to_s.strip.downcase)
      end
    end,
    # ─────────────────────────────────────────────────────────────────────────────
    # -- Vertex model discovery and validation
    # ─────────────────────────────────────────────────────────────────────────────
    fetch_publisher_models: lambda do |connection, publisher = 'google'|
      # Build the cache key (incl all relevant param to ensure regions/publishers are cached separately)
      region = connection['region'].presence || 'us-central1'
      include_preview = connection['include_preview_models'] || false
      cache_key = "models_#{region}_#{publisher}_preview_#{include_preview}"

      # Try for a cache hit (using Workato's built-in caching)
      begin
        cached_data = workato.cache.get(cache_key)
        if cached_data.present?
          # Check if cache is still fresh (we'll cache for 1 hour)
          cache_time = Time.parse(cached_data['cached_at'])
          if cache_time > 1.hour.ago
            puts "Using cached model list (#{cached_data['models'].length} models, cached #{((Time.now - cache_time) / 60).round} minutes ago)"
            return cached_data['models']
          else
            puts "Model cache expired, refreshing..."
          end
        end
      rescue => e
        # If cache access fails, continue without it
        puts "Cache access failed: #{e.message}, fetching fresh data"
      end
      
      # Fetch fresh models from the API
      models = call('fetch_fresh_publisher_models', connection, publisher, region)
      
      # Cache the results if we got any
      if models.present?
        begin
          cache_data = {
            'models' => models,
            'cached_at' => Time.now.iso8601,
            'count' => models.length
          }
          # Cache for 1 hour (3600 seconds)
          workato.cache.set(cache_key, cache_data, 3600)
          puts "Cached #{models.length} models for future use"
        rescue => e
          puts "Failed to cache models: #{e.message}"
        end
      end
      
      models
    end,
    fetch_fresh_publisher_models: lambda do |connection, publisher, region|
      # Use the regional service endpoint; list is in v1beta1.
      # Docs: publishers.models.list (v1beta1), supports 'view' and pagination.
      # https://cloud.google.com/vertex-ai/docs/reference/rest/v1beta1/publishers.models/list
      host = "https://#{region}-aiplatform.googleapis.com"
      url = "#{host}/v1beta1/publishers/#{publisher}/models"
      
      models = []
      page_token = nil
      pages_fetched = 0
      max_pages = 5  # Reduced from 10 for faster response
      total_api_time = 0
      
      begin
        loop do
          pages_fetched += 1
          
          # Stop if we've fetched enough pages
          if pages_fetched > max_pages
            puts "Reached maximum page limit (#{max_pages}), stopping model fetch"
            break
          end
          
          # Time each API call for monitoring
          api_start = Time.now
          
          resp = get(url).
            params(
              page_size: 500,  # Increased from 200 - get more models per request
              page_token: page_token,
              view: 'PUBLISHER_MODEL_VIEW_BASIC',  # Changed from FULL - we only need basic info
              # filter: build_model_filter(connection)  # << server-side filtering is limited, stick to client-side
            ).
            after_error_response(/.*/) do |code, body, _hdrs, message|
              # Log but don't fail completely
              if connection['verbose_errors']
                puts "Model listing failed (HTTP #{code}): #{body}"
              else
                puts "Model listing failed (HTTP #{code}) - using static fallback"
              end
              raise "API Error"
            end
          
          api_time = Time.now - api_start
          total_api_time += api_time
          
          batch = resp['publisherModels'] || []
          models.concat(batch)
          
          puts "Fetched page #{pages_fetched}: #{batch.length} models in #{api_time.round(2)}s"
          
          # Check for pagination
          page_token = resp['nextPageToken']
          
          # Smart early exit - if we have enough models, stop fetching
          if models.length >= 100 && !connection['fetch_all_models']
            puts "Have #{models.length} models, stopping early for performance"
            break
          end
          
          break if page_token.blank? || batch.empty?
        end
        
        puts "Total model fetch: #{models.length} models in #{total_api_time.round(2)}s across #{pages_fetched} pages"
        models
        
      rescue => e
        puts "Failed to fetch models from API: #{e.message}"
        # Return empty array to trigger static fallback
        []
      end
    end,
    validate_publisher_model!: lambda do |connection, model_name|
      # Early exit conditions (no need to validate in input absent or validation disabled)
      return if model_name.blank?
      return unless connection['validate_model_on_run']
      
      # This is the caching mechanism - @validated_models persists within a single execution
      # In Workato, instance variables (@) live for the duration of one recipe execution
      @validated_models ||= {}

      # Create a unique cache key that includes both region and model (model avail can vary by region)
      cache_key = "#{connection['region']}/#{model_name}"
      
      # Check cache first - if we've already validated this exact model in this region, skip
      if @validated_models[cache_key]
        # Add logging for debugging
        puts "Model #{model_name} already validated in #{connection['region']}, using cache"
        return
      end
      
      # 1. Validate model name format first (no API call needed)
      # regex checks for the pattern: publishers/{publisher}/models/{model}
      unless model_name.match?(/^publishers\/[^\/]+\/models\/[^\/]+$/)
        error("Invalid model name format: #{model_name}\n" \
              "Expected format: publishers/{publisher}/models/{model}\n" \
              "Example: publishers/google/models/gemini-1.5-pro")
      end
      
      # Verify the model actually exists
      region = connection['region'].presence || 'us-central1'
      
      # Build the validation URL (v1 endpoint for model metadata)
      url = "https://#{region}-aiplatform.googleapis.com/v1/#{model_name}"

      begin
        # Make the validation request with specific error handling
        resp = get(url).
          params(view: 'PUBLISHER_MODEL_VIEW_BASIC').  # Changed from FULL to BASIC for speed
          after_error_response(/404/) do |code, body, _hdrs, message|
            # Model not found - provide helpful context about what might be wrong
            error("Model '#{model_name}' not found in region '#{region}'.\n" \
                  "Possible issues:\n" \
                  "• Model name typo (check spelling carefully)\n" \
                  "• Model not available in #{region} (try us-central1)\n" \
                  "• Model deprecated or renamed\n" \
                  "• Using preview model without enabling preview models in connection")
          end.
          after_error_response(/403/) do |code, body, _hdrs, message|
            # Permission denied - guide user to fix their setup
            error("Access denied to model '#{model_name}'.\n" \
                  "To fix this:\n" \
                  "1. Verify Vertex AI API is enabled in Google Cloud Console\n" \
                  "2. Check service account has 'Vertex AI User' role\n" \
                  "3. Ensure billing is enabled for your project\n" \
                  "4. Confirm project ID is correct: #{connection['project']}")
          end.
          after_error_response(/.*/) do |code, body, _hdrs, message|
            # Use the centralized error handler for other errors
            call('handle_vertex_error', connection, code, body, message)
          end
        
        # Additional validation: Check if model is GA when preview models aren't allowed
        unless connection['include_preview_models']
          stage = resp['launchStage'].to_s
          if stage.present? && stage != 'GA'
            error("Model '#{model_name}' is in #{stage} stage (not Generally Available).\n" \
                  "To use preview models:\n" \
                  "1. Go to your connection settings\n" \
                  "2. Enable 'Include preview/experimental models'\n" \
                  "3. Save and retry\n\n" \
                  "Note: Preview models may have different pricing and stability")
          end
        end
        
        # Success! Cache the validation result
        @validated_models[cache_key] = {
          validated_at: Time.now,
          launch_stage: resp['launchStage'],
          model_version: resp['versionId']
        }
        
        puts "Model #{model_name} validated successfully in #{region}"
        
      rescue => e
        # If anything goes wrong, provide a clear error message
        error("Model validation failed: #{e.message}\n" \
              "This usually means a temporary network issue. Try again in a moment.")
      end
    end,
    # - Partition models by capability.
    vertex_model_bucket: lambda do |model_id|
      id = model_id.to_s.downcase

      # Use a hash for 0(1) lookup instead of multiple str includes
      @model_categories ||= {
        'embedding' => %w[embedding gecko multimodalembedding embeddinggemma],
        'image' => %w[vision imagegeneration imagen],
        'audio' => %w[tts audio speech],
        'code' => %w[code codey],
        'chat' => %w[chat],
        'text' => []  # Default category
      }

      # Find the category for this model
      @model_categories.each do |category, keywords|
        return category.to_sym if keywords.any? { |keyword| id.include?(keyword) }
      end
    
      :text # default to text if no match
    end,
    # - Sort model options by version, tier, then alphabetically      
    sort_model_options: lambda do |options|
      options.sort_by do |label, value|
        # Extract version number if present
        version_match = label.match(/(\d+)\.(\d+)/)
        major_version = version_match ? version_match[1].to_i : 0
        minor_version = version_match ? version_match[2].to_i : 0
        
        # Determine model tier
        tier = case label
              when /\bPro\b/i then 0
              when /\bFlash\b/i then 1  
              when /\bLite\b/i then 2
              else 3
              end
        
        # Sort by: version (desc), tier, then alphabetical
        [
          -major_version,  # Newest version first
          -minor_version,  # Higher minor version first
          tier,            # Pro > Flash > Lite
          label            # Alphabetical as tiebreaker
        ]
      end
    end,
    # - Filter/sort + convert to picklist options [label, value]
    to_model_options: lambda do |models, bucket:, include_preview: false|
      return [] if models.blank?
      
      # Pre-compile the regex for retired models to avoid recompiling
      retired_pattern = /(^|-)1\.0-|text-bison|chat-bison/
    
      # Filter models efficiently
      filtered = models.select do |m|
        model_id = m['name'].to_s.split('/').last
        next false if model_id.blank?
        
        # Skip retired models
        next false if model_id =~ retired_pattern
        
        # Check bucket match
        next false unless call('vertex_model_bucket', model_id) == bucket
        
        # Check GA status if needed
        if !include_preview
          stage = m['launchStage'].to_s
          next false unless stage == 'GA' || stage.blank?
        end
        
        true
      end
      
      # Extract unique model IDs efficiently
      seen_ids = Set.new
      unique_models = filtered.select do |m|
        id = m['name'].to_s.split('/').last
        seen_ids.add?(id)  # Returns true if added (wasn't present), false if already present
      end
      
      # Build options with better sorting
      options = unique_models.map do |m|
        id = m['name'].to_s.split('/').last
        # Create a human-friendly label
        label = create_model_label(id, m)
        [label, "publishers/google/models/#{id}"]
      end
      
      # Sort with a more sophisticated algorithm
      sort_model_options(options)
    end,
    # - Context-aware model label creation
    create_model_label: lambda do |model_id, model_metadata = {}|
      # Start with the basic formatting
      label = model_id.gsub('-', ' ').split.map { |word| 
        # Keep version numbers as-is, capitalize other words
        word =~ /^\d/ ? word : word.capitalize 
      }.join(' ')
      
      # Add helpful context if available
      if model_metadata['launchStage'].present? && model_metadata['launchStage'] != 'GA'
        label += " (#{model_metadata['launchStage']})"
      end
      
      label
    end,
    # - Picklist generator with static fallback
    dynamic_model_picklist: lambda do |connection, bucket, static_fallback|
      # 1. Check if dynamic models are enabled (return to static if not)
      unless connection['dynamic_models']
        puts "Dynamic models disabled, using static list"
        return static_fallback
      end

      # 2. Fetch models (with caching)
      begin
        models = call('fetch_publisher_models', connection, 'google')
        
        if models.present?
          # Convert to options
          options = call('to_model_options', models,
                        bucket: bucket,
                        include_preview: connection['include_preview_models'])
          
          # 3. Ensure we have options, otherwise fall back
          if options.present?
            puts "Returning #{options.length} dynamic models for #{bucket}"
            return options
          else
            puts "No models matched criteria for #{bucket}, using static list"
            return static_fallback
          end
        end
      rescue => e
        puts "Error in dynamic model fetch: #{e.message}"
      end
      
      # 4. Ultimate fallback to static list
      puts "All dynamic fetch attempts failed, using static list"
      static_fallback
    end,


    # ─────────────────────────────────────────────────────────────────────────────
    # -- Payload construction
    # ─────────────────────────────────────────────────────────────────────────────
    # = BASE PAYLOAD BUILDER =
    build_base_payload: lambda do |instruction, user_content, safety_settings = nil, options = {}|
      # Build the base structure
      payload = {
        'systemInstruction' => {
          'role' => 'model',
          'parts' => [{ 'text' => instruction }]
        },
        'contents' => [
          {
            'role' => 'user',
            'parts' => if user_content.is_a?(Array)
              user_content  # Allow passing pre-built parts array
            else
              [{ 'text' => user_content }]  # Default to text part
            end
          }
        ],
        'generationConfig' => options['generationConfig'] || { 'temperature' => 0 }
      }
      
      # Add safety settings if provided
      payload['safetySettings'] = safety_settings if safety_settings.present?
      
      # Allow additional top-level fields through options
      options.except('generationConfig').each do |key, value|
        payload[key] = value if value.present?
      end
      
      payload.compact
    end,
    build_conversation_payload: lambda do |input|
      # Handle generation config with response schema
      if input&.dig('generationConfig', 'responseSchema').present?
        input['generationConfig']['responseSchema'] = 
          parse_json(input.dig('generationConfig', 'responseSchema'))
      end
      
      # Handle tools with function declarations
      if input['tools'].present?
        input['tools'] = input['tools'].map do |tool|
          if tool['functionDeclarations'].present?
            tool['functionDeclarations'] = tool['functionDeclarations'].map do |function|
              if function['parameters'].present?
                function['parameters'] = parse_json(function['parameters'])
              end
              function
            end.compact
          end
          tool
        end.compact
      end
      
      # Build contents based on message type
      contents = if input['message_type'] == 'single_message'
        [{
          'role' => 'user',
          'parts' => [{ 'text' => input.dig('messages', 'message') }]
        }]
      else
        input.dig('messages', 'chat_transcript')&.map do |m|
          {
            'role' => m['role'],
            'parts' => call('build_message_parts', m)
          }
        end
      end
      
      # Build the final payload
      {
        'contents' => contents,
        'generationConfig' => input['generationConfig'],
        'systemInstruction' => input['systemInstruction'],
        'tools' => input['tools'],
        'toolConfig' => input['toolConfig'],
        'safetySettings' => input['safetySettings']
      }.compact.merge(input.except('model', 'message_type', 'messages'))
    end,
    build_message_parts: lambda do |m|
      parts = []
      parts << { 'text' => m['text'] } if m['text'].present?

      if m['fileData'].present?
        parts << { 'fileData' => m['fileData'] } # { mimeType, fileUri }
      end
      if m['inlineData'].present?
        parts << { 'inlineData' => m['inlineData'] } # { mimeType, data }
      end

      if m['functionCall'].present?
        fc = m['functionCall']
        # if args provided as string JSON, parse once
        if fc['args'].is_a?(String) && fc['args'].strip.start_with?('{','[')
          begin
            fc = fc.merge('args' => parse_json(fc['args']))
          rescue
            # keep raw if parse fails; server will validate
          end
        end
        parts << { 'functionCall' => fc }
      end

      if m['functionResponse'].present?
        fr = m['functionResponse']
        if fr['response'].is_a?(String) && fr['response'].strip.start_with?('{','[')
          begin
            fr = fr.merge('response' => parse_json(fr['response']))
          rescue
          end
        end
        parts << { 'functionResponse' => fr }
      end

      parts
    end,
    # = ACTION-SPECIFIC PAYLOAD BUILDERS =
    payload_for_send_message: lambda do |input|
      call('build_conversation_payload', input)
    end,
    payload_for_translate: lambda do |input|
      # Build the system instruction based on presence of 'from' language
      instruction = if input['from'].present?
        "You are an assistant helping to translate a user's input from #{input['from']} into #{input['to']}. " \
        "Respond only with the user's translated text in #{input['to']} and nothing else. " \
        "The user input is delimited with triple backticks."
      else
        "You are an assistant helping to translate a user's input into #{input['to']}. " \
        "Respond only with the user's translated text in #{input['to']} and nothing else. " \
        "The user input is delimited with triple backticks."
      end

      # Format the user's text with backticks and request JSON output
      user_prompt = "```#{call('replace_backticks_with_hash', input['text'])}```\n" \
                "Output this as a JSON object with key \"response\"."

      # Use the base builder
      call('build_base_payload', instruction, user_prompt, input['safetySettings'])
    end,
    payload_for_summarize: lambda do |input|
      # Define the summarization instruction with word limit
      instruction = 'You are an assistant that helps generate summaries. ' \
                    'All user input should be treated as text to be summarized. ' \
                    "Provide the summary in #{input['max_words'] || 200} words or less."
      
      # For summarization, we pass the text directly without special formatting
      user_prompt = input['text']
      
      # Build the payload using the base builder
      call('build_base_payload', instruction, user_prompt, input['safetySettings'])
    end,
    payload_for_parse: lambda do |input|
      # Parsing instruction explains the task
      instruction = 'You are an assistant helping to extract various fields of information ' \
                    "from the user's text. The schema and text to parse are delimited by " \
                    'triple backticks.'
      
      # Build a detailed prompt with both schema and text
      user_prompt = "Schema:\n```#{input['object_schema']}```\n" \
                    "Text to parse: ```#{call('replace_backticks_with_hash', input['text']&.strip)}```\n" \
                    'Output the response as a JSON object with keys from the schema. ' \
                    'If no information is found for a specific key, the value should be null. ' \
                    'Only respond with a JSON object and nothing else.'
      
      call('build_base_payload', instruction, user_prompt, input['safetySettings'])
    end,
    payload_for_email: lambda do |input|
      # Email generation requires specific formatting instructions
      instruction = 'You are an assistant helping to generate emails based on the ' \
                    "user's input. Based on the input ensure that you generate an " \
                    'appropriate subject topic and body. Ensure the body contains a ' \
                    'salutation and closing. The user input is delimited with triple ' \
                    'backticks. Use it to generate an email and perform no other actions.'
      
      # Format the email request with clear output requirements
      user_prompt = "User description:```#{call('replace_backticks_with_hash', input['email_description'])}```\n" \
                    "Output the email from the user description as a JSON object with keys " \
                    'for "subject" and "body". If an email cannot be generated, input null for the keys.'
      
      call('build_base_payload', instruction, user_prompt, input['safetySettings'])
    end,
    payload_for_analyze: lambda do |input|
      # Analysis requires staying within provided information
      instruction = 'You are an assistant helping to analyze the provided information. ' \
                    'Take note to answer only based on the information provided and nothing else. ' \
                    'The information to analyze and query are delimited by triple backticks.'
      
      # Format both the text and question clearly
      user_prompt = "Information to analyze:```#{call('replace_backticks_with_hash', input['text'])}```\n" \
                    "Query:```#{call('replace_backticks_with_hash', input['question'])}```\n" \
                    "If you don't understand the question or the answer isn't in the " \
                    'information to analyze, input the value as null for "response". ' \
                    'Only return a JSON object.'

      call('build_base_payload', instruction, user_prompt, input['safetySettings'])
    end,

    payload_for_ai_classify: lambda do |connection, input|
      # Extract categories and options
      categories = Array(input['categories'] || [])
      options = input['options'] || {}
      temperature = (options['temperature'] || 0.1).to_f

      # Build categories text with descriptions
      categories_text = categories.map do |cat|
        key = cat['key'].to_s
        desc = cat['description'].to_s
        desc.empty? ? key : "#{key}: #{desc}"
      end.join("\n")

      # Build instruction for AI classification
      instruction = 'You are an expert text classifier. Classify the provided text into one of the given categories. ' \
                    'Analyze the text carefully and select the most appropriate category. ' \
                    'Return confidence scores and alternative classifications if requested. ' \
                    'The categories and text are delimited by triple backticks.'

      # Build the classification prompt
      user_prompt = "Categories:\n```#{categories_text}```\n" \
                    "Text to classify:\n```#{call('replace_backticks_with_hash', input['text']&.strip)}```\n\n"

      # Add output format instructions
      if options['return_confidence'] && options['return_alternatives']
        user_prompt += 'Return a JSON object with: ' \
                       '{"selected_category": "category_key", ' \
                       '"confidence": 0.95, ' \
                       '"alternatives": [{"category": "other_key", "confidence": 0.05}]}. ' \
                       'Confidence scores should be between 0.0 and 1.0. ' \
                       'Only respond with the JSON object.'
      elsif options['return_confidence']
        user_prompt += 'Return a JSON object with: ' \
                       '{"selected_category": "category_key", "confidence": 0.95}. ' \
                       'Confidence should be between 0.0 and 1.0. ' \
                       'Only respond with the JSON object.'
      else
        user_prompt += 'Return a JSON object with: {"selected_category": "category_key"}. ' \
                       'Only respond with the JSON object.'
      end

      # Build payload with temperature setting
      payload = call('build_base_payload', instruction, user_prompt, input['safetySettings'])
      payload['generationConfig'] ||= {}
      payload['generationConfig']['temperature'] = temperature
      payload
    end,
    payload_for_analyze_image: lambda do |input|
      # We can't use the base builder since we have to pass image data in parts
      {
        'contents' => [
          {
            'role' => 'user',
            'parts' => [
              {
                'text' => input['question']
              },
              {
                'inlineData' => {
                  'mimeType' => input['mime_type'],
                  'data' => input['image']&.encode_base64
                }
              }
            ]
          }
        ],
        'generationConfig' => {
          'temperature' => 0
        },
        'safetySettings' => input['safetySettings'].presence
      }.compact
    end,
    payload_for_text_embedding: lambda do |input|
      {
        'instances' => [
          {
            'task_type' => input['task_type'].presence,
            'title' => input['title'].presence,
            'content' => input['text']
          }.compact
        ]
      }
    end,

    generate_embeddings_batch_exec: lambda do |connection, input|
      # Validate model
      call('validate_publisher_model!', connection, input['model'])

      # Extract inputs
      batch_id = input['batch_id'].to_s
      texts = Array(input['texts'] || [])
      model = input['model']
      task_type = input['task_type']

      # Initialize statistics
      total_requests = 0
      successful_requests = 0
      failed_requests = 0
      total_tokens = 0
      embeddings = []

      # Process each text individually
      texts.each do |text_obj|
        begin
          total_requests += 1

          # Build individual payload
          payload = {
            'instances' => [
              {
                'task_type' => task_type.presence,
                'content' => text_obj['content'].to_s
              }.compact
            ]
          }

          # Build the url
          url = "projects/#{connection['project']}/locations/#{connection['region']}" \
                "/#{model}:predict"

          # Make the request
          response = post(url, payload).
            after_error_response(/.*/) do |code, body, _header, message|
              call('handle_vertex_error', connection, code, body, message)
            end

          # Extract embedding from response
          vals = response&.dig('predictions', 0, 'embeddings', 'values') ||
                 response&.dig('predictions', 0, 'embeddings')&.first&.dig('values') ||
                 []

          # Add to results
          embeddings << {
            'id' => text_obj['id'],
            'vector' => vals,
            'dimensions' => vals.length,
            'metadata' => text_obj['metadata'] || {}
          }

          successful_requests += 1
          # Estimate tokens (rough approximation: ~4 characters per token)
          total_tokens += (text_obj['content'].to_s.length / 4.0).ceil

        rescue => e
          failed_requests += 1
          # Add failed embedding with empty vector
          embeddings << {
            'id' => text_obj['id'],
            'vector' => [],
            'dimensions' => 0,
            'metadata' => (text_obj['metadata'] || {}).merge('error' => e.message)
          }
        end
      end

      # Return batch results
      {
        'batch_id' => batch_id,
        'embeddings' => embeddings,
        'model_used' => model,
        'total_processed' => texts.length,
        'usage_statistics' => {
          'total_requests' => total_requests,
          'successful_requests' => successful_requests,
          'failed_requests' => failed_requests,
          'total_tokens' => total_tokens
        }
      }
    end,
    payload_for_find_neighbors: lambda do |input|
      # We follow Google’s JSON casing for FindNeighbors REST:
      # top-level: deployedIndexId, returnFullDatapoint, queries[]
      # queries[].datapoint.*: datapointId, featureVector, sparseEmbedding, restricts, numericRestricts, crowdingTag
      #
      # Numeric restricts accept ONE of valueInt/valueFloat/valueDouble with 'op' enum.
      queries = (input['queries'] || []).map do |q|
        dp = q['datapoint'] || {}

        # Pass through as-is; assume UI provided correct shapes/casing.
        {
          'datapoint' => {
            'datapointId'     => dp['datapointId'].presence,
            'featureVector'   => dp['featureVector'].presence,
            'sparseEmbedding' => dp['sparseEmbedding'].presence, # { values: [Float], dimensions: [Integer] }
            'restricts'       => dp['restricts'].presence,       # [{ namespace, allowList[], denyList[] }]
            'numericRestricts'=> dp['numericRestricts'].presence,# [{ namespace, op, valueInt|valueFloat|valueDouble }]
            'crowdingTag'     => dp['crowdingTag'].presence      # { crowdingAttribute }
          }.compact,
          'neighborCount'                          => q['neighborCount'],
          'approximateNeighborCount'               => q['approximateNeighborCount'],
          'perCrowdingAttributeNeighborCount'      => q['perCrowdingAttributeNeighborCount'],
          'fractionLeafNodesToSearchOverride'      => q['fractionLeafNodesToSearchOverride'],
          'rrf'                                    => q['rrf'].presence # optional future-proofing; if you need RRF fusion
        }.compact
      end

      {
        'deployedIndexId'      => input['deployedIndexId'],
        'queries'              => queries,
        'returnFullDatapoint'  => !!input['returnFullDatapoint']
      }.compact
    end,

    # ─────────────────────────────────────────────────────────────────────────────
    # -- Response extraction and normalization
    # ─────────────────────────────────────────────────────────────────────────────
    extract_json: lambda do |resp|
      json_txt = resp&.dig('candidates', 0, 'content', 'parts', 0, 'text')
      return {} if json_txt.blank?

      # Cleanup markdown code blocks
      json = json_txt.gsub(/^```(?:json|JSON)?\s*\n?/, '')  # Remove opening fence
                    .gsub(/\n?```\s*$/, '')                # Remove closing fence
                    .gsub(/`+$/, '')                       # Remove any trailing backticks
                    .strip

      begin
        parse_json(json) || {}
      rescue => e
        # Log error for debugging, but return empty hash to prevent action failure
        puts "JSON parsing failed: #{e.message}. Raw text: #{json_txt}"
        {}
      end
    end,
    get_safety_ratings: lambda do |ratings|
      {
        'sexually_explicit' =>
          ratings&.find do |r|
            r['category'] == 'HARM_CATEGORY_SEXUALLY_EXPLICIT'
          end&.[]('probability'),
        'hate_speech' =>
          ratings&.find { |r| r['category'] == 'HARM_CATEGORY_HATE_SPEECH' }&.[]('probability'),
        'harassment' =>
          ratings&.find { |r| r['category'] == 'HARM_CATEGORY_HARASSMENT' }&.[]('probability'),
        'dangerous_content' =>
          ratings&.find do |r|
            r['category'] == 'HARM_CATEGORY_DANGEROUS_CONTENT'
          end&.[]('probability')
      }
    end,
    check_finish_reason: lambda do |reason|
      case reason&.downcase
      when 'finish_reason_unspecified'
        error 'ERROR - The finish reason is unspecified.'
      when 'other'
        error 'ERROR - Token generation stopped due to an unknown reason.'
      when 'max_tokens'
        error 'ERROR - Token generation reached the configured maximum output tokens.'
      when 'safety'
        error 'ERROR - Token generation stopped because the content potentially contains ' \
              'safety violations.'
      when 'recitation'
        error 'ERROR - Token generation stopped because the content potentially contains ' \
              'copyright violations.'
      when 'blocklist'
        error 'ERROR - Token generation stopped because the content contains forbidden items.'
      when 'prohibited_content'
        error 'ERROR - Token generation stopped for potentially containing prohibited content.'
      when 'spii'
        error 'ERROR - Token generation stopped because the content potentially contains ' \
              'Sensitive Personal Identifiable Information (SPII).'
      when 'malformed_function_call'
        error 'ERROR - The function call generated by the model is invalid.'
      end
    end,
    extract_generic_response: lambda do |resp, is_json_response|
      call('check_finish_reason', resp.dig('candidates', 0, 'finishReason'))
      ratings = call('get_safety_ratings', resp.dig('candidates', 0, 'safetyRatings'))
      return({ 'answer' => 'N/A', 'safety_ratings' => {} }) if ratings.blank?

      answer = if is_json_response
                call('extract_json', resp)&.[]('response')
              else
                resp&.dig('candidates', 0, 'content', 'parts', 0, 'text')
              end
      {
        'answer' => answer,
        'safety_ratings' => ratings,
        'usage' => resp['usageMetadata']
      }
    end,
    extract_generated_email_response: lambda do |resp|
      call('check_finish_reason', resp.dig('candidates', 0, 'finishReason'))
      ratings = call('get_safety_ratings', resp.dig('candidates', 0, 'safetyRatings'))
      json = call('extract_json', resp)
      {
        'subject' => json&.[]('subject'),
        'body' => json&.[]('body'),
        'safety_ratings' => ratings,
        'usage' => resp['usageMetadata']
      }
    end,
    extract_parsed_response: lambda do |resp|
      call('check_finish_reason', resp.dig('candidates', 0, 'finishReason'))
      ratings = call('get_safety_ratings', resp.dig('candidates', 0, 'safetyRatings'))
      json = call('extract_json', resp)
      json&.each_with_object({}) do |(key, value), hash|
        hash[key] = value
      end&.merge('safety_ratings' => ratings,
                 'usage' => resp['usageMetadata'])
    end,
    extract_embedding_response: lambda do |resp|
      vals = resp&.dig('predictions', 0, 'embeddings', 'values') ||
            resp&.dig('predictions', 0, 'embeddings')&.first&.dig('values') ||
            []
      { 'embedding' => vals.map { |v| { 'value' => v } } }
    end,

    extract_ai_classify_response: lambda do |resp, input|
      call('check_finish_reason', resp.dig('candidates', 0, 'finishReason'))
      ratings = call('get_safety_ratings', resp.dig('candidates', 0, 'safetyRatings'))
      return({ 'selected_category' => 'N/A', 'confidence' => 0.0, 'safety_ratings' => {} }) if ratings.blank?

      json = call('extract_json', resp)
      options = input['options'] || {}

      # Extract the basic classification result
      selected_category = json&.[]('selected_category') || 'N/A'
      confidence = json&.[]('confidence')&.to_f || 1.0
      alternatives = json&.[]('alternatives') || []

      # Build the response based on options
      result = {
        'selected_category' => selected_category,
        'safety_ratings' => ratings
      }

      # Add confidence if requested
      if options['return_confidence'] != false
        result['confidence'] = confidence
      end

      # Add alternatives if requested
      if options['return_alternatives'] != false
        result['alternatives'] = alternatives
      end

      # Add usage metrics
      if resp['usageMetadata']
        result['usage_metrics'] = {
          'prompt_token_count' => resp['usageMetadata']['promptTokenCount'],
          'candidates_token_count' => resp['usageMetadata']['candidatesTokenCount'],
          'total_token_count' => resp['usageMetadata']['totalTokenCount']
        }
      end

      result
    end,
 
    # ─────────────────────────────────────────────────────────────────────────────
    # -- Samples and UX helpers
    sample_record_output: lambda do |input|
      case input
      when 'send_message'
        {
          candidates: [
            {
              content: {
                role: 'model',
                parts: [
                  {
                    text: "Hey there! I'm happy to answer your question about dark clouds."
                  }
                ]
              },
              finishReason: 'STOP',
              safetyRatings: [
                {
                  category: 'HARM_CATEGORY_HATE_SPEECH',
                  probability: 'NEGLIGIBLE',
                  probabilityScore: 0.022583008,
                  severity: 'HARM_SEVERITY_NEGLIGIBLE',
                  severityScore: 0.018554688
                }
              ],
              avgLogprobs: -0.19514432351939617
            }
          ],
          usageMetadata: {
            promptTokenCount: 23,
            candidatesTokenCount: 557,
            totalTokenCount: 580,
            trafficType: 'ON_DEMAND',
            promptTokensDetails: [
              { modality: 'TEXT', tokenCount: 105 }
            ],
            candidatesTokensDetails: [
              { modality: 'TEXT', tokenCount: 516 }
            ]
          },
          modelVersion: 'gemini-1.5-pro',
          createTime: '2025-08-01T10:36:16.110916Z',
          responseId: 'oJiMaMTiBoKrmecPqYqFWA'
        }
      when 'translate_text'
        {
          answer: '<Translated text>'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'summarize_text'
        {
          answer: '<Summarized text>'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'draft_email'
        {
          subject: 'Sample email subject',
          body: 'This is a sample email body'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'analyze_text'
        {
          answer: 'This text describes rainy weather'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'analyze_image'
        {
          answer: 'This image shows birds'
        }.merge(call('safety_ratings_output_sample'),
                call('usage_output_sample'))
      when 'text_embedding'
        {
          embedding: [
            { value: -0.04629135504364967 }
          ]
        }
        when 'find_neighbors'
          {
            nearestNeighbors: [
              {
                id: 'query-1',
                neighbors: [
                  {
                    datapoint: {
                      datapointId: 'doc_001_chunk_1',
                      featureVector: [0.1, 0.2, 0.3],
                      crowdingTag: {
                        crowdingAttribute: 'doc_001'
                      }
                    },
                    distance: 0.95
                  }
                ]
              }
            ]
          }
      end
    end,
    safety_ratings_output_sample: lambda do
      {
        'safety_ratings' => {
          'sexually_explicit' => 'NEGLIGIBLE',
          'hate_speech' => 'NEGLIGIBLE',
          'harassment' => 'NEGLIGIBLE',
          'dangerous_content' => 'NEGLIGIBLE'
        }
      }
    end,
    usage_output_sample: lambda do
      {
        'usage' => {
          'promptTokenCount' => 23,
          'candidatesTokenCount' => 557,
          'totalTokenCount' => 580
        }
      }
    end,
    format_parse_sample: lambda do |input|
      input&.each_with_object({}) do |element, hash|
        if element['type'] == 'array' && element['of'] == 'object'
          hash[element['name']] = [call('format_parse_sample', element['properties'])]
        elsif element['type'] == 'object'
          hash[element['name']] = call('format_parse_sample', element['properties'])
        else
          hash[element['name'].gsub(/^\d|\W/) { |c| "_ #{c.unpack('H*')}" }] = '<Sample Text>'
        end
      end || {}
    end

  },

  object_definitions: {
    prediction: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'predictions',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'content' },
              { name: 'citationMetadata',
                type: 'object',
                properties: [
                  { name: 'citations',
                    type: 'array',
                    of: 'object',
                    properties: [
                      { name: 'startIndex',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' },
                      { name: 'endIndex',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' },
                      { name: 'url' },
                      { name: 'title' },
                      { name: 'license' },
                      { name: 'publicationDate' }
                    ] }
                ] },
              { name: 'logprobs',
                label: 'Log probabilities',
                type: 'object',
                properties: [
                  { name: 'tokenLogProbs',
                    label: 'Token log probabilities',
                    type: 'array', of: 'number' },
                  { name: 'tokens',
                    type: 'array', of: 'string' },
                  { name: 'topLogProbs',
                    label: 'Top log probabilities' }
                ] },
              { name: 'safetyAttributes',
                type: 'object',
                properties: [
                  { name: 'categories',
                    type: 'array',
                    of: 'string' },
                  { name: 'blocked',
                    type: 'boolean',
                    control_type: 'checkbox',
                    convert_output: 'boolean_conversion' },
                  { name: 'scores',
                    type: 'array',
                    of: 'number' },
                  { name: 'errors',
                    type: 'array',
                    of: 'number' },
                  { name: 'safetyRatings',
                    type: 'array', of: 'object',
                    properties: [
                      { name: 'category' },
                      { name: 'severity' },
                      { name: 'severityScore',
                        type: 'number',
                        convert_output: 'float_conversion' },
                      { name: 'probabilityScore',
                        type: 'number',
                        convert_output: 'float_conversion' }
                    ] }
                ] }
            ] },
          { name: 'metadata',
            type: 'object',
            properties: [
              { name: 'tokenMetadata',
                type: 'object',
                properties: [
                  { name: 'inputTokenCount',
                    type: 'object',
                    properties: [
                      { name: 'totalTokens',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' },
                      { name: 'totalBillableCharacters',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' }
                    ] },
                  { name: 'outputTokenCount',
                    type: 'object',
                    properties: [
                      { name: 'totalTokens',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' },
                      { name: 'totalBillableCharacters',
                        type: 'integer',
                        control_type: 'integer',
                        convert_output: 'integer_conversion' }
                    ] }
                ] }
            ] }
        ]
      end
    },
    get_prediction_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'instances',
            type: 'array', of: 'object',
            group: 'Instances',
            properties: [
              { name: 'prompt',
                hint: 'Text input to generate model response. Can include preamble, ' \
                      'questions, suggestions, instructions, or examples.',
                sticky: true }
            ] },
          { name: 'parameters',
            type: 'object',
            group: 'Parameters',
            properties: [
              { name: 'temperature',
                hint: 'The temperature is used for sampling during response generation, ' \
                      'which occurs when topP and topK are applied. Temperature controls ' \
                      'the degree of randomness in token selection.',
                type: 'number',
                convert_input: 'float_conversion',
                sticky: true },
              { name: 'maxOutputTokens',
                label: 'Maximum number of tokens',
                hint: ' A token is approximately four characters. 100 tokens correspond to ' \
                      'roughly 60-80 words. Specify a lower value for shorter responses and ' \
                      'a higher value for longer responses.',
                type: 'integer',
                convert_input: 'integer_conversion',
                sticky: true },
              { name: 'topK',
                hint: 'Specify a lower value for less random responses and a higher value for ' \
                      'more random responses. The default top-K is 40.',
                type: 'integer',
                convert_input: 'integer_conversion',
                sticky: true },
              { name: 'topP',
                hint: 'Specify a lower value for less random responses and a higher value for ' \
                      'more random responses. The default top-P is 0.95.',
                type: 'integer',
                convert_input: 'integer_conversion',
                sticky: true },
              { name: 'logprobs',
                label: 'Log probabilities',
                hint: 'Returns the top `logprobs` most likely candidate tokens with ' \
                      'their log probabilities at each generation step',
                control_type: 'integer',
                convert_input: 'integer_conversion' },
              { name: 'presencePenalty',
                hint: 'Positive values penalize tokens that already appear in the generated ' \
                      'text, increasing the probability of generating more diverse content. ' \
                      'Acceptable values are -2.0—2.0.',
                control_type: 'number',
                convert_input: 'float_conversion' },
              { name: 'frequencyPenalty',
                hint: 'Positive values penalize tokens that repeatedly appear in the ' \
                      'generated text, decreasing the probability of repeating content. ' \
                      'Acceptable values are -2.0—2.0.',
                control_type: 'number',
                convert_input: 'float_conversion' },
              { name: 'logitBias',
                hint: 'Mapping of token IDs to their bias values. The bias values are added ' \
                      'to the logits before sampling. Allowed values: From -100 to 100.' },
              { name: 'stopSequences',
                type: 'array', of: 'string',
                hint: 'Specifies a list of strings that tells the model to stop generating text ' \
                      'if one of the strings is encountered in the response. If a string ' \
                      'appears multiple times in the response, then the response truncates ' \
                      "where it's first encountered. The strings are case-sensitive.",
                sticky: true },
              { name: 'candidateCount',
                type: 'integer',
                hint: 'Specify the number of response variations to return.',
                convert_input: 'integer_conversion',
                sticky: true },
              { name: 'echo',
                type: 'boolean',
                hint: 'If true, the prompt is echoed in the generated text.',
                control_type: 'checkbox',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'echo',
                  label: 'Echo',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Enter custom value',
                  hint: 'Allowed values are: true or false.'
                } }
            ] }
        ]
      end
    },
    config_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'tools',
            type: 'array',
            of: 'object',
            hint: 'Specify the list of tools the model may use to generate ' \
                  'the next response.',
            group: 'Tools',
            properties: [
              { name: 'functionDeclarations',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'name',
                    hint: 'The name of the function to call. Must start with a letter ' \
                          'or an underscore.' },
                  { name: 'description',
                    hint: 'The description and purpose of the function. Model uses it ' \
                          'to decide how and whether to call the function.' },
                  { name: 'parameters',
                    control_type: 'text-area',
                    hint: 'Provide the JSON schema object format.' }
                ] }
            ] },

          { name: 'toolConfig',
            type: 'object',
            hint: 'This tool config is shared for all tools provided in the request.',
            group: 'Tools',
            properties: [
              { name: 'functionCallingConfig',
                type: 'object',
                properties: [
                  { name: 'mode',
                    control_type: 'select',
                    pick_list: :function_call_mode,
                    hint: 'Select the mode to use',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                      name: 'mode',
                      label: 'Mode',
                      type: 'string',
                      control_type: 'text',
                      optional: true,
                      toggle_hint: 'Use custom value',
                      hint: 'Acceptable values are: MODE_UNSPECIFIED, AUTO, ANY or NONE.'
                    } },
                  { name: 'allowedFunctionNames',
                    type: 'array',
                    of: 'string',
                    hint: 'Function names to call. Only set when the Mode is ANY.' }
                ] }
            ] },

          { name: 'safetySettings',
            type: 'array',
            of: 'object',
            hint: 'Specify safety settings when relevant',
            group: 'Safety',
            properties: [
              { name: 'category',
                control_type: 'select',
                pick_list: :safety_categories,
                hint: 'Select appropriate safety category',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'category',
                  label: 'Category',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Provide a safety category',
                  hint: 'Acceptable values are: HARM_CATEGORY_UNSPECIFIED, ' \
                        'HARM_CATEGORY_DANGEROUS_CONTENT, HARM_CATEGORY_HATE_SPEECH, ' \
                        'HARM_CATEGORY_HARASSMENT or HARM_CATEGORY_SEXUALLY_EXPLICIT.'
                } },
              { name: 'threshold',
                control_type: 'select',
                pick_list: :safety_threshold,
                hint: 'Select the appropriate safety threshold',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'threshold',
                  label: 'Threshold',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Provide a safety threshold',
                  hint: 'Acceptable values are: HARM_BLOCK_THRESHOLD_UNSPECIFIED, ' \
                        'BLOCK_LOW_AND_ABOVE, BLOCK_MEDIUM_AND_ABOVE, BLOCK_ONLY_HIGH, ' \
                        'BLOCK_NONE or OFF.'
                } },
              { name: 'method',
                control_type: 'select',
                pick_list: :safety_method,
                hint: 'Specify if the threshold is used for probability or severity ' \
                      'score. If left blank, threshold is used for probability score.',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'method',
                  label: 'Method',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Provide a method',
                  hint: 'Acceptable values are: HARM_BLOCK_METHOD_UNSPECIFIED, ' \
                        'SEVERITY or PROBABILITY.'
                } }
            ] },

          { name: 'generationConfig',
            type: 'object',
            hint: 'Specify parameters that are suitable for your use case',
            group: 'Generation',
            properties: [
              { name: 'stopSequences',
                type: 'array',
                of: 'string',
                hint: 'A list of strings that the model will stop generating text at.' },
              { name: 'responseMimeType',
                label: 'Response MIME type',
                control_type: 'select',
                pick_list: :response_type,
                hint: 'Select the response type. Defaults to text/plain if left blank.',
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: 'responseMimeType',
                  label: 'Response MIME type',
                  type: 'string',
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Provide a response type',
                  hint: 'Acceptable values are: text/plain or application/json.'
                } },
              { name: 'temperature',
                sticky: true,
                control_type: 'number',
                convert_input: 'float_conversion',
                hint: "A number that controls the randomness of the model's output. " \
                      'A higher temperature will result in more random output, while a ' \
                      'lower temperature will result in more predictable output. The ' \
                      'supported range is 0 to 2.000.' },
              { name: 'topP',
                label: 'Top P',
                control_type: 'number',
                convert_input: 'float_conversion',
                hint: 'A number that controls the probability of the model generating each token. ' \
                      'A higher topP will result in the model generating more likely tokens, while a ' \
                      'lower topP will result in the model generating more unlikely tokens. ' \
                      'Allowed values: Any decimal value between 0 and 1.' },
              { name: 'topK',
                label: 'Top K',
                control_type: 'number',
                convert_input: 'float_conversion',
                hint: 'A number that controls the number of tokens that the model considers when ' \
                      'generating each token. A higher topK will result in the model considering more ' \
                      'tokens, while a lower topK will result in the model considering fewer tokens. ' \
                      'The supported range is 1 to 40.' },
              { name: 'candidateCount',
                control_type: 'integer',
                convert_input: 'integer_conversion',
                hint: 'The number of candidates to generate.' },
              { name: 'maxOutputTokens',
                control_type: 'integer',
                convert_input: 'integer_conversion',
                hint: 'The maximum number of tokens that the model will generate.' },
              { name: 'presencePenalty',
                control_type: 'number',
                convert_input: 'float_conversion',
                ngIf: 'input.model != "publishers/google/models/gemini-pro"',
                hint: 'The amount of positive penalties.' },
              { name: 'frequencyPenalty',
                control_type: 'number',
                convert_input: 'float_conversion',
                ngIf: 'input.model != "publishers/google/models/gemini-pro"',
                hint: 'The frequency of penalties.' },
              { name: 'seed',
                control_type: 'integer',
                convert_input: 'integer_conversion',
                hint: 'The seed value initializes the generation of an image. ' \
                      'It is randomly generated if left blank. Controlling the ' \
                      'seed can help generate reproducible images.' },
              { name: 'responseSchema',
                control_type: 'text-area',
                ngIf: 'input.generationConfig.responseMimeType == "application/json"',
                hint: 'Define the output data schema.' }
            ] },

          { name: 'systemInstruction',
            type: 'object',
            hint: 'Specify the system instructions for the model.',
            group: 'System instructions',
            properties: [
              { name: 'role',
                hint: 'The role should be <b>model</b> when defining system instructions.' },
              { name: 'parts',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'text',
                    control_type: 'text-area',
                    hint: 'The system instructions for the model.' }
                ] }
            ] }
        ]
      end
    },
    send_messages_input: {
      fields: lambda do |_connection, config_fields, object_definitions|
        is_single_message = config_fields['message_type'] == 'single_message'
        message_schema = if is_single_message
                           [
                             { name: 'message',
                               label: 'Text to send',
                               type: 'string',
                               control_type: 'text-area',
                               optional: false,
                               hint: 'Enter a message to start a conversation with Gemini.' }
                           ]
                         else
                           [
                             { name: 'chat_transcript',
                               type: 'array',
                               of: 'object',
                               optional: false,
                               properties: [
                                 { name: 'role',
                                   control_type: 'select',
                                   pick_list: :chat_role,
                                   sticky: true,
                                   extends_schema: true,
                                   hint: 'Select the role of the author of this message.',
                                   toggle_hint: 'Select from list',
                                   toggle_field: {
                                     name: 'role',
                                     label: 'Role',
                                     control_type: 'text',
                                     type: 'string',
                                     optional: true,
                                     extends_schema: true,
                                     toggle_hint: 'Use custom value',
                                     hint: 'Provide the role of the author of this message. ' \
                                           'Allowed values: <b>user</b> or <b>model</b>.'
                                   } },
                                 { name: 'text',
                                   control_type: 'text-area',
                                   sticky: true,
                                   hint: 'The contents of the selected role message.' },
                                 { name: 'fileData',
                                   type: 'object',
                                   properties: [
                                     { name: 'mimeType', label: 'MIME type' },
                                     { name: 'fileUri', label: 'File URI' }
                                   ] },
                                 { name: 'inlineData',
                                   type: 'object',
                                   properties: [
                                     { name: 'mimeType', label: 'MIME type' },
                                     { name: 'data' }
                                   ] },
                                 { name: 'functionCall',
                                   type: 'object',
                                   properties: [
                                     { name: 'name', label: 'Function name' },
                                     { name: 'args', control_type: 'text-area', label: 'Arguments' }
                                   ] },
                                 { name: 'functionResponse',
                                   type: 'object',
                                   properties: [
                                     { name: 'name', label: 'Function name' },
                                     { name: 'response',
                                       control_type: 'text-area',
                                       hint: 'Use this field to send function response. ' \
                                             'Parameters field in Tools > Function declarations ' \
                                             'should also be used when using this field.' }
                                   ] }
                               ],
                               hint: 'A list of messages describing the conversation so far.' }
                           ]
                         end
        object_definitions['text_model_schema'].concat(
          [
            { name: 'message_type',
              label: 'Message type',
              type: 'string',
              control_type: 'select',
              pick_list: :message_types,
              extends_schema: true,
              optional: false,
              hint: 'Choose the type of the message to send.',
              group: 'Message' },
            { name: 'messages',
              label: is_single_message ? 'Message' : 'Messages',
              type: 'object',
              optional: false,
              properties: message_schema,
              group: 'Message' },
            { name: 'formatted_prompt',
              label: 'Formatted prompt (RAG_Utils)',
              type: 'object',
              optional: true,
              hint: 'Pre-formatted prompt payload from RAG_Utils. When provided, this will be used directly instead of building from messages.',
              group: 'Advanced' }
          ].compact
        ).concat(object_definitions['config_schema'])
      end
    },
    send_messages_output: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'candidates',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'content',
                type: 'object',
                properties: [
                  { name: 'role' },
                  { name: 'parts',
                    type: 'array',
                    of: 'object',
                    properties: [
                      { name: 'text' },
                      { name: 'fileData',
                        type: 'object',
                        properties: [
                          { name: 'mimeType', label: 'MIME type' },
                          { name: 'fileUri', label: 'File URI' }
                        ] },
                      { name: 'inlineData',
                        type: 'object',
                        properties: [
                          { name: 'mimeType', label: 'MIME type' },
                          { name: 'data' }
                        ] },
                      { name: 'functionCall',
                        type: 'object',
                        properties: [
                          { name: 'name' },
                          { name: 'args', label: 'Arguments' }
                        ] }
                    ] }
                ] },
              { name: 'finishReason' },
              { name: 'safetyRatings',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'category' },
                  { name: 'probability' },
                  { name: 'probabilityScore', type: 'number' },
                  { name: 'severity' },
                  { name: 'severityScore', type: 'number' }
                ] },
              { name: 'avgLogprobs',
                label: 'Average log probabilities',
                type: 'number' }
            ] },
          { name: 'usageMetadata',
            type: 'object',
            properties: [
              { name: 'promptTokenCount', type: 'integer' },
              { name: 'candidatesTokenCount', type: 'integer' },
              { name: 'totalTokenCount', type: 'integer' },
              { name: 'trafficType' },
              { name: 'promptTokensDetails',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'modality' },
                  { name: 'tokenCount', type: 'integer' }
                ] },
              { name: 'candidatesTokensDetails',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'modality' },
                  { name: 'tokenCount', type: 'integer' }
                ] }
            ] },
          { name: 'modelVersion' },
          { name: 'createTime', type: 'date_time' },
          { name: 'responseId' }
        ]
      end
    },
    translate_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'to',
              label: 'Output language',
              optional: false,
              control_type: 'select',
              pick_list: :languages_picklist,
              toggle_field: {
                name: 'to',
                control_type: 'text',
                type: 'string',
                optional: false,
                label: 'Output language',
                toggle_hint: 'Provide custom value',
                hint: 'Enter the output language. Eg. English'
              },
              toggle_hint: 'Select from list',
              hint: 'Select the desired output language',
              group: 'Task input' },
            { name: 'from',
              label: 'Source language',
              optional: true,
              sticky: true,
              control_type: 'select',
              pick_list: :languages_picklist,
              toggle_field: {
                name: 'from',
                control_type: 'text',
                type: 'string',
                optional: true,
                label: 'Source language',
                toggle_hint: 'Provide custom value',
                hint: 'Enter the source language. Eg. English'
              },
              toggle_hint: 'Select from list',
              hint: 'Select the source language. If this value is left blank, we will ' \
                    'automatically attempt to identify it.',
              group: 'Task input' },
            { name: 'text',
              label: 'Source text',
              type: 'string',
              control_type: 'text-area',
              optional: false,
              hint: 'Enter the text to be translated. Please limit to 2000 tokens',
              group: 'Task input' }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    translate_text_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer',
            label: 'Translation' }
        ].concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    summarize_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'text',
              label: 'Source text',
              type: 'string',
              control_type: 'text-area',
              optional: false,
              hint: 'Provide the text to be summarized',
              group: 'Task input' },
            { name: 'max_words',
              label: 'Maximum words',
              type: 'integer',
              control_type: 'integer',
              optional: true,
              sticky: true,
              hint: 'Enter the maximum number of words for the summary. ' \
                    'If left blank, defaults to 200.',
              group: 'Summary options' }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    summarize_text_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer',
            label: 'Summary' }
        ].concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    parse_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'text',
              label: 'Source text',
              control_type: 'text-area',
              optional: false,
              hint: 'Provide the text to be parsed',
              group: 'Task input' },
            { name: 'object_schema',
              optional: false,
              control_type: 'schema-designer',
              extends_schema: true,
              sample_data_type: 'json_http',
              empty_schema_title: 'Provide output fields for your job output.',
              label: 'Fields to identify',
              hint: 'Enter the fields that you want to identify from the text. Add descriptions ' \
                    'for extracting the fields. Required fields take effect only on top level. ' \
                    'Nested fields are always optional.',
              exclude_fields: %w[hint label],
              exclude_fields_types: %w[integer date date_time],
              custom_properties: [
                {
                  name: 'description',
                  type: 'string',
                  optional: true,
                  label: 'Description'
                }
              ],
              group: 'Schema' }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    parse_text_output: {
      fields: lambda do |_connection, config_fields, object_definitions|
        next [] if config_fields['object_schema'].blank?

        schema = parse_json(config_fields['object_schema'] || '[]')
        schema.concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    draft_email_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'email_description',
              label: 'Email description',
              type: 'string',
              control_type: 'text-area',
              optional: false,
              hint: 'Enter a description for the email',
              group: 'Task input' }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    draft_email_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'subject', label: 'Email subject' },
          { name: 'body', label: 'Email body' }
        ].concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    analyze_text_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        object_definitions['text_model_schema'].concat(
          [
            { name: 'text',
              label: 'Source text',
              control_type: 'text-area',
              hint: 'Provide the text to be analyzed.',
              optional: false,
              group: 'Task input' },
            { name: 'question',
              label: 'Instruction',
              optional: false,
              hint: 'Enter analysis instructions, such as an analysis ' \
                    'technique or question to be answered.',
              group: 'Instruction' }
          ]
        ).concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    analyze_text_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer', label: 'Analysis' }
        ].concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    analyze_image_input: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'model',
            optional: false,
            control_type: 'select',
            pick_list: :available_image_models,
            extends_schema: true,
            hint: 'Select the Gemini model to use',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'model',
              label: 'Model',
              type: 'string',
              control_type: 'text',
              optional: false,
              extends_schema: true,
              toggle_hint: 'Use custom value',
              hint: 'Provide the model you want to use in this format: ' \
                    '<b>publishers/{publisher}/models/{model}</b>. ' \
                    'E.g. publishers/google/models/gemini-1.5-pro-001'
            },
            group: 'Model' },
          { name: 'question',
            label: 'Your question about the image',
            hint: 'Please specify a clear question for image analysis.',
            optional: false,
            group: 'Prompt' },
          { name: 'image',
            label: 'Image data',
            hint: 'Provide the image to be analyzed.',
            optional: false,
            group: 'Image' },
          { name: 'mime_type',
            label: 'MIME type',
            optional: false,
            hint: 'Provide the MIME type of the image. E.g. image/jpeg.',
            group: 'Image' }
        ].concat(object_definitions['config_schema'].only('safetySettings'))
      end
    },
    analyze_image_output: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'answer',
            label: 'Analysis' }
        ].concat(object_definitions['safety_rating_schema']).
          concat(object_definitions['usage_schema'])
      end
    },
    find_neighbors_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'index_endpoint_host',
            label: 'Index endpoint host',
            optional: false,
            hint: 'The host for the index endpoint (no path). Example: 1234.us-central1.vdb.vertexai.goog '\
                  'for public endpoints, or your PSC DNS/IP. Do NOT include https://.',
            group: 'Endpoint' },

          { name: 'index_endpoint_id',
            label: 'Index endpoint ID',
            optional: false,
            hint: 'Resource ID only (not full path). Find it on the Index endpoint details page.',
            group: 'Index context' },

          { name: 'deployedIndexId',
            label: 'Deployed index ID',
            optional: false,
            sticky: true,
            hint: 'The deployed index to query (from your index endpoint).',
            group: 'Index context' },

          { name: 'returnFullDatapoint',
            label: 'Return full datapoints',
            type: 'boolean',
            control_type: 'checkbox',
            hint: 'If enabled, returns full vectors and restricts. Increases latency and cost.',
            group: 'Options' },

          {
            name: 'queries',
            type: 'array',
            of: 'object',
            optional: false,
            hint: 'One or more nearest-neighbor queries.',
            group: 'Queries',
            properties: [
              {
                name: 'datapoint',
                type: 'object',
                properties: [
                  { name: 'datapointId', label: 'Datapoint ID' },
                  { name: 'featureVector', label: 'Feature vector', type: 'array', of: 'number',
                    hint: 'Dense embedding (float array). Provide either a vector or an ID (or both).' },
                  { name: 'sparseEmbedding', type: 'object', properties: [
                    { name: 'values', type: 'array', of: 'number' },
                    { name: 'dimensions', type: 'array', of: 'integer' }
                  ]},
                  { name: 'restricts', type: 'array', of: 'object', properties: [
                    { name: 'namespace' },
                    { name: 'allowList', type: 'array', of: 'string' },
                    { name: 'denyList',  type: 'array', of: 'string' }
                  ]},
                  { name: 'numericRestricts', type: 'array', of: 'object', properties: [
                    { name: 'namespace' },
                    { name: 'op', control_type: 'select',
                      pick_list: :numeric_comparison_op,
                      toggle_hint: 'Select from list',
                      toggle_field: { name: 'op', type: 'string', control_type: 'text', optional: true,
                                      toggle_hint: 'Use custom value' } },
                    { name: 'valueInt',    type: 'integer', control_type: 'integer' },
                    { name: 'valueFloat',  type: 'number',  control_type: 'number'  },
                    { name: 'valueDouble', type: 'number',  control_type: 'number'  }
                  ]},
                  { name: 'crowdingTag', type: 'object', properties: [
                    { name: 'crowdingAttribute' }
                  ], hint: 'Optional; used to improve result diversity by limiting same-tag neighbors.' }
                ]
              },

              { name: 'neighborCount', type: 'integer', control_type: 'integer',
                hint: 'k — number of neighbors to return.' },
              { name: 'approximateNeighborCount', type: 'integer', control_type: 'integer',
                hint: 'Candidate pool size before exact re-ranking.' },
              { name: 'perCrowdingAttributeNeighborCount', type: 'integer', control_type: 'integer',
                hint: 'Max neighbors sharing same crowding attribute.' },
              { name: 'fractionLeafNodesToSearchOverride', type: 'number', control_type: 'number',
                hint: '0.0–1.0. Higher → better recall, higher latency.' }
            ]
          }
        ]
      end
    },
    find_neighbors_output: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          {
            name: 'nearestNeighbors',
            type: 'array',
            of: 'object',
            properties: [
              { name: 'id', label: 'Query datapoint ID' },
              {
                name: 'neighbors',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'distance', type: 'number' },
                  {
                    name: 'datapoint', type: 'object',
                    properties: [
                      { name: 'datapointId' },
                      { name: 'featureVector', type: 'array', of: 'number' },
                      { name: 'restricts', type: 'array', of: 'object', properties: [
                        { name: 'namespace' },
                        { name: 'allowList', type: 'array', of: 'string' },
                        { name: 'denyList',  type: 'array', of: 'string' }
                      ]},
                      { name: 'numericRestricts', type: 'array', of: 'object', properties: [
                        { name: 'namespace' },
                        { name: 'op' },
                        { name: 'valueInt',    type: 'integer' },
                        { name: 'valueFloat',  type: 'number' },
                        { name: 'valueDouble', type: 'number' }
                      ]},
                      { name: 'crowdingTag', type: 'object', properties: [
                        { name: 'crowdingAttribute' }
                      ]},
                      { name: 'sparseEmbedding', type: 'object', properties: [
                        { name: 'values', type: 'array', of: 'number' },
                        { name: 'dimensions', type: 'array', of: 'integer' }
                      ]}
                    ]
                  }
                ]
              }
            ]
          }
        ]
      end
    },
    safety_rating_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'safety_ratings',
            type: 'object',
            properties: [
              { name: 'sexually_explicit' },
              { name: 'hate_speech' },
              { name: 'harassment' },
              { name: 'dangerous_content' }
            ] }
        ]
      end
    },
    usage_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'usage',
            type: 'object',
            properties: [
              { name: 'promptTokenCount', type: 'integer' },
              { name: 'candidatesTokenCount', type: 'integer' },
              { name: 'totalTokenCount', type: 'integer' }
            ] }
        ]
      end
    },
    text_model_schema: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [
          { name: 'model',
            optional: false,
            control_type: 'select',
            pick_list: :available_text_models,
            extends_schema: true,
            hint: 'Select the Gemini model to use',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'model',
              label: 'Model',
              type: 'string',
              control_type: 'text',
              optional: false,
              extends_schema: true,
              toggle_hint: 'Use custom value',
              hint: 'Provide the model you want to use in this format: ' \
                    '<b>publishers/{publisher}/models/{model}</b>. ' \
                    'E.g. publishers/google/models/gemini-1.5-pro-001'
            },
            group: 'Model'
          }
        ]
      end
    }

  },

  pick_lists: {
    available_text_models: lambda do |connection|
      static = [
        ['Gemini 1.0 Pro', 'publishers/google/models/gemini-pro'],
        ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
        ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
        ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
        ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
        ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
        ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
        ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
      ]
      call('dynamic_model_picklist', connection, :text, static)
    end,
    available_image_models: lambda do |connection|
      static = [
        ['Gemini Pro Vision', 'publishers/google/models/gemini-pro-vision'],
        ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
        ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
        ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
        ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
        ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
        ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
        ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
      ]
      call('dynamic_model_picklist', connection, :image, static)
    end,
    available_embedding_models: lambda do |connection|
      static = [
        ['Text embedding gecko-001', 'publishers/google/models/textembedding-gecko@001'],
        ['Text embedding gecko-003', 'publishers/google/models/textembedding-gecko@003'],
        ['Text embedding-004', 'publishers/google/models/text-embedding-004']
      ]
      call('dynamic_model_picklist', connection, :embedding, static)
    end,
    message_types: lambda do
      %w[single_message chat_transcript].map { |m| [m.humanize, m] }
    end,
    numeric_comparison_op: lambda do
      %w[EQUAL NOT_EQUAL LESS LESS_EQUAL GREATER GREATER_EQUAL].map { |m| [m.humanize, m] }
    end,
    safety_categories: lambda do
      %w[HARM_CATEGORY_UNSPECIFIED HARM_CATEGORY_HATE_SPEECH
         HARM_CATEGORY_DANGEROUS_CONTENT HARM_CATEGORY_HARASSMENT
         HARM_CATEGORY_SEXUALLY_EXPLICIT].map { |m| [m.humanize, m] }
    end,
    safety_threshold: lambda do
      %w[HARM_BLOCK_THRESHOLD_UNSPECIFIED BLOCK_LOW_AND_ABOVE
         BLOCK_MEDIUM_AND_ABOVE BLOCK_ONLY_HIGH BLOCK_NONE OFF].
        map { |m| [m.humanize, m] }
    end,
    safety_method: lambda do
      %w[HARM_BLOCK_METHOD_UNSPECIFIED SEVERITY PROBABILITY].
        map { |m| [m.humanize, m] }
    end,
    response_type: lambda do
      [
        ['Text', 'text/plain'],
        ['JSON', 'application/json']
      ]
    end,
    chat_role: lambda do
      %w[model user].map { |m| [m.labelize, m] }
    end,
    function_call_mode: lambda do
      %w[MODE_UNSPECIFIED AUTO ANY NONE].map { |m| [m.humanize, m] }
    end,
    languages_picklist: lambda do
      [
        'Albanian', 'Arabic', 'Armenian', 'Awadhi', 'Azerbaijani', 'Bashkir', 'Basque',
        'Belarusian', 'Bengali', 'Bhojpuri', 'Bosnian', 'Brazilian Portuguese', 'Bulgarian',
        'Cantonese (Yue)', 'Catalan', 'Chhattisgarhi', 'Chinese', 'Croatian', 'Czech', 'Danish',
        'Dogri', 'Dutch', 'English', 'Estonian', 'Faroese', 'Finnish', 'French', 'Galician',
        'Georgian', 'German', 'Greek', 'Gujarati', 'Haryanvi', 'Hindi',
        'Hungarian', 'Indonesian', 'Irish', 'Italian', 'Japanese', 'Javanese', 'Kannada',
        'Kashmiri', 'Kazakh', 'Konkani', 'Korean', 'Kyrgyz', 'Latvian', 'Lithuanian',
        'Macedonian', 'Maithili', 'Malay', 'Maltese', 'Mandarin', 'Mandarin Chinese', 'Marathi',
        'Marwari', 'Min Nan', 'Moldovan', 'Mongolian', 'Montenegrin', 'Nepali', 'Norwegian',
        'Oriya', 'Pashto', 'Persian (Farsi)', 'Polish', 'Portuguese', 'Punjabi', 'Rajasthani',
        'Romanian', 'Russian', 'Sanskrit', 'Santali', 'Serbian', 'Sindhi', 'Sinhala', 'Slovak',
        'Slovene', 'Slovenian', 'Swedish', 'Ukrainian', 'Urdu', 'Uzbek', 'Vietnamese',
        'Welsh', 'Wu'
      ]
    end,
    embedding_task_list: lambda do
      [
        ['Retrieval query', 'RETRIEVAL_QUERY'],
        ['Retrieval document', 'RETRIEVAL_DOCUMENT'],
        ['Semantic similarity', 'SEMANTIC_SIMILARITY'],
        %w[Classification CLASSIFICATION],
        %w[Clustering CLUSTERING],
        ['Question answering', 'QUESTION_ANSWERING'],
        ['Fact verification', 'FACT_VERIFICATION']
      ]
    end,
  }
  
}
