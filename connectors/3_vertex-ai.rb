{
  title: 'Vertex AI',

  connection: {
    # Base connection fields; do not use pick_lists here, use "options"
    fields: [
      { name: 'project', label: 'Project ID', optional: false },
      { name: 'region',  label: 'Region', optional: false, control_type: 'select', 
        options: [ 
          ['US central 1', 'us-central1'],
          ['US east 1', 'us-east1'],
          ['US east 4', 'us-east4'],
          ['US east 5', 'us-east5'],
          ['US west 1', 'us-west1'],
          ['US west 4', 'us-west4'],
          ['US south 1', 'us-south1'],
        ]},
      { name: 'service_account_email', label: 'Service Account Email', optional: false },
      { name: 'client_id', label: 'Client ID', optional: false },
      { name: 'private_key', label: 'Private Key', optional: false, control_type: 'password', multiline: true }
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
                        assertion: jwt_token).
                    request_format_www_form_urlencoded

        { access_token: response['access_token'] }
      end,
      refresh_on: [401],
      apply: lambda do |connection|
        headers(Authorization: "Bearer #{connection['access_token']}")
      end
    },
    base_uri: lambda do |connection|
      "https://#{connection['region']}-aiplatform.googleapis.com/v1"
    end
  },
  # Establish connection validity, should emit bool True if connection exists
  test: lambda do |connection|
    get("/projects/#{connection['project']}/locations/#{connection['region']}/datasets").
      params(pageSize: 1)
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
    # Test action
    simple_generate: {
      title: 'Simple AI Generate',
      input_fields: lambda do
        [
          { name: 'model', optional: false, default: 'publishers/google/models/gemini-1.5-flash' },
          { name: 'prompt', control_type: 'text-area', optional: false }
        ]
      end,
      execute: lambda do |connection, input|
        url = "#{call('base_url', connection)}/#{input['model']}:generateContent"
        payload = {
          'contents' => [{ 'role' => 'user', 'parts' => [{ 'text' => input['prompt'] }] }]
        }

        call('execute_request', method: 'POST', url: url, payload: payload)
      end,
      output_fields: lambda do
        [{ name: 'response', type: 'object' }]
      end
    }
  },

  # ---------------------------------------------------------------------------
  # Triggers
  # ---------------------------------------------------------------------------
  triggers: {
    unique_trigger_name: {
      title: '', # string
      subtitle: '', # string
      description: lambda do |input, picklist_label|
        # string
      end,
      help: lambda do |input, picklist_label|
        {} # hash
      end,
      display_priority: 1, # integer
      batch: false, # boolean, defaults to false if unspecified
      bulk: false, # boolean, defaults to false if absent
      deprecated: false, # boolean, defaults to false if not indicated
      config_fields: [], # array
      input_fields: lambda do |object_definitions, connection, config_fields|
        [] # array
      end,
      webhook_key: lambda do |connection, input|
        # string
      end,
      webhook_response_type: '', # string
      webhook_response_body: '', # string
      webhook_response_headers: '', # string
      webhook_response_status: 1, # integer
      webhook_payload_type: '', # string
      webhook_subscribe: lambda do |webhook_url, connection, input, recipe_id|
        # hash or array
      end,
      webhook_refresh: lambda do |webhook_subscribe_output|
        [] # array
      end,
      webhook_unsubscribe: lambda do |webhook_subscribe_output, connection|
        {} # hash
      end,
      webhook_notification: lambda do |input, payload, extended_input_schema, extended_output_schema, headers, params, connection, webhook_subscribe_output|
        # hash or array
      end,
      poll: lambda do |connection, input, closure|
        {} # hash
      end,
      dedup: lambda do |record|
        # string
      end,
      output_fields: lambda do |object_definitions, connection, config_fields|
        [] # array
      end,
      sample_output: lambda do |connection, input|
        {} # hash
      end,
      summarize_input: [], # array
      sumamrize_output: [] # array
    }
  },

  # ---------------------------------------------------------------------------
  # Object Definitions
  # ---------------------------------------------------------------------------
  object_definitions: {},

  # ---------------------------------------------------------------------------
  # Pick Lists
  # ---------------------------------------------------------------------------
  pick_lists: {
    unique_pick_list_1: lambda do |connection, pick_list_params|
      [] # array
    end
  },

  # ---------------------------------------------------------------------------
  # Methods
  # ---------------------------------------------------------------------------
  methods: {
    execute_request: lambda do |method:, url:, payload: nil, retries: 3|
      retries.times do |attempt|
        begin
          case method.upcase
          when 'GET' then return get(url)
          when 'POST' then post(url, payload)
          end
        rescue => e
          raise e if attempt >= retries -1
            sleep(2 ** attempt)
        end
      end
    end
  },

  # ---------------------------------------------------------------------------
  # Secure Tunnel
  # ---------------------------------------------------------------------------
  secure_tunnel: false,

  # ---------------------------------------------------------------------------
  # Webhook Keys
  # ---------------------------------------------------------------------------
  webhook_keys: lambda do
    # string
  end,

  # ---------------------------------------------------------------------------
  # Streams
  # ---------------------------------------------------------------------------
  streams: {}
}
