# Iteration 2 - DRY up the Vertex connector

## Phase 1: Foundation Methods (Must Do First)
These create the base utilities that other refactors depend on.

---

### **Refactor 1: API Request Wrapper**
**Priority:** Critical - enables all other refactors
**Lines of code saved:** ~200 lines

#### Step 1.1: Add Base Request Method
**Location:** Add to `methods:` section (around line 2000)
```ruby
methods: {
  # Add this FIRST in methods section
  api_request: lambda do |connection, method, url, options = {}|
    # Build the request based on method
    request = case method.to_sym
    when :get
      if options[:params]
        get(url).params(options[:params])
      else
        get(url)
      end
    when :post
      if options[:payload]
        post(url, options[:payload])
      else
        post(url)
      end
    when :put
      put(url, options[:payload])
    when :delete
      delete(url)
    else
      error("Unsupported HTTP method: #{method}")
    end
    
    # Apply standard error handling
    request.after_error_response(/.*/) do |code, body, _header, message|
      # Check if custom error handler provided
      if options[:error_handler]
        options[:error_handler].call(code, body, message)
      else
        call('handle_vertex_error', connection, code, body, message)
      end
    end
  end,
  # ... rest of existing methods
}
```

#### Step 1.2: Update ALL Existing API Calls
**Affected Actions:** Every action making API calls (~30 locations)

**Example transformation for `fetch_drive_file`:**
```ruby
# BEFORE (line ~3100):
metadata_response = get("https://www.googleapis.com/drive/v3/files/#{file_id}").
  params(fields: 'id,name,mimeType,size,modifiedTime,md5Checksum,owners').
  after_error_response(/.*/) do |code, body, _header, message|
    error_msg = call('handle_drive_error', connection, code, body, message)
    error(error_msg)
  end

# AFTER:
metadata_response = call('api_request', connection, :get, 
  "https://www.googleapis.com/drive/v3/files/#{file_id}",
  {
    params: { fields: 'id,name,mimeType,size,modifiedTime,md5Checksum,owners' },
    error_handler: lambda do |code, body, message|
      error(call('handle_drive_error', connection, code, body, message))
    end
  })
```

#### Ripple Effects:
- Every action needs updating
- Test each action after conversion
- Some actions have special error handling that needs the `error_handler` option

---

### **Refactor 2: Drive API URL Builder**
**Priority:** High - used by all Drive actions
**Lines saved:** ~50 lines

#### Step 2.1: Add URL Builder Method
**Location:** Add to `methods:` section (after api_request)
```ruby
drive_api_url: lambda do |endpoint, file_id = nil, options = {}|
  base = 'https://www.googleapis.com/drive/v3'
  
  case endpoint.to_sym
  when :file
    "#{base}/files/#{file_id}"
  when :export
    "#{base}/files/#{file_id}/export"
  when :download
    "#{base}/files/#{file_id}?alt=media"
  when :files
    "#{base}/files"
  when :changes
    "#{base}/changes"
  when :start_token
    "#{base}/changes/startPageToken"
  else
    error("Unknown Drive API endpoint: #{endpoint}")
  end
end,
```

#### Step 2.2: Update Drive Actions
**Affected files:** fetch_drive_file, list_drive_files, batch_fetch_drive_files, monitor_drive_changes

**Example for fetch_drive_file:**
```ruby
# BEFORE:
"https://www.googleapis.com/drive/v3/files/#{file_id}"

# AFTER:
call('drive_api_url', :file, file_id)
```

---

## Phase 2: Object Definitions Consolidation

### **Refactor 3: Common Field Definitions**
**Priority:** High - reduces duplication across output schemas
**Lines saved:** ~150 lines

#### Step 3.1: Create Shared Object Definitions
**Location:** Add to `object_definitions:` section (around line 4500)
```ruby
object_definitions: {
  # Add these NEW definitions
  drive_file_fields: {
    fields: lambda do |_connection, _config_fields, _object_definitions|
      [
        { name: 'id', label: 'File ID', type: 'string',
          hint: 'Google Drive file identifier' },
        { name: 'name', label: 'File name', type: 'string',
          hint: 'Original filename in Google Drive' },
        { name: 'mime_type', label: 'MIME type', type: 'string',
          hint: 'File MIME type' },
        { name: 'size', label: 'File size', type: 'integer',
          hint: 'File size in bytes' },
        { name: 'modified_time', label: 'Modified time', type: 'date_time',
          hint: 'Last modification timestamp' },
        { name: 'checksum', label: 'MD5 checksum', type: 'string',
          hint: 'MD5 hash for change detection' }
      ]
    end
  },
  
  drive_file_extended: {
    fields: lambda do |_connection, _config_fields, object_definitions|
      object_definitions['drive_file_fields'].concat([
        { name: 'owners', label: 'File owners', type: 'array', of: 'object',
          properties: [
            { name: 'displayName', label: 'Display name', type: 'string' },
            { name: 'emailAddress', label: 'Email address', type: 'string' }
          ]
        },
        { name: 'text_content', label: 'Text content', type: 'string' },
        { name: 'needs_processing', label: 'Needs processing', type: 'boolean' },
        { name: 'export_mime_type', label: 'Export MIME type', type: 'string' },
        { name: 'fetch_method', label: 'Fetch method', type: 'string' }
      ])
    end
  },
  
  safety_and_usage: {
    fields: lambda do |_connection, _config_fields, object_definitions|
      object_definitions['safety_rating_schema'].concat(
        object_definitions['usage_schema']
      )
    end
  },
  # ... existing definitions
}
```

