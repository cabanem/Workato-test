# Connector Migration Strategy (Google Drive Integration)

## **Strategy: Drive as Gateway, RAG as Processor, Vertex as AI Engine**

### 1. **Drive Operations - Centralize in Vertex**

**Current state**: No Drive integration exists yet
**Proposed Implementation**:
- **Vertex** owns all Drive API interactions (OAuth2, file fetching, listing)
- **RAG_Utils** owns all document processing (chunking, cleaning, metadata)
- **Clear boundary**: Raw file access vs. content processing

**Rationale**: Vertex already handles OAuth2 authentication. Adding Drive scope here avoids duplicate auth flows. RAG_Utils remains focused on text processing without API dependencies.

### 2. **Document Processing Pipeline - Strict Separation**

**Potential overlap**: Both could process documents
**Proposed Modification(s)**:
- **Vertex**: Fetches raw content only - no processing
- **RAG_Utils**: Receives raw content, performs all transformations

**Implementation Pattern**:
```ruby
# Clear data flow
1. Vertex: fetch_drive_file → raw content + metadata
2. RAG_Utils: process_document_for_rag → chunks + enhanced metadata  
3. Vertex: generate_embeddings → vectors with preserved metadata
4. Vertex: upsert_index_datapoints → stored with document context
```

### 3. **Metadata Management - Layered Approach**

**Potential overlap**: Both generate and use metadata
**Proposed Modification(s)**:
- **Vertex** provides Drive-specific metadata (file_id, mime_type, modified_time, owner)
- **RAG_Utils** enriches with processing metadata (chunk_count, token_count, language, key_topics)

**Metadata Flow**:
```ruby
# Vertex output (Drive metadata)
{
  file_id: "abc123",
  file_name: "policy.pdf",
  mime_type: "application/pdf",
  modified_time: "2024-01-15T10:00:00Z",
  checksum: "md5hash..."
}

# RAG_Utils enhancement (Processing metadata)
{
  ...drive_metadata,
  document_id: "generated_id",
  chunks: 15,
  total_tokens: 3500,
  language: "english",
  key_topics: ["policy", "compliance"]
}
```

### 4. **Batch Operations - Specialized Responsibilities**

**Potential overlap**: Both have batching capabilities
**Proposed Modification(s)**:
- **Vertex**: Batch Drive fetching (`batch_fetch_drive_files`)
- **RAG_Utils**: Batch text processing (`prepare_document_batch`)
- **Vertex**: Batch embedding generation (existing)

**Clear Distinction**:
```ruby
# Vertex handles API batching
batch_fetch_drive_files(file_ids: ["id1", "id2", "id3"])

# RAG_Utils handles content batching
prepare_document_batch(documents: [doc1_content, doc2_content])

# Vertex handles embedding batching  
generate_embeddings(batch_id: "batch_001", texts: prepared_chunks)
```

### 5. **Change Detection - Collaborative Approach**

**Implementation Strategy**:
- **Vertex**: Detects Drive changes (`monitor_drive_changes`)
- **RAG_Utils**: Determines if reprocessing needed (`check_document_changes`)

**Decision Flow**:
```ruby
1. Vertex: monitor_drive_changes → changed_files[]
2. For each changed file:
   a. Vertex: fetch current checksum
   b. RAG_Utils: compare with stored checksum
   c. Decision: reprocess if content changed
```

### 6. **Error Handling - Context-Aware Layers**

**Proposed Implementation**:
- **Vertex**: Drive-specific errors (404, 403, quota)
- **RAG_Utils**: Processing errors (encoding, chunking failures)

**Error Propagation**:
```ruby
# Vertex Drive errors
handle_drive_error: lambda do |code, body|
  case code
  when 404: "File not found. Check file ID and permissions."
  when 403: "Access denied. Share file with service account."
  when 429: "Rate limited. Implement exponential backoff."
  end
end

# RAG_Utils processing errors
handle_processing_error: lambda do |error_type|
  case error_type
  when :encoding: "Unable to extract text. Try different export format."
  when :size: "Document too large. Consider chunking parameters."
  end
end
```

## **Resulting Architecture**

