# Migration Map

## Objective
> Delineate clear separation of conerns for connectors, **RAG Utilities** and **Vertex**.

## Phased Implementation
### Phase 1: RAG Utilities Actions
```ruby
migration_map = {
  # ============================================
  # RAG_UTILS CONNECTOR ACTIONS
  # ============================================
  
  "rag::smart_chunk_text" => {
    status: "keep_as_is",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "none",
    notes: "Core preparation function, no changes needed"
  },
  
  "rag::clean_email_text" => {
    status: "keep_as_is",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "none",
    notes: "Email preparation, stays in prep layer"
  },
  
  "rag::calculate_similarity" => {
    status: "keep_as_is",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "none",
    notes: "Math utility, belongs in prep layer"
  },
  
  "rag::format_embeddings_batch" => {
    status: "enhance",
    new_location: "rag_utils",
    new_name: "prepare_embedding_batch",
    breaking_change: true,
    migration_complexity: "low",
    changes: {
      output: "Match embedding_request contract",
      add_fields: ["batch_id", "task_type"],
      remove_fields: ["format_type", "payload"]
    },
    migration_pattern: "Add batch_id generation internally"
  },
  
  "rag::build_rag_prompt" => {
    status: "enhance",
    new_location: "rag_utils",
    new_name: "build_prompt",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      output: "Add Vertex-ready format option",
      new_modes: ["vertex_format", "raw_format"],
      data_tables: "Keep template loading"
    },
    migration_pattern: "Add 'output_format' parameter"
  },
  
  "rag::validate_llm_response" => {
    status: "enhance",
    new_location: "rag_utils",
    new_name: "validate_ai_response",
    breaking_change: false,
    migration_complexity: "medium",
    changes: {
      input: "Accept Vertex response format",
      add_validation: ["safety_ratings", "finish_reason"],
      output: "Unified validation result"
    },
    migration_pattern: "Auto-detect input format"
  },
  
  "rag::generate_document_metadata" => {
    status: "keep_as_is",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "none"
  },
  
  "rag::check_document_changes" => {
    status: "keep_as_is",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "none"
  },
  
  "rag::calculate_metrics" => {
    status: "keep_as_is",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "none"
  },
  
  "rag::optimize_batch_size" => {
    status: "keep_as_is",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "none"
  },
  
  "rag::evaluate_email_by_rules" => {
    status: "rename",
    new_location: "rag_utils",
    new_name: "classify_by_pattern",
    breaking_change: true,
    migration_complexity: "low",
    changes: {
      clarify_purpose: "Pattern-based classification only",
      output: "Add 'classification_method': 'pattern'"
    },
    migration_pattern: "Simple rename in recipes"
  },
  
  "rag::adapt_chunks_for_vertex" => {
    status: "generalize",
    new_location: "rag_utils",
    new_name: "prepare_chunks_for_vectordb",
    breaking_change: true,
    migration_complexity: "low",
    changes: {
      remove_vendor_specific: "Make vendor-agnostic",
      output: "Generic vector DB format"
    }
  },
  
  "rag::serialize_chunks_to_jsonl" => {
    status: "keep_as_is",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "none"
  },
  
  "rag::to_vertex_datapoints" => {
    status: "generalize",
    new_location: "rag_utils",
    new_name: "format_vector_datapoints",
    breaking_change: true,
    migration_complexity: "medium",
    changes: {
      add_parameter: "target_system",
      support_multiple: ["vertex", "pinecone", "weaviate"]
    }
  },
  
  "rag::resolve_project_context" => {
    status: "keep_as_is",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "none",
    notes: "Workato-specific utility"
  }
}
```

### Phase 2: Vertex Actions

```ruby
vertex_migration = {
  # ============================================
  # VERTEX CONNECTOR ACTIONS
  # ============================================
  
  "vertex::send_messages" => {
    status: "enhance",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      accept_prepared_input: "From RAG contracts",
      remove: "Template building logic"
    }
  },
  
  "vertex::translate_text" => {
    status: "simplify",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      remove: "Text preprocessing",
      expect: "Clean input from RAG_Utils"
    }
  },
  
  "vertex::summarize_text" => {
    status: "simplify",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      remove: "Text preprocessing",
      expect: "Clean input from RAG_Utils"
    }
  },
  
  "vertex::parse_text" => {
    status: "keep_as_is",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "none",
    notes: "Pure AI task, no prep needed"
  },
  
  "vertex::draft_email" => {
    status: "keep_as_is",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "none",
    notes: "Pure generation task"
  },
  
  "vertex::categorize_text" => {
    status: "remove",
    new_location: "deleted",
    replacement: "rag::classify_by_pattern OR vertex::ai_classify",
    breaking_change: true,
    migration_complexity: "high",
    migration_steps: [
      "1. Identify if using rules or AI",
      "2. If rules: migrate to rag::classify_by_pattern",
      "3. If AI: use rag::prepare_text + vertex::ai_classify",
      "4. Update Data Tables integration to RAG_Utils"
    ],
    deprecation_message: "Use RAG_Utils for rule-based or new ai_classify for AI"
  },
  
  "vertex::analyze_text" => {
    status: "simplify",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      expect: "Pre-processed text from RAG"
    }
  },
  
  "vertex::analyze_image" => {
    status: "keep_as_is",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "none",
    notes: "No text preprocessing needed"
  },
  
  "vertex::generate_embedding" => {
    status: "enhance",
    new_location: "vertex",
    new_name: "generate_embeddings",
    breaking_change: true,
    migration_complexity: "medium",
    changes: {
      accept_batch: "Process multiple texts",
      input_format: "Match embedding_request contract",
      output_format: "Match embedding_response contract"
    }
  },
  
  "vertex::find_neighbors" => {
    status: "enhance",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      accept_prepared: "Vector search request contract",
      simplify_input: "Remove inline formatting"
    }
  },
  
  "vertex::get_prediction" => {
    status: "deprecate",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "low",
    notes: "Legacy Text Bison, keep for compatibility only",
    deprecation_message: "Use send_messages with Gemini models"
  }
}
```

