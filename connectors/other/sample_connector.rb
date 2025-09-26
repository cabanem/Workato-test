{
  title: "Sample Connector",
  connection: {
    fields: [
      { name: "api_key", label: "API Key", optional: false, control_type: "password" }
    ],
    authorization: {
      type: "custom_auth",
      apply: lambda { |conn| headers("Authorization": "Bearer #{conn['api_key']}") }
    },
    base_uri: lambda { |conn| "https://api.example.com/v1" }
  },
  test: lambda { |conn| get("/ping") },
  actions: {},
  triggers: {},
  object_definitions: {}
}
