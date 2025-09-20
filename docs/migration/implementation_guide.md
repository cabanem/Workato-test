# Google Drive Integration Implementation Guide

## Overview
This document provides step-by-step implementation instructions for adding Google Drive capabilities to the Vertex AI and RAG_Utils connectors for document processing in the RAG Email Response System.

---

## Part 1: Vertex AI Connector - OAuth2 & Helper Methods

### Task 1: Add Drive Scope to OAuth2
**Location:** Connection authorization section (~line 100-120)  
**Action:** Extend OAuth2 scopes

**Implementation Prompt:**
```
In the Vertex AI connector, find the authorization_url lambda in the oauth2 section.
Current state shows only: 'https://www.googleapis.com/auth/cloud-platform'

Add the Drive scope to make it:
scopes = [
  'https://www.googleapis.com/auth/cloud-platform',
  'https://www.googleapis.com/auth/drive.readonly'
].join(' ')

IMPORTANT: Users will need to re-authenticate after this change.
```

### Task 2: Add Drive Helper Methods
**Location:** Methods section (~line 2000)  
**Action:** Add utility methods

**Implementation Prompt:**
```
Add four new helper methods to the Vertex connector methods section:

1. extract_drive_file_id: Parse file IDs from various URL formats
   - Handle: /d/{id}, ?id={id}, or raw ID
   - Use regex patterns for extraction
   - Return standardized ID

2. get_export_mime_type: Map Google Workspace types
   - Google Docs → text/plain
   - Google Sheets → text/csv
   - Google Slides → text/plain
   - Return nil for regular files

3. build_drive_query: Construct API query strings
   - Always include 'trashed = false'
   - Add folder, date, and MIME filters as needed
   - Join with ' and '

4. handle_drive_error: Provide actionable error messages
   - 404: "File not found, verify ID"
   - 403: "Share with service account: {email}"
   - 429: "Rate limited, implement backoff"
```

---

## Part 2: Vertex AI Connector - Drive Actions

### Task 3: Implement fetch_drive_file
**Location:** After existing actions (~line 1500)  
**Action:** Create core file fetching action

**Implementation Prompt:**
```
Create 'fetch_drive_file' action that:

Step 1 - Get metadata:
- URL: https://www.googleapis.com/drive/v3/files/{file_id}
- Fields: id,name,mimeType,size,modifiedTime,md5Checksum,owners
- Use handle_drive_error for error handling

Step 2 - Determine fetch method:
- If Google Workspace file: use export endpoint
- If regular file: use download endpoint
- Check MIME type with get_export_mime_type helper

Step 3 - Fetch content:
- Export URL: /files/{id}/export?mimeType={export_type}
- Download URL: /files/{id}?alt=media
- Force UTF-8 encoding on text content

Output all metadata plus:
- text_content (empty if binary)
- needs_processing (true for PDFs, images)
- checksum for change detection
```

### Task 4: Implement list_drive_files
**Location:** After fetch_drive_file action  
**Action:** Create file listing capability

**Implementation Prompt:**
```
Create 'list_drive_files' action:

Input processing:
- Extract folder_id using extract_drive_file_id helper
- Convert modified_after to ISO 8601 format
- Build query with build_drive_query helper

API request:
- URL: https://www.googleapis.com/drive/v3/files
- Parameters:
  - q: constructed query string
  - pageSize: min(max_results, 1000)
  - fields: nextPageToken,files(id,name,mimeType,size,modifiedTime,md5Checksum)
  - orderBy: 'modifiedTime desc'

Output structure:
- files: array of file objects
- count: files.length
- has_more: check nextPageToken presence
- next_page_token: for pagination
```

### Task 5: Implement batch_fetch_drive_files
**Location:** After list_drive_files action  
**Action:** Create batch processing capability

**Implementation Prompt:**
```
Create 'batch_fetch_drive_files' action for multiple files:

Processing logic:
1. Initialize tracking arrays (successful_files, failed_files)
2. For each file_id in input:
   - Extract ID using helper
   - Call fetch_drive_file (reuse existing logic)
   - Track success/failure
   - If skip_errors=false, fail fast on first error

Error handling:
- Wrap each file in try/catch
- Capture error message and file_id
- Continue or fail based on skip_errors flag

Metrics to track:
- total_processed
- success_count and failure_count
- success_rate as percentage
- processing_time_ms

Return both successful content and failure details.
```

