# Data Contracts v2.0

**Connectors:** RAG Utilities, Vertex AI, Google Drive  
**Version:** 2.0  
**Last Updated:** September 19, 2025

---

## 1. Text Preparation Contracts (_modified, 09/19/25_)

### RAG &rarr; Vertex: Cleaned Text
```ruby
{
  # Required fields
  "text": "string",                    # Cleaned/processed text, max 32k tokens
  "metadata": {
    "original_length": "integer",      # Pre-cleaning character count
    "cleaned_length": "integer",       # Post-cleaning character count
    "processing_applied": ["array"],   # ["remove_signatures", "normalize_whitespace"]
    "source_type": "string"            # "email" | "document" | "chat" | "drive_file" (_new, 09/19/25_)
  },
  
  # Optional fields
  "extracted_sections": {
    "query": "string",                 # Main question/intent if identifiable
    "context": "string",               # Supporting information
    "entities": ["array"]              # Extracted entities if any
  },
  
  # (_new, 09/19/25_) Optional for drive_file source
  "document_metadata": {
    "file_id": "string",               # Google Drive file ID
    "file_name": "string",             # Original filename
    "mime_type": "string",             # MIME type
    "file_path": "string",             # Full path in Drive
    "modified_time": "timestamp",      # Last modified in Drive
    "file_hash": "string"              # SHA256 of content
  }
}
```

## 2. Document Processing Contracts (_new, 09/19/25_)

### Vertex (Drive) &rarr; RAG: Document Fetch Request
```ruby
{
  # Required fields
  "file_id": "string",                 # Google Drive file ID
  
  # Optional fields
  "export_format": "string",           # "text/plain" | "application/pdf" | etc
  "include_metadata": "boolean",       # Include Drive metadata
  "version": "string"                  # Specific revision ID
}
```

### Vertex (Drive) &rarr; RAG: Document Fetch Response
```ruby
{
  # Required fields
  "file_id": "string",
  "content": "string",                 # File content (text or base64)
  "content_type": "string",            # "text" | "binary"
  
  # Optional fields
  "metadata": {
    "name": "string",
    "mime_type": "string",
    "size": "integer",                 # Bytes
    "created_time": "timestamp",
    "modified_time": "timestamp",
    "version": "string",
    "parents": ["array"],              # Parent folder IDs
    "web_view_link": "string",
    "owners": ["array"],
    "last_modifying_user": "string"
  },
  "extracted_text": "string"           # For PDFs/images after OCR
}
```

### RAG &rarr; RAG: Document Chunking Request
```ruby
{
  # Required fields
  "document": {
    "file_id": "string",
    "content": "string",
    "file_name": "string"
  },
  
  # Optional fields
  "chunking_strategy": {
    "method": "string",                # "token" | "semantic" | "paragraph"
    "chunk_size": "integer",           # Tokens per chunk (default: 1000)
    "chunk_overlap": "integer",        # Overlap tokens (default: 100)
    "preserve_sections": "boolean",    # Keep document structure
    "max_chunks": "integer"            # Limit total chunks
  },
  
  "metadata_to_preserve": {
    "file_metadata": "boolean",        # Include Drive metadata
    "section_headers": "boolean",      # Preserve section context
    "page_numbers": "boolean"          # For PDFs
  }
}
```

### RAG &rarr; Vertex: Document Chunks Response
```ruby
{
  # Required fields
  "document_id": "string",              # Unique document identifier
  "file_id": "string",                  # Google Drive file ID
  "chunks": [
    {
      "chunk_id": "string",             # "doc_123_chunk_0"
      "chunk_index": "integer",
      "text": "string",
      "token_count": "integer",
      "metadata": {
        "document_id": "string",
        "file_id": "string",
        "file_name": "string",
        "chunk_index": "integer",
        "total_chunks": "integer",
        "section": "string",           # Section/chapter if identified
        "page_number": "integer"       # For PDFs
      }
    }
  ],
  
  # Statistics
  "stats": {
    "total_chunks": "integer",
    "total_tokens": "integer",
    "average_chunk_size": "integer",
    "processing_time_ms": "integer"
  }
}
```

## 3. Embedding Contracts 📝

