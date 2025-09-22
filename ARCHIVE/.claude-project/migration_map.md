# Migration Map for Google Drive Integration

## Objective
> Integrate Google Drive document processing into the RAG Email Response System while maintaining backward compatibility and clear separation of concerns between RAG_Utils and Vertex connectors.

## Phased Implementation

### Phase 1: Existing Actions Enhancement

```ruby
drive_migration_map = {
  # ============================================
  # RAG_UTILS CONNECTOR - ENHANCEMENTS
  # ============================================
  
  "rag::smart_chunk_text" => {
    status: "enhance",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      add_metadata: "Document source tracking",
      new_fields: ["file_id", "file_name", "chunk_total"],
      preserve: "All existing functionality"
    },
    notes: "Add document context to chunk metadata"
  },
  
  "rag::prepare_embedding_batch" => {
    status: "enhance",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "medium",
    changes: {
      input: "Accept document metadata",
      add_fields: ["file_id", "file_name", "document_checksum"],
      output: "Include document tracking in metadata",
      batch_size: "Optimize for Vertex limits (25)"
    },
    migration_pattern: "Auto-populate if metadata missing"
  },
  
  "rag::build_rag_prompt" => {
    status: "enhance",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      context_enhancement: "Include document source info",
      add_fields: ["source_documents[]"],
      template_updates: "Add document citation support"
    },
    notes: "Optionally include document references in prompts"
  },
  
  "rag::generate_document_metadata" => {
    status: "enhance",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      add_fields: ["google_drive_id", "mime_type", "owner"],
      enhance: "Checksum generation for change detection"
    }
  },
  
  "rag::prepare_for_ai" => {
    status: "enhance",
    new_location: "rag_utils",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      source_types: "Add 'drive_file' option",
      metadata: "Include file source tracking"
    }
  },
  
  # ============================================
  # VERTEX CONNECTOR - ENHANCEMENTS
  # ============================================
  
  "vertex::generate_embeddings" => {
    status: "enhance",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "medium",
    changes: {
      metadata_preservation: "Maintain document metadata through pipeline",
      add_fields: ["document_checksum", "chunk_total"],
      batch_optimization: "Handle document batches efficiently"
    },
    migration_pattern: "Backward compatible - ignore new fields if not present"
  },
  
  "vertex::find_neighbors" => {
    status: "enhance",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "medium",
    changes: {
      add_filters: ["file_ids[]", "file_types[]", "modified_after"],
      response_enhancement: "Group results by document",
      add_output: ["document_groups", "adjacent_chunks"]
    },
    notes: "Document-aware search capabilities"
  },
  
  "vertex::upsert_index_datapoints" => {
    status: "enhance",
    new_location: "vertex",
    breaking_change: false,
    migration_complexity: "low",
    changes: {
      metadata_support: "Include document restricts",
      add_restricts: ["source:file_id", "type:mime_type"],
      batch_handling: "Process document chunks together"
    }
  }
}
```

### Phase 2: New Drive Actions