### Phase 3: New Actions

```ruby
new_actions = {
  # ============================================
  # NEW ACTIONS IN RAG_UTILS
  # ============================================
  
  "rag::prepare_for_ai" => {
    purpose: "Universal preparation for any AI task",
    inputs: ["text", "task_type", "options"],
    outputs: "Contract-compliant prepared data",
    complexity: "medium"
  },
  
  "rag::load_classification_rules" => {
    purpose: "Centralized rule loading from Data Tables",
    inputs: ["table_id", "rule_type"],
    outputs: "Normalized rule set",
    complexity: "low"
  },
  
  "rag::batch_prepare_texts" => {
    purpose: "Prepare multiple texts for batch processing",
    inputs: ["texts[]", "preparation_type"],
    outputs: "Batch-ready format",
    complexity: "medium"
  },
  
  "rag::merge_ai_response" => {
    purpose: "Combine AI response with metadata",
    inputs: ["ai_response", "original_metadata"],
    outputs: "Enriched response",
    complexity: "low"
  },
  
  # ============================================
  # NEW ACTIONS IN VERTEX
  # ============================================
  
  "vertex::ai_classify" => {
    purpose: "Pure AI classification without rules",
    inputs: ["prepared_text", "categories[]"],
    outputs: "Classification with confidence",
    complexity: "low",
    replaces: "Part of categorize_text"
  },
  
  "vertex::batch_process" => {
    purpose: "Process multiple items in parallel",
    inputs: ["batch_request"],
    outputs: "Batch results with partial success",
    complexity: "high"
  },
  
  "vertex::stream_generate" => {
    purpose: "Streaming responses for long generation",
    inputs: ["prompt", "stream_config"],
    outputs: "Chunked responses",
    complexity: "high",
    future: true
  }
}
```

## Phase 4: Refactor Method Dependencies
```Ruby
method_refactoring = {
  # ============================================
  # SHARED METHODS TO EXTRACT
  # ============================================
  
  "workato_api_methods" => {
    current_location: "both",
    new_location: "rag_utils",
    methods: [
      "workato_get",
      "workato_post", 
      "list_datatables",
      "list_datatable_columns",
      "fetch_datatable_rows"
    ],
    migration: "Remove from Vertex entirely"
  },
  
  "caching_methods" => {
    current_location: "both",
    new_location: "rag_utils",
    methods: [
      "cached_table_rows",
      "get_cached_datatables",
      "get_cached_table_columns"
    ],
    migration: "Centralize in RAG_Utils"
  },
  
  "prompt_builders" => {
    current_location: "vertex",
    new_location: "rag_utils",
    methods: [
      "payload_for_translate",
      "payload_for_summarize",
      "payload_for_categorize"
    ],
    migration: "Move to RAG as template builders"
  },
  
  "validation_methods" => {
    current_location: "split",
    new_location: "rag_utils",
    methods: [
      "check_finish_reason",
      "get_safety_ratings"
    ],
    migration: "Consolidate validation logic"
  }
}
```

### Phase 5: Configuration Migration

```ruby
configuration_migration = {
  "rag_utils_connection" => {
    add_fields: [
      "verbose_errors",
      "default_ai_provider"
    ],
    keep_fields: [
      "api_token",
      "environment",
      "chunk_size_default",
      "similarity_threshold"
    ],
    remove_fields: []
  },
  
  "vertex_connection" => {
    add_fields: [],
    keep_fields: [
      "auth_type",
      "region",
      "project",
      "version",
      "model_validation"
    ],
    remove_fields: [
      "workato_api_token",
      "workato_api_host"
    ]
  }
}
```

### Phase 6: Recipe Impact Analysis

```ruby
recipe_impact = {
  "high_impact_patterns" => [
    {
      pattern: "Vertex::categorize_text with Data Tables",
      count_estimate: "20-30 recipes",
      migration_effort: "high",
      new_pattern: "RAG::load_rules → RAG::prepare → Vertex::ai_classify"
    },
    {
      pattern: "Direct Vertex embeddings",
      count_estimate: "10-15 recipes",
      migration_effort: "medium",
      new_pattern: "RAG::batch_prepare → Vertex::generate_embeddings"
    }
  ],
  
  "low_impact_patterns" => [
    {
      pattern: "Vertex::translate_text",
      count_estimate: "5-10 recipes",
      migration_effort: "low",
      new_pattern: "Optional: Add RAG::clean_text before"
    },
    {
      pattern: "Vertex::analyze_image",
      count_estimate: "3-5 recipes",
      migration_effort: "none",
      new_pattern: "No change needed"
    }
  ]
}
```
## Migration Versioning and Timeline Approximation

```ruby
timeline = {
  "v1.1" => {
    duration: "2 weeks",
    actions: [
      "Add new actions in both connectors",
      "Add deprecation warnings",
      "Create compatibility shims"
    ]
  },
  
  "v1.2" => {
    duration: "1 month after v1.1",
    actions: [
      "Hide deprecated actions in UI",
      "Release migration guide",
      "Update all documentation"
    ]
  },
  
  "v2.0" => {
    duration: "3 months after v1.2",
    actions: [
      "Remove deprecated actions",
      "Remove compatibility shims",
      "Final cleanup"
    ]
  }
}
```