#### Step 3.2: Update All Output Field Definitions
**Affected actions:** fetch_drive_file, list_drive_files, batch_fetch_drive_files, etc.

**Example for fetch_drive_file:**
```ruby
# BEFORE:
output_fields: lambda do |object_definitions|
  [
    { name: 'id', label: 'File ID', type: 'string', hint: '...' },
    { name: 'name', label: 'File name', type: 'string', hint: '...' },
    # ... 10+ more repeated fields
  ]
end

# AFTER:
output_fields: lambda do |object_definitions|
  object_definitions['drive_file_extended']
end
```

#### Ripple Effects:
- All Drive actions need output_fields updated
- Some actions may need custom fields added via concat
- Test that all output datapills still appear correctly

---

## Phase 3: Core Processing Logic

### **Refactor 4: Unified File Content Fetcher**
**Priority:** Critical - eliminates major duplication
**Lines saved:** ~100 lines

#### Step 4.1: Create Unified Fetch Method
**Location:** Add to `methods:` section
```ruby
fetch_file_content: lambda do |connection, file_id, metadata, include_content = true|
  return { 
    text_content: '', 
    needs_processing: false,
    fetch_method: 'skipped',
    export_mime_type: nil 
  } unless include_content
  
  export_mime_type = call('get_export_mime_type', metadata['mimeType'])
  
  if export_mime_type.present?
    # Google Workspace file - use export
    content = call('api_request', connection, :get,
      call('drive_api_url', :export, file_id),
      { 
        params: { mimeType: export_mime_type },
        error_handler: lambda do |code, body, message|
          error(call('handle_drive_error', connection, code, body, message))
        end
      }
    )
    
    {
      text_content: content.force_encoding('UTF-8'),
      needs_processing: false,
      fetch_method: 'export',
      export_mime_type: export_mime_type
    }
  else
    # Regular file - download
    content = call('api_request', connection, :get,
      call('drive_api_url', :download, file_id),
      {
        error_handler: lambda do |code, body, message|
          error(call('handle_drive_error', connection, code, body, message))
        end
      }
    )
    
    # Determine if text or binary
    is_text = metadata['mimeType']&.start_with?('text/') ||
              ['application/json', 'application/xml'].include?(metadata['mimeType'])
    
    needs_processing = ['application/pdf', 'image/'].any? { |prefix|
      metadata['mimeType']&.start_with?(prefix)
    }
    
    {
      text_content: is_text ? content.force_encoding('UTF-8') : '',
      needs_processing: needs_processing,
      fetch_method: 'download',
      export_mime_type: nil
    }
  end
end,
```

#### Step 4.2: Refactor fetch_drive_file Action
```ruby
execute: lambda do |connection, input|
  file_id = call('extract_drive_file_id', input['file_id'])
  
  # Get metadata
  metadata = call('api_request', connection, :get,
    call('drive_api_url', :file, file_id),
    {
      params: { fields: 'id,name,mimeType,size,modifiedTime,md5Checksum,owners' },
      error_handler: lambda do |code, body, message|
        error(call('handle_drive_error', connection, code, body, message))
      end
    }
  )
  
  # Get content using unified method
  content_result = call('fetch_file_content', 
    connection, 
    file_id, 
    metadata, 
    input.fetch('include_content', true)
  )
  
  # Merge and return
  metadata.merge(content_result)
end
```

#### Step 4.3: Refactor batch_fetch_drive_files
```ruby
# Inside the loop, replace the entire content fetching logic with:
content_result = call('fetch_file_content', 
  connection, 
  file_id, 
  metadata_response, 
  include_content
)

successful_file = metadata_response.merge(content_result)
```

---

## Phase 4: Response Processing

