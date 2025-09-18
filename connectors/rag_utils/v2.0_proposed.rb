require 'digest'
require 'time'
require 'json'
require 'csv'

{
  title: "RAG Utilities",
  description: "Custom utility functions for RAG email response system",
  version: "1.1", # Increment for every change
  help: ->() { "Provides text processing, chunking, similarity, prompt building, and validation utilities for retrieval-augmented generation (RAG) systems." },
  author: "",

  # ==========================================
  # CONNECTION CONFIGURATION
  # ==========================================
  connection: {
    help: ->() { "Configure default settings for text processing. These can be overriden in individual actions. Environment selection determines logging verbosity and processing limits." },
    fields: [
      {
        name: "developer_api_host",
        label: "Workato region",
        hint: "Only required when using custom rules from Data Tables. Defaults to EU. See Workato data centers.",
        optional: true,
        control_type: "select",
        options: [ # <- use options (static) on connection
          ["US (www.workato.com)", "www"],
          ["EU (app.eu.workato.com)", "app.eu"],
          ["JP (app.jp.workato.com)", "app.jp"],
          ["SG (app.sg.workato.com)", "app.sg"],
          ["AU (app.au.workato.com)", "app.au"],
          ["IL (app.il.workato.com)", "app.il"],
          ["Developer sandbox (app.trial.workato.com)", "app.trial"]
        ],
        default: "app.eu",
        group: "Developer API",
        sticky: true,
        support_pills: false
      },
      {
        name: "api_token",
        label: "API token (Bearer)",
        hint: "Workspace admin → API clients → API keys",
        control_type: "password",
        optional: true,
        group: "Developer API",
        sticky: true
      },
      {
        name: "environment",
        label: "Environment",
        hint: "Select the environment for the connector (for your own routing/labeling).",
        optional: false,
        control_type: "select",
        options: [
          ["Development", "development"],
          ["Staging", "staging"],
          ["Production", "production"]
        ],
        default: "development",
        group: "Labeling",
        sticky: true,
        support_pills: false
      },
      {
        name: "chunk_size_default", label: "Default Chunk Size",
        hint: "Default token size for text chunks",
        optional: true, default: 1000, control_type: "number",
        type: "integer", convert_input: "integer_conversion",
        group: "RAG defaults"
      },
      {
        name: "chunk_overlap_default", label: "Default Chunk Overlap",
        hint: "Default token overlap between chunks",
        optional: true, default: 100, control_type: "number",
        type: "integer", convert_input: "integer_conversion",
        group: "RAG defaults"
      },
      {
        name: "similarity_threshold", label: "Similarity Threshold",
        hint: "Minimum similarity score (0-1) for cosine/euclidean; used as default gate.",
        optional: true, type: "number", control_type: "number",
        default: 0.7, convert_input: "float_conversion",
        group: "Similarity defaults"
      }
    ],
    authorization: {
      type: "custom_auth",
      apply: lambda do |connection|
        if connection['api_token'].present?
          headers('Authorization' => "Bearer #{connection['api_token']}",
                  'Accept' => 'application/json')
        end
      end
    },
    base_uri: lambda do |connection|
      host = (connection['developer_api_host'].presence || 'app.eu').to_s
      "https://#{host}.workato.com"
    end
  },

  # ==========================================
  # CONNECTION TEST
  # ==========================================
  test: lambda do |connection|
    # Always return something informative for UX; only call APIs if token provided
    result = { environment: connection["environment"] || "dev" }

    if connection['api_token'].present?
      # Validate token + region (users.me) and Data Tables listing for completeness
      whoami = call(:execute_with_retry, connection, lambda { get('/api/users/me') })
      result[:account]   = whoami["name"] || whoami["id"]
      result[:region]    = connection['developer_api_host']
      # Data tables are optional; verify reachability if permitted
      begin
        _tables = call(:execute_with_retry, connection, lambda { get('/api/data_tables').params(page: 1, per_page: 1) })
        result[:data_tables] = "reachable"
      rescue RestClient::ExceptionWithResponse => e
        # Token may not have this privilege; surface gently
        result[:data_tables] = "not reachable (#{e.http_code})"
      end
      # Lightweight probes for project/folder lookups (privilege dependent)
      begin
        _projects = call(:execute_with_retry, connection, lambda { get('/api/projects').params(page: 1, per_page: 1) })
        result[:projects] = "reachable"
      rescue RestClient::ExceptionWithResponse => e
        result[:projects] = "not reachable (#{e.http_code})"
      end
      begin
        _folders = call(:execute_with_retry, connection, lambda { get('/api/folders').params(page: 1, per_page: 1) })
        result[:folders] = "reachable"
      rescue RestClient::ExceptionWithResponse => e
        result[:folders] = "not reachable (#{e.http_code})"
      end
      result[:status] = "connected"
    else
      result[:status] = "connected (no API token)"
    end

    result
  end,

  # ==========================================
  # ACTIONS
  # ==========================================
  actions: {

    # ------------------------------------------
    # 1. SMART CHUNK TEXT
    # ------------------------------------------
    smart_chunk_text: {
      title: "Smart Chunk Text",
      subtitle: "Intelligently chunk text preserving context",
      description: "Split text into chunks with smart boundaries and overlap.",
      help: lambda do
        {
          body: "Splits text into token‑approximate chunks using sentence/paragraph boundaries and overlap. Use connection defaults to avoid per‑step config.",
          learn_more_url: "https://docs.workato.com/developing-connectors/sdk/sdk-reference/schema.html#using-convert_input-and-convert_output-for-easy-transformations",
          learn_more_text: "Schema & conversions"
        }
      end,

      config_fields: [
        {
          name: "use_custom_settings",
          label: "Configuration mode",
          control_type: "select",
          pick_list: [
            ["Use connection defaults", "defaults"],
            ["Custom settings", "custom"]
          ],
          default: "defaults",
          sticky: true,
          hint: "Select 'Custom' to override connection defaults."
        }
      ],

      input_fields: lambda do |object_definitions, connection, config|
        fields = [
          { name: "text", label: "Input text", type: "string",
            optional: false, control_type: "text-area",
            hint: "Raw text to be chunked" }
        ]
        if config["use_custom_settings"] == "custom"
          fields.concat(object_definitions["chunking_config"])
        end
        fields
      end,

      output_fields: lambda do |object_definitions|
        object_definitions["chunking_result"]
      end,

      sample_output: lambda do
        {
          "chunks" => [
            { "chunk_id" => "chunk_0", "chunk_index" => 0, "text" => "Lorem ipsum…", "token_count" => 120, "start_char" => 0, "end_char" => 480, "metadata" => { "has_overlap" => false, "is_final" => false } }
          ],
          "total_chunks" => 1,
          "total_tokens" => 120
        }
      end,

      execute: lambda do |connection, input, _eis, _eos, config|
        if config["use_custom_settings"] != "custom"
          input['chunk_size']     ||= (connection['chunk_size_default'] || 1000)
          input['chunk_overlap']  ||= (connection['chunk_overlap_default'] || 100)
          input['preserve_sentences']  = true  if input['preserve_sentences'].nil?
          input['preserve_paragraphs'] = false if input['preserve_paragraphs'].nil?
        end

        # Guards for pathological inputs
        cs = (input['chunk_size'] || 1000).to_i
        co = (input['chunk_overlap'] || 100).to_i
        error("Chunk size must be > 0")        if cs <= 0
        error("Chunk overlap must be >= 0")    if co < 0

        call(:chunk_text_with_overlap, input)
      end
    },

    # ------------------------------------------
    # 2. CLEAN EMAIL TEXT
    # ------------------------------------------
    clean_email_text: {
      title: "Clean Email Text",
      subtitle: "Preprocess email content for RAG",
      description: "Clean and preprocess email body text",
      help: lambda do
        {
          body: "Removes signatures, quoted text, disclaimers; normalizes whitespace; optional URL extraction.",
          learn_more_url: "https://docs.workato.com/developing-connectors/sdk/sdk-reference/actions.html#help",
          learn_more_text: "Action help patterns"
        }
      end,

      input_fields: lambda do |object_definitions|
        [
          {
            name: "email_body", label: "Email body", type: "string", optional: false,
            control_type: "text-area", hint: "Raw email body text to be cleaned"
          }
        ] + object_definitions["email_cleaning_options"]
      end,

      output_fields: lambda do |object_definitions|
        object_definitions["email_cleaning_result"]
      end,

      sample_output: lambda do
        {
          "cleaned_text" => "Hello team, …",
          "extracted_query" => "Hello team, …",
          "removed_sections" => ["--\nJohn\n"],
          "extracted_urls" => ["https://example.com"],
          "original_length" => 1024,
          "cleaned_length" => 680,
          "reduction_percentage" => 33.59
        }
      end,

      execute: lambda do |_connection, input|
        call(:process_email_text, input)
      end
    },

    # ------------------------------------------
    # 3. CALCULATE SIMILARITY
    # ------------------------------------------
    calculate_similarity: {
      title: "Calculate Vector Similarity",
      subtitle: "Compute similarity scores for vectors",
      description: "Compute similarity between embedding vectors",
      help: lambda do
        {
          body: "Supports cosine, euclidean, and dot product. Dot product without normalization requires a model‑appropriate absolute threshold.",
          learn_more_url: "https://docs.workato.com/developing-connectors/sdk/guides/config_fields.html",
          learn_more_text: "Dynamic fields via config_fields"
        }
      end,

      config_fields: [
        {
          name: "similarity_method",
          label: "Similarity method",
          control_type: "select",
          pick_list: "similarity_types",
          default: "cosine",
          sticky: true,
          hint: "Controls which inputs are shown below."
        }
      ],

      input_fields: lambda do |_object_definitions, _connection, config|
        fields = [
          {
            name: "vectors", label: "Vectors to compare", type: "object",
            properties: [
              { name: "vector_a", label: "First vector",  type: "array", of: "number", list_mode_toggle: true, optional: false },
              { name: "vector_b", label: "Second vector", type: "array", of: "number", list_mode_toggle: true, optional: false }
            ],
            group: "Vectors"
          }
        ]
        method = (config['similarity_method'] || 'cosine').to_s
        unless method == 'dot_product'
          fields << {
            name: "normalize", label: "Normalize vectors", control_type: "checkbox",
            type: "boolean", default: true, optional: true,
            hint: "Ignored for dot product.", group: "Options"
          }
        end
        fields
      end,

      output_fields: lambda do |object_definitions|
        object_definitions["similarity_result"]
      end,

      sample_output: lambda do
        {
          "similarity_score" => 0.873421,
          "similarity_percentage" => 87.34,
          "is_similar" => true,
          "similarity_type" => "cosine",
          "computation_time_ms" => 2,
          "threshold_used" => 0.7,
          "vectors_normalized" => true
        }
      end,

      execute: lambda do |connection, input, _eis, _eos, config|
        input['vector_a'] = Array(input.dig('vectors', 'vector_a'))
        input['vector_b'] = Array(input.dig('vectors', 'vector_b'))
        error("Vectors cannot be empty") if input['vector_a'].empty? || input['vector_b'].empty?
        input['similarity_type'] = (config['similarity_method'] || 'cosine')
        call(:compute_similarity, input, connection)
      end
    },

    # ------------------------------------------
    # 4. FORMAT EMBEDDINGS BATCH
    # ------------------------------------------
    format_embeddings_batch: {
      title: "Format Embeddings for Vertex AI",
      subtitle: "Format embeddings for batch processing",
      description: "Prepare embedding data for Vertex AI Vector Search",
      help: lambda do
        {
          body: "Formats embedding vectors into batches suitable for vector ingestion with JSON/JSONL/CSV payloads.",
          learn_more_url: "https://docs.workato.com/developing-connectors/sdk/sdk-reference/object_definitions.html",
          learn_more_text: "Object definitions"
        }
      end,

      input_fields: lambda do |object_definitions|
        [
          {
            name: "embeddings", label: "Embeddings data",
            type: "array", of: "object",
            properties: object_definitions["embedding_object"],
            list_mode_toggle: true
          },
          { name: "index_endpoint", label: "Index endpoint ID", type: "string", optional: false },
          { name: "batch_size", label: "Batch size", type: "integer", optional: true, default: 25, hint: "Embeddings per batch" },
          {
            name: "format_type", label: "Format type",
            type: "string", optional: true, default: "json",
            control_type: "select", pick_list: "format_types",
            toggle_hint: "Select",
            toggle_field: { name: "format_type", label: "Format type (custom)", type: "string", control_type: "text", toggle_hint: "Use text" }
          }
        ]
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: "formatted_batches", type: "array", of: "object", properties: object_definitions["vertex_batch"] },
          { name: "total_batches", type: "integer" },
          { name: "total_embeddings", type: "integer" },
          { name: "index_endpoint", type: "string" },
          { name: "format", type: "string" },
          { name: "payload", type: "string" }
        ]
      end,

      sample_output: lambda do
        {
          "formatted_batches" => [{ "batch_id" => "batch_0", "batch_number" => 0, "datapoints" => [], "size" => 0 }],
          "total_batches" => 1, "total_embeddings" => 0, "index_endpoint" => "idx-123", "format" => "json", "payload" => "[]"
        }
      end,

      execute: lambda do |_connection, input|
        call(:format_for_vertex_ai, input)
      end
    },

    # ------------------------------------------
    # 5. BUILD RAG PROMPT
    # ------------------------------------------
    build_rag_prompt: {
      title: "Build RAG Prompt",
      subtitle: "Construct optimized RAG prompt",
      description: "Build retrieval‑augmented generation prompt",
      help: lambda do
        {
          body: "Use a built‑in template or select a custom template from Data Tables. Custom selection requires API token & table access."
        }
      end,

      config_fields: [
        {
          name: "prompt_mode",
          label: "Prompt configuration",
          control_type: "select",
          pick_list: [["Template-based", "template"], ["Custom instructions", "custom"]],
          default: "template",
          sticky: true,
          support_pills: false
        },
        {
          name: "template_source",
          label: "Template source",
          control_type: "select",
          pick_list: [["Built-in", "builtin"], ["Custom (Data Tables)", "custom"]],
          default: "builtin",
          sticky: true,
          support_pills: false
        },
        {
          name: "templates_table_id",
          label: "Templates table (Data Tables)",
          control_type: "select",
          pick_list: "tables",
          ngIf: 'input.template_source == "custom"', # <- fix root to input
          hint: "Required when Template source = Custom",
          support_pills: false
        },
        {
          name: "template_display_field",
          label: "Display field name",
          type: "string", default: "name", optional: true, sticky: true,
          ngIf: 'input.template_source == "custom"', # <- fix root to input
          hint: "Column shown in the dropdown",
          support_pills: false
        },
        {
          name: "template_value_field",
          label: "Value field name",
          type: "string", default: "", optional: true, sticky: true,
          ngIf: 'input.template_source == "custom"', # <- fix root to input
          hint: "Stored value for the selection. Leave blank to use the Record ID.",
          support_pills: false
        },
        {
          name: "template_content_field",
          label: "Content field name",
          type: "string", default: "content", optional: true, sticky: true,
          ngIf: 'input.template_source == "custom"', # <- fix root to input
          hint: "Column containing the prompt text",
          support_pills: false
        }
      ],

      input_fields: lambda do |object_definitions, _connection, config|
        fields = [
          { name: "query", label: "User query", type: "string", optional: false, control_type: "text-area", group: "Query" },
          {
            name: "context_documents", label: "Context documents",
            type: "array", of: "object",
            properties: object_definitions["context_document"],
            list_mode_toggle: true, optional: false, group: "Context"
          }
        ]
        if config["prompt_mode"] == "template"
          fields << {
            name: "prompt_template", label: "Prompt template",
            type: "string", group: "Template settings",
            control_type: "select", pick_list: "prompt_templates",
            pick_list_params: {
              template_source: (config['template_source'] || 'builtin'),
              templates_table_id: config['templates_table_id'],
              template_display_field: (config['template_display_field'] || 'name'),
              template_value_field: (config['template_value_field'] || ''),
              template_content_field: (config['template_content_field'] || 'content')
            },
            optional: true,
            toggle_hint: "Select",
            toggle_field: { name: "prompt_template", label: "Template (custom text)", type: "string", control_type: "text", toggle_hint: "Use text" }
          }
        else
          fields << {
            name: "system_instructions", label: "System instructions",
            type: "string", control_type: "text-area", optional: true,
            hint: "Custom system instructions for the prompt", group: "Custom settings"
          }
        end

        fields += [
          {
            name: "advanced_settings", label: "Advanced settings", type: "object", optional: true,
            group: "Advanced", hint: "Optional configuration",
            properties: [
              { name: "max_context_length", label: "Max context length (tokens)", type: "integer", default: 3000, convert_input: "integer_conversion", hint: "Maximum tokens for context" },
              { name: "include_metadata", label: "Include metadata", type: "boolean", control_type: "checkbox", default: false, convert_input: "boolean_conversion", hint: "Include document metadata in prompt" }
            ]
          }
        ]
        fields
      end,

      output_fields: lambda do
        [
          { name: "formatted_prompt", type: "string" },
          { name: "token_count", type: "integer" },
          { name: "context_used", type: "integer" },
          { name: "truncated", type: "boolean", control_type: "checkbox" },
          { name: "prompt_metadata", type: "object" }
        ]
      end,

      sample_output: lambda do
        {
          "formatted_prompt" => "Context:\n…\n\nQuery: …\n\nAnswer:",
          "token_count" => 512, "context_used" => 3, "truncated" => false,
          "prompt_metadata" => { "template" => "standard", "using_template_content" => false }
        }
      end,

      execute: lambda do |connection, input, _eis, _eos, config|
        if input['advanced_settings']
          input.merge!(input['advanced_settings'])
          input.delete('advanced_settings')
        end

        if config["prompt_mode"] == "template"
          source = (config["template_source"] || "builtin").to_s
          sel    = (input["prompt_template"] || "").to_s

          if source == "custom" && config["templates_table_id"].present? && sel.present?
            inline = (sel.include?("\n") || sel.length > 200)

            unless inline
              resolved = call(:resolve_template_selection, connection, config, sel)
              if resolved && resolved["content"].to_s.strip.length.positive?
                input["template_content"] = resolved["content"].to_s
                input["prompt_metadata"] = {
                  template_source: "custom",
                  templates_table_id: config["templates_table_id"],
                  template_value: sel,
                  template_display: resolved["display"]
                }.compact
              end
            else
              input["template_content"] = sel
              input["prompt_metadata"] = { template_source: "inline" }
            end
          elsif sel.present? && (sel.include?("\n") || sel.length > 200)
            input["template_content"] = sel
            input["prompt_metadata"] = { template_source: "inline" }
          end
        end

        call(:construct_rag_prompt, input)
      end
    },

    # ------------------------------------------
    # 6. VALIDATE LLM RESPONSE
    # ------------------------------------------
    validate_llm_response: {
      title: "Validate LLM Response",
      subtitle: "Validate and score LLM output",
      description: "Check response quality and relevance",
      help: lambda do
        {
          body: "Lightweight heuristics: query overlap, length, rule checks, and confidence score.",
          learn_more_url: "https://docs.workato.com/developing-connectors/sdk/sdk-reference/actions.html#sample_output",
          learn_more_text: "Why sample output matters"
        }
      end,

      input_fields: lambda do |object_definitions|
        [
          { name: "response_text", label: "LLM response", type: "string", optional: false, control_type: "text-area" },
          { name: "original_query", label: "Original query", type: "string", optional: false },
          { name: "context_provided", label: "Context documents", type: "array", of: "string", optional: true, list_mode_toggle: true },
          { name: "validation_rules", label: "Validation rules", type: "array", of: "object", properties: object_definitions["validation_rule"], optional: true },
          { name: "min_confidence", label: "Minimum confidence", type: "number", convert_input: "float_conversion", optional: true, default: 0.7, sticky: true }
        ]
      end,

      output_fields: lambda do
        [
          { name: "is_valid", type: "boolean", control_type: "checkbox" },
          { name: "confidence_score", type: "number" },
          { name: "validation_results", type: "object" },
          { name: "issues_found", type: "array", of: "string" },
          { name: "requires_human_review", type: "boolean", control_type: "checkbox" },
          { name: "suggested_improvements", type: "array", of: "string" }
        ]
      end,

      sample_output: lambda do
        {
          "is_valid" => true, "confidence_score" => 0.84,
          "validation_results" => { "query_overlap" => 0.33, "response_length" => 1100, "word_count" => 230 },
          "issues_found" => [], "requires_human_review" => false, "suggested_improvements" => []
        }
      end,

      execute: lambda do |_connection, input|
        call(:validate_response, input)
      end
    },

    # ------------------------------------------
    # 7. GENERATE DOCUMENT METADATA
    # ------------------------------------------
    generate_document_metadata: {
      title: "Generate Document Metadata",
      subtitle: "Extract metadata from documents",
      description: "Generate metadata for document indexing",
      help: lambda do
        {
          body: "Token estimate uses 4 chars/token heuristic; key topics via naive frequency analysis.",
          learn_more_url: "https://docs.workato.com/developing-connectors/sdk/sdk-reference/object_definitions.html",
          learn_more_text: "Reusable schemas"
        }
      end,

      input_fields: lambda do
        [
          { name: "document_content", label: "Document content", type: "string", optional: false, control_type: "text-area" },
          { name: "file_path", label: "File path", type: "string", optional: false },
          { name: "file_type", label: "File type", type: "string", optional: true, control_type: "select", pick_list: "file_types" },
          { name: "extract_entities", label: "Extract entities", type: "boolean", optional: true, default: true, control_type: "checkbox" },
          { name: "generate_summary", label: "Generate summary", type: "boolean", optional: true, default: true, control_type: "checkbox" }
        ]
      end,

      output_fields: lambda do
        [
          { name: "document_id", type: "string" },
          { name: "file_hash", type: "string" },
          { name: "word_count", type: "integer" },
          { name: "character_count", type: "integer" },
          { name: "estimated_tokens", type: "integer" },
          { name: "language", type: "string" },
          { name: "summary", type: "string" },
          { name: "key_topics", type: "array", of: "string" },
          { name: "entities", type: "object" },
          { name: "created_at", type: "timestamp" },
          { name: "processing_time_ms", type: "integer" }
        ]
      end,

      sample_output: lambda do
        {
          "document_id" => "abc123", "file_hash" => "…sha256…", "word_count" => 2500, "character_count" => 14000,
          "estimated_tokens" => 3500, "language" => "english", "summary" => "…", "key_topics" => %w[rules r ag email],
          "entities" => { "people" => [], "organizations" => [], "locations" => [] },
          "created_at" => Time.now.iso8601, "processing_time_ms" => 12
        }
      end,

      execute: lambda do |_connection, input|
        call(:extract_metadata, input)
      end
    },

    # ------------------------------------------
    # 8. CHECK DOCUMENT CHANGES
    # ------------------------------------------
    check_document_changes: {
      title: "Check Document Changes",
      subtitle: "Detect changes in documents",
      description: "Compare document versions to detect modifications",
      help: lambda do
        {
          body: "Choose Hash only (fast), Content diff (line‑based), or Smart diff (tokens + structure).",
          learn_more_url: "https://docs.workato.com/developing-connectors/sdk/sdk-reference/actions.html",
          learn_more_text: "Action anatomy"
        }
      end,

      input_fields: lambda do
        [
          { name: "current_hash", label: "Current document hash", type: "string", optional: false },
          { name: "current_content", label: "Current content", type: "string", optional: true, control_type: "text-area" },
          { name: "previous_hash", label: "Previous document hash", type: "string", optional: false },
          { name: "previous_content", label: "Previous content", type: "string", optional: true, control_type: "text-area" },
          { name: "check_type", label: "Check type", type: "string", optional: true, default: "hash", control_type: "select", pick_list: "check_types" }
        ]
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: "has_changed", type: "boolean", control_type: "checkbox" },
          { name: "change_type", type: "string" },
          { name: "change_percentage", type: "number" },
          { name: "added_content", type: "array", of: "string" },
          { name: "removed_content", type: "array", of: "string" },
          { name: "modified_sections", type: "array", of: "object", properties: object_definitions["diff_section"] },
          { name: "requires_reindexing", type: "boolean", control_type: "checkbox" }
        ]
      end,

      sample_output: lambda do
        {
          "has_changed" => true, "change_type" => "content_changed", "change_percentage" => 12.5,
          "added_content" => ["new line"], "removed_content" => ["old line"],
          "modified_sections" => [{ "type" => "modified", "current_range" => [10,10], "previous_range" => [10,10], "current_lines" => ["A"], "previous_lines" => ["B"] }],
          "requires_reindexing" => true
        }
      end,

      execute: lambda do |_connection, input|
        call(:detect_changes, input)
      end
    },

    # ------------------------------------------
    # 9. CALCULATE METRICS
    # ------------------------------------------
    calculate_metrics: {
      title: "Calculate Performance Metrics",
      subtitle: "Calculate system performance metrics",
      description: "Calculate averages, percentiles, trend and anomalies from time‑series data",
      help: lambda do
        {
          body: "Computes avg/median/min/max/stddev, P95/P99, simple trend and 2σ anomalies.",
          learn_more_url: "https://docs.workato.com/developing-connectors/sdk/sdk-reference/object_definitions.html",
          learn_more_text: "Reusable datapoint schema"
        }
      end,

      input_fields: lambda do |object_definitions|
        [
          { name: "metric_type", label: "Metric type", type: "string", optional: false, control_type: "select", pick_list: "metric_types" },
          { name: "data_points", label: "Data points", list_mode_toggle: true, type: "array", of: "object", optional: false, properties: object_definitions["metric_datapoint"] },
          { name: "aggregation_period", label: "Aggregation period", type: "string", optional: true, default: "hour", control_type: "select", pick_list: "time_periods" },
          { name: "include_percentiles", label: "Include percentiles", type: "boolean", control_type: "checkbox", convert_input: "boolean_conversion", optional: true, default: true }
        ]
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: "average", type: "number" },
          { name: "median", type: "number" },
          { name: "min", type: "number" },
          { name: "max", type: "number" },
          { name: "std_deviation", type: "number" },
          { name: "percentile_95", type: "number" },
          { name: "percentile_99", type: "number" },
          { name: "total_count", type: "integer" },
          { name: "trend", type: "string" },
          { name: "anomalies_detected", type: "array", of: "object", properties: object_definitions["anomaly"] }
        ]
      end,

      sample_output: lambda do
        {
          "average" => 12.3, "median" => 11.8, "min" => 4.2, "max" => 60.0,
          "std_deviation" => 5.1, "percentile_95" => 22.0, "percentile_99" => 29.5,
          "total_count" => 1440, "trend" => "increasing",
          "anomalies_detected" => [{ "timestamp" => Time.now.iso8601, "value" => 42.0 }]
        }
      end,

      execute: lambda do |_connection, input|
        call(:compute_metrics, input)
      end
    },

    # ------------------------------------------
    # 10. OPTIMIZE BATCH SIZE
    # ------------------------------------------
    optimize_batch_size: {
      title: "Optimize Batch Size",
      subtitle: "Calculate optimal batch size for processing",
      description: "Recommend an optimal batch size based on historical performance",
      help: lambda do
        {
          body: "Heuristic scoring by target (throughput/latency/cost/accuracy).",
          learn_more_url: "https://docs.workato.com/developing-connectors/sdk/guides/best-practices.html",
          learn_more_text: "SDK best practices"
        }
      end,

      input_fields: lambda do
        [
          { name: "total_items", label: "Total items to process", type: "integer", optional: false },
          {
            name: "processing_history", label: "Processing history",
            type: "array", of: "object", optional: true,
            properties: [
              { name: "batch_size", type: "integer" },
              { name: "processing_time", type: "number" },
              { name: "success_rate", type: "number" },
              { name: "memory_usage", type: "number" }
            ]
          },
          { name: "optimization_target", label: "Optimization target", type: "string", optional: true, default: "throughput", control_type: "select", pick_list: "optimization_targets" },
          { name: "max_batch_size", label: "Maximum batch size", type: "integer", optional: true, default: 100 },
          { name: "min_batch_size", label: "Minimum batch size", type: "integer", optional: true, default: 10 }
        ]
      end,

      output_fields: lambda do
        [
          { name: "optimal_batch_size", type: "integer" },
          { name: "estimated_batches", type: "integer" },
          { name: "estimated_processing_time", type: "number" },
          { name: "throughput_estimate", type: "number" },
          { name: "confidence_score", type: "number" },
          { name: "recommendation_reason", type: "string" }
        ]
      end,

      sample_output: lambda do
        {
          "optimal_batch_size" => 50, "estimated_batches" => 20, "estimated_processing_time" => 120.5,
          "throughput_estimate" => 41.5, "confidence_score" => 0.8, "recommendation_reason" => "Based on historical performance data"
        }
      end,

      execute: lambda do |_connection, input|
        call(:calculate_optimal_batch, input)
      end
    },

    # ------------------------------------------
    # 11. EVALUATE EMAIL BY RULES
    # ------------------------------------------
    evaluate_email_by_rules: {
      title: "Evaluate email against rules",
      subtitle: "Standard patterns or custom rules from Data Tables",
      description: "Evaluate email and return best‑matching rule and action",
      help: lambda do
        {
          body: "Use standard patterns or supply a Data Table of rules {rule_id, rule_type, rule_pattern, action, priority, active}. Requires API token to read Data Tables.",
          learn_more_url: "https://docs.workato.com/workato-api/data-tables.html",
          learn_more_text: "Developer API: Data tables"
        }
      end,

      config_fields: [ # Remember -- config drives inputs
        {
          name: "rules_source", label: "Rules source", control_type: "select",
          pick_list: [["Standard", "standard"], ["Custom (Data Tables)", "custom"]],
          default: "standard", sticky: true, support_pills: false,
          hint: "Use 'Custom' to evaluate against a data table of rules."
        },
        {
          name: "custom_rules_table_id", label: "Rules table (Data Tables)",
          control_type: "select", pick_list: "tables", support_pills: false,
          ngIf: 'input.rules_source == "custom"', sticky: true,
          hint: "Required when rules_source is custom"
        },
        # Optional column mapping when teams use different column names
        {
          name: "enable_column_mapping",
          label: "Custom column names?",
          type: "boolean", control_type: "checkbox", default: false,
          ngIf: 'input.rules_source == "custom"',
          sticky: true, support_pills: false
        },
        # Mapped columns – only shown when mapping is enabled
        { name: "col_rule_id",      label: "Rule ID column",      control_type: "select", pick_list: "table_columns",
          ngIf: 'input.rules_source == "custom" && input.enable_column_mapping == true',
          optional: true, sticky: true, support_pills: false },
        { name: "col_rule_type",    label: "Rule type column",    control_type: "select", pick_list: "table_columns",
          ngIf: 'input.rules_source == "custom" && input.enable_column_mapping == true',
          optional: true, sticky: true, support_pills: false },
        { name: "col_rule_pattern", label: "Rule pattern column", control_type: "select", pick_list: "table_columns",
          ngIf: 'input.rules_source == "custom" && input.enable_column_mapping == true',
          optional: true, sticky: true, support_pills: false },
        { name: "col_action",       label: "Action column",       control_type: "select", pick_list: "table_columns",
          ngIf: 'input.rules_source == "custom" && input.enable_column_mapping == true',
          optional: true, sticky: true, support_pills: false },
        { name: "col_priority",     label: "Priority column",     control_type: "select", pick_list: "table_columns",
          ngIf: 'input.rules_source == "custom" && input.enable_column_mapping == true',
          optional: true, sticky: true, support_pills: false },
        { name: "col_active",       label: "Active column",       control_type: "select", pick_list: "table_columns",
          ngIf: 'input.rules_source == "custom" && input.enable_column_mapping == true',
          optional: true, sticky: true, support_pills: false }

      ],

      input_fields: lambda do |object_definitions, _connection, config|
        fields = [
          {
            name: "email", label: "Email", type: "object", optional: false,
            properties: object_definitions["email_envelope"], group: "Email"
          },
          {
            name: "stop_on_first_match", label: "Stop on first match", control_type: "checkbox",
            type: "boolean", default: true, optional: true, sticky: true,
            hint: "When true, returns as soon as a rule matches.", group: "Execution"
          },
          {
            name: "fallback_to_standard", label: "Fallback to standard patterns",
            type: "boolean", default: true, optional: true, sticky: true, control_type: "checkbox",
            hint: "If custom rules have no match, also evaluate built‑in standard patterns.", group: "Execution"
          },
          {
            name: "max_rules_to_apply", label: "Max rules to apply",
            type: "integer", default: 100, optional: true,
            hint: "Guardrail for pathological rule sets.", group: "Advanced"
          }
        ]

        # Show selected table id as read-only context when relevant
        if (config["rules_source"] || "standard").to_s == "custom"
          fields << {
            name: "selected_rules_table_id",
            label: "Selected rules table",
            type: "string", optional: true, sticky: true,
            hint: "From configuration above.",
            default: config["custom_rules_table_id"],
            control_type: "plain-text", # documented read-only
            support_pills: false,
            group: "Advanced"
          }
        end

        fields
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: "pattern_match", type: "boolean", control_type: "checkbox" },
          { name: "rule_source", type: "string" }, # "custom", "standard", or "none"
          { name: "selected_action", type: "string" },
          { name: "top_match", type: "object", properties: object_definitions["rules_row"] },
          { name: "matches", type: "array", of: "object", properties: object_definitions["rules_row"] },
          { name: "standard_signals", type: "object", properties: object_definitions["standard_signals"] },
          {
            name: "debug", type: "object", properties: [
              { name: "evaluated_rules_count", type: "integer" },
              { name: "schema_validated", type: "boolean", control_type: "checkbox" },
              { name: "errors", type: "array", of: "string" }
            ]
          }
        ]
      end,

      sample_output: lambda do
        {
          "pattern_match" => true,
          "rule_source" => "custom",
          "selected_action" => "archive",
          "top_match" => { "rule_id" => "R-1", "rule_type" => "subject", "rule_pattern" => "receipt", "action" => "archive", "priority" => 10, "field_matched" => "subject", "sample" => "Receipt #12345" },
          "matches" => [],
          "standard_signals" => { "sender_flags" => ["no[-_.]?reply"], "subject_flags" => ["\\breceipt\\b"], "body_flags" => [] },
          "debug" => { "evaluated_rules_count" => 25, "schema_validated" => true, "errors" => [] }
        }
      end,

      execute: lambda do |connection, input, _eis, _eos, config|
        call(:evaluate_email_by_rules_exec, connection, input, config)
      end
    },
  
    adapt_chunks_for_vertex: {
      title: "Adapt chunks for Vertex",
      subtitle: "Map chunk objects → {id, text, metadata}",
      description: "Generate stable IDs and merge base metadata.",
      input_fields: lambda do |object_definitions|
        [
          { name: "chunks", type: "array", of: "object", list_mode_toggle: true, optional: false,
            properties: object_definitions["chunk_object"] },
          { name: "id_strategy", control_type: "select", default: "docid_index", sticky: true,
            pick_list: [[ "Use chunk_id", "pass_through" ],
                        [ "Prefix + index", "prefix_index" ],
                        [ "Document ID/Hash + index", "docid_index" ]] },
          { name: "id_prefix", hint: "Used when Prefix + index" },
          { name: "document_id", hint: "Used when Document ID/Hash + index (e.g. from Generate document metadata)" },
          { name: "base_metadata", type: "object", label: "Base metadata merged into each chunk" }
        ]
      end,
      output_fields: lambda do
        [
          { name: "records", type: "array", of: "object", properties: [
            { name: "id" }, { name: "text" }, { name: "metadata", type: "object" }
          ]},
          { name: "count", type: "integer" }
        ]
      end,
      execute: lambda do |_connection, input|
        chunks    = Array(input['chunks'])
        strategy  = (input['id_strategy'] || 'docid_index').to_s
        base_meta = input['base_metadata'] || {}

        recs = chunks.each_with_index.map do |c, idx|
          id =
            case strategy
            when 'pass_through' then (c['chunk_id'].presence || "chunk_#{idx}")
            when 'prefix_index' then [input['id_prefix'], idx].compact.join('_')
            else                      [input['document_id'], idx].compact.join('_')
            end

          meta = (c['metadata'] || {}).merge(base_meta)
                  .merge('chunk_index' => c['chunk_index'], 'chunk_id' => (c['chunk_id'] || id))

          { 'id' => id, 'text' => c['text'].to_s, 'metadata' => meta }
        end

        { 'records' => recs, 'count' => recs.length }
      end
    },
    serialize_chunks_to_jsonl: {
      title: "Serialize chunks (JSONL)",
      subtitle: "Emit JSONL with id/text/metadata",
      input_fields: lambda do |object_definitions|
        [
          { name: "chunks", type: "array", of: "object", list_mode_toggle: true, optional: false,
            properties: object_definitions["chunk_object"] },
          { name: "include_metadata", type: "boolean", control_type: "checkbox", default: true },
          { name: "id_field_name", default: "id" },
          { name: "id_strategy", control_type: "select", default: "docid_index", sticky: true,
            pick_list: [[ "Use chunk_id", "pass_through" ],
                        [ "Prefix + index", "prefix_index" ],
                        [ "Document ID/Hash + index", "docid_index" ]] },
          { name: "id_prefix" }, { name: "document_id" }
        ]
      end,
      output_fields: lambda do
        [ { name: "jsonl", type: "string" }, { name: "lines", type: "integer" } ]
      end,
      execute: lambda do |_connection, input|
        chunks = Array(input['chunks'])
        strat  = (input['id_strategy'] || 'docid_index').to_s
        name   = (input['id_field_name'] || 'id').to_s

        lines = chunks.each_with_index.map do |c, idx|
          id =
            case strat
            when 'pass_through' then (c['chunk_id'].presence || "chunk_#{idx}")
            when 'prefix_index' then [input['id_prefix'], idx].compact.join('_')
            else                      [input['document_id'], idx].compact.join('_')
            end
          row = { name => id, 'text' => c['text'].to_s }
          row['metadata'] = c['metadata'] if input['include_metadata']
          JSON.generate(row)
        end

        { 'jsonl' => lines.join("\n"), 'lines' => lines.length }
      end
    },
    to_vertex_datapoints: {
      title: "Build Vertex datapoints",
      subtitle: "Embeddings + metadata → upsert payload",
      description: "Produce datapoints with restricts/numericRestricts ready for Vertex upsertDatapoints.",
      input_fields: lambda do |object_definitions|
        [
          { name: "embeddings", type: "array", of: "object", list_mode_toggle: true, optional: false,
            properties: object_definitions["embedding_object"] },
          { name: "restrict_mode", control_type: "select", default: "per_key", sticky: true,
            pick_list: [[ "Per-key namespaces", "per_key" ], [ "Flat namespace (key=value)", "flat" ]] },
          { name: "flat_namespace", hint: "Used when restrict_mode = flat", sticky: true },
          { name: "promote_numeric", type: "boolean", control_type: "checkbox", default: true,
            hint: "Turn numeric metadata into numericRestricts[EQUAL]" }
        ]
      end,
      output_fields: lambda do |object_definitions|
        [
          { name: "datapoints", type: "array", of: "object", properties: object_definitions["vertex_datapoint_upsert"] },
          { name: "count", type: "integer" }
        ]
      end,
      execute: lambda do |_connection, input|
        mode = (input['restrict_mode'] || 'per_key').to_s
        flat_ns = input['flat_namespace']
        promote = !!input['promote_numeric']

        dps = Array(input['embeddings']).map do |e|
          meta = e['metadata'] || {}
          restricts, numeric = call(:build_vertex_restricts, meta, (mode == 'flat' ? 'flat' : 'per_key'), flat_ns, promote)
          {
            'datapointId'    => e['id'],
            'featureVector'  => Array(e['vector'] || []),
            'restricts'      => (restricts if restricts.any?),
            'numericRestricts' => (numeric if numeric.any?)
          }.compact
        end

        { 'datapoints' => dps, 'count' => dps.length }
      end
    },

    # Resolve project context for a recipe
    resolve_project_context: {
      title: "Resolve project context from recipe",
      subtitle: "Recipe → folder → owning project (environment-aware)",
      description: "Given a Recipe ID, returns its folder and the project it belongs to.",
      input_fields: lambda do
        [
          { name: "recipe_id", optional: false,
            hint: "Map the Recipe ID datapill or enter an ID manually" }
        ]
      end,
      output_fields: lambda do
        [
          { name: "recipe_id" },
          { name: "folder_id" },
          { name: "folder_name" },
          { name: "is_project_folder", type: "boolean" },
          { name: "project_id" },
          { name: "project_name" },
          { name: "project_folder_id" },
          { name: "environment_host", label: "Environment host" }
        ]
      end,
      execute: lambda do |connection, input|
        error("API token is required for Developer API calls") if connection['api_token'].blank?
        call(:resolve_project_from_recipe, connection, input["recipe_id"])
      end
    }

  },

  # ==========================================
  # METHODS (Helper Functions)
  # ==========================================
  methods: {

    build_vertex_restricts: lambda do |_connection, metadata, mode, flat_ns, promote_numeric|
      md = metadata.is_a?(Hash) ? metadata : {}
      restricts = []
      numeric   = []

      md.each do |k, v|
        key = k.to_s
        case v
        when String
          if mode == 'flat'
            restricts << { 'namespace' => (flat_ns || 'tags'), 'allowList' => ["#{key}=#{v}"] }
          else
            restricts << { 'namespace' => key, 'allowList' => [v] }
          end
        when Array
          vals = v.map(&:to_s)
          if mode == 'flat'
            # flatten: key=val for each
            restricts << { 'namespace' => (flat_ns || 'tags'), 'allowList' => vals.map { |s| "#{key}=#{s}" } }
          else
            restricts << { 'namespace' => key, 'allowList' => vals }
          end
        when Integer
          if promote_numeric
            numeric << { 'namespace' => key, 'op' => 'EQUAL', 'valueInt' => v.to_i }
          end
        when Float
          if promote_numeric
            numeric << { 'namespace' => key, 'op' => 'EQUAL', 'valueDouble' => v.to_f }
          end
        end
      end

      [restricts, numeric]
    end,

    chunk_text_with_overlap: lambda do |input|
      text = input['text'].to_s
      chunk_size = (input['chunk_size'] || 1000).to_i
      overlap    = (input['chunk_overlap'] || 100).to_i
      preserve_sentences  = !!input['preserve_sentences']
      preserve_paragraphs = !!input['preserve_paragraphs']

      chunk_size = 1 if chunk_size <= 0
      overlap = [[overlap, 0].max, [chunk_size - 1, 0].max].min

      # rough token->char estimate
      chars_per_chunk = [chunk_size, 1].max * 4
      char_overlap    = overlap * 4

      chunks = []
      chunk_index = 0
      position = 0
      text_len = text.length

      while position < text_len
        tentative_end = [position + chars_per_chunk, text_len].min
        chunk_end = tentative_end
        segment = text[position...tentative_end]

        if preserve_paragraphs && tentative_end < text_len
          rel_end = call(:util_last_boundary_end, segment, /\n{2,}/)
          chunk_end = position + rel_end if rel_end
        end

        if preserve_sentences && chunk_end == tentative_end && tentative_end < text_len
          rel_end = call(:util_last_boundary_end, segment, /[.!?]["')\]]?\s/)
          chunk_end = position + rel_end if rel_end
        end

        chunk_end = [position + [chars_per_chunk, 1].max, text_len].min if chunk_end <= position

        chunk_text = text[position...chunk_end]
        token_count = (chunk_text.length / 4.0).ceil

        chunks << {
          chunk_id:    "chunk_#{chunk_index}",
          chunk_index: chunk_index,
          text:        chunk_text,
          token_count: token_count,
          start_char:  position,
          end_char:    chunk_end,
          metadata:    { has_overlap: chunk_index.positive?, is_final: chunk_end >= text_len }
        }

        break if chunk_end >= text_len

        next_position = chunk_end - char_overlap
        position = next_position > position ? next_position : chunk_end
        chunk_index += 1
      end

      {
        chunks: chunks,
        total_chunks: chunks.length,
        total_tokens: chunks.sum { |c| c[:token_count] }
      }
    end,

    process_email_text: lambda do |input|
      cleaned = (input['email_body'] || '').dup
      original_length = cleaned.length
      removed_sections = []
      extracted_urls = []

      cleaned.gsub!("\r\n", "\n")

      if input['remove_quotes']
        lines = cleaned.lines
        quoted = lines.select { |l| l.lstrip.start_with?('>') }
        removed_sections << quoted.join unless quoted.empty?
        lines.reject! { |l| l.lstrip.start_with?('>') }
        cleaned = lines.join
      end

      if input['remove_signatures']
        lines = cleaned.lines
        sig_idx = lines.rindex { |l| l =~ /^\s*(--\s*$|Best regards,|Regards,|Sincerely,|Thanks,|Sent from my)/i }
        if sig_idx
          removed_sections << lines[sig_idx..-1].join
          cleaned = lines[0...sig_idx].join
        end
      end

      if input['remove_disclaimers']
        lines = cleaned.lines
        disc_idx = lines.rindex { |l| l =~ /(This (e-)?mail|This message).*(confidential|intended only)/i }
        if disc_idx && disc_idx >= lines.length - 25
          removed_sections << lines[disc_idx..-1].join
          cleaned = lines[0...disc_idx].join
        end
      end

      if input['extract_urls']
        extracted_urls = cleaned.scan(%r{https?://[^\s<>"'()]+})
      end

      if input['normalize_whitespace']
        cleaned.gsub!(/[ \t]+/, ' ')
        cleaned.gsub!(/\n{3,}/, "\n\n")
        cleaned.strip!
      end

      extracted_query = cleaned.split(/\n{2,}/).find { |p| p.strip.length.positive? } || cleaned[0, 200].to_s

      {
        cleaned_text: cleaned,
        extracted_query: extracted_query,
        removed_sections: removed_sections,
        extracted_urls: extracted_urls,
        original_length: original_length,
        cleaned_length: cleaned.length,
        reduction_percentage: (original_length.zero? ? 0 : ((1 - cleaned.length.to_f / original_length) * 100)).round(2)
      }
    end,

    compute_similarity: lambda do |input, connection|
      start_time = Time.now

      a = call(:util_coerce_numeric_vector, input['vector_a'])
      b = call(:util_coerce_numeric_vector, input['vector_b'])
      error('Vectors must be the same length.') unless a.length == b.length
      error('Vectors cannot be empty') if a.empty?

      normalize = input.key?('normalize') ? !!input['normalize'] : true
      type      = (input['similarity_type'] || 'cosine').to_s
      threshold = (connection['similarity_threshold'] || 0.7).to_f

      if normalize
        norm = ->(v) { mag = Math.sqrt(v.sum { |x| x * x }); mag.zero? ? v : v.map { |x| x / mag } }
        a = norm.call(a)
        b = norm.call(b)
      end

      dot   = a.zip(b).sum { |x, y| x * y }
      mag_a = Math.sqrt(a.sum { |x| x * x })
      mag_b = Math.sqrt(b.sum { |x| x * x })

      score =
        case type
        when 'cosine'
          (mag_a > 0 && mag_b > 0) ? dot / (mag_a * mag_b) : 0.0
        when 'euclidean'
          dist = Math.sqrt(a.zip(b).sum { |x, y| (x - y)**2 })
          1.0 / (1.0 + dist)
        when 'dot_product'
          dot
        else
          (mag_a > 0 && mag_b > 0) ? dot / (mag_a * mag_b) : 0.0
        end

      percent = %w[cosine euclidean].include?(type) ? (score * 100).round(2) : nil

      similar =
        case type
        when 'cosine', 'euclidean'
          score >= threshold
        when 'dot_product'
          if normalize
            score >= threshold
          else
            error('For dot_product without normalization, provide an absolute threshold appropriate to your embedding scale.')
          end
        end

      {
        similarity_score: score.round(6),
        similarity_percentage: percent,
        is_similar: similar,
        similarity_type: type,
        computation_time_ms: ((Time.now - start_time) * 1000).round,
        threshold_used: threshold,
        vectors_normalized: normalize
      }
    end,

    format_for_vertex_ai: lambda do |input|
      embeddings = input['embeddings'] || []
      batch_size = (input['batch_size'] || 25).to_i
      format     = (input['format_type'] || 'json').to_s

      batches = []
      embeddings.each_slice(batch_size).with_index do |batch, index|
        formatted_batch = {
          batch_id: "batch_#{index}",
          batch_number: index,
          datapoints: batch.map do |emb|
            {
              datapoint_id: emb['id'],
              feature_vector: emb['vector'] || [],
              restricts: emb['metadata'] || {}
            }
          end,
          size: batch.length
        }
        batches << formatted_batch
      end

      all_datapoints = batches.flat_map { |b| b[:datapoints] }

      payload = case format
                when 'jsonl'
                  all_datapoints.map { |dp| JSON.generate(dp) }.join("\n")
                when 'csv'
                  rows = [%w[datapoint_id feature_vector restricts]]
                  all_datapoints.each do |dp|
                    rows << [dp[:datapoint_id], JSON.generate(dp[:feature_vector]), JSON.generate(dp[:restricts])]
                  end
                  CSV.generate { |c| rows.each { |r| c << r } }
                else
                  JSON.generate(all_datapoints)
                end

      {
        formatted_batches: batches,
        total_batches: batches.length,
        total_embeddings: embeddings.length,
        index_endpoint: input['index_endpoint'],
        format: format,
        payload: payload
      }
    end,

    construct_rag_prompt: lambda do |input|
      query = input['query'].to_s
      context_docs = Array(input['context_documents'] || [])
      template_key = (input['prompt_template'] || 'standard').to_s
      max_length = (input['max_context_length'] || 3000).to_i
      include_metadata = !!input['include_metadata']
      system_instructions = input['system_instructions'].to_s
      template_content = input['template_content'].to_s

      sorted_context = context_docs.sort_by { |doc| (doc['relevance_score'] || 0) }.reverse

      context_parts = []
      total_tokens = 0
      sorted_context.each do |doc|
        content = doc['content'].to_s
        doc_tokens = (content.length / 4.0).ceil
        break if doc_tokens > max_length && context_parts.empty?
        next if total_tokens + doc_tokens > max_length

        part = content.dup
        part << "\nMetadata: #{JSON.generate(doc['metadata'])}" if include_metadata && doc['metadata']
        context_parts << part
        total_tokens += doc_tokens
      end
      context_text = context_parts.join("\n\n---\n\n")

      base =
        if template_content.strip.length.positive?
          template_content
        else
          case template_key
          when 'standard'
            "Context:\n{{context}}\n\nQuery: {{query}}\n\nAnswer:"
          when 'customer_service'
            "You are a customer service assistant.\n\nContext:\n{{context}}\n\nCustomer Question: {{query}}\n\nResponse:"
          when 'technical'
            "You are a technical support specialist.\n\nContext:\n{{context}}\n\nTechnical Issue: {{query}}\n\nSolution:"
          when 'sales'
            "You are a sales representative.\n\nContext:\n{{context}}\n\nSales Inquiry: {{query}}\n\nResponse:"
          else
            header = system_instructions.strip
            header = "Instructions:\n#{header}\n\n" if header.length.positive?
            "#{header}Context:\n{{context}}\n\nQuery: {{query}}\n\nAnswer:"
          end
        end

      compiled = base.dup
      compiled.gsub!(/{{\s*context\s*}}/i, context_text)
      compiled.gsub!(/{{\s*query\s*}}/i,   query)
      unless base.match?(/{{\s*context\s*}}/i) || base.match?(/{{\s*query\s*}}/i)
        compiled << "\n\nContext:\n#{context_text}\n\nQuery: #{query}\n\nAnswer:"
      end

      {
        formatted_prompt: compiled,
        token_count: (compiled.length / 4.0).ceil,
        context_used: context_parts.length,
        truncated: context_parts.length < sorted_context.length,
        prompt_metadata: (input['prompt_metadata'] || {}).merge(
          template: template_key,
          using_template_content: template_content.strip.length.positive?
        )
      }
    end,

    validate_response: lambda do |input, _connection|
      response = (input['response_text'] || '').to_s
      query    = (input['original_query'] || '').to_s
      rules    = Array(input['validation_rules'] || [])
      min_confidence = (input['min_confidence'] || 0.7).to_f

      issues = []
      confidence = 1.0

      if response.strip.empty?
        issues << 'Response is empty'
        confidence -= 0.5
      elsif response.length < 10
        issues << 'Response is too short'
        confidence -= 0.3
      end

      query_words = query.downcase.split(/\W+/).reject(&:empty?)
      response_words = response.downcase.split(/\W+/).reject(&:empty?)
      overlap = query_words.empty? ? 0.0 : ((query_words & response_words).length.to_f / query_words.length)

      if overlap < 0.1
        issues << 'Response may not address the query'
        confidence -= 0.4
      end

      if response.include?('...') || response.downcase.include?('incomplete')
        issues << 'Response appears incomplete'
        confidence -= 0.2
      end

      rules.each do |rule|
        case rule['rule_type']
        when 'contains'
          unless response.include?(rule['rule_value'].to_s)
            issues << "Response does not contain required text: #{rule['rule_value']}"
            confidence -= 0.3
          end
        when 'not_contains'
          if response.include?(rule['rule_value'].to_s)
            issues << "Response contains prohibited text: #{rule['rule_value']}"
            confidence -= 0.3
          end
        end
      end

      confidence = [[confidence, 0.0].max, 1.0].min

      {
        is_valid: confidence >= min_confidence,
        confidence_score: confidence.round(2),
        validation_results: { query_overlap: overlap.round(2), response_length: response.length, word_count: response_words.length },
        issues_found: issues,
        requires_human_review: confidence < 0.5,
        suggested_improvements: issues.empty? ? [] : ['Review and improve response quality']
      }
    end,

    extract_metadata: lambda do |input|
      content = input['document_content'].to_s
      file_path = input['file_path'].to_s
      extract_entities = input.key?('extract_entities') ? !!input['extract_entities'] : true
      generate_summary = input.key?('generate_summary') ? !!input['generate_summary'] : true

      start_time = Time.now

      word_count = content.split(/\s+/).reject(&:empty?).length
      char_count = content.length
      estimated_tokens = (content.length / 4.0).ceil

      language = content.match?(/[àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ]/i) ? 'non-english' : 'english'
      summary = generate_summary ? (content[0, 200].to_s + (content.length > 200 ? '...' : '')) : ''

      key_topics = []
      if extract_entities
        common = %w[the a an and or but in on at to for of with by from is are was were be been being this that these those there here then than into out over under after before about as it its it's their them they our we you your he she his her him not will would can could should may might must also just more most other some such]
        words = content.downcase.scan(/[a-z0-9\-]+/).reject { |w| w.length < 4 || common.include?(w) }
        freq = words.each_with_object(Hash.new(0)) { |w, h| h[w] += 1 }
        key_topics = freq.sort_by { |_, c| -c }.first(5).map(&:first)
      end

      file_hash = Digest::SHA256.hexdigest(content)
      document_id = Digest::SHA1.hexdigest("#{file_path}|#{file_hash}")

      {
        document_id: document_id,
        file_hash: file_hash,
        word_count: word_count,
        character_count: char_count,
        estimated_tokens: estimated_tokens,
        language: language,
        summary: summary,
        key_topics: key_topics,
        entities: { people: [], organizations: [], locations: [] },
        created_at: Time.now.iso8601,
        processing_time_ms: ((Time.now - start_time) * 1000).round
      }
    end,

    detect_changes: lambda do |input|
      current_hash     = input['current_hash']
      current_content  = input['current_content']
      previous_hash    = input['previous_hash']
      previous_content = input['previous_content']
      check_type       = (input['check_type'] || 'hash').to_s

      if check_type == 'smart' && current_content && previous_content
        diff = call(:util_diff_lines, current_content.to_s, previous_content.to_s)

        tokens_cur  = current_content.to_s.split(/\s+/)
        tokens_prev = previous_content.to_s.split(/\s+/)
        union = (tokens_cur | tokens_prev).length
        intersection = (tokens_cur & tokens_prev).length
        smart_change = union.zero? ? 0.0 : ((1.0 - intersection.to_f / union) * 100).round(2)

        changed = smart_change > 0.0 || diff[:added].any? || diff[:removed].any? || diff[:modified_sections].any?

        return {
          has_changed: changed,
          change_type: changed ? 'smart_changed' : 'none',
          change_percentage: smart_change,
          added_content: diff[:added],
          removed_content: diff[:removed],
          modified_sections: diff[:modified_sections],
          requires_reindexing: changed
        }
      end

      has_changed = current_hash != previous_hash
      change_type = 'none'
      change_percentage = 0.0
      added = []
      removed = []
      modified_sections = []

      if has_changed
        change_type = 'hash_changed'

        if check_type == 'content' && current_content && previous_content
          diff = call(:util_diff_lines, current_content.to_s, previous_content.to_s)
          added = diff[:added]
          removed = diff[:removed]
          modified_sections = diff[:modified_sections]
          change_percentage = diff[:line_change_percentage]
          change_type = 'content_changed'
        end
      end

      {
        has_changed: has_changed,
        change_type: change_type,
        change_percentage: change_percentage,
        added_content: added,
        removed_content: removed,
        modified_sections: modified_sections,
        requires_reindexing: has_changed
      }
    end,

    compute_metrics: lambda do |input|
      data_points = Array(input['data_points'] || [])
      values = data_points.map { |dp| dp['value'].to_f }.sort

      return {
        average: 0, median: 0, min: 0, max: 0,
        std_deviation: 0, percentile_95: 0, percentile_99: 0,
        total_count: 0, trend: 'stable', anomalies_detected: []
      } if values.empty?

      avg = values.sum / values.length.to_f
      median = values.length.odd? ? values[values.length / 2] :
               (values[values.length / 2 - 1] + values[values.length / 2]) / 2.0
      min_v = values.first
      max_v = values.last

      variance = values.map { |v| (v - avg)**2 }.sum / values.length
      std_dev = Math.sqrt(variance)

      pct = lambda do |arr, p|
        return 0 if arr.empty?
        r = (p/100.0) * (arr.length - 1)
        lo = r.floor
        hi = r.ceil
        lo == hi ? arr[lo] : arr[lo] + (r - lo) * (arr[hi] - arr[lo])
      end
      p95 = pct.call(values, 95)
      p99 = pct.call(values, 99)

      half = values.length / 2
      first_half_avg = half.zero? ? avg : values[0...half].sum / half.to_f
      second_half_avg = (values.length - half).zero? ? avg : values[half..-1].sum / (values.length - half).to_f
      trend =
        if second_half_avg > first_half_avg * 1.1 then 'increasing'
        elsif second_half_avg < first_half_avg * 0.9 then 'decreasing'
        else 'stable'
        end

      anomalies = data_points.select { |dp| (dp['value'].to_f - avg).abs > 2 * std_dev }
                             .map { |dp| { timestamp: dp['timestamp'], value: dp['value'] } }

      {
        average: avg.round(2),
        median: median.round(2),
        min: min_v,
        max: max_v,
        std_deviation: std_dev.round(2),
        percentile_95: p95.round(2),
        percentile_99: p99.round(2),
        total_count: values.length,
        trend: trend,
        anomalies_detected: anomalies
      }
    end,

    calculate_optimal_batch: lambda do |input|
      total_items = (input['total_items'] || 0).to_i
      history = Array(input['processing_history'] || [])
      target = (input['optimization_target'] || 'throughput').to_s
      max_batch = (input['max_batch_size'] || 100).to_i
      min_batch = (input['min_batch_size'] || 10).to_i

      if history.empty?
        optimal = [[(total_items / 10.0).ceil, max_batch].min, min_batch].max
        return {
          optimal_batch_size: optimal,
          estimated_batches: (optimal.zero? ? 0 : (total_items.to_f / optimal).ceil),
          estimated_processing_time: 0.0,
          throughput_estimate: 0.0,
          confidence_score: 0.5,
          recommendation_reason: 'No history available, using default calculation'
        }
      end

      optimal =
        case target
        when 'throughput'
          best = history.max_by { |h| h['batch_size'].to_f / [h['processing_time'].to_f, 0.0001].max }
          best['batch_size'].to_i
        when 'latency'
          best = history.min_by { |h| h['processing_time'].to_f / [h['batch_size'].to_f, 1].max }
          best['batch_size'].to_i
        when 'cost'
          best = history.min_by { |h| (h['memory_usage'].to_f * 0.7) - (h['batch_size'].to_f / [h['processing_time'].to_f, 0.0001].max) * 0.3 }
          best['batch_size'].to_i
        when 'accuracy'
          best = history.max_by { |h| (h['success_rate'].to_f * 1000) + (h['batch_size'].to_f / [h['processing_time'].to_f, 0.0001].max) }
          best['batch_size'].to_i
        else
          (history.sum { |h| h['batch_size'].to_i } / [history.length, 1].max)
        end

      optimal = [[optimal, max_batch].min, min_batch].max
      estimated_batches = (optimal.zero? ? 0 : (total_items.to_f / optimal).ceil)
      avg_time = history.sum { |h| h['processing_time'].to_f } / [history.length, 1].max
      estimated_time = avg_time * estimated_batches
      throughput = estimated_time.zero? ? 0.0 : (total_items.to_f / estimated_time)

      {
        optimal_batch_size: optimal,
        estimated_batches: estimated_batches,
        estimated_processing_time: estimated_time.round(2),
        throughput_estimate: throughput.round(2),
        confidence_score: 0.8,
        recommendation_reason: 'Based on historical performance data'
      }
    end,

    # ---------- Helpers ----------

    util_last_boundary_end: lambda do |segment, regex|
      matches = segment.to_enum(:scan, regex).map { Regexp.last_match }
      return nil if matches.empty?
      matches.last.end(0)
    end,

    util_coerce_numeric_vector: lambda do |arr|
      Array(arr).map do |x|
        begin
          Float(x)
        rescue
          error 'Vectors must contain only numerics.'
        end
      end
    end,

    util_diff_lines: lambda do |current_content, previous_content|
      cur = current_content.to_s.split("\n")
      prev = previous_content.to_s.split("\n")
      i = 0
      j = 0
      window = 20
      added = []
      removed = []
      modified_sections = []

      while i < cur.length && j < prev.length
        if cur[i] == prev[j]
          i += 1
          j += 1
          next
        end

        idx_in_cur = ((i + 1)..[i + window, cur.length - 1].min).find { |k| cur[k] == prev[j] }
        idx_in_prev = ((j + 1)..[j + window, prev.length - 1].min).find { |k| prev[k] == cur[i] }

        if idx_in_cur
          block = cur[i...idx_in_cur]
          added.concat(block)
          modified_sections << { type: 'added', current_range: [i, idx_in_cur - 1], previous_range: [j - 1, j - 1], current_lines: block }
          i = idx_in_cur
        elsif idx_in_prev
          block = prev[j...idx_in_prev]
          removed.concat(block)
          modified_sections << { type: 'removed', current_range: [i - 1, i - 1], previous_range: [j, idx_in_prev - 1], previous_lines: block }
          j = idx_in_prev
        else
          modified_sections << { type: 'modified', current_range: [i, i], previous_range: [j, j], current_lines: [cur[i]], previous_lines: [prev[j]] }
          added << cur[i]
          removed << prev[j]
          i += 1
          j += 1
        end
      end

      if i < cur.length
        block = cur[i..-1]
        added.concat(block)
        modified_sections << { type: 'added', current_range: [i, cur.length - 1], previous_range: [j - 1, j - 1], current_lines: block }
      elsif j < prev.length
        block = prev[j..-1]
        removed.concat(block)
        modified_sections << { type: 'removed', current_range: [i - 1, i - 1], previous_range: [j, prev.length - 1], previous_lines: block }
      end

      total_lines = [cur.length, prev.length].max
      line_change_percentage = total_lines.zero? ? 0.0 : (((added.length + removed.length).to_f / total_lines) * 100).round(2)

      { added: added, removed: removed, modified_sections: modified_sections, line_change_percentage: line_change_percentage }
    end,

    # ---------- Project resolution helpers ----------
    get_recipe_details: lambda do |connection, recipe_id|
      path = "/api/recipes/#{recipe_id}"
      call(:execute_with_retry, connection, -> { get(path) })
    rescue RestClient::ExceptionWithResponse => e
      hdrs = e.response&.headers || {}
      cid  = hdrs["x-correlation-id"] || hdrs[:x_correlation_id]
      error("Failed to load recipe #{recipe_id} (#{e.http_code}). cid=#{cid} body=#{e.response&.body}")
    end,

    folders_index_cached: lambda do |connection|
      return @__folders_by_id if defined?(@__folders_by_id) && @__folders_by_id.present?
      page = 1
      acc  = {}
      loop do
        resp = call(:execute_with_retry, connection, -> { get('/api/folders').params(page: page, per_page: 100) })
        rows = resp.is_a?(Array) ? resp : (resp["data"] || [])
        rows.each { |f| acc[f["id"]] = f }
        break if rows.size < 100
        page += 1
      end
      @__folders_by_id = acc
    end,

    projects_index_cached: lambda do |connection|
      return @__projects_by_id if defined?(@__projects_by_id) && @__projects_by_id.present?
      page = 1
      acc  = {}
      loop do
        resp = call(:execute_with_retry, connection, -> { get('/api/projects').params(page: page, per_page: 100) })
        rows = resp.is_a?(Array) ? resp : (resp["data"] || [])
        rows.each { |p| acc[p["id"]] = p }
        break if rows.size < 100
        page += 1
      end
      @__projects_by_id = acc
    end,

    resolve_project_from_recipe: lambda do |connection, recipe_id|
      rec = call(:get_recipe_details, connection, recipe_id)
      f_id = rec["folder_id"]
      error("Recipe #{recipe_id} did not include folder_id") if f_id.blank?

      folders = call(:folders_index_cached, connection)
      folder  = folders[f_id]
      error("Folder #{f_id} not found or not visible to this token") if folder.blank?

      result = {
        recipe_id: recipe_id,
        folder_id: f_id,
        folder_name: folder["name"],
        is_project_folder: !!folder["is_project"],
        project_id: nil,
        project_name: nil,
        project_folder_id: nil,
        environment_host: connection["developer_api_host"]
      }

      if folder["is_project"]
        projects = call(:projects_index_cached, connection)
        proj = projects.values.find { |p| p["folder_id"] == f_id }
        result[:project_id]        = proj&.dig("id")
        result[:project_name]      = proj&.dig("name")
        result[:project_folder_id] = f_id
      else
        result[:project_id] = folder["project_id"]
        if result[:project_id].present?
          projects = call(:projects_index_cached, connection)
          proj = projects[result[:project_id]]
          result[:project_name]      = proj&.dig("name")
          result[:project_folder_id] = proj&.dig("folder_id")
        end
      end
      result
    end,

    # ---------- HTTP helpers & endpoints ----------
    devapi_base: lambda do |connection|
      host = (connection['developer_api_host'].presence || 'app.eu').to_s
      "https://#{host}.workato.com"
    end,

    dt_records_base: lambda do |_connection|
      "https://data-tables.workato.com"
    end,

    execute_with_retry: lambda do |connection, operation = nil, &block|
      retries     = 0
      max_retries = 3

      begin
        op = block || operation
        error('Internal error: execute_with_retry called without an operation') unless op
        op.call
      rescue RestClient::ExceptionWithResponse => e
        code = e.http_code.to_i
        if ([429] + (500..599).to_a).include?(code) && retries < max_retries
          hdrs  = e.response&.headers || {}
          ra    = hdrs["Retry-After"] || hdrs[:retry_after]
          delay = if ra.to_s =~ /^\d+$/ then ra.to_i
                  elsif ra.present?
                    begin
                      [(Time.httpdate(ra) - Time.now).ceil, 1].max
                    rescue
                      60
                    end
                  else
                    2 ** retries
                  end
          sleep([delay, 30].min + rand(0..3))
          retries += 1
          retry
        end
        raise
      rescue RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout => e
        if retries < max_retries
          sleep((2 ** retries) + rand(0..2))
          retries += 1
          retry
        end
        raise e
      end
    end,

    validate_table_id: lambda do |table_id|
      error("Table ID is required") if table_id.blank?
      uuid = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
      error("Table ID must be a UUID") unless table_id.to_s.match?(uuid)
    end,

    # Return [ [name, name], ... ] for picklists
    dt_table_columns: lambda do |connection, table_id|
      table = call(:devapi_get_table, connection, table_id)
      schema = table['schema'] || table.dig('data', 'schema') || []
      cols = Array(schema).map { |c| n = (c['name'] || '').to_s; [n, n] }.reject { |a| a[0].empty? }
      cols.presence || [[ "No columns found", nil ]]
    end,

    pick_tables: lambda do |connection|
      # Use relative path against base_uri; pass params hash per docs
      resp = call(:execute_with_retry, connection, lambda { get('/api/data_tables').params(page: 1, per_page: 100) })
      arr = resp.is_a?(Array) ? resp : (resp['data'] || [])
      arr.map { |t| [t['name'] || t['id'].to_s, t['id']] }
    rescue RestClient::ExceptionWithResponse => e
      hdrs = e.response&.headers || {}
      cid  = hdrs["x-correlation-id"] || hdrs[:x_correlation_id]
      msg  = e.response&.body || e.message
      hint = "Check API token and Developer API host (#{connection['developer_api_host'] || 'www'})."
      error("Failed to load tables (#{e.http_code}) cid=#{cid} #{hint} #{msg}")
    end,

    devapi_get_table: lambda do |connection, table_id|
      call(:execute_with_retry, connection, lambda { get("/api/data_tables/#{table_id}") })
    end,

    validate_rules_schema!: lambda do |_connection, schema, required_names, mapping = {}|
      names = Array(schema).map { |c| (c['name'] || '').to_s }
      expected = required_names.map { |n| (mapping[n] || n).to_s }
      missing = expected.reject { |n| names.include?(n) }
      error("Rules table missing required fields: #{missing.join(', ')}") unless missing.empty?
    end,

    schema_field_id_map: lambda do |_connection, schema|
      Hash[Array(schema).map { |c| [(c['name'] || '').to_s, (c['field_id'] || c['id'] || '').to_s] }]
    end,

    # Pull and normalize rules with optional column mapping
    dt_query_rules_all: lambda do |connection, table_id, required_fields, max_rules, schema = nil, mapping = {}|
      base = call(:dt_records_base, connection)
      url  = "#{base}/api/v1/tables/#{table_id}/query"

      schema ||= begin
        table = call(:devapi_get_table, connection, table_id)
        table['schema'] || table.dig('data', 'schema') || []
      end

      name_to_uuid = call(:schema_field_id_map, connection, schema)

      # Apply mapping (or defaults) consistently
      col = ->(key) { (mapping[key] || key).to_s }
      select_fields = required_fields.map { |k| col.call(k) } + ['$record_id', '$created_at', '$updated_at']
      active_col = col.call('active')
      prio_col   = col.call('priority')

      where = { active_col => { '$eq' => true } }
      order = { by: prio_col, order: 'asc', case_sensitive: false }

      records = []
      cont = nil
      loop do
        body = { select: select_fields.uniq, where: where, order: order, limit: 200, continuation_token: cont }.compact
        resp = call(:execute_with_retry, connection, lambda { post(url).payload(body) })
        recs = resp['records'] || resp['data'] || []
        records.concat(recs)
        cont = resp['continuation_token']
        break if cont.blank? || records.length >= max_rules
      end

      # Decode each record to a name->value row using schema
      decoded = records.map do |r|
        doc = r['document'] || []
        row = {}
        doc.each do |cell|
          fid  = (cell['field_id'] || '').to_s
          name = name_to_uuid.key(fid) || cell['name']
          row[name.to_s] = cell['value']
        end
        row['$record_id']  = r['record_id']  if r['record_id']
        row['$created_at'] = r['created_at'] if r['created_at']
        row['$updated_at'] = r['updated_at'] if r['updated_at']
        row
      end

      # Normalize to connector’s canonical keys, respecting mapping
      normalized = decoded.map do |row|
        {
          'rule_id'      => (row[col.call('rule_id')]      || '').to_s,
          'rule_type'    => (row[col.call('rule_type')]    || '').to_s.downcase,
          'rule_pattern' => (row[col.call('rule_pattern')] || '').to_s,
          'action'       => (row[col.call('action')]       || '').to_s,
          'priority'     => call(:coerce_int, connection, row[col.call('priority')], 1000),
          'active'       => call(:coerce_bool, connection, row[col.call('active')]),
          'created_at'   => row['$created_at']
        }
      end

      normalized
        .select { |r| r['active'] == true }
        .sort_by { |r| r['priority'] }
        .first(max_rules)
    end,

    coerce_bool: lambda do |_connection, v|
      return true  if v == true || v.to_s.strip.downcase == 'true' || v.to_s == '1'
      return false if v == false || v.to_s.strip.downcase == 'false' || v.to_s == '0'
      !!v
    end,

    coerce_int: lambda do |_connection, v, default|
      Integer(v)
    rescue
      default.to_i
    end,

    safe_regex: lambda do |_connection, pattern|
      p = pattern.to_s.strip
      max_len = 512
      p = p[0, max_len]
      if p.start_with?('/') && p.end_with?('/') && p.length >= 2
        Regexp.new(p[1..-2], Regexp::IGNORECASE)
      elsif p.start_with?('re:')
        Regexp.new(p.sub(/^re:/i, ''), Regexp::IGNORECASE)
      else
        Regexp.new(Regexp.escape(p), Regexp::IGNORECASE)
      end
    rescue RegexpError => e
      error("Invalid regex pattern in rules: #{e.message}")
    end,

    normalize_email: lambda do |_connection, email|
      {
        from_email: (email['from_email'] || '').to_s,
        from_name:  (email['from_name']  || '').to_s,
        subject:    (email['subject']    || '').to_s,
        body:       (email['body']       || '').to_s,
        headers:    email['headers'].is_a?(Hash) ? email['headers'] : {},
        message_id: (email['message_id'] || '').to_s
      }
    end,

    evaluate_standard_patterns: lambda do |_connection, email|
      from = "#{email[:from_name]} <#{email[:from_email]}>"
      subj = email[:subject].to_s
      body = email[:body].to_s

      sender_rx = [ /\bno[-_.]?reply\b/i, /\bdo[-_.]?not[-_.]?reply\b/i, /\bdonotreply\b/i, /\bnewsletter\b/i, /\bmailer\b/i, /\bautomated\b/i ]
      subject_rx = [ /\border\s*(no\.|#)?\s*\d+/i, /\b(order|purchase)\s+confirmation\b/i, /\bconfirmation\b/i, /\breceipt\b/i, /\binvoice\b/i, /\b(password\s*reset|verification\s*code|two[-\s]?factor)\b/i ]
      body_rx = [ /\bunsubscribe\b/i, /\bmanage (your )?preferences\b/i, /\bautomated (message|email)\b/i, /\bdo not reply\b/i, /\bview (this|in) browser\b/i ]

      matches = []
      flags_sender  = sender_rx.select { |rx| from.match?(rx) }.map(&:source)
      flags_subject = subject_rx.select { |rx| subj.match?(rx) }.map(&:source)
      flags_body    = body_rx.select  { |rx| body.match?(rx) }.map(&:source)

      flags_sender.each do |src|
        m = from.match(Regexp.new(src, Regexp::IGNORECASE))
        matches << { rule_id: "std:sender:#{src}", rule_type: "sender", rule_pattern: src, action: nil, priority: 1000, field_matched: "sender", sample: m&.to_s }
      end
      flags_subject.each do |src|
        m = subj.match(Regexp.new(src, Regexp::IGNORECASE))
        matches << { rule_id: "std:subject:#{src}", rule_type: "subject", rule_pattern: src, action: nil, priority: 1000, field_matched: "subject", sample: m&.to_s }
      end
      flags_body.each do |src|
        m = body.match(Regexp.new(src, Regexp::IGNORECASE))
        matches << { rule_id: "std:body:#{src}", rule_type: "body", rule_pattern: src, action: nil, priority: 1000, field_matched: "body", sample: m&.to_s }
      end

      { matches: matches, sender_flags: flags_sender, subject_flags: flags_subject, body_flags: flags_body }
    end,

    apply_rules_to_email: lambda do |connection, email, rules, stop_on_first|
      from    = "#{email[:from_name]} <#{email[:from_email]}>"
      subject = email[:subject].to_s
      body    = email[:body].to_s

      out       = []
      evaluated = 0

      rules.each do |r|
        rt      = r['rule_type']
        pattern = r['rule_pattern']
        next if rt.blank? || pattern.blank?

        rx = call(:safe_regex, connection, pattern)

        field = case rt
                when 'sender'  then 'sender'
                when 'subject' then 'subject'
                when 'body'    then 'body'
                else next
                end

        haystack = case field
                  when 'sender'  then from
                  when 'subject' then subject
                  when 'body'    then body
                  end

        evaluated += 1
        m = haystack.match(rx)
        if m
          out << { rule_id: r['rule_id'], rule_type: rt, rule_pattern: pattern, action: r['action'], priority: r['priority'], field_matched: field, sample: m.to_s }
          break if stop_on_first
        end
      end

      { matches: out.sort_by { |h| [h[:priority] || 1000, h[:rule_id].to_s] }, evaluated_count: evaluated }
    end,

    # Orchestrate logic with mapping support + unconditional table-id validation
    evaluate_email_by_rules_exec: lambda do |connection, input, config|
      email = call(:normalize_email, connection, input['email'] || {})

      source   = (config && config['rules_source'] || input['rules_source'] || 'standard').to_s
      table_id = (config && config['custom_rules_table_id'] || input['custom_rules_table_id']).to_s.presence

      stop_on      = input.key?('stop_on_first_match') ? !!input['stop_on_first_match'] : true
      fallback_std = input.key?('fallback_to_standard') ? !!input['fallback_to_standard'] : true
      max_rules    = (input['max_rules_to_apply'] || 500).to_i.clamp(1, 10_000)

      selected_action = nil
      used_source     = 'none'
      matches         = []
      evaluated_count = 0

      std = call(:evaluate_standard_patterns, connection, email)

      if source == 'custom'
        error('api_token is required in connector connection to read custom rules from Data Tables') unless connection['api_token'].present?
        call(:validate_table_id, table_id) # <- unconditional validation

        # Load schema and validate required set with mapping
        table_info = call(:devapi_get_table, connection, table_id)
        schema     = table_info['schema'] || table_info.dig('data', 'schema') || []

        required   = %w[rule_id rule_type rule_pattern action priority active]

        # Build optional column mapping from config
        mapping = {}
        if config['enable_column_mapping']
          %w[col_rule_id col_rule_type col_rule_pattern col_action col_priority col_active].each do |ck|
            v = (config[ck] || '').to_s.strip
            next if v.empty?
            key = ck.sub(/^col_/, '')
            mapping[key] = v
          end
        end

        call(:validate_rules_schema!, connection, schema, required, mapping)

        rules     = call(:dt_query_rules_all, connection, table_id, required, max_rules, schema, mapping)
        applied   = call(:apply_rules_to_email, connection, email, rules, stop_on)
        matches   = applied[:matches]
        evaluated_count = applied[:evaluated_count]

        if matches.any?
          used_source     = 'custom'
          selected_action = matches.first[:action]
        elsif fallback_std && std[:matches].any?
          used_source = 'standard'
          matches     = std[:matches]
        end
      else
        matches     = std[:matches]
        used_source = matches.any? ? 'standard' : 'none'
      end

      {
        pattern_match: matches.any?,
        rule_source:   used_source,
        selected_action: selected_action,
        top_match:     matches.first,
        matches:       matches,
        standard_signals: {
          sender_flags:  std[:sender_flags],
          subject_flags: std[:subject_flags],
          body_flags:    std[:body_flags]
        },
        debug: {
          evaluated_rules_count: evaluated_count,
          schema_validated:      (source == 'custom'),
          errors: []
        }
      }
    end,

    # ----- Templates (Data Tables) -----
    pick_templates_from_table: lambda do |connection, config|
      error('api_token is required in connector connection to read templates from Data Tables') unless connection['api_token'].present?

      table_id  = (config['templates_table_id'] || '').to_s.strip
      call(:validate_table_id, table_id)

      display  = (config['template_display_field']  || 'name').to_s
      valuef   = (config['template_value_field']    || '').to_s
      contentf = (config['template_content_field']  || 'content').to_s

      table_info = call(:devapi_get_table, connection, table_id)
      schema     = table_info['schema'] || table_info.dig('data', 'schema') || []
      names      = Array(schema).map { |c| (c['name'] || '').to_s }
      missing    = [display, contentf].reject { |n| names.include?(n) }
      error("Templates table missing required fields: #{missing.join(', ')}") unless missing.empty?

      base   = call(:dt_records_base, connection)
      url    = "#{base}/api/v1/tables/#{table_id}/query"
      select = [display, contentf]
      select << valuef if valuef.present?
      select << 'active' if names.include?('active')
      where  = names.include?('active') ? { 'active' => { '$eq' => true } } : nil
      order  = { by: display, order: 'asc', case_sensitive: false }

      records = []
      cont = nil
      loop do
        body = { select: select.uniq, where: where, order: order, limit: 200, continuation_token: cont }.compact
        resp = call(:execute_with_retry, connection, lambda { post(url).payload(body) })
        recs = resp['records'] || resp['data'] || []
        records.concat(recs)
        cont = resp['continuation_token']
        break if cont.blank? || records.length >= 2000
      end

      name_to_uuid = call(:schema_field_id_map, connection, schema)
      rows = records.map do |r|
        doc = r['document'] || []
        row = {}
        doc.each do |cell|
          fid  = (cell['field_id'] || '').to_s
          name = name_to_uuid.key(fid) || cell['name']
          row[name.to_s] = cell['value']
        end
        row['$record_id'] = r['record_id'] if r['record_id']
        row
      end

      opts = rows.map do |row|
        disp = (row[display] || row['$record_id']).to_s
        val  = valuef.present? ? row[valuef].to_s : row['$record_id'].to_s
        [disp, val]
      end

      opts.empty? ? [[ "No templates found in selected table", nil ]] : opts
    rescue RestClient::ExceptionWithResponse => e
      hdrs = e.response&.headers || {}
      cid  = hdrs["x-correlation-id"] || hdrs[:x_correlation_id]
      msg  = e.response&.body || e.message
      error("Failed to load templates (#{e.http_code}) cid=#{cid} #{msg}")
    end,

    resolve_template_selection: lambda do |connection, config, selected_value|
      table_id   = (config['templates_table_id'] || '').to_s
      valuef     = (config['template_value_field']   || '').to_s
      contentf   = (config['template_content_field'] || 'content').to_s
      displayf   = (config['template_display_field'] || 'name').to_s

      table_info = call(:devapi_get_table, connection, table_id)
      schema     = table_info['schema'] || table_info.dig('data', 'schema') || []

      base = call(:dt_records_base, connection)

      if valuef.present?
        body = { select: [valuef, displayf, contentf, '$record_id'].uniq, where: { valuef => { '$eq' => selected_value } }, limit: 1 }
        resp = call(:execute_with_retry, connection, lambda { post("#{base}/api/v1/tables/#{table_id}/query").payload(body) })
        rec  = (resp['records'] || resp['data'] || [])[0]
        return nil unless rec
        row  = call(:dt_decode_record_doc, connection, schema, rec)
        { 'value' => selected_value, 'display' => row[displayf], 'content' => row[contentf], 'record_id' => row['$record_id'] }
      else
        rec = call(:execute_with_retry, connection, lambda { get("#{base}/api/v1/tables/#{table_id}/records/#{selected_value}") })
        row = call(:dt_decode_record_doc, connection, schema, rec)
        { 'value' => selected_value, 'display' => row[displayf], 'content' => row[contentf], 'record_id' => selected_value }
      end
    end,

    dt_decode_record_doc: lambda do |connection, schema, record|
      name_to_uuid = call(:schema_field_id_map, connection, schema)
      doc = record['document'] || []
      row = {}
      doc.each do |cell|
        fid  = (cell['field_id'] || '').to_s
        name = name_to_uuid.key(fid) || cell['name']
        row[name.to_s] = cell['value']
      end
      row['$record_id']  = record['record_id']  if record['record_id']
      row['$created_at'] = record['created_at'] if record['created_at']
      row['$updated_at'] = record['updated_at'] if record['updated_at']
      row
    end
  },

  # ==========================================
  # OBJECT DEFINITIONS (Schemas)
  # ==========================================
  object_definitions: {
    chunk_object: {
      fields: lambda do
        [
          { name: "chunk_id", type: "string" },
          { name: "chunk_index", type: "integer" },
          { name: "text", type: "string" },
          { name: "token_count", type: "integer" },
          { name: "start_char", type: "integer" },
          { name: "end_char", type: "integer" },
          { name: "metadata", type: "object" }
        ]
      end
    },

    embedding_object: {
      fields: lambda do
        [
          { name: "id", type: "string", sticky: true },
          { name: "vector", type: "array", of: "number", sticky: true },
          { name: "metadata", type: "object", sticky: true }
        ]
      end
    },

    metric_datapoint: {
      fields: lambda do
        [
          { name: "timestamp", type: "timestamp", sticky: true },
          { name: "value", type: "number", sticky: true },
          { name: "metadata", type: "object", sticky: true }
        ]
      end
    },

    email_envelope: {
      fields: lambda do
        [
          { name: "from_email", label: "From email", sticky: true },
          { name: "from_name",  label: "From name", sticky: true },
          { name: "subject",    label: "Subject", sticky: true },
          { name: "body",       label: "Body", control_type: "text-area", sticky: true },
          { name: "headers",    label: "Headers", type: "object", sticky: true },
          { name: "message_id", label: "Message ID", sticky: true },
          { name: "to",         label: "To", type: "array", of: "string", sticky: true },
          { name: "cc",         label: "Cc", type: "array", of: "string", sticky: true }
        ]
      end
    },

    rules_row: {
      fields: lambda do
        [
          { name: "rule_id" }, { name: "rule_type" }, { name: "rule_pattern" },
          { name: "action" }, { name: "priority", type: "integer" }, { name: "field_matched" },
          { name: "sample" }
        ]
      end
    },

    standard_signals: {
      fields: lambda do
        [
          { name: "sender_flags",  type: "array", of: "string" },
          { name: "subject_flags", type: "array", of: "string" },
          { name: "body_flags",    type: "array", of: "string" }
        ]
      end
    },

    validation_rule: {
      fields: lambda do
        [
          { name: "rule_type", sticky: true },
          { name: "rule_value", sticky: true }
        ]
      end
    },

    context_document: {
      fields: lambda do
        [
          { name: "content", type: "string", sticky: true },
          { name: "relevance_score", type: "number", sticky: true },
          { name: "source", type: "string", sticky: true },
          { name: "metadata", type: "object", sticky: true }
        ]
      end
    },

    diff_section: {
      fields: lambda do
        [
          { name: "type" },
          { name: "current_range", type: "array", of: "integer" },
          { name: "previous_range", type: "array", of: "integer" },
          { name: "current_lines", type: "array", of: "string" },
          { name: "previous_lines", type: "array", of: "string" }
        ]
      end
    },

    anomaly: {
      fields: lambda do
        [
          { name: "timestamp", type: "timestamp" },
          { name: "value", type: "number" }
        ]
      end
    },

    vertex_datapoint: {
      fields: lambda do
        [
          { name: "datapoint_id", type: "string" },
          { name: "feature_vector", type: "array", of: "number" },
          { name: "restricts", type: "object" }
        ]
      end
    },

  vertex_datapoint_upsert: {
    fields: lambda do
      [
        { name: "datapointId", type: "string" },
        { name: "featureVector", type: "array", of: "number" },
        { name: "restricts", type: "array", of: "object", properties: [
          { name: "namespace" },
          { name: "allowList", type: "array", of: "string" },
          { name: "denyList",  type: "array", of: "string" }
        ]},
        { name: "numericRestricts", type: "array", of: "object", properties: [
          { name: "namespace" },
          { name: "op" }, # EQUAL, LESS, GREATER, etc.
          { name: "valueInt",    type: "integer" },
          { name: "valueFloat",  type: "number"  },
          { name: "valueDouble", type: "number"  }
        ]}
      ]
    end
  },

    vertex_batch: {
      fields: lambda do |connection, _config, object_definitions|
        [
          { name: "batch_id", type: "string" },
          { name: "batch_number", type: "integer" },
          { name: "datapoints", type: "array", of: "object", properties: object_definitions["vertex_datapoint"] },
          { name: "size", type: "integer" }
        ]
      end
    },

    chunking_config: {
      fields: lambda do
        [
          { name: "chunk_size", label: "Chunk size (tokens)", type: "integer", default: 1000, convert_input: "integer_conversion", sticky: true, hint: "Maximum tokens per chunk" },
          { name: "chunk_overlap", label: "Chunk overlap (tokens)", type: "integer", default: 100, convert_input: "integer_conversion", sticky: true, hint: "Token overlap between chunks" },
          { name: "preserve_sentences", label: "Preserve sentences", type: "boolean", control_type: "checkbox", default: true, convert_input: "boolean_conversion", sticky: true, hint: "Don't break mid‑sentence" },
          { name: "preserve_paragraphs", label: "Preserve paragraphs", type: "boolean", control_type: "checkbox", default: false, convert_input: "boolean_conversion", sticky: true, hint: "Try to keep paragraphs intact" }
        ]
      end
    },

    chunking_result: {
      fields: lambda do |connection, _config, object_definitions|
        [
          { name: "chunks", type: "array", of: "object", properties: object_definitions["chunk_object"] },
          { name: "total_chunks", type: "integer" },
          { name: "total_tokens", type: "integer" }
        ]
      end
    },

    email_cleaning_options: {
      fields: lambda do
        [
          { name: "remove_signatures",  label: "Remove signatures",     type: "boolean", default: true,  control_type: "checkbox", convert_input: "boolean_conversion", sticky: true, group: "Options" },
          { name: "remove_quotes",      label: "Remove quoted text",    type: "boolean", default: true,  control_type: "checkbox", convert_input: "boolean_conversion", sticky: true, group: "Options" },
          { name: "remove_disclaimers", label: "Remove disclaimers",    type: "boolean", default: true,  control_type: "checkbox", convert_input: "boolean_conversion", sticky: true, group: "Options" },
          { name: "normalize_whitespace", label: "Normalize whitespace", type: "boolean", default: true, control_type: "checkbox", convert_input: "boolean_conversion", sticky: true, group: "Options" },
          { name: "extract_urls",       label: "Extract URLs",          type: "boolean", default: false, control_type: "checkbox", convert_input: "boolean_conversion", sticky: true, group: "Options" }
        ]
      end
    },

    email_cleaning_result: {
      fields: lambda do
        [
          { name: "cleaned_text", type: "string" },
          { name: "extracted_query", type: "string" },
          { name: "removed_sections", type: "array", of: "string" },
          { name: "extracted_urls", type: "array", of: "string" },
          { name: "original_length", type: "integer" },
          { name: "cleaned_length", type: "integer" },
          { name: "reduction_percentage", type: "number" }
        ]
      end
    },

    similarity_result: {
      fields: lambda do
        [
          { name: "similarity_score",       type: "number", label: "Similarity score", hint: "0–1 for cosine/euclidean; unbounded for dot product" },
          { name: "similarity_percentage",  type: "number", label: "Similarity percentage", hint: "0–100; only for cosine/euclidean" },
          { name: "is_similar",             type: "boolean", control_type: "checkbox", label: "Is similar", hint: "Whether the vectors meet the threshold" },
          { name: "similarity_type",        type: "string", label: "Similarity type", hint: "cosine, euclidean, or dot_product" },
          { name: "computation_time_ms",    type: "integer", label: "Computation time (ms)" },
          { name: "threshold_used",         type: "number", label: "Threshold used", optional: true },
          { name: "vectors_normalized",     type: "boolean", control_type: "checkbox", label: "Vectors normalized", optional: true }
        ]
      end
    }
  },

  # ==========================================
  # PICK LISTS (Dropdown Options)
  # ==========================================
  pick_lists: {

    environments: lambda do
      [
        ["Development", "dev"],
        ["Staging", "staging"],
        ["Production", "prod"]
      ]
    end,

    similarity_types: lambda do
      [
        ["Cosine similarity", "cosine"],
        ["Euclidean distance", "euclidean"],
        ["Dot product", "dot_product"]
      ]
    end,

    format_types: lambda do
      [
        ["JSON", "json"],
        ["JSONL", "jsonl"],
        ["CSV", "csv"]
      ]
    end,

    prompt_templates: lambda do |connection, config = {}|
      cfg = config || {}
      template_source        = (cfg['template_source'] || cfg[:template_source] || 'builtin').to_s
      templates_table_id     = cfg['templates_table_id'] || cfg[:templates_table_id]
      template_display_field = (cfg['template_display_field'] || cfg[:template_display_field] || 'name').to_s
      template_value_field   = (cfg['template_value_field'] || cfg[:template_value_field]).to_s
      template_content_field = (cfg['template_content_field'] || cfg[:template_content_field] || 'content').to_s

      if template_source == 'custom'
        if connection['api_token'].blank? || templates_table_id.to_s.strip.empty?
          [[ "Configure API token and Templates table in action config", nil ]]
        else
          call(:pick_templates_from_table, connection, {
            'templates_table_id'      => templates_table_id,
            'template_display_field'  => template_display_field,
            'template_value_field'    => template_value_field,
            'template_content_field'  => template_content_field
          })
        end
      else
        [
          ["Standard RAG",      "standard"],
          ["Customer service",  "customer_service"],
          ["Technical support", "technical"],
          ["Sales inquiry",     "sales"]
        ]
      end
    end,

    file_types: lambda do
      [
        ["PDF", "pdf"], ["Word Document", "docx"], ["Text File", "txt"], ["Markdown", "md"], ["HTML", "html"]
      ]
    end,

    check_types: lambda do
      [
        ["Hash only", "hash"],
        ["Content diff", "content"],
        ["Smart diff", "smart"]
      ]
    end,

    metric_types: lambda do
      [
        ["Response time", "response_time"],
        ["Token usage", "token_usage"],
        ["Cache hit rate", "cache_hit"],
        ["Error rate", "error_rate"],
        ["Throughput", "throughput"]
      ]
    end,

    time_periods: lambda do
      [
        ["Minute", "minute"], ["Hour", "hour"], ["Day", "day"], ["Week", "week"]
      ]
    end,

    optimization_targets: lambda do
      [
        ["Throughput", "throughput"], ["Latency", "latency"], ["Cost", "cost"], ["Accuracy", "accuracy"]
      ]
    end,

    devapi_regions: lambda do
      [
        ["US (www.workato.com)", "www"],
        ["EU (app.eu.workato.com)", "app.eu"],
        ["JP (app.jp.workato.com)", "app.jp"],
        ["SG (app.sg.workato.com)", "app.sg"],
        ["AU (app.au.workato.com)", "app.au"],
        ["IL (app.il.workato.com)", "app.il"]
      ]
    end,

    tables: lambda do |connection|
      if connection['api_token'].blank?
        [[ "Please configure API token in connector connection", nil ]]
      else
        call(:pick_tables, connection)
      end
    end,

  table_columns: lambda do |connection, config = {}|
    cfg = config || {}
    if connection['api_token'].blank?
      [[ "Please configure API token in connector connection", nil ]]
    else
      tbl = (cfg.is_a?(Hash) ? (cfg['custom_rules_table_id'] || cfg[:custom_rules_table_id]) : nil).to_s
      if tbl.empty?
        [[ "Select a Data Table above first", nil ]]
      else
        call(:dt_table_columns, connection, tbl)
      end
    end
  end

  }
}
