# API

## Consolidated Endpoints

```ruby
API_ENDPOINTS = {
  # Vertex - AI - Generation
  'vertex_generate' => {
    method: 'POST',
    url_template: '{vertex_base}/publishers/google/models/{model}:generateContent',
    actions: ['translate', 'summarize', 'parse', 'classify', 'analyze', 'email', 'conversation', 'image_analysis']
  },
  
  # Vertex - AI - Prediction (embeddings)
  'vertex_predict' => {
    method: 'POST',
    url_template: '{vertex_base}/publishers/google/models/{model}:predict',
    actions: ['embed_single', 'embed_batch']
  },
  
  # Vertex - Vector - Search
  'vector_search' => {
    method: 'POST',
    url_template: 'https://{custom_host}/v1/projects/{project}/locations/{region}/indexEndpoints/{endpoint}:findNeighbors',
    actions: ['find_neighbors']
  },
  
  # Vertex - Vector - Upsert
  'vector_upsert' => {
    method: 'POST',
    url_template: '{vertex_base}/indexes/{index_id}:upsertDatapoints',
    actions: ['upsert_datapoints']
  },
  
  # Drive - Fetch metadata
  'drive_metadata' => {
    method: 'GET',
    url_template: 'https://www.googleapis.com/drive/v3/files/{file_id}',
    actions: ['fetch_file', 'batch_fetch']
  },
  
  # Drive - Fetch Content - Text
  'drive_export' => {
    method: 'GET',
    url_template: 'https://www.googleapis.com/drive/v3/files/{file_id}/export',
    actions: ['fetch_file_content']
  },
  
  # Drive - Fetch Content - Image/PDF
  'drive_download' => {
    method: 'GET', 
    url_template: 'https://www.googleapis.com/drive/v3/files/{file_id}?alt=media',
    actions: ['fetch_file_content']
  },
  
  # Drive - List Files
  'drive_list' => {
    method: 'GET',
    url_template: 'https://www.googleapis.com/drive/v3/files',
    actions: ['list_files']
  },
  
  # Drive - Monitor for Changes
  'drive_changes' => {
    method: 'GET',
    url_template: 'https://www.googleapis.com/drive/v3/changes',
    actions: ['monitor_changes']
  }
}
```

# Connector Actions

## Steps by Action

### 1. `send_messages`
```
1. Validate model access
2. Parse response schema from JSON (if present)
3. Build message parts (text, fileData, inLineData, functionCall)
4. Construct conversation payload or single message
5. Rate limit check
6. POST to Vertex AI endpoint
7. Add trace metadata (correlation ID, duration)
8. Return raw response with telemetry
```

### 2. `translate_text`
```
1. Validate model access
2. Build translation instruction prompt
3. Escape triple backticks in source text
4. Format with source/target languages
5. Add JSON output instruction
6. Rate limit check
7. POST to Vertex AI endpoint
8. Extract JSON from response text
9. Strip markdown fences
10. Parse JSON and extract 'response' field
11. Return with success indicators
```

### 3. `summarize_text`
```
1. Validate model access
2. Build summarization instruction w/word limit
3. Create prompt with text
4. Rate limit check
5. POST to Vertex AI
6. Extract plain text from response
7. Add safety ratings and usage metrics
8. Return summary with metadata
```

### 4. `parse_text`
```
1. Validate model access
2. Parse user's schema definition
3. Escape tripple backticks in text
4. Build schema-guided prompt
5. Rate limit check
6. POST to Vertex AI endpoint
7. Extract JSON response
8. Strip markdown fences
9. Parse JSON matching schema
10. Return null for missing fields
11. Add safety ratings
12. Return structured data
```

### 5. `draft_email`
```
1. Validate model access
2. Escape triple backticks in description
3. Build email generation prompt
4. Request JSON with subject/body keys
5. Rate limit check
6. POST to Vertex AI
7. Extract JSON response
8. Parse subject and body fields
9. Add safety ratings
10. Return email components
```

### 6. `ai_classify`
```
1. Validate model access
2. Format categories with descriptions
3. Build classification prompt
4. Set low temperature (0.1)
5. Rate limit check
6. POST to Vertex AI
7. Extract JSON with confidence scores
8. Parse category, confidence, alternatives
9. Check confidence threshold (0.7)
10. Flag for human review if needed
11. Calculate pass/fail status
12. Return classification with metadata
```

