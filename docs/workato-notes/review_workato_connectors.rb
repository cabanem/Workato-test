{
  title: 'Vertex AI',

  connection: {
    # Base connection fields; do not use pick_lists here, use "options"
    fields: [],
    # Enables the display of additional fields based on connection type
    extended_fields: lambda do |connection|
      # Array
    end,
    authorization: {
      
      # Expects "basic_auth", "api_key", "oauth2", "custom_auth", "multi"
      type: String,

      client_id: lambda do |connection|
        # string
      end,

      client_secret: lambda do |connection|
        # string
      end,

      authorization_url: lambda do |connection|
        # string
      end,

      token_url: lambda do |connection|
        # string
      end,

      acquire: lambda do |connection, auth_code, redirect_uri, verifier|
        # hash or array
      end,

      apply: lambda do |connection, access_token|
        # see apply documentation for more information
      end,

      refresh_on: Array,

      detect_on: Array,

      refresh: lambda do |connection, refresh_token|
        Hash or Array
      end,

      identity: lambda do |connection|
        String
      end,

      # Applies to OAuth2 connections when code grant w/PKCE auth is required
      pkce: lambda do |verifier, challenge|
      end,

      selected: lambda do |connection|
      end,

      # For type: "multi"
      options: {
        option_name1: {},
        option_name2: {}
      },

      noopener: false
    },
    base_uri: lambda do |connection|
      # string
    end
  },

  # Establish connection validity || true if no connection
  test: lambda do
    # Boolean
  end,

  # ---------------------------------------------------------------------------
  # Custom Action
  # Allows the user to quickly define custom actions to unblock their workflow
  # in the event that no standard action has been defined
  # ---------------------------------------------------------------------------
  custom_action: true, # boolean
  custom_action_help: {
    learn_more_url:   '', # string
    learn_more_text:  '', # string
    body:             '' # string
  },

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------
  actions: {},

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
  # - Represent specific resources from a target application
  # - Stored as an array of hashes
  # - Possible arguments:
  #   - connection
  #   - config_fields
  #   - object_definitions
  # - Supply arguments in order to make the field dynamic
  # ---------------------------------------------------------------------------
  object_definitions: {},

  # ---------------------------------------------------------------------------
  # Pick Lists
  # - Used w/some input fields to enumerate options as drop-down
  # - Input fields using pick_list attribute must be of control_type:
  #   - select (user to select a single output from drop-down)
  #   - multiselect (user to select multiple inputs from drop-down)
  #   - tree (user selects 1 or many from hierarchical drop-down)
  # ---------------------------------------------------------------------------
  pick_lists: {
    unique_pick_list_1: lambda do |connection, pick_list_params|
      [] # array
    end
  },

  # ---------------------------------------------------------------------------
  # Methods
  # ---------------------------------------------------------------------------
  methods: {},

  # ---------------------------------------------------------------------------
  # Secure Tunnel
  # - Defaults to 'false' if absent
  # ---------------------------------------------------------------------------
  secure_tunnel: false, # boolean

  # ---------------------------------------------------------------------------
  # Webhook Keys
  # ---------------------------------------------------------------------------
  webhook_keys: lambda do
    # string
  end,

  # ---------------------------------------------------------------------------
  # Streams
  # - Enables the download of large amounts of data in chunks
  # - Must be used in coordination with an action or trigger
  # - Usage:
  #   - stream name acts as the key
  #   - invoked by any streaming action via `workato.stream.out` callback
  # ---------------------------------------------------------------------------
  streams: {
    # Example
    unique_stream_1: lambda do | input, starting_byte_range, ending_byte_range, byte_size|
      []
    end
  }
}
