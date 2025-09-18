# Data Contracts 

Connectors: **RAG Utilities**, **Vertex AI**

--- 

## 1. Text Preparation Contracts

### RAG &rarr; Vertex: Cleaned Text
```ruby
{
  # Required fields
  "text": "string",                    # Cleaned/processed text, max 32k tokens
  "metadata": {
    "original_length": "integer",      # Pre-cleaning character count
    "cleaned_length": "integer",       # Post-cleaning character count
    "processing_applied": ["array"],   # ["remove_signatures", "normalize_whitespace"]
    "source_type": "string"            # "email" | "document" | "chat"
  },
  
  # Optional fields
  "extracted_sections": {
    "query": "string",                 # Main question/intent if identifiable
    "context": "string",               # Supporting information
    "entities": ["array"]              # Extracted entities if any
  }
}
```

## 2. Embedding Contracts

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
        "source": "string"
      }
    }
  ],
  
  # Optional fields
  "task_type": "string",                # "RETRIEVAL_DOCUMENT" | "RETRIEVAL_QUERY" | etc
  "title": "string",                    # For RETRIEVAL_DOCUMENT task type
  "model": "string"                     # Override default model
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

## 3. Classification Contracts

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

## 4. Prompt Contracts

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

## 5. Vector Search Contracts

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
    
    "filters": {                        # Metadata filtering
      "restricts": [
        {
          "namespace": "string",
          "allowList": ["array"],
          "denyList": ["array"]
        }
      ],
      "numericRestricts": [
        {
          "namespace": "string",
          "op": "string",               # "EQUAL" | "LESS" | "GREATER" | etc
          "value": "number"
        }
      ]
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
      "datapoint": {                    # If return_full_datapoint=true
        "featureVector": ["array"],
        "restricts": [],
        "numericRestricts": []
      }
    }
  ],
  
  # Optional fields
  "query_id": "string",
  "search_time_ms": "integer"
}
```

## 6. Validation Contracts

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

## 7. Error Contracts

### Standard Error Format (Both Connectors)
```ruby
{
  "error": {
    "code": "string",                   # "INVALID_INPUT" | "QUOTA_EXCEEDED" | etc
    "message": "string",                # Human-readable message
    "details": {
      "field": "string",                # Error-causing field
      "constraint": "string",           # Descr of violated constraint
      "provided": "any",                # Provided content
      "expected": "any"                 # Content expected
    },
    "retry_after": "integer",           # Seconds to wait before retry
    "correlation_id": "string"          # For debugging across connectors
  }
}
```

## 8. Batch Processing Contracts

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

### Email Response Pipeline
```ruby
# 1. Email arrives => RAG cleans
rag_output = {
  "text": "cleaned email content",
  "metadata": { "source_type": "email" }
}

# 2. RAG evaluates => Vertex classifies if needed
classification_request = {
  "text": rag_output["text"],
  "classification_mode": "ai",
  "categories": [...]
}

# 3. RAG builds prompt => Vertex generates
prompt_request = {
  "prompt_type": "rag_response",
  "formatted_prompt": "...",
  "context_documents": [...]
}

# 4. Vertex responds => RAG validates
validation_request = {
  "response": vertex_response["content"],
  "original_query": original_email["text"]
}
```
---