### RAG &rarr; Vertex: Embedding Request
```ruby
{
  # Required fields
  "batch_id": "string",                # Unique batch identifier
  "texts": [                           # Array of texts to embed
    {
      "id": "string",                   # Unique identifier (e.g., "doc_123_chunk_0")
      "content": "string",              # Text content, max 8192 tokens
      "metadata": {                    # Metadata to attach to embedding
        "chunk_index": "integer",
        "document_id": "string",
        "source": "string",
        
        # 🆕 Document-specific metadata
        "file_id": "string",           # Google Drive file ID
        "file_name": "string",
        "file_path": "string",
        "document_type": "string",     # "policy" | "faq" | "manual" | etc
        "last_updated": "timestamp"
      }
    }
  ],
  
  # Optional fields
  "task_type": "string",                # "RETRIEVAL_DOCUMENT" | "RETRIEVAL_QUERY" | etc
  "title": "string",                    # For RETRIEVAL_DOCUMENT task type
  "model": "string",                     # Override default model
  
  # 🆕 Batch metadata
  "batch_metadata": {
    "source": "string",                # "drive_sync" | "manual_upload" | etc
    "processing_id": "string",         # Job/recipe run ID
    "total_documents": "integer"       # Documents in this batch
  }
}
```

### Vertex &rarr; RAG: Embedding Response
```ruby
{
  # Required fields
  "batch_id": "string",                 # Matching request batch_id
  "embeddings": [
    {
      "id": "string",                   # Matching input text id
      "vector": ["array of float"],    # Embedding vector
      "dimensions": "integer"           # Vector dimensions (e.g., 768)
    }
  ],
  "model_used": "string",               # "text-embedding-004"
  
  # Optional fields
  "usage": {
    "total_tokens": "integer",
    "characters_processed": "integer"
  },
  "errors": [                          # Per-item errors if any
    {
      "id": "string",
      "error": "string"
    }
  ]
}
```

## 4. Classification Contracts ✅

### RAG &rarr; Vertex: Classification Request
```ruby
{
  # Required fields
  "text": "string",                     # Text to classify
  "classification_mode": "string",      # "rules" | "ai" | "hybrid"
  
  # For AI classification
  "categories": [
    {
      "key": "string",                  # Category identifier
      "description": "string",          # Optional description/rule
      "examples": ["array"]             # Optional examples
    }
  ],
  
  # Optional fields
  "options": {
    "return_confidence": "boolean",     # Default: true
    "return_alternatives": "integer",   # Top N alternatives, default: 0
    "temperature": "float",             # Model temperature, default: 0
    "max_tokens": "integer"             # Response limit
  }
}
```

### Vertex &rarr; RAG: Classification Response
```ruby
{
  # Required fields
  "selected_category": "string",        # Chosen category key
  "confidence": "float",                # 0.0 to 1.0
  
  # Optional fields
  "alternatives": [
    {
      "category": "string",
      "confidence": "float"
    }
  ],
  "reasoning": "string",                # Model's explanation if requested
  "usage": {
    "prompt_tokens": "integer",
    "completion_tokens": "integer"
  }
}
```

## 5. Prompt Contracts ✅

### RAG &rarr; Vertex: Prepared Prompt
```ruby
{
  # Required fields
  "prompt_type": "string",              # "rag_response" | "analysis" | "generation"
  "formatted_prompt": "string",         # Complete formatted prompt
  
  # Optional fields
  "system_instruction": {
    "role": "model",
    "parts": [{"text": "string"}]
  },
  
  "context_documents": [                # For RAG responses
    {
      "id": "string",
      "content": "string",
      "relevance_score": "float",
      "metadata": {}
    }
  ],
  
  "generation_config": {
    "temperature": "float",             # 0.0 to 2.0
    "maxOutputTokens": "integer",       # Max response tokens
    "topK": "integer",                  # Top K sampling
    "topP": "float",                    # Top P sampling
    "responseMimeType": "string"        # "text/plain" | "application/json"
  },
  
  "response_schema": {                  # For structured output
    "type": "object",
    "properties": {},
    "required": ["array"]
  },
  
  "safety_settings": [
    {
      "category": "string",
      "threshold": "string"
    }
  ]
}
```