### Task 6: Enhance Connection Test
**Location:** Connection test lambda (~line 300)  
**Action:** Add Drive validation

**Implementation Prompt:**
```
Modify the test lambda to validate both APIs:

Structure:
results = {
  'vertex_ai' => 'unknown',
  'google_drive' => 'unknown',
  'errors' => []
}

Vertex AI test (keep existing):
- Try listing datasets
- Set status to 'connected' or 'failed'

Google Drive test (add new):
- Only run if auth_type == 'oauth2'
- Try: GET /drive/v3/files?pageSize=1
- Check for 403 (API not enabled)
- Count files found
- Set status: connected/failed/not_configured

Return combined results with actionable error messages.
```

---

## Part 3: RAG_Utils Connector - Document Processing

### Task 7: Add Document Helper Methods
**Location:** Methods section (~line 1600)  
**Action:** Add document utilities

**Implementation Prompt:**
```
Add three document processing helpers to RAG_Utils:

1. generate_document_id:
   - Input: file_path and checksum
   - Use SHA256 hash of "path|checksum"
   - Return stable document ID

2. calculate_chunk_boundaries:
   - Smart boundary detection
   - Prefer sentence endings ([.!?]\s)
   - Apply overlap in characters (tokens * 4)
   - Return array of {start, end} positions

3. merge_document_metadata:
   - Combine chunk and document metadata
   - Add: document_id, file_name, file_id
   - Add: source='google_drive', indexed_at timestamp
   - Return merged hash
```

### Task 8: Create process_document_for_rag
**Location:** After existing actions (~line 1100)  
**Action:** Complete processing pipeline

**Implementation Prompt:**
```
Create 'process_document_for_rag' action:

Input structure:
- document_content (raw text)
- file_metadata object (file_id, file_name, checksum, mime_type)
- chunk_size (default 1000)
- chunk_overlap (default 100)

Processing steps:
1. Generate document_id using helper
2. Call chunk_text_with_overlap
3. For each chunk:
   - Generate chunk_id: "{doc_id}_chunk_{index}"
   - Merge metadata using helper
   - Add to enhanced_chunks array

Output:
- document_id
- chunks array with full metadata
- document_metadata (totals and timestamp)
- ready_for_embedding: true
```

### Task 9: Create prepare_document_batch
**Location:** After process_document_for_rag  
**Action:** Batch document processor

**Implementation Prompt:**
```
Create 'prepare_document_batch' for multiple documents:

Processing flow:
1. For each document in input:
   - Call process_document_for_rag
   - Collect all chunks
2. Group chunks into batches (default 25)
3. Generate batch_id with timestamp

Batch structure:
- batch_id: "batch_{timestamp}_{index}"
- chunks: array of chunk objects
- document_count: unique document IDs in batch

Output summary:
- batches array
- total_chunks across all documents
- total_documents processed
```

### Task 10: Enhance smart_chunk_text
**Location:** smart_chunk_text execute block (~line 200)  
**Action:** Add document awareness

**Implementation Prompt:**
```
Modify smart_chunk_text to accept document metadata:

In execute block, after getting chunk result:
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

This maintains backward compatibility while enabling document tracking.
```

---

## Part 4: Integration Testing

### Task 11: Create End-to-End Test Recipe
**Recipe Name:** Test_Drive_Document_Pipeline

**Implementation Prompt:**
```
Create a comprehensive test recipe:

Trigger: Manual with test folder_id

Steps:
1. Vertex::list_drive_files
   - Input: folder_id, modified_after=yesterday
   - Log: file count and names

2. Vertex::fetch_drive_file (single file test)
   - Input: first file from list
   - Verify: text_content extracted
   - Log: checksum and metadata

3. RAG_Utils::process_document_for_rag
   - Input: content from step 2
   - Verify: chunks created with metadata
   - Log: chunk count and IDs

4. Vertex::batch_fetch_drive_files (batch test)
   - Input: first 3 files from list
   - Verify: success rate > 0
   - Log: failures if any

5. RAG_Utils::prepare_document_batch
   - Input: successful files from step 4
   - Verify: batches created
   - Log: batch distribution

Success criteria:
- All steps complete without error
- Text extracted from at least one file
- Chunks have document metadata
- Batch processing handles errors gracefully
```