### **Refactor 5: Unified Gemini Response Extractor**
**Priority:** Medium - used by 8+ actions
**Lines saved:** ~80 lines

#### Step 5.1: Create Unified Extractor
```ruby
extract_gemini_response: lambda do |resp, options = {}|
  # Always check finish reason
  call('check_finish_reason', resp.dig('candidates', 0, 'finishReason'))
  
  # Base response structure
  result = {
    'safety_ratings' => call('get_safety_ratings', 
      resp.dig('candidates', 0, 'safetyRatings')
    )
  }
  
  # Add usage if present
  if resp['usageMetadata']
    result['usage'] = resp['usageMetadata']
    result['prompt_tokens'] = resp.dig('usageMetadata', 'promptTokenCount') || 0
    result['response_tokens'] = resp.dig('usageMetadata', 'candidatesTokenCount') || 0
    result['total_tokens'] = resp.dig('usageMetadata', 'totalTokenCount') || 0
  end
  
  # Extract content based on type
  if options[:extract_json]
    json = call('extract_json', resp)
    if options[:json_key]
      result['answer'] = json[options[:json_key]]
    else
      result.merge!(json)
    end
  else
    result['answer'] = resp&.dig('candidates', 0, 'content', 'parts', 0, 'text')
  end
  
  # Add recipe-friendly fields if requested
  if options[:add_recipe_fields]
    has_answer = result['answer'].present? && 
                 result['answer'].to_s.strip != 'N/A'
    result.merge!({
      'has_answer' => has_answer,
      'pass_fail' => has_answer,
      'action_required' => has_answer ? 'use_answer' : 'try_different_approach',
      'answer_length' => result['answer'].to_s.length
    })
  end
  
  result
end,
```

#### Step 5.2: Update All Extract Methods
```ruby
# BEFORE (in translate_text action):
extract_generic_response: lambda do |resp, is_json_response|
  call('check_finish_reason', resp.dig('candidates', 0, 'finishReason'))
  ratings = call('get_safety_ratings', resp.dig('candidates', 0, 'safetyRatings'))
  # ... more code
end

# AFTER:
# In translate_text execute:
response = call('extract_gemini_response', response, {
  extract_json: true,
  json_key: 'response',
  add_recipe_fields: true
})
```

---

## Phase 5: Rate Limiting Wrapper

### **Refactor 6: Unified Rate-Limited Request Handler**
**Priority:** Medium
**Lines saved:** ~60 lines

#### Step 6.1: Create Wrapper Method
```ruby
rate_limited_ai_request: lambda do |connection, model, action_type, url, payload|
  # Apply rate limiting
  rate_limit_info = call('enforce_vertex_rate_limits', connection, model, action_type)
  
  # Make request with 429 handling
  response = call('handle_429_with_backoff', connection, action_type, model) do
    call('api_request', connection, :post, url, { payload: payload })
  end
  
  # Add rate limit info if response is a hash
  if response.is_a?(Hash)
    response['rate_limit_status'] = rate_limit_info
  end
  
  response
end,
```

#### Step 6.2: Update All AI Actions
```ruby
# BEFORE (in send_messages):
rate_limit_info = call('enforce_vertex_rate_limits', connection, input['model'], 'inference')
response = call('handle_429_with_backoff', connection, 'inference', input['model']) do
  post(url, payload).after_error_response(/.*/) do |code, body, _header, message|
    call('handle_vertex_error', connection, code, body, message)
  end
end
response['rate_limit_status'] = rate_limit_info

# AFTER:
response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
```

---

## Implememntation Details

### Implementation Schedule

**Week 1: Foundation**
- Day 1-2: Implement api_request wrapper (Refactor 1)
- Day 3: Test all converted actions
- Day 4-5: Add URL builders and shared field definitions (Refactors 2 & 3)

**Week 2: Core Logic**
- Day 1-2: Implement fetch_file_content (Refactor 4)
- Day 3: Update fetch_drive_file and batch_fetch_drive_files
- Day 4-5: Implement unified extractors (Refactor 5)

**Week 3: Final Optimizations**
- Day 1-2: Rate limiting wrapper (Refactor 6)
- Day 3-4: Final testing of all actions
- Day 5: Documentation and cleanup

### Testing Strategy

After each refactor:
1. Test the specific action(s) modified
2. Run integration tests for dependent actions
3. Verify output schema still matches expected datapills
4. Check error handling still works correctly
5. Validate rate limiting still functions

### Rollback Plan

Keep original code commented until all refactors complete:
```ruby
# TODO: Remove after DRY refactor verified
# Original code:
# get("https://...").params(...).after_error_response...
```

--- 