### Vertex &rarr; RAG: Generation Response
```ruby
{
  # Required fields
  "content": "string",                  # Generated text
  "finish_reason": "string",            # "STOP" | "MAX_TOKENS" | "SAFETY" | etc
  
  # Optional fields
  "structured_data": {},                # If JSON response requested
  
  "safety_ratings": {
    "sexually_explicit": "string",      # "NEGLIGIBLE" | "LOW" | "MEDIUM" | "HIGH"
    "hate_speech": "string",
    "harassment": "string",
    "dangerous_content": "string"
  },
  
  "usage": {
    "promptTokenCount": "integer",
    "candidatesTokenCount": "integer",
    "totalTokenCount": "integer"
  },
  
  "model_version": "string",
  "response_id": "string"
}
```

## 6. Vector Index Management Contracts 🆕

### RAG &rarr; Vertex: Index Update Request
```ruby
{
  # Required fields
  "index_id": "string",                # Vector index resource ID
  "operation": "string",               # "upsert" | "delete" | "update"
  
  # For upsert/update
  "datapoints": [
    {
      "datapoint_id": "string",        # Unique ID (e.g., "doc_123_chunk_0")
      "feature_vector": ["array"],     # Embedding vector
      
      # Metadata for filtering
      "restricts": [
        {
          "namespace": "string",        # "file_id" | "document_type" | etc
          "allowList": ["array"]        # Allowed values
        }
      ],
      
      # Numeric filtering
      "numericRestricts": [
        {
          "namespace": "string",        # "last_updated" | "relevance_score"
          "valueFloat": "float"
        }
      ],
      
      "crowding_tag": "string"          # Document ID for result diversity
    }
  ],
  
  # For delete
  "datapoint_ids": ["array"],
  
  # Optional
  "update_mask": ["array"]             # Fields to update
}
```

### Vertex &rarr; RAG: Index Update Response
```ruby
{
  # Required fields
  "operation": "string",
  "successfully_processed": "integer",
  
  # Optional fields
  "failed_datapoints": [
    {
      "datapoint_id": "string",
      "error": "string"
    }
  ],
  
  "index_stats": {
    "total_datapoints": "integer",
    "index_id": "string",
    "deployed_state": "string",        # "DEPLOYED" | "UNDEPLOYED"
    "last_update": "timestamp"
  }
}
```

## 7. Vector Search Contracts 📝

### RAG &rarr; Vertex: Vector Search Request
```ruby
{
  # Required fields
  "query_vector": ["array of float"],   # Query embedding
  "index_endpoint": {
    "host": "string",                   # "1234.us-central1.vdb.vertexai.goog"
    "endpoint_id": "string",            # Index endpoint ID
    "deployed_index_id": "string"       # Deployed index ID
  },
  
  # Optional fields
  "search_params": {
    "neighbor_count": "integer",        # k value, default: 10
    "return_full_datapoint": "boolean", # Include vectors in response
    
    # 🆕 Document-aware filtering
    "filters": {
      "restricts": [
        {
          "namespace": "string",        # "file_id" | "document_type" | etc
          "allowList": ["array"],       # Allowed values
          "denyList": ["array"]         # Excluded values
        }
      ],
      
      "numericRestricts": [
        {
          "namespace": "string",        # "last_updated" | "relevance_score"
          "op": "string",               # "EQUAL" | "LESS" | "GREATER" | etc
          "value": "number"
        }
      ]
    },
    
    # (_new, 09/19/25_) Result grouping
    "crowding": {
      "per_crowding_attribute_count": "integer"  # Max results per document
    }
  }
}
```

### Vertex &rarr; RAG: Vector Search Response
```ruby
{
  # Required fields
  "neighbors": [
    {
      "id": "string",                   # Document/chunk ID
      "distance": "float",              # Distance metric
      
      # (_new, 09/19/25_) Enhanced metadata
      "document_info": {
        "file_id": "string",
        "file_name": "string",
        "chunk_index": "integer",
        "section": "string"
      },
      
      "datapoint": {                    # If return_full_datapoint=true
        "featureVector": ["array"],
        "restricts": [],
        "numericRestricts": [],
        "crowding_tag": "string"        # Document ID
      }
    }
  ],
  
  # Optional fields
  "query_id": "string",
  "search_time_ms": "integer",
  
  # (_new, 09/19/25_) Search statistics
  "stats": {
    "documents_searched": "integer",
    "unique_documents": "integer",
    "filters_applied": ["array"]
  }
}
```

## 8. Document Sync Contracts (_new, 09/19/25_)