### 7. `analyze_text`
```
1. Validate model access
2. Escape triple backticks in text and question
3. Build analysis prompt
4. Instruct to use only provided text
5. Rate limit check
6. POST to Vertex AI
7. Extract JSON response
8. Get 'response' field or null
9. Check if answer found
10. Add safety ratings
11. Return analysis result
```

### 8. `analyze_image`
```
1. Validate model access
2. Base64 encode image data
3. Build multimodal payload (text + image)
4. Set MIME type
5. Rate limit check
6. POST to Vertex AI
7. Extract text response
8. Parse JSON if requested
9. Add safety ratings
10. Return analysis
```

### 9. `generate_embeddings` (batch)
```
1. Validate embedding model
2. Split texts into batches of 25
3. For each batch:
   a. Build instances array
   b. Add task_type if specified
   c. Rate limit check
   d. POST to Vertex AI
   e. Extract embedding vectors
   f. Track success/failure per text
   g. Estimate token count
4. Aggregate all results
5. Calculate cost savings
6. Serialize to JSON for bulk ops
7. Return with metrics
```

### 10. `generate_embedding_single`
```
1. Validate embedding model
2. Check text length (<8192 tokens)
3. Prepend title if provided
4. Build single instance payload
5. Rate limit check
6. POST to Vertex AI
7. Extract embedding vector
8. Count dimensions
9. Estimate tokens
10. Return vector with metadata
```

### 11. `find_neighbors`
```
1. Normalize host URL (remove https://)
2. Build queries array with vectors
3. Add filters (restricts, crowdingTag)
4. Rate limit check
5. POST to vector search endpoint
6. Transform distances to similarities (1 - distance/2)
7. Flatten nested results
8. Sort by similarity score
9. Extract best match
10. Return sorted matches
```

### 12. `upsert_index_datapoints`
```
1. Validate index format
2. GET index details (check deployed)
3. Validate each datapoint structure
4. Split into batches of 100
5. For each batch:
   a. Format datapoints
   b. Add restricts/crowding tags
   c. Rate limit check
   d. POST to index endpoint
   e. Retry on 429 errors
   f. Track success/failure
6. Update index statistics
7. Return counts and errors
```

### 13. `test_connection`
```
1. Initialize results structure
2. If test_vertex_ai:
   - GET datasets (1 item)
   - Extract permissions
3. If test_models:
   - GET models list
   - GET Gemini model access
4. If test_drive:
   - GET files list
   - Try file read if found
5. If test_index:
   - Validate index format
   - GET index details
   - Check deployment status
6. Add quota information
7. Generate recommendations
8. Calculate summary stats
9. Return diagnostic report
```

### 14. `get_prediction` (legacy)
```
1. Build instances with prompt
2. Add parameters (temperature, tokens)
3. POST to text-bison endpoint
4. Return raw predictions
```

### 15. `fetch_drive_file`
```
1. Extract file ID from URL
2. GET file metadata
3. Check MIME type
4. If Google Workspace file:
   - Determine export format
   - GET exported content
5. Else:
   - GET raw file content
6. Apply UTF-8 encoding if text
7. Flag if needs processing (PDF/image)
8. Return metadata + content
```

### 16. `list_drive_files`
```
1. Extract folder ID from URL (optional)
2. Build query string with filters:
   - Folder parent
   - Date ranges
   - MIME type
   - Exclude trashed
3. Set page size (max 1000)
4. GET files with query
5. Process each file:
   - Extract core fields
   - Format sizes
6. Check for more pages
7. Return file array with pagination
```

### 17. `batch_fetch_drive_files`
```
1. Initialize tracking arrays
2. For each file ID:
   a. Extract ID from URL
   b. GET file metadata
   c. Conditionally fetch content
   d. Handle errors (skip or fail)
   e. Add to success/failure array
3. Calculate metrics:
   - Success rate
   - Processing time
4. Return all results with stats
```

### 18. `monitor_drive_changes`
```
1. If no page token (initial):
   - GET start token
   - Return empty changes
2. Else:
   - GET changes since token
3. Filter by folder if specified
4. Classify each change:
   - Added (new file)
   - Modified (updated)
   - Removed (deleted)
5. Build categorized arrays
6. Get new page token
7. Calculate summary counts
8. Return changes with token
```