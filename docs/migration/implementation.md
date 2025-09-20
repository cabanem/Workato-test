# Google Drive Integration Modifications

## **Vertex AI Connector Modifications**

### **Action 1: Add Drive Scope to OAuth2 Authorization**
```ruby
# FIND this section in connection fields (around line 100-120):
authorization_url: lambda do |connection|
  scopes = [
    'https://www.googleapis.com/auth/cloud-platform'
  ].join(' ')

# REPLACE with:
authorization_url: lambda do |connection|
  scopes = [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/drive.readonly'
  ].join(' ')
  
  # Keep the rest of the authorization_url lambda unchanged
```

### **Action 2: Add Drive Helper Methods**
```ruby
# In the methods section (after line ~2000, after existing helper methods)
# ADD these new methods:

# Extract file ID from various Drive URL formats
extract_drive_file_id: lambda do |input|
  return input if input.nil? || input.empty?
  
  # Handle various Google Drive URL formats
  patterns = [
    %r{/d/([a-zA-Z0-9-_]+)},           # /d/{id}
    %r{id=([a-zA-Z0-9-_]+)},           # ?id={id}
    %r{^([a-zA-Z0-9-_]+)$}             # Raw ID
  ]
  
  patterns.each do |pattern|
    match = input.match(pattern)
    return match[1] if match
  end
  
  input # Return as-is if no pattern matches
end,

# Determine export MIME type for Google Workspace files
get_export_mime_type: lambda do |google_mime_type, requested_format|
  # Google Workspace MIME types that need export
  workspace_types = {
    'application/vnd.google-apps.document' => 'text/plain',
    'application/vnd.google-apps.spreadsheet' => 'text/csv',
    'application/vnd.google-apps.presentation' => 'text/plain',
    'application/vnd.google-apps.drawing' => 'image/png'
  }
  
  if workspace_types.key?(google_mime_type)
    requested_format == 'original' ? workspace_types[google_mime_type] : requested_format
  else
    nil # Regular files don't need export
  end
end,

# Build Drive API query string from filters
build_drive_query: lambda do |filters|
  queries = ['trashed = false']
  
  if filters['folder_id'].present?
    queries << "'#{filters['folder_id']}' in parents"
  end
  
  if filters['modified_after'].present?
    # Ensure ISO 8601 format
    time = filters['modified_after'].to_s.include?('T') ? 
           filters['modified_after'] : 
           "#{filters['modified_after']}T00:00:00Z"
    queries << "modifiedTime > '#{time}'"
  end
  
  if filters['mime_types'].present? && filters['mime_types'].any?
    mime_conditions = filters['mime_types'].map { |mt| "mimeType='#{mt}'" }.join(' or ')
    queries << "(#{mime_conditions})"
  end
  
  queries.join(' and ')
end,

# Handle Drive-specific errors with helpful messages
handle_drive_error: lambda do |connection, code, body, message|
  error_detail = begin
    parsed = parse_json(body)
    parsed.dig('error', 'message') || parsed['message'] || body
  rescue
    body
  end
  
  case code
  when 404
    error("File not found. Verify the file ID and ensure it hasn't been deleted.\nID attempted: #{message}")
  when 403
    if error_detail.include?('insufficientPermissions')
      error("Permission denied. The file needs to be shared with the service account email: #{connection['service_account_email']}")
    else
      error("Access forbidden. This might be due to: 1) File not shared with service account, 2) Drive API not enabled, or 3) OAuth scope missing")
    end
  when 429
    error("Rate limit exceeded. Implement exponential backoff or reduce request frequency.")
  else
    call('handle_vertex_error', connection, code, body, message)
  end
end,
```