### Task 12: Create Change Detection Test
**Recipe Name:** Test_Drive_Change_Detection

**Implementation Prompt:**
```
Test incremental update capability:

1. Initial run:
   - Fetch file and store checksum
   - Process document
   - Store document_id

2. Modify file in Drive

3. Second run:
   - Fetch same file
   - Compare checksums
   - Verify: different checksum detected
   - Reprocess if changed

4. Third run (no change):
   - Fetch same file
   - Compare checksums
   - Verify: same checksum, skip processing

Log all checksum comparisons and processing decisions.
```

---

## Part 5: Error Handling & Edge Cases

### Task 13: Test Error Scenarios
**Test Name:** Drive_Error_Handling_Test

**Implementation Prompt:**
```
Create tests for common error scenarios:

Test cases:
1. Invalid file ID:
   - Input: "invalid_id_12345"
   - Expected: 404 error with helpful message

2. File not shared:
   - Create private file
   - Expected: 403 error with sharing instructions

3. Binary file (PDF):
   - Fetch PDF file
   - Expected: needs_processing=true, empty text_content

4. Large file:
   - File > 10MB
   - Expected: Successful but check timing

5. Empty folder:
   - List empty folder
   - Expected: Empty array, no errors

6. Rate limiting:
   - Rapid successive calls
   - Expected: Appropriate backoff

Document all error messages for troubleshooting guide.
```

---

## Verification Checklist

### Pre-Implementation Verification:
```
Before starting:
□ Backup current connector versions
□ Document current recipe dependencies
□ Verify test folder has sample files
□ Service account email noted
□ Drive API enabled in GCP Console
```

### Post-Implementation Verification:
```
OAuth2 & Authentication:
□ OAuth2 flow requests both scopes
□ Re-authentication successful
□ Service account alternative documented

Drive Operations:
□ fetch_drive_file extracts text from Google Docs
□ fetch_drive_file identifies PDFs correctly
□ list_drive_files filters work (folder, date, MIME)
□ batch_fetch_drive_files handles partial failures
□ All helper methods work with various URL formats

Document Processing:
□ process_document_for_rag generates stable IDs
□ Chunks preserve document metadata
□ Batch processing maintains document grouping
□ Change detection using checksums works

Error Handling:
□ 404 errors provide helpful messages
□ 403 errors include sharing instructions
□ Rate limiting handled gracefully
□ Binary files flagged appropriately

Integration:
□ End-to-end pipeline processes documents
□ Metadata flows through all stages
□ Performance acceptable (<60s for 10 docs)
□ No breaking changes to existing actions
```

---

## Quick Reference Card

### API Endpoints Used:
| Operation | Endpoint | Purpose |
|-----------|----------|---------|
| Get metadata | `/drive/v3/files/{id}` | File details |
| Export Google file | `/drive/v3/files/{id}/export` | Extract text |
| Download file | `/drive/v3/files/{id}?alt=media` | Get content |
| List files | `/drive/v3/files` | Find documents |
| Get changes | `/drive/v3/changes` | Incremental updates |

### Key Patterns:
| Pattern | Implementation | Used In |
|---------|---------------|---------|
| ID extraction | Regex: `/d/([a-zA-Z0-9-_]+)` | All Drive actions |
| Checksum comparison | MD5 from metadata | Change detection |
| Batch processing | Sequential with error collection | batch_fetch |
| Document ID | SHA256(path\|checksum) | process_document |

### Common Issues & Solutions:
| Issue | Solution | Prevention |
|-------|----------|------------|
| "File not found" | Verify ID, check trash | Validate IDs before use |
| "Permission denied" | Share with service account | Document sharing requirement |
| "Rate limited" | Implement exponential backoff | Batch operations |
| "No text extracted" | Check MIME type, use OCR for PDFs | Set needs_processing flag |

---

## Rollback Plan

If implementation fails:
```
1. Immediate rollback:
   - Remove Drive scope from OAuth2
   - Delete new Drive actions
   - Remove Drive helper methods
   - Restore original test lambda

2. Partial rollback (keep preparations):
   - Keep document processing enhancements
   - Remove only Drive API calls
   - Use manual file upload instead

3. Data cleanup:
   - No data migration needed
   - Existing recipes unaffected
   - Re-authentication reverses OAuth changes
```