### Vertex (Drive) &rarr; RAG: Folder Monitor Request
```ruby
{
  # Required fields
  "folder_id": "string",                # Google Drive folder ID
  
  # Optional fields
  "options": {
    "recursive": "boolean",             # Include subfolders
    "file_types": ["array"],           # MIME types to include
    "exclude_patterns": ["array"],     # Regex patterns to exclude
    "modified_after": "timestamp",      # Incremental sync
    "page_size": "integer"              # Results per page
  }
}
```

### Vertex (Drive) &rarr; RAG: Folder Monitor Response
```ruby
{
  # Required fields
  "folder_id": "string",
  "files": [
    {
      "file_id": "string",
      "name": "string",
      "mime_type": "string",
      "size": "integer",
      "modified_time": "timestamp",
      "md5_checksum": "string",
      "status": "string"                # "new" | "modified" | "unchanged"
    }
  ],
  
  # Pagination
  "next_page_token": "string",
  "total_files": "integer"
}
```

## 9. Processing Pipeline Contract (_new, 09/19/25_)

### RAG Orchestration: Document Processing Job
```ruby
{
  # Job definition
  "job_id": "string",
  "job_type": "string",                 # "full_sync" | "incremental" | "single_file"
  "status": "string",                   # "pending" | "processing" | "completed" | "failed"
  
  # Source
  "source": {
    "type": "string",                   # "google_drive_vertex"
    "folder_id": "string",
    "file_ids": ["array"]
  },
  
  # Processing steps
  "pipeline": {
    "fetch": {
      "total": "integer",
      "completed": "integer",
      "failed": ["array"]
    },
    "chunk": {
      "total_documents": "integer",
      "total_chunks": "integer",
      "completed": "integer"
    },
    "embed": {
      "total_batches": "integer",
      "completed_batches": "integer",
      "total_embeddings": "integer"
    },
    "index": {
      "total_datapoints": "integer",
      "successfully_indexed": "integer",
      "failed": ["array"]
    }
  },
  
  # Metrics
  "metrics": {
    "start_time": "timestamp",
    "end_time": "timestamp",
    "processing_time_ms": "integer",
    "total_tokens_processed": "integer",
    "estimated_cost": "float"
  }
}
```

## 10. Validation Contracts 

### RAG &rarr; RAG: Validation Request
```ruby
{
  # Required fields
  "response": "string",                 # LLM response to validate
  "original_query": "string",           # Original user question
  
  # Optional fields
  "context_provided": ["array"],        # Context documents used
  "expected_format": "string",          # "json" | "email" | "list" | etc
  "validation_rules": [
    {
      "rule_type": "string",            # "contains" | "not_contains" | "length"
      "rule_value": "any"
    }
  ]
}
```

### RAG Response: Validation Result
```ruby
{
  # Required fields
  "is_valid": "boolean",
  "confidence_score": "float",          # 0.0 to 1.0
  
  # Optional fields
  "issues_found": ["array"],
  "requires_human_review": "boolean",
  "validation_details": {
    "query_overlap": "float",
    "response_length": "integer",
    "format_valid": "boolean"
  }
}
```

## 11. Error Contracts 

### Standard Error Format (All Connectors)
```ruby
{
  "error": {
    "code": "string",                   # "INVALID_INPUT" | "QUOTA_EXCEEDED" | etc
    "message": "string",                # Human-readable message
    "details": {
      "field": "string",                # Error-causing field
      "constraint": "string",           # Description of violated constraint
      "provided": "any",                # Provided content
      "expected": "any"                 # Expected content
    },
    "retry_after": "integer",           # Seconds to wait before retry
    "correlation_id": "string"          # For debugging across connectors
  }
}
```

## 12. Batch Processing Contracts 

### RAG &rarr; Vertex: Batch Request
```ruby
{
  "batch_id": "string",
  "batch_type": "string",               # "embeddings" | "classifications" | "generations"
  "items": ["array"],                   # Array of individual requests
  "batch_config": {
    "max_parallel": "integer",          # Max parallel API calls
    "retry_failed": "boolean",          # Auto-retry failed items
    "partial_success_ok": "boolean"     # Continue if some items fail
  }
}
```

## Usage Patterns