```ruby
new_drive_actions = {
  # ============================================
  # NEW ACTIONS IN VERTEX CONNECTOR
  # ============================================
  
  "vertex::fetch_drive_file" => {
    purpose: "Retrieve and extract text from Google Drive files",
    complexity: "medium",
    inputs: {
      file_id: "string",
      export_format: "text/plain | application/pdf | original"
    },
    outputs: {
      file_id: "string",
      file_name: "string",
      text_content: "string",
      mime_type: "string",
      checksum: "string",
      needs_processing: "boolean"
    },
    oauth_required: true,
    implementation_priority: "critical"
  },
  
  "vertex::list_drive_files" => {
    purpose: "List files in Drive folder with filtering",
    complexity: "low",
    inputs: {
      folder_id: "string (optional)",
      modified_after: "datetime (optional)",
      mime_types: "array (optional)",
      max_results: "integer"
    },
    outputs: {
      files: "array",
      count: "integer",
      has_more: "boolean"
    },
    oauth_required: true,
    implementation_priority: "critical"
  },
  
  "vertex::batch_fetch_drive_files" => {
    purpose: "Efficiently fetch multiple files",
    complexity: "high",
    inputs: {
      file_ids: "array",
      skip_errors: "boolean",
      export_format: "string"
    },
    outputs: {
      successful_files: "array",
      failed_files: "array",
      success_rate: "float"
    },
    oauth_required: true,
    implementation_priority: "high"
  },
  
  "vertex::monitor_drive_changes" => {
    purpose: "Track incremental file changes",
    complexity: "medium",
    inputs: {
      page_token: "string (optional)",
      folder_id: "string (optional)"
    },
    outputs: {
      changes: "array",
      new_page_token: "string",
      files_added: "array",
      files_modified: "array",
      files_removed: "array"
    },
    oauth_required: true,
    implementation_priority: "medium"
  },
  
  "vertex::test_connection" => {
    purpose: "Test all API connections and permissions",
    complexity: "medium",
    inputs: {
      test_vertex_ai: "boolean",
      test_drive: "boolean",
      test_models: "boolean",
      test_index: "boolean",
      verbose: "boolean"
    },
    outputs: {
      overall_status: "string",
      tests_performed: "array",
      errors: "array",
      recommendations: "array"
    },
    oauth_required: true,
    implementation_priority: "high"
  },
  
  # ============================================
  # NEW ACTIONS IN RAG_UTILS CONNECTOR
  # ============================================
  
  "rag::process_document_for_rag" => {
    purpose: "Complete document processing pipeline",
    complexity: "high",
    inputs: {
      document_content: "string",
      file_path: "string",
      file_type: "string",
      chunk_size: "integer",
      chunk_overlap: "integer"
    },
    outputs: {
      document_id: "string",
      chunks: "array",
      document_metadata: "object",
      ready_for_embedding: "boolean"
    },
    implementation_priority: "critical"
  },
  
  "rag::prepare_document_batch" => {
    purpose: "Process multiple documents for embedding",
    complexity: "medium",
    inputs: {
      documents: "array",
      batch_size: "integer"
    },
    outputs: {
      batches: "array",
      total_chunks: "integer"
    },
    implementation_priority: "high"
  }
}
```

### Phase 3: Configuration Migration

```ruby
configuration_migration = {
  "vertex_connection" => {
    add_fields: [
      {
        field: "drive_scope",
        value: "https://www.googleapis.com/auth/drive.readonly",
        location: "oauth2.scopes",
        required: true
      }
    ],
    modify_fields: [
      {
        field: "authorization_url",
        change: "Add Drive scope to existing scopes array",
        breaking_change: true,
        migration: "Re-authenticate after update"
      }
    ],
    keep_fields: ["auth_type", "region", "project", "service_account_email"]
  },
  
  "rag_utils_connection" => {
    add_fields: [
      {
        field: "document_source",
        type: "select",
        options: ["google_drive", "upload", "api"],
        default: "google_drive"
      },
      {
        field: "default_chunk_size",
        type: "integer",
        default: 1000,
        note: "For document processing"
      }
    ],
    keep_fields: "all_existing"
  }
}
```

### Phase 4: Data Contract Migration

```ruby
contract_migration = {
  "text_preparation_contract" => {
    status: "enhance",
    breaking_change: false,
    changes: {
      metadata: {
        add: ["source_type: 'drive_file'"],
        optional: ["source_metadata object"]
      }
    }
  },
  
  "embedding_request_contract" => {
    status: "enhance",
    breaking_change: false,
    changes: {
      text_metadata: {
        add: ["file_id", "file_name", "chunk_total", "document_checksum"],
        all_optional: true
      },
      new_section: "batch_config object"
    }
  },
  
  "vector_search_contract" => {
    status: "enhance",
    breaking_change: false,
    changes: {
      search_params: {
        add: ["document_filters object"],
        response: ["document_groups array", "adjacent_chunks object"]
      }
    }
  },
  
  "new_contracts" => [
    "document_processing_contract",
    "drive_operations_contract",
    "vector_index_contract",
    "document_pipeline_contract"
  ]
}
```

### Phase 5: Recipe Impact Analysis

```ruby
recipe_impact = {
  "high_impact_recipes" => [
    {
      pattern: "Manual document upload workflow",
      count_estimate: "10-15 recipes",
      migration_effort: "high",
      changes_required: [
        "Replace with Drive fetch actions",
        "Add document metadata tracking",
        "Update embedding generation"
      ],
      new_pattern: "Drive::list → Drive::fetch → RAG::process → Vertex::embed"
    },
    {
      pattern: "Email response generation",
      count_estimate: "5-10 recipes",
      migration_effort: "medium",
      changes_required: [
        "Update vector search with document filters",
        "Add document citation in responses"
      ],
      new_pattern: "Add document_filters to find_neighbors"
    }
  ],
  
  "low_impact_recipes" => [
    {
      pattern: "Pure email classification",
      count_estimate: "20+ recipes",
      migration_effort: "none",
      changes_required: [],
      notes: "No changes needed - Drive integration optional"
    }
  ],
  
  "new_recipe_patterns" => [
    {
      name: "Document Ingestion Pipeline",
      trigger: "Scheduled or on-demand",
      actions: [
        "vertex::list_drive_files",
        "vertex::batch_fetch_drive_files",
        "rag::process_document_for_rag",
        "vertex::generate_embeddings",
        "vertex::upsert_index_datapoints"
      ]
    },
    {
      name: "Incremental Document Updates",
      trigger: "Scheduled (every 6 hours)",
      actions: [
        "vertex::monitor_drive_changes",
        "rag::check_document_changes",
        "conditional: reprocess if changed"
      ]
    }
  ]
}
```

### Phase 6: Helper Method Refactoring

```ruby
method_refactoring = {
  "new_helper_methods" => {
    "drive_utilities" => {
      location: "vertex",
      methods: [
        "extract_drive_file_id",
        "get_export_mime_type",
        "build_drive_query",
        "handle_drive_error"
      ]
    },
    
    "document_processing" => {
      location: "rag_utils",
      methods: [
        "generate_document_id",
        "calculate_chunk_boundaries",
        "merge_document_metadata",
        "track_document_lineage"
      ]
    }
  },
  
  "enhanced_methods" => {
    "batch_processing" => {
      location: "both",
      changes: "Add document-aware batching",
      methods: ["optimize_document_batches", "group_chunks_by_document"]
    }
  }
}
```

## Migration Timeline

```ruby
timeline = {
  "Phase 1: Foundation" => {
    duration: "1 week",
    sprint: "Week 1",
    actions: [
      "Add OAuth2 Drive scope",
      "Implement fetch_drive_file",
      "Implement list_drive_files",
      "Test basic Drive connectivity"
    ],
    deliverables: ["Basic Drive access working"],
    risks: ["OAuth re-authentication required"]
  },
  
  "Phase 2: Document Processing" => {
    duration: "1 week",
    sprint: "Week 2",
    actions: [
      "Implement process_document_for_rag",
      "Enhance chunking with metadata",
      "Update embedding contracts",
      "Test document pipeline"
    ],
    deliverables: ["End-to-end document processing"],
    risks: ["Contract compatibility"]
  },
  
  "Phase 3: Batch & Search" => {
    duration: "1 week",
    sprint: "Week 3",
    actions: [
      "Implement batch_fetch_drive_files",
      "Enhance vector search with filters",
      "Add document grouping",
      "Test at scale"
    ],
    deliverables: ["Production-ready batch processing"],
    risks: ["Performance at scale"]
  },
  
  "Phase 4: Monitoring & Polish" => {
    duration: "1 week",
    sprint: "Week 4",
    actions: [
      "Implement monitor_drive_changes",
      "Add test_connection action",
      "Complete error handling",
      "Documentation"
    ],
    deliverables: ["Complete Drive integration"],
    risks: ["Edge cases in change detection"]
  },
  
  "Phase 5: Recipe Migration" => {
    duration: "2 weeks",
    sprint: "Weeks 5-6",
    actions: [
      "Update existing recipes",
      "Create new recipe templates",
      "Test all workflows",
      "Performance optimization"
    ],
    deliverables: ["All recipes using new capabilities"],
    risks: ["Recipe regression"]
  }
}
```

## Rollback Plan

```ruby
rollback_strategy = {
  "compatibility_mode" => {
    description: "Keep old actions working during migration",
    implementation: "Feature flags for new capabilities",
    duration: "3 months after release"
  },
  
  "versioning" => {
    v1_5: "Current + Drive integration (backward compatible)",
    v2_0: "Breaking changes allowed (3 months later)"
  },
  
  "fallback_patterns" => {
    drive_unavailable: "Fall back to manual upload",
    oauth_failure: "Use service account with shared files",
    api_quota: "Implement exponential backoff"
  }
}
```

## Success Metrics

```ruby
success_criteria = {
  functional: [
    "Process 100+ documents without error",
    "Incremental updates working",
    "Search with document filtering",
    "OAuth and service account both working"
  ],
  
  performance: [
    "Batch process 25 documents in <60 seconds",
    "Vector search with filters <500ms",
    "Document change detection <5 seconds"
  ],
  
  compatibility: [
    "All existing recipes still working",
    "No breaking changes for 3 months",
    "Gradual migration path available"
  ]
}
```