```
Vertex AI Connector (API Layer):
├── Drive Operations
│   ├── fetch_drive_file (single)
│   ├── list_drive_files (discovery)
│   ├── batch_fetch_drive_files (bulk)
│   └── monitor_drive_changes (incremental)
├── AI Operations (existing)
│   ├── generate_embeddings
│   ├── find_neighbors
│   └── send_messages
└── Storage Operations
    └── upsert_index_datapoints

RAG_Utils Connector (Processing Layer):
├── Document Processing
│   ├── process_document_for_rag (complete pipeline)
│   ├── smart_chunk_text (enhanced with metadata)
│   └── generate_document_metadata
├── Batch Preparation
│   ├── prepare_document_batch
│   └── prepare_embedding_batch
└── Validation & Detection
    ├── check_document_changes
    └── validate_llm_response
```

## **Migration Path for Existing Actions**

### Actions to Enhance (Backward Compatible):
```ruby
# RAG_Utils enhancements
smart_chunk_text: {
  # ADD: document tracking metadata
  new_fields: ["file_id", "file_name", "chunk_total"],
  breaking_change: false
}

prepare_embedding_batch: {
  # ADD: document context preservation
  new_fields: ["document_checksum", "file_metadata"],
  breaking_change: false
}

# Vertex enhancements
find_neighbors: {
  # ADD: document-aware filtering
  new_fields: ["file_ids[]", "document_groups"],
  breaking_change: false
}
```

### New Actions (Clean Separation):
```ruby
# Vertex: Pure Drive operations
fetch_drive_file: { owner: "vertex", purpose: "raw_access" }
list_drive_files: { owner: "vertex", purpose: "discovery" }
monitor_drive_changes: { owner: "vertex", purpose: "tracking" }

# RAG_Utils: Pure processing
process_document_for_rag: { owner: "rag_utils", purpose: "transform" }
prepare_document_batch: { owner: "rag_utils", purpose: "optimize" }
```

## **Benefits of This Architecture**

1. **Single Responsibility**: Each connector has a clear, non-overlapping purpose
2. **Authentication Simplicity**: One OAuth2 flow in Vertex handles all Google APIs
3. **Testing Isolation**: Can test document processing without Drive access
4. **Cost Optimization**: Process documents once, reuse prepared chunks
5. **Debugging Clarity**: Errors clearly indicate which layer failed

## **Implementation Priority**

```
Week 1: Foundation
├── Add OAuth2 Drive scope to Vertex
├── Implement fetch_drive_file
└── Test basic connectivity

Week 2: Processing Pipeline  
├── Enhance RAG_Utils chunking with metadata
├── Implement process_document_for_rag
└── Test document flow

Week 3: Batch & Search
├── Implement batch_fetch_drive_files
├── Enhance vector search with document filters
└── Test at scale

Week 4: Monitoring
├── Implement monitor_drive_changes
├── Add change detection logic
└── Complete error handling
```

## **Recipe Pattern Examples**

### Initial Document Ingestion:
```
Scheduled Trigger: Daily at 2 AM
→ Vertex: list_drive_files (folder_id: "docs_folder")
→ Vertex: batch_fetch_drive_files (file_ids: from list)
→ Loop for each file:
  → RAG_Utils: process_document_for_rag
  → Vertex: generate_embeddings (with metadata)
  → Vertex: upsert_index_datapoints
```

### Incremental Updates:
```
Scheduled Trigger: Every 6 hours
→ Vertex: monitor_drive_changes (page_token: from storage)
→ Filter: changed_files.any?
  → Yes: For each changed file
    → RAG_Utils: check_document_changes
    → If significant: Reprocess document
  → No: Skip
→ Store: new_page_token for next run
```

### Query with Document Context:
```
Trigger: Email received
→ RAG_Utils: clean_email_text
→ RAG_Utils: prepare_for_ai
→ Vertex: generate_embedding_single (query)
→ Vertex: find_neighbors (with document_filters)
→ RAG_Utils: build_rag_prompt (with document citations)
→ Vertex: send_messages
```

## **Rollback Safety**

All enhancements are backward compatible. Existing recipes continue working:
- New fields are optional
- Old patterns still supported
- Feature flags can disable Drive integration
- 3-month compatibility window before deprecation

This architecture ensures clean separation while maintaining the flexibility to evolve each connector independently.