### Complete Document Processing Pipeline
```ruby
# Step 1: Monitor Drive folder for changes
monitor_request = {
  "folder_id": "drive_folder_123",
  "options": {
    "recursive": true,
    "file_types": ["application/pdf", "text/plain", "application/vnd.google-apps.document"],
    "modified_after": "2024-01-01T00:00:00Z"
  }
}

# Step 2: Fetch changed documents
fetch_request = {
  "file_id": "document_abc",
  "export_format": "text/plain",
  "include_metadata": true
}

# Step 3: Chunk document with metadata preservation
chunking_request = {
  "document": {
    "file_id": "document_abc",
    "content": "document text content...",
    "file_name": "Policy_2024.pdf"
  },
  "chunking_strategy": {
    "method": "token",
    "chunk_size": 1000,
    "chunk_overlap": 100,
    "preserve_sections": true
  },
  "metadata_to_preserve": {
    "file_metadata": true,
    "section_headers": true,
    "page_numbers": true
  }
}

# Step 4: Generate embeddings with document tracking
embedding_request = {
  "batch_id": "batch_20240115_001",
  "texts": chunks["chunks"].map { |chunk|
    {
      "id": chunk["chunk_id"],
      "content": chunk["text"],
      "metadata": {
        "document_id": "doc_123",
        "file_id": "document_abc",
        "file_name": "Policy_2024.pdf",
        "file_path": "/policies/2024/Policy_2024.pdf",
        "document_type": "policy",
        "chunk_index": chunk["chunk_index"],
        "total_chunks": chunks["stats"]["total_chunks"],
        "section": chunk["metadata"]["section"],
        "last_updated": "2024-01-15T10:00:00Z"
      }
    }
  },
  "task_type": "RETRIEVAL_DOCUMENT",
  "batch_metadata": {
    "source": "drive_sync",
    "processing_id": "job_456",
    "total_documents": 1
  }
}

# Step 5: Update vector index with document metadata
index_request = {
  "index_id": "projects/PROJECT/locations/REGION/indexes/INDEX",
  "operation": "upsert",
  "datapoints": embeddings["embeddings"].map { |emb|
    {
      "datapoint_id": emb["id"],
      "feature_vector": emb["vector"],
      "restricts": [
        {
          "namespace": "file_id",
          "allowList": ["document_abc"]
        },
        {
          "namespace": "document_type",
          "allowList": ["policy"]
        }
      ],
      "numericRestricts": [
        {
          "namespace": "last_updated",
          "valueFloat": Time.parse("2024-01-15T10:00:00Z").to_i
        }
      ],
      "crowding_tag": "document_abc"
    }
  }
}

# Step 6: Search with document filtering
search_request = {
  "query_vector": query_embedding["vector"],
  "index_endpoint": {
    "host": "1234.us-central1.vdb.vertexai.goog",
    "endpoint_id": "endpoint_xyz",
    "deployed_index_id": "deployed_index_123"
  },
  "search_params": {
    "neighbor_count": 10,
    "return_full_datapoint": false,
    "filters": {
      "restricts": [
        {
          "namespace": "document_type",
          "allowList": ["policy", "faq"]
        }
      ],
      "numericRestricts": [
        {
          "namespace": "last_updated",
          "op": "GREATER",
          "valueInt": 1704067200
        }
      ]
    },
    "crowding": {
      "per_crowding_attribute_count": 2
    }
  }
}
```

### Incremental Document Sync
```ruby
# Check for modified files since last sync
monitor_response = vertex_ai.monitor_drive_folder({
  "folder_id": "folder_123",
  "options": {
    "recursive": true,
    "modified_after": last_sync_timestamp
  }
})

# Process only changed files
modified_files = monitor_response["files"].select { |f| f["status"] == "modified" }

modified_files.each do |file|
  # Fetch document
  doc = vertex_ai.fetch_drive_document({
    "file_id": file["file_id"],
    "include_metadata": true
  })
  
  # Compare with stored hash
  if doc["metadata"]["md5_checksum"] != stored_checksums[file["file_id"]]
    # Delete old chunks from index
    vertex_ai.update_index({
      "index_id": index_id,
      "operation": "delete",
      "datapoint_ids": get_chunk_ids_for_file(file["file_id"])
    })
    
    # Process new version
    chunks = rag_utils.chunk_document(doc)
    embeddings = vertex_ai.generate_embeddings(chunks)
    
    # Insert new chunks
    vertex_ai.update_index({
      "index_id": index_id,
      "operation": "upsert",
      "datapoints": embeddings_to_datapoints(embeddings)
    })
    
    # Update stored hash
    stored_checksums[file["file_id"]] = doc["metadata"]["md5_checksum"]
  end
end
```