### **Action 3: Implement fetch_drive_file Action**
```ruby
# ADD this new action after existing actions (around line 1500):

fetch_drive_file: {
  title: 'Fetch Drive file',
  subtitle: 'Retrieve and extract text from Google Drive',
  description: lambda do |input|
    file_id = input['file_id']
    if file_id.present?
      "Fetch file <span class='provider'>#{file_id}</span> from Google Drive"
    else
      'Fetch a file from <span class=\'provider\'>Google Drive</span>'
    end
  end,
  
  help: {
    body: 'Fetches a file from Google Drive and extracts text content. Handles both Google Workspace files (Docs, Sheets) and regular files.',
    learn_more_url: 'https://developers.google.com/drive/api/v3/reference/files/get',
    learn_more_text: 'Google Drive API documentation'
  },
  
  input_fields: lambda do
    [
      {
        name: 'file_id',
        label: 'File ID or URL',
        type: 'string',
        optional: false,
        hint: 'Google Drive file ID or sharing URL'
      },
      {
        name: 'export_format',
        label: 'Export format',
        type: 'string',
        control_type: 'select',
        pick_list: [
          ['Plain text', 'text/plain'],
          ['Original format', 'original']
        ],
        default: 'text/plain',
        optional: true,
        hint: 'Format for text extraction from Google Workspace files'
      }
    ]
  end,
  
  output_fields: lambda do
    [
      { name: 'file_id', type: 'string' },
      { name: 'file_name', type: 'string' },
      { name: 'mime_type', type: 'string' },
      { name: 'text_content', type: 'string' },
      { name: 'checksum', type: 'string', hint: 'MD5 checksum for change detection' },
      { name: 'modified_time', type: 'datetime' },
      { name: 'size', type: 'integer' },
      { name: 'owner', type: 'string' },
      { name: 'needs_processing', type: 'boolean', hint: 'True if file needs OCR or conversion' }
    ]
  end,
  
  execute: lambda do |connection, input|
    file_id = call('extract_drive_file_id', input['file_id'])
    
    # Step 1: Get file metadata
    metadata_url = "https://www.googleapis.com/drive/v3/files/#{file_id}"
    metadata_params = {
      fields: 'id,name,mimeType,size,modifiedTime,md5Checksum,owners'
    }
    
    metadata_response = get(metadata_url).params(metadata_params).
      after_error_response(/.*/) do |code, body, _header, message|
        call('handle_drive_error', connection, code, body, file_id)
      end
    
    mime_type = metadata_response['mimeType']
    export_mime = call('get_export_mime_type', mime_type, input['export_format'])
    
    # Step 2: Fetch file content
    content = if export_mime
      # Google Workspace file - use export
      export_url = "https://www.googleapis.com/drive/v3/files/#{file_id}/export"
      export_response = get(export_url).params(mimeType: export_mime).
        after_error_response(/.*/) do |code, body, _header, message|
          call('handle_drive_error', connection, code, body, file_id)
        end
      
      # Force UTF-8 encoding
      export_response.force_encoding('UTF-8')
    else
      # Regular file - download directly
      download_url = "https://www.googleapis.com/drive/v3/files/#{file_id}?alt=media"
      download_response = get(download_url).
        after_error_response(/.*/) do |code, body, _header, message|
          call('handle_drive_error', connection, code, body, file_id)
        end
      
      # Check if it's a text file we can process
      if mime_type.start_with?('text/')
        download_response.force_encoding('UTF-8')
      else
        # Binary file - flag for external processing
        nil
      end
    end
    
    {
      'file_id' => file_id,
      'file_name' => metadata_response['name'],
      'mime_type' => mime_type,
      'text_content' => content || '',
      'checksum' => metadata_response['md5Checksum'],
      'modified_time' => metadata_response['modifiedTime'],
      'size' => metadata_response['size'].to_i,
      'owner' => metadata_response.dig('owners', 0, 'emailAddress'),
      'needs_processing' => content.nil? && !mime_type.start_with?('text/')
    }
  end
},
```

