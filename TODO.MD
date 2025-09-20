# Getting started
```
Working on Workato connector integration in Codespaces.
Context: Vertex AI integration with Google Drive, contract validation
Current task: [specifictask]
File: connectors/vertex/v2.0_proposed.rb
```
--- 

## Task #1
Add Drive Helper Methods

Location: Methods section (~line 2000)
Action: Add utility methods

Implementation Prompt:

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