### Email RAG Response with Document Context
```ruby
# 1. Email arrives and gets cleaned
cleaned = rag_utils.clean_email_text({
  "email_body": email_content
})

# 2. Generate query embedding
query_embedding = vertex_ai.generate_embedding_single({
  "text": cleaned["extracted_query"] || cleaned["text"],
  "task_type": "RETRIEVAL_QUERY"
})

# 3. Search with document-aware filtering
search_results = vertex_ai.find_neighbors({
  "query_vector": query_embedding["vector"],
  "index_endpoint": {
    "host": "1234.us-central1.vdb.vertexai.goog",
    "endpoint_id": "endpoint_xyz",
    "deployed_index_id": "deployed_index_123"
  },
  "search_params": {
    "neighbor_count": 5,
    "filters": {
      "restricts": [
        {
          "namespace": "document_type",
          "allowList": ["policy", "faq", "manual"]
        }
      ],
      "numericRestricts": [
        {
          "namespace": "last_updated",
          "op": "GREATER",
          "valueInt": (Time.now - 90.days).to_i  # Only docs updated in last 90 days
        }
      ]
    },
    "crowding": {
      "per_crowding_attribute_count": 1  # One chunk per document for diversity
    }
  }
})

# 4. Build prompt with document references
prompt = rag_utils.build_rag_prompt({
  "query": cleaned["extracted_query"],
  "context_documents": search_results["neighbors"].map { |neighbor|
    {
      "id": neighbor["id"],
      "content": fetch_chunk_content(neighbor["id"]),
      "relevance_score": 1.0 - neighbor["distance"],
      "source": neighbor["document_info"]["file_name"],
      "metadata": {
        "file_id": neighbor["document_info"]["file_id"],
        "section": neighbor["document_info"]["section"],
        "chunk_index": neighbor["document_info"]["chunk_index"]
      }
    }
  },
  "prompt_type": "rag_response",
  "system_instruction": {
    "role": "model",
    "parts": [{
      "text": "You are a helpful customer service assistant. Answer based only on the provided context documents."
    }]
  }
})

# 5. Generate response
response = vertex_ai.send_messages({
  "formatted_prompt": prompt["formatted_prompt"],
  "generation_config": {
    "temperature": 0.3,
    "maxOutputTokens": 500
  }
})

# 6. Validate response
validation = rag_utils.validate_response({
  "response": response["content"],
  "original_query": cleaned["extracted_query"],
  "context_provided": prompt["context_documents"].map { |doc| doc["content"] }
})

# 7. Send response if valid
if validation["is_valid"]
  send_email_response(response["content"])
else
  escalate_to_human(email, validation["issues_found"])
end
```

## Migration Guide

### Backward Compatibility
- All v1.0 contracts remain valid
- New fields are optional unless marked as required for document workflows
- Existing actions continue to work without modification

### Key Changes from v1.0
1. **Text Preparation**: Added `drive_file` as source_type, new `document_metadata` field
2. **Embeddings**: Added document tracking metadata fields
3. **Vector Search**: Enhanced with document filtering and result grouping
4. **New Contracts**: Added 5 new contract types for document operations
5. **Index Management**: New contracts for vector index CRUD operations

### Upgrade Path
1. **Phase 1**: Update connectors to handle new optional fields (backward compatible)
2. **Phase 2**: Add Google Drive connector implementing new contracts
3. **Phase 3**: Enhance RAG_Utils actions to pass document metadata
4. **Phase 4**: Update Vertex AI connector for index management
5. **Phase 5**: Modify search queries to leverage document filtering

### Testing Checklist
- [ ] Existing workflows continue without modification
- [ ] New document fields are properly passed through pipeline
- [ ] Vector search filters work with document metadata
- [ ] Batch processing includes document tracking
- [ ] Index operations handle document-specific metadata
- [ ] Error handling covers new failure modes

---

**Version History**
- v1.0 (September 18, 2025): Initial contracts for email RAG system
- v2.0 (September 19, 2025): Added Google Drive document processing support