### **Action 4: Implement list_drive_files Action**
```ruby
# ADD after fetch_drive_file action:

list_drive_files: {
  title: 'List Drive files',
  subtitle: 'List and filter files from Google Drive',
  description: 'Retrieve a filtered list of files from Google Drive folders',
  
  help: {
    body: 'Lists files from Google Drive with optional filtering by folder, date, and MIME type.',
    learn_more_url: 'https://developers.google.com/drive/api/v3/reference/files/list',
    learn_more_text: 'Files: list API'
  },
  
  input_fields: lambda do
    [
      {
        name: 'folder_id',
        label: 'Folder ID',
        type: 'string',
        optional: true,
        hint: 'Leave blank for root folder. Use folder ID or URL.'
      },
      {
        name: 'modified_after',
        label: 'Modified after',
        type: 'datetime',
        optional: true,
        hint: 'Filter files modified after this date/time'
      },
      {
        name: 'mime_types',
        label: 'MIME types',
        type: 'array',
        of: 'string',
        optional: true,
        list_mode_toggle: true,
        hint: 'Filter by specific MIME types (e.g., application/pdf)'
      },
      {
        name: 'max_results',
        label: 'Maximum results',
        type: 'integer',
        default: 100,
        optional: true,
        hint: 'Maximum number of files to return (1-1000)'
      }
    ]
  end,
  
  output_fields: lambda do
    [
      {
        name: 'files',
        type: 'array',
        of: 'object',
        properties: [
          { name: 'id', type: 'string' },
          { name: 'name', type: 'string' },
          { name: 'mimeType', type: 'string' },
          { name: 'size', type: 'integer' },
          { name: 'modifiedTime', type: 'datetime' },
          { name: 'md5Checksum', type: 'string' }
        ]
      },
      { name: 'count', type: 'integer' },
      { name: 'has_more', type: 'boolean' },
      { name: 'next_page_token', type: 'string' }
    ]
  end,
  
  execute: lambda do |connection, input|
    # Extract folder ID if URL provided
    folder_id = input['folder_id'] ? call('extract_drive_file_id', input['folder_id']) : nil
    
    # Build query
    query = call('build_drive_query', {
      'folder_id' => folder_id,
      'modified_after' => input['modified_after'],
      'mime_types' => input['mime_types']
    })
    
    # Make request
    list_url = "https://www.googleapis.com/drive/v3/files"
    list_params = {
      q: query,
      pageSize: [input['max_results'] || 100, 1000].min,
      fields: 'nextPageToken,files(id,name,mimeType,size,modifiedTime,md5Checksum)',
      orderBy: 'modifiedTime desc'
    }
    
    response = get(list_url).params(list_params).
      after_error_response(/.*/) do |code, body, _header, message|
        call('handle_drive_error', connection, code, body, message)
      end
    
    files = response['files'] || []
    
    {
      'files' => files,
      'count' => files.length,
      'has_more' => response['nextPageToken'].present?,
      'next_page_token' => response['nextPageToken']
    }
  end
},
```

### **Action 5: Implement batch_fetch_drive_files Action**
```ruby
# ADD after list_drive_files action:

batch_fetch_drive_files: {
  title: 'Batch fetch Drive files',
  subtitle: 'Fetch multiple files in one action',
  description: 'Efficiently fetch multiple Drive files with error handling',
  
  help: {
    body: 'Fetches multiple files from Google Drive in a single action. Handles individual file errors gracefully.',
    learn_more_url: 'https://developers.google.com/drive/api/v3/batch',
    learn_more_text: 'Batch requests'
  },
  
  input_fields: lambda do
    [
      {
        name: 'file_ids',
        label: 'File IDs',
        type: 'array',
        of: 'string',
        optional: false,
        list_mode_toggle: true,
        hint: 'Array of file IDs or URLs to fetch'
      },
      {
        name: 'skip_errors',
        label: 'Skip errors',
        type: 'boolean',
        control_type: 'checkbox',
        default: true,
        optional: true,
        hint: 'Continue processing if individual files fail'
      },
      {
        name: 'export_format',
        label: 'Export format',
        type: 'string',
        control_type: 'select',
        pick_list: [
          ['Plain text', 'text/plain'],
          ['Original format', 'original']
        ],
        default: 'text/plain',
        optional: true
      }
    ]
  end,
  
  output_fields: lambda do
    [
      {
        name: 'successful_files',
        type: 'array',
        of: 'object',
        properties: [
          { name: 'file_id', type: 'string' },
          { name: 'file_name', type: 'string' },
          { name: 'text_content', type: 'string' },
          { name: 'checksum', type: 'string' }
        ]
      },
      {
        name: 'failed_files',
        type: 'array',
        of: 'object',
        properties: [
          { name: 'file_id', type: 'string' },
          { name: 'error', type: 'string' }
        ]
      },
      { name: 'total_processed', type: 'integer' },
      { name: 'success_count', type: 'integer' },
      { name: 'failure_count', type: 'integer' },
      { name: 'success_rate', type: 'number' },
      { name: 'processing_time_ms', type: 'integer' }
    ]
  end,
  
  execute: lambda do |connection, input|
    start_time = Time.now
    successful_files = []
    failed_files = []
    
    input['file_ids'].each do |file_id_input|
      begin
        file_id = call('extract_drive_file_id', file_id_input)
        
        # Use existing fetch_drive_file logic
        result = call('fetch_drive_file', connection, {
          'file_id' => file_id,
          'export_format' => input['export_format']
        })
        
        successful_files << {
          'file_id' => result['file_id'],
          'file_name' => result['file_name'],
          'text_content' => result['text_content'],
          'checksum' => result['checksum']
        }
        
      rescue => e
        if input['skip_errors']
          failed_files << {
            'file_id' => file_id_input,
            'error' => e.message
          }
        else
          # Fail fast
          error("Failed to fetch file #{file_id_input}: #{e.message}")
        end
      end
    end
    
    total = input['file_ids'].length
    success_count = successful_files.length
    
    {
      'successful_files' => successful_files,
      'failed_files' => failed_files,
      'total_processed' => total,
      'success_count' => success_count,
      'failure_count' => failed_files.length,
      'success_rate' => total > 0 ? (success_count.to_f / total * 100).round(2) : 0,
      'processing_time_ms' => ((Time.now - start_time) * 1000).to_i
    }
  end
},
```

### **Action 6: Enhance test_connection for Drive**
```ruby
# FIND the test lambda in connection (around line 300):
test: lambda do |connection|

# REPLACE the entire test block with:
test: lambda do |connection|
  results = {
    'vertex_ai' => 'unknown',
    'google_drive' => 'unknown',
    'errors' => []
  }
  
  # Test Vertex AI
  begin
    get("projects/#{connection['project']}/locations/#{connection['region']}/datasets").
      params(pageSize: 1).
      after_error_response(/.*/) do |code, body, _header, message|
        call('handle_vertex_error', connection, code, body, message)
      end
    results['vertex_ai'] = 'connected'
  rescue => e
    results['vertex_ai'] = 'failed'
    results['errors'] << "Vertex AI: #{e.message}"
  end
  
  # Test Google Drive (only for OAuth2)
  if connection['auth_type'] == 'oauth2'
    begin
      # Try to list one file to verify access
      response = get("https://www.googleapis.com/drive/v3/files").
        params(pageSize: 1, q: 'trashed = false').
        after_error_response(/.*/) do |code, body, _header, message|
          case code
          when 403
            error("Drive API access denied. Ensure Drive API is enabled and OAuth includes Drive scope.")
          else
            call('handle_drive_error', connection, code, body, message)
          end
        end
      
      results['google_drive'] = 'connected'
      results['drive_files_found'] = (response['files'] || []).length
      
    rescue => e
      results['google_drive'] = 'failed'
      results['errors'] << "Google Drive: #{e.message}"
    end
  else
    results['google_drive'] = 'not_configured'
  end
  
  # Overall status
  if results['errors'].empty?
    results['status'] = 'All connections successful'
  else
    results['status'] = "Some connections failed: #{results['errors'].join('; ')}"
  end
  
  results
end
```

## **RAG_Utils Connector Modifications**

### **Action 7: Add Document Processing Helper Methods**
```ruby
# In the methods section (after existing helpers, around line 1600)
# ADD these new methods:

generate_document_id: lambda do |file_path, checksum|
  # Create stable document ID from file path and checksum
  Digest::SHA256.hexdigest("#{file_path}|#{checksum}")
end,

calculate_chunk_boundaries: lambda do |text, chunk_size, overlap|
  # Smart boundary calculation preserving sentences
  boundaries = []
  position = 0
  text_length = text.length
  chars_per_chunk = chunk_size * 4  # Rough token to char conversion
  
  while position < text_length
    chunk_end = [position + chars_per_chunk, text_length].min
    
    # Try to end at sentence boundary
    if chunk_end < text_length
      sentence_end = text.rindex(/[.!?]\s/, chunk_end)
      chunk_end = sentence_end + 1 if sentence_end && sentence_end > position
    end
    
    boundaries << { start: position, end: chunk_end }
    position = chunk_end - (overlap * 4)  # Apply overlap
    break if position >= text_length
  end
  
  boundaries
end,

merge_document_metadata: lambda do |chunk_metadata, document_metadata|
  # Merge document-level metadata into each chunk
  chunk_metadata.merge({
    'document_id' => document_metadata['document_id'],
    'file_name' => document_metadata['file_name'],
    'file_id' => document_metadata['file_id'],
    'source' => 'google_drive',
    'indexed_at' => Time.now.iso8601
  })
end,
```

### **Action 8: Create process_document_for_rag Action**
```ruby
# ADD this new action after existing actions (around line 1100):

process_document_for_rag: {
  title: 'Process document for RAG',
  subtitle: 'Complete document processing pipeline',
  description: 'Process Drive document through complete RAG preparation pipeline',
  
  help: {
    body: 'Takes raw document content and produces chunks ready for embedding generation.',
    learn_more_url: 'https://docs.workato.com/developing-connectors/sdk/guides/best-practices.html',
    learn_more_text: 'Best practices'
  },
  
  input_fields: lambda do |object_definitions|
    [
      {
        name: 'document_content',
        label: 'Document content',
        type: 'string',
        control_type: 'text-area',
        optional: false,
        hint: 'Raw text content from Drive file'
      },
      {
        name: 'file_metadata',
        label: 'File metadata',
        type: 'object',
        optional: false,
        properties: [
          { name: 'file_id', type: 'string', optional: false },
          { name: 'file_name', type: 'string', optional: false },
          { name: 'checksum', type: 'string', optional: false },
          { name: 'mime_type', type: 'string' }
        ]
      },
      {
        name: 'chunk_size',
        label: 'Chunk size (tokens)',
        type: 'integer',
        default: 1000,
        optional: true
      },
      {
        name: 'chunk_overlap',
        label: 'Chunk overlap (tokens)',
        type: 'integer',
        default: 100,
        optional: true
      }
    ]
  end,
  
  output_fields: lambda do |object_definitions|
    [
      { name: 'document_id', type: 'string' },
      {
        name: 'chunks',
        type: 'array',
        of: 'object',
        properties: [
          { name: 'chunk_id', type: 'string' },
          { name: 'chunk_index', type: 'integer' },
          { name: 'text', type: 'string' },
          { name: 'token_count', type: 'integer' },
          { name: 'metadata', type: 'object' }
        ]
      },
      {
        name: 'document_metadata',
        type: 'object',
        properties: [
          { name: 'total_chunks', type: 'integer' },
          { name: 'total_tokens', type: 'integer' },
          { name: 'processing_timestamp', type: 'datetime' }
        ]
      },
      { name: 'ready_for_embedding', type: 'boolean' }
    ]
  end,
  
  execute: lambda do |connection, input|
    # Generate document ID
    document_id = call('generate_document_id', 
                      input.dig('file_metadata', 'file_name'),
                      input.dig('file_metadata', 'checksum'))
    
    # Chunk the document
    chunk_result = call('chunk_text_with_overlap', {
      'text' => input['document_content'],
      'chunk_size' => input['chunk_size'] || 1000,
      'chunk_overlap' => input['chunk_overlap'] || 100,
      'preserve_sentences' => true
    })
    
    # Enhance chunks with document metadata
    enhanced_chunks = chunk_result['chunks'].map do |chunk|
      chunk['metadata'] = call('merge_document_metadata', 
                               chunk['metadata'] || {},
                               input['file_metadata'])
      chunk['chunk_id'] = "#{document_id}_chunk_#{chunk['chunk_index']}"
      chunk
    end
    
    {
      'document_id' => document_id,
      'chunks' => enhanced_chunks,
      'document_metadata' => {
        'total_chunks' => chunk_result['total_chunks'],
        'total_tokens' => chunk_result['total_tokens'],
        'processing_timestamp' => Time.now.iso8601
      },
      'ready_for_embedding' => true
    }
  end
},
```

### **Action 9: Create prepare_document_batch Action**
```ruby
# ADD after process_document_for_rag:

prepare_document_batch: {
  title: 'Prepare document batch',
  subtitle: 'Process multiple documents for batch embedding',
  description: 'Prepare multiple documents for efficient batch processing',
  
  input_fields: lambda do
    [
      {
        name: 'documents',
        label: 'Documents',
        type: 'array',
        of: 'object',
        optional: false,
        list_mode_toggle: true,
        properties: [
          { name: 'content', type: 'string', optional: false },
          { name: 'file_id', type: 'string', optional: false },
          { name: 'file_name', type: 'string', optional: false },
          { name: 'checksum', type: 'string', optional: false }
        ]
      },
      {
        name: 'batch_size',
        label: 'Batch size',
        type: 'integer',
        default: 25,
        optional: true,
        hint: 'Number of chunks per embedding batch'
      },
      {
        name: 'chunk_size',
        label: 'Chunk size',
        type: 'integer',
        default: 1000,
        optional: true
      }
    ]
  end,
  
  output_fields: lambda do
    [
      {
        name: 'batches',
        type: 'array',
        of: 'object',
        properties: [
          { name: 'batch_id', type: 'string' },
          { name: 'chunks', type: 'array', of: 'object' },
          { name: 'document_count', type: 'integer' }
        ]
      },
      { name: 'total_chunks', type: 'integer' },
      { name: 'total_documents', type: 'integer' }
    ]
  end,
  
  execute: lambda do |connection, input|
    all_chunks = []
    
    # Process each document
    input['documents'].each do |doc|
      result = call('process_document_for_rag', connection, {
        'document_content' => doc['content'],
        'file_metadata' => {
          'file_id' => doc['file_id'],
          'file_name' => doc['file_name'],
          'checksum' => doc['checksum']
        },
        'chunk_size' => input['chunk_size']
      })
      
      all_chunks.concat(result['chunks'])
    end
    
    # Group into batches
    batches = []
    batch_size = input['batch_size'] || 25
    
    all_chunks.each_slice(batch_size).with_index do |batch_chunks, index|
      batch_id = "batch_#{Time.now.to_i}_#{index}"
      batches << {
        'batch_id' => batch_id,
        'chunks' => batch_chunks,
        'document_count' => batch_chunks.map { |c| c.dig('metadata', 'document_id') }.uniq.length
      }
    end
    
    {
      'batches' => batches,
      'total_chunks' => all_chunks.length,
      'total_documents' => input['documents'].length
    }
  end
},
```

### **Action 10: Update smart_chunk_text to Include Document Metadata**
```ruby
# FIND smart_chunk_text action (around line 200):
# In the output handling of execute block, ADD:

execute: lambda do |connection, input, _eis, _eos, config|
  # ... existing chunking logic ...
  
  result = call(:chunk_text_with_overlap, input)
  
  # ADD: Enhance with document metadata if provided
  if input['document_metadata'].present?
    result['chunks'].each_with_index do |chunk, idx|
      chunk['metadata'] ||= {}
      chunk['metadata'].merge!({
        'document_id' => input['document_metadata']['document_id'],
        'file_name' => input['document_metadata']['file_name'],
        'total_chunks' => result['total_chunks']
      })
    end
  end
  
  call(:validate_contract, connection, result, 'chunking_result')
end
```

## **Integration Test Recipe Structure**

After implementing all modifications, create this test recipe:

```yaml
Test Recipe: Drive Document Processing Pipeline

1. Vertex::list_drive_files
   - folder_id: [test_folder_id]
   - modified_after: [yesterday]
   - Output: files[]

2. Loop: For each file in files
   
   3. Vertex::fetch_drive_file
      - file_id: [file.id]
      - export_format: text/plain
      - Output: text_content, file_metadata
   
   4. RAG_Utils::process_document_for_rag
      - document_content: [text_content]
      - file_metadata: [from step 3]
      - Output: chunks[], document_id
   
   5. RAG_Utils::prepare_embedding_batch
      - texts: [chunks from step 4]
      - batch_size: 25
      - Output: batches[]
   
   6. Loop: For each batch
      
      7. Vertex::generate_embeddings
         - batch_id: [batch.batch_id]
         - texts: [batch.chunks]
         - model: text-embedding-004
         - Output: embeddings[]
      
      8. Vertex::upsert_index_datapoints
         - datapoints: [embeddings]
         - index_id: [your_index_id]
```

## **Verification Checklist**

After completing all actions:

□ OAuth2 includes Drive scope  
□ Drive helper methods added to Vertex  
□ fetch_drive_file action works  
□ list_drive_files action works  
□ batch_fetch_drive_files handles errors correctly  
□ test_connection validates both APIs  
□ process_document_for_rag generates proper chunks  
□ prepare_document_batch handles multiple documents  
□ Document metadata flows through entire pipeline  
□ End-to-end test recipe runs successfully  
□ Checksums enable change detection  
□ Error messages are helpful and actionable
