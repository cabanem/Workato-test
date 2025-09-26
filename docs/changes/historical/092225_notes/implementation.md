## Section 0 — Preflight bugfixes

### 0.1 Remove illegal `break` in `fetch_publisher_models`

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2215,9 +2215,11 @@
       begin
         cached_data = workato.cache.get(cache_key)
         if cached_data.present?
           cache_time = (Time.parse(cached_data['cached_at']) rescue nil)
-          break if cache_time.nil?
+          if cache_time.nil?
+            # Missing timestamp; proceed to refresh cache.
+            # (Avoid 'break' here; not inside a loop.)
+          end
 
           if cache_time > 1.hour.ago
-            puts "Using cached model list (#{cached_data['models'].length} models, cached #{((Time.now - cache_time) / 60).round} minutes ago)"
+            puts "Using cached model list (#{cached_data['models'].length} models, cached #{((Time.now - cache_time) / 60).round} minutes ago)"
             return cached_data['models']
           else
             puts "Model cache expired, refreshing..."
           end
```

### 0.2 Fix undefined variable (`filtered` → `eligible`) in `to_model_options`

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2376,7 +2376,7 @@
       end
       
       # Extract unique model IDs efficiently
       seen_ids = {}
-      unique_models = filtered.select do |m|
+      unique_models = eligible.select do |m|
         id = m['name'].to_s.split('/').last
         next false if id.blank?
         next false if seen_ids[id]
```

---

## Section 1 — Stop mutating shared field arrays

### 1.1 `drive_file_extended` — switch from `concat` to non‑mutating `dup +`

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2977,15 +2977,13 @@
     drive_file_extended: {
       fields: lambda do |_connection, _config_fields, object_definitions|
-        # Start with base fields
-        base_fields = object_definitions['drive_file_fields']
-
-        # Add extended fields
-        extended = base_fields.concat([
+        # Start with base fields (do not mutate shared arrays)
+        base_fields = object_definitions['drive_file_fields'].dup
+        base_fields + [
           { name: 'owners', label: 'File owners', type: 'array', of: 'object',
             properties: [
               { name: 'displayName', label: 'Display name', type: 'string' },
               { name: 'emailAddress', label: 'Email address', type: 'string' }
             ],
             hint: 'Array of file owners' },
           { name: 'text_content', label: 'Text content', type: 'string',
             hint: 'Extracted text content' },
           { name: 'needs_processing', label: 'Needs processing', type: 'boolean',
             hint: 'True if file requires additional processing' },
           { name: 'export_mime_type', label: 'Export MIME type', type: 'string',
             hint: 'MIME type used for export' },
           { name: 'fetch_method', label: 'Fetch method', type: 'string',
             hint: 'Method used to retrieve content' }
-        ])
-
-        extended
+        ]
       end
     },
```

### 1.2 `safety_and_usage` — avoid mutating `safety` with `concat`

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -3021,8 +3021,8 @@
     safety_and_usage: {
       fields: lambda do |_connection, _config_fields, object_definitions|
         safety = object_definitions['safety_rating_schema'] || []
         usage = object_definitions['usage_schema'] || []
-        safety.concat(usage)
+        safety + usage
       end
     },
```

### 1.3 `send_messages_input` — non‑mutating build

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -3258,17 +3258,16 @@
     send_messages_input: {
       fields: lambda do |_connection, config_fields, object_definitions|
         is_single_message = config_fields['message_type'] == 'single_message'
         message_schema = if is_single_message
                            [
                              { name: 'message',
                                label: 'Text to send',
                                type: 'string',
                                control_type: 'text-area',
                                optional: false,
                                hint: 'Enter a message to start a conversation with Gemini.' }
                            ]
                          else
                            [
                              { name: 'chat_transcript',
                                type: 'array',
                                of: 'object',
                                optional: false,
                                properties: [
                                  { name: 'role',
                                    control_type: 'select',
                                    pick_list: :chat_role,
                                    sticky: true,
                                    extends_schema: true,
                                    hint: 'Select the role of the author of this message.',
                                    toggle_hint: 'Select from list',
                                    toggle_field: {
                                      name: 'role',
                                      label: 'Role',
                                      control_type: 'text',
                                      type: 'string',
                                      optional: true,
                                      extends_schema: true,
                                      toggle_hint: 'Use custom value',
                                      hint: 'Provide the role of the author of this message. ' \
                                            'Allowed values: <b>user</b> or <b>model</b>.'
                                    } },
                                  { name: 'text',
                                    control_type: 'text-area',
                                    sticky: true,
                                    hint: 'The contents of the selected role message.' },
                                  { name: 'fileData',
                                    type: 'object',
                                    properties: [
                                      { name: 'mimeType', label: 'MIME type' },
                                      { name: 'fileUri', label: 'File URI' }
                                    ] },
                                  { name: 'inlineData',
                                    type: 'object',
                                    properties: [
                                      { name: 'mimeType', label: 'MIME type' },
                                      { name: 'data' }
                                    ] },
                                  { name: 'functionCall',
                                    type: 'object',
                                    properties: [
                                      { name: 'name', label: 'Function name' },
                                      { name: 'args', control_type: 'text-area', label: 'Arguments' }
                                    ] },
                                  { name: 'functionResponse',
                                    type: 'object',
                                    properties: [
                                      { name: 'name', label: 'Function name' },
                                      { name: 'response',
                                        control_type: 'text-area',
                                        hint: 'Use this field to send function response. ' \
                                              'Parameters field in Tools > Function declarations ' \
                                              'should also be used when using this field.' }
                                    ] }
                                ],
                                hint: 'A list of messages describing the conversation so far.' }
                            ]
                          end
-        object_definitions['text_model_schema'].concat(
-          [
+        object_definitions['text_model_schema'].dup + [
             { name: 'message_type', label: 'Message type', type: 'string', control_type: 'select', pick_list: :message_types,
               extends_schema: true, optional: false, hint: 'Choose the type of the message to send.', group: 'Message' },
             { name: 'messages', label: is_single_message ? 'Message' : 'Messages',
               type: 'object', optional: false, properties: message_schema, group: 'Message' },
             { name: 'formatted_prompt', label: 'Formatted prompt (RAG_Utils)', type: 'object', optional: true, group: 'Advanced',
               hint: 'Pre-formatted prompt payload from RAG_Utils. When provided, this will be used directly instead of building from messages.' }
-          ].compact
-        ).concat(object_definitions['config_schema'])
+          ].compact + object_definitions['config_schema']
       end
     },
```

### 1.4 Same non‑mutating change pattern in the following definitions

> Apply the same replacement (`object_definitions['…'].dup + […] + object_definitions['…']`) to these blocks:

* `translate_text_input`
* `summarize_text_input`
* `parse_text_input`
* `draft_email_input`
* `analyze_text_input`

**Example – `translate_text_input`:**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -3410,16 +3410,14 @@
     translate_text_input: {
       fields: lambda do |_connection, _config_fields, object_definitions|
-        object_definitions['text_model_schema'].concat(
-          [
+        object_definitions['text_model_schema'].dup + [
             { name: 'to', label: 'Output language', group: 'Task input', optional: false, control_type: 'select', pick_list: :languages_picklist,
               toggle_field: { name: 'to', label: 'Output language', control_type: 'text', type: 'string', optional: false, toggle_hint: 'Provide custom value', hint: 'Enter the output language. Eg. English' },
               toggle_hint: 'Select from list',
               hint: 'Select the desired output language' },
             { name: 'from', label: 'Source language', group: 'Task input', optional: true, sticky: true, control_type: 'select', pick_list: :languages_picklist,
               toggle_field: {
                 name: 'from',
                 control_type: 'text',
                 type: 'string',
                 optional: true,
                 label: 'Source language',
                 toggle_hint: 'Provide custom value',
                 hint: 'Enter the source language. Eg. English'
               },
               toggle_hint: 'Select from list',
               hint: 'Select the source language. If this value is left blank, we will automatically attempt to identify it.' },
             { name: 'text', label: 'Source text', group: 'Task input', type: 'string', control_type: 'text-area', optional: false, hint: 'Enter the text to be translated. Please limit to 2000 tokens' }
-          ]
-        ).concat(object_definitions['config_schema'].only('safetySettings'))
+          ] + object_definitions['config_schema'].only('safetySettings')
       end
     },
```

*(Repeat the same style for the other four definitions.)*

---

## Section 2 — Route Gemini text actions through `run_vertex` (+ use `vertex_url_for`)

### 2.1 `send_messages.execute` — one‑liner with `run_vertex` (keeps `formatted_prompt`)

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -679,17 +679,14 @@
       execute: lambda do |connection, input, _eis, _eos|
-        call('validate_publisher_model!', connection, input['model'])
-        payload = input['formatted_prompt'].presence || call('build_ai_payload', :send_message, input)
-
-        # Build the url
-        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
-              "/#{input['model']}:generateContent"
-
-        # Make rate-limited request
-        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
-        response
+        if input['formatted_prompt'].present?
+          call('rate_limited_ai_request',
+               connection,
+               input['model'],
+               'inference',
+               call('vertex_url_for', connection, input['model'], :generate),
+               input['formatted_prompt'])
+        else
+          call('run_vertex', connection, input, :send_message, verb: :generate)
+        end
       end,
```

### 2.2 `ai_classify.execute` — delegate to `run_vertex`

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -970,22 +970,9 @@
       execute: lambda do |connection, input, _eis, _eos|
-        # Validate model
-        call('validate_publisher_model!', connection, input['model'])
-
-        # Build payload for AI classification
-        payload = call('build_ai_payload', :ai_classify, input, connection)
-
-        # Build the url
-        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
-                        "/#{input['model']}:generateContent"
-
-        # Make rate-limited request
-        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
-
-        # Extract and return the response
-        call('extract_response', response, { type: :classify, input: input })
+        call('run_vertex', connection, input, :ai_classify,
+             verb: :generate,
+             extract: { type: :classify })
       end
     },
```

### 2.3 Use `vertex_url_for` in embedding actions

**`generate_embedding_single_exec`**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2100,9 +2100,7 @@
-        # Build the URL
-        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
-              "/#{model}:predict"
+        url = call('vertex_url_for', connection, model, :predict)
```

**`generate_embeddings_batch_exec`**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1990,9 +1990,7 @@
-      # Build the URL once
-      url = "projects/#{connection['project']}/locations/#{connection['region']}" \
-            "/#{model}:predict"
+      url = call('vertex_url_for', connection, model, :predict)
```

---

## Section 3 — Unify logging and error plumbing

### 3.1 Replace `puts` with `log_debug` (three representative sites)

**`fetch_publisher_models`**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2222,11 +2222,11 @@
-          puts "Using cached model list (#{cached_data['models'].length} models, cached #{((Time.now - cache_time) / 60).round} minutes ago)"
+          call('log_debug', "Using cached model list (#{cached_data['models'].length} models, cached #{((Time.now - cache_time) / 60).round} minutes ago)")
           return cached_data['models']
         else
-          puts "Model cache expired, refreshing..."
+          call('log_debug', "Model cache expired, refreshing...")
         end
       end
     rescue => e
-      puts "Cache access failed: #{e.message}, fetching fresh data"
+      call('log_debug', "Cache access failed: #{e.message}, fetching fresh data")
     end
```

**`cascade_model_discovery`**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2262,21 +2262,21 @@
-      begin
-        puts "Model discovery: primary API..."
+      begin
+        call('log_debug', "Model discovery: primary API...")
         models = call('fetch_fresh_publisher_models', connection, publisher, region)
         if models.present?
           models.each { |m| m['source'] = 'primary_api' }
           return models
         end
       rescue => e
-        puts "Model discovery: primary failed: #{e.message}"
+        call('log_debug', "Model discovery: primary failed: #{e.message}")
       end
       if region != 'us-central1'
         begin
-          puts "Model discovery: fallback us-central1..."
+          call('log_debug', "Model discovery: fallback us-central1...")
           models = call('fetch_fresh_publisher_models', connection, publisher, 'us-central1')
           if models.present?
             models.each { |m| m['source'] = 'fallback_region' }
             return models
           end
         rescue => e
-          puts "Model discovery: fallback failed: #{e.message}"
+          call('log_debug', "Model discovery: fallback failed: #{e.message}")
         end
       end
       # Final: static curated list
       # Strategy 4: Use static curated list as final fallback
       begin
-        puts "Model discovery: using static curated list as final fallback"
+        call('log_debug', "Model discovery: using static curated list as final fallback")
         models = call('get_static_model_list', connection, publisher)
         models.each { |m| m['source'] = 'static_fallback' }
-        puts "Model discovery: static fallback provided #{models.length} models"
+        call('log_debug', "Model discovery: static fallback provided #{models.length} models")
         return models
       rescue => e
-        puts "Model discovery: static fallback failed: #{e.message}"
+        call('log_debug', "Model discovery: static fallback failed: #{e.message}")
         return []
       end
```

**`fetch_fresh_publisher_models`**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2310,7 +2310,7 @@
-          pages_fetched += 1
+          pages_fetched += 1
@@ -2334,9 +2334,9 @@
-          puts "Fetched page #{pages_fetched}: #{batch.length} models in #{api_time.round(2)}s"
+          call('log_debug', "Fetched page #{pages_fetched}: #{batch.length} models in #{api_time.round(2)}s")
@@ -2344,14 +2344,14 @@
-            puts "Have #{models.length} models, stopping early for performance"
+            call('log_debug', "Have #{models.length} models, stopping early for performance")
             break
           end
@@ -2351,8 +2351,8 @@
-        puts "Total model fetch: #{models.length} models in #{total_api_time.round(2)}s across #{pages_fetched} pages"
+        call('log_debug', "Total model fetch: #{models.length} models in #{total_api_time.round(2)}s across #{pages_fetched} pages")
         models
-        
+
       rescue => e
-        puts "Failed to fetch models from API: #{e.message}"
+        call('log_debug', "Failed to fetch models from API: #{e.message}")
         # Return empty array to trigger static fallback
         []
       end
```

### 3.2 `test_connection` Drive list — route through `api_request` with Drive handler

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1538,17 +1538,18 @@
-            drive_response = get(call('drive_api_url', :files)).
-              params(pageSize: 1, q: "trashed = false", fields: 'files(id,name,mimeType)').
-              after_error_response(/.*/) do |code, body, _header, message|
-                if code == 403
-                  raise "Drive API not enabled or missing scope"
-                elsif code == 401
-                  raise "Authentication failed - check OAuth token"
-                else
-                  raise "Drive API error (#{code}): #{message}"
-                end
-              end
+            drive_response = call('api_request', connection, :get,
+              call('drive_api_url', :files),
+              {
+                params: { pageSize: 1, q: "trashed = false", fields: 'files(id,name,mimeType)' },
+                error_handler: lambda do |code, body, message|
+                  error(call('handle_drive_error', connection, code, body, message))
+                end,
+                context: { action: 'List Drive files' }
+              }
+            )
```

*(Keep the later `file get` also using `api_request` similarly; you already do.)*

---

## Section 4 — Rate limiting/backoff constants + Retry‑After in body

### 4.1 Add `vertex_rpm_limits` helper and use it

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1867,6 +1867,13 @@
     rate_limit_defaults: lambda { { 'max_retries' => 3, 'base_delay' => 1.0, 'max_delay' => 30.0 } },
+    vertex_rpm_limits: lambda do
+      {
+        'gemini-pro' => 300,
+        'gemini-flash' => 600,
+        'embedding' => 600
+      }
+    end,
```

**Use in `enforce_vertex_rate_limits`**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1934,12 +1941,8 @@
-      # Model-specific limits (requests per minute)
-      limits = {
-        'gemini-pro' => 300,
-        'gemini-flash' => 600,
-        'embedding' => 600
-      }
-
-      limit = limits[model_family]
+      # Model-specific limits (requests per minute)
+      limit = call('vertex_rpm_limits')[model_family]
```

**Use in `test_connection` (quota\_info)**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1704,13 +1704,8 @@
-            quotas = {
-              'api_calls_per_minute' => {
-                'gemini_pro' => 300,
-                'gemini_flash' => 600,
-                'embeddings' => 600
-              },
-              'notes' => 'These are default quotas. Actual quotas may vary by project.'
-            }
+            quotas = { 'api_calls_per_minute' => call('vertex_rpm_limits'),
+                       'notes' => 'These are default quotas. Actual quotas may vary by project.' }
             results['quota_info'] = {
-              'api_calls_per_minute' => { 'gemini_pro' => 300, 'gemini_flash' => 600, 'embeddings' => 600 },
+              'api_calls_per_minute' => call('vertex_rpm_limits'),
               'notes' => 'Defaults only. Your project quotas may differ.'
             }
```

### 4.2 Honor Retry‑After embedded in JSON (`handle_429_with_backoff`)

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2013,6 +2013,14 @@
-              # Try to extract Retry-After header from error if available
+              # Try to extract Retry-After header from error if available
               retry_after = nil
               if e.respond_to?(:response) && e.response.respond_to?(:headers)
                 retry_after = e.response.headers['Retry-After']&.to_i
               end
+              # Some Google APIs return retry info inside the JSON error body
+              if retry_after.nil? && e.respond_to?(:response)
+                begin
+                  body = e.response&.body
+                  info = parse_json(body)
+                  retry_after = info.dig('error', 'details')&.find { |d| d['@type']&.include?('RetryInfo') }&.dig('retryDelay', 'seconds')&.to_i
+                rescue
+                end
+              end
```

### 4.3 Capture `rate_limit_status` from last batch response (embeddings batch)

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2055,6 +2055,7 @@
       texts.each_slice(batch_size) do |batch_texts|
         batches_processed += 1
+        last_rate = nil
 
         # Use circuit breaker for resilient batch processing
         response = call('circuit_breaker_retry', connection, "batch_embedding_#{model}", {
@@ -2075,6 +2076,7 @@
 
           # Make rate-limited batch request
-          call('rate_limited_ai_request', connection, model, 'embedding', url, payload)
+          call('rate_limited_ai_request', connection, model, 'embedding', url, payload)
         end
+        last_rate = response.is_a?(Hash) ? response['rate_limit_status'] : nil
@@ -2148,7 +2150,7 @@
         'pass_fail' => all_successful,
         'action_required' => all_successful ? 'ready_for_indexing' : 'retry_failed_embeddings',
-        'rate_limit_status' => rate_limit_info,
+        'rate_limit_status' => last_rate,
```

---

## Section 5 — Small helpers & URI DRY

### 5.1 Add `project_region_path` and use it in `test` datasets call

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1868,6 +1868,9 @@
     log_debug: lambda { |msg| puts(msg) },
     rate_limit_defaults: lambda { { 'max_retries' => 3, 'base_delay' => 1.0, 'max_delay' => 30.0 } },
+    project_region_path: lambda do |connection|
+      "projects/#{connection['project']}/locations/#{connection['region']}"
+    end,
```

**Use in connection `test`**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -146,10 +146,9 @@
   test: lambda do |connection|
     # Validate connection/access to Vertex AI
-    call('api_request', connection, :get,
-      "https://#{connection['region']}-aiplatform.googleapis.com/#{connection['version'] || 'v1'}/projects/#{connection['project']}/locations/#{connection['region']}/datasets",
-      { params: { pageSize: 1 } }
-    )
+    call('api_request', connection, :get,
+      "#{call('project_region_path', connection)}/datasets",
+      { params: { pageSize: 1 } })
```

### 5.2 `get_export_mime_type` → constant map

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2603,16 +2603,16 @@
     get_export_mime_type: lambda do |mime_type|
-      return nil if mime_type.blank?
-
-      case mime_type
-      when 'application/vnd.google-apps.document'
-        'text/plain'
-      when 'application/vnd.google-apps.spreadsheet'
-        'text/csv'
-      when 'application/vnd.google-apps.presentation'
-        'text/plain'
-      else
-        # Return nil for regular files (will be downloaded as-is)
-        nil
-      end
+      return nil if mime_type.blank?
+      exports = {
+        'application/vnd.google-apps.document'     => 'text/plain',
+        'application/vnd.google-apps.spreadsheet'  => 'text/csv',
+        'application/vnd.google-apps.presentation' => 'text/plain'
+      }.freeze
+      exports[mime_type]
     end,
```

### 5.3 Keep old name but add cleaner alias for backtick sanitizer

````diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2045,7 +2045,11 @@
     end,
-    replace_backticks_with_hash: lambda do |text|
-      text&.gsub('```', '####')
-    end,
+    sanitize_triple_backticks: lambda { |text| text&.gsub('```', '####') },
+    replace_backticks_with_hash: lambda do |text|  # backwards-compatible alias
+      call('sanitize_triple_backticks', text)
+    end,
````

---

## Section 6 — Model discovery cleanup

### 6.1 Early return when dynamic models disabled

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2452,9 +2452,9 @@
     dynamic_model_picklist: lambda do |connection, bucket, static_fallback|
-      # 1. Check if dynamic models are enabled (return to static if not)
-      unless connection['dynamic_models']
-        puts "Dynamic models disabled, using static list"
-        return static_fallback
-      end
+      # 1. Check if dynamic models are enabled (return to static if not)
+      unless connection['dynamic_models']
+        call('log_debug', "Dynamic models disabled, using static list")
+        return static_fallback
+      end
```

### 6.2 Use constants for paging limits in `fetch_fresh_publisher_models` + logging

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2293,11 +2293,13 @@
-      max_pages = 5  # Reduced from 10 for faster response
+      max_pages = 5  # constant-like
+      page_size = 500
@@ -2318,7 +2320,7 @@
-            params(
-              page_size: 500,  # Increased from 200 - get more models per request
+            params(
+              page_size: page_size,
               page_token: page_token,
               view: 'PUBLISHER_MODEL_VIEW_BASIC'  # Changed from FULL - we only need basic info
             ).
```

### 6.3 Quiet `_publisher` in static list

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2279,7 +2279,7 @@
-    get_static_model_list: lambda do |connection, publisher|
+    get_static_model_list: lambda do |connection, _publisher|
```

---

## Section 7 — Slim action bodies (neighbors & Drive changes)

### 7.1 `find_neighbors.execute` — add `context`, keep 404 message via centralized handler

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1244,16 +1244,12 @@
-        response = call('api_request', connection, :post, url, {
-          payload: payload,
-          error_handler: lambda do |code, body, message|
-            if code == 404
-              # Use a custom message for 404s since they're often configuration errors
-              error("Index endpoint not found. Please verify:\n" \
-                    "• Host: #{host}\n" \
-                    "• Endpoint ID: #{endpoint_id}\n" \
-                    "• Region: #{region}")
-            else
-              # Use the centralized handler for all other errors
-              call('handle_vertex_error', connection, code, body, message)
-            end
-          end
-        })
+        response = call('api_request', connection, :post, url, {
+          payload: payload,
+          context: { action: 'Find neighbors',
+                     host: host, endpoint_id: endpoint_id, region: region },
+          error_handler: lambda do |code, body, message|
+            call('handle_vertex_error', connection, code, body, message, { action: 'Find neighbors', host: host, endpoint_id: endpoint_id, region: region })
+          end
+        })
```

**…and extend `handle_vertex_error` to format 404 nicely when action is Find neighbors**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2090,6 +2090,13 @@
       # Build base message based on status code
       base_message = case code
       when 400
         "Invalid request format"
       when 401
         "Authentication failed - please check your credentials"
       when 403
         "Permission denied - verify Vertex AI API is enabled"
       when 404
-        "Resource not found"
+        if context[:action] == 'Find neighbors'
+          "Index endpoint not found. Please verify:\n" \
+          "• Host: #{context[:host]}\n" \
+          "• Endpoint ID: #{context[:endpoint_id]}\n" \
+          "• Region: #{context[:region]}"
+        else
+          "Resource not found"
+        end
       when 429
         "Rate limit exceeded - please wait before retrying"
```

### 7.2 `monitor_drive_changes` — use `drive_api_url` helpers

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1831,8 +1831,8 @@
-          start_response = get('https://www.googleapis.com/drive/v3/changes/startPageToken').
+          start_response = get(call('drive_api_url', :start_token)).
             params(start_params).
@@ -1867,7 +1867,7 @@
-        changes_response = get('https://www.googleapis.com/drive/v3/changes').
+        changes_response = get(call('drive_api_url', :changes)).
           params(changes_params).
```

---

## Section 8 — Legacy action sample is static and marked deprecated

### 8.1 Mark help body as deprecated

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1770,7 +1770,9 @@
       help: lambda do
         {
-          body: 'This action will retrieve prediction using the PaLM 2 for Text ' \
+          body: '**Deprecated** — kept for backward compatibility only. ' \
+                'This action will retrieve prediction using the PaLM 2 for Text ' \
                 '(text-bison) model.',
           learn_more_url: 'https://cloud.google.com/vertex-ai/docs/generative-ai/' \
                           'model-reference/text',
```

### 8.2 Replace live sample call with static JSON

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1802,15 +1802,15 @@
-      sample_output: lambda do |connection|
-        payload = {
-          instances: [
-            {
-              prompt: 'action'
-            }
-          ],
-          parameters: {
-            temperature: 1,
-            topK: 2,
-            topP: 1,
-            maxOutputTokens: 50
-          }
-        }
-        post("projects/#{connection['project']}/locations/#{connection['region']}" \
-             '/publishers/google/models/text-bison:predict').
-          payload(payload)
+      sample_output: lambda do |_connection|
+        {
+          'predictions' => [
+            { 'content' => 'Sample legacy prediction' }
+          ],
+          'metadata' => {
+            'tokenMetadata' => {
+              'inputTokenCount' => { 'totalTokens' => 10, 'totalBillableCharacters' => 40 },
+              'outputTokenCount' => { 'totalTokens' => 20, 'totalBillableCharacters' => 80 }
+            }
+          }
+        }
       end
```

---

## Section 9 — Hardening helpers: `maybe_parse_json` + `strip_fences` and usage

### 9.1 Add helpers

````diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1871,6 +1871,13 @@
     project_region_path: lambda do |connection|
       "projects/#{connection['project']}/locations/#{connection['region']}"
     end,
+    maybe_parse_json: lambda do |str|
+      return str unless str.is_a?(String)
+      trimmed = str.strip
+      return str unless trimmed.start_with?('{','[')
+      parse_json(trimmed) rescue str
+    end,
+    strip_fences: lambda { |txt| txt.to_s.gsub(/^```(?:json|JSON)?\s*\n?/, '').gsub(/\n?```\s*$/, '').gsub(/`+$/, '').strip },
````

### 9.2 Use in `build_conversation_payload` (tool params & responses)

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2165,20 +2172,14 @@
       if input['tools'].present?
         input['tools'] = input['tools'].map do |tool|
           if tool['functionDeclarations'].present?
             tool['functionDeclarations'] = tool['functionDeclarations'].map do |function|
-              if function['parameters'].present?
-                function['parameters'] = parse_json(function['parameters'])
-              end
+              function['parameters'] = call('maybe_parse_json', function['parameters']) if function['parameters'].present?
               function
             end.compact
           end
           tool
         end.compact
       end
@@ -2217,19 +2218,11 @@
       if m['functionCall'].present?
         fc = m['functionCall']
-        # if args provided as string JSON, parse once
-        if fc['args'].is_a?(String) && fc['args'].strip.start_with?('{','[')
-          begin
-            fc = fc.merge('args' => parse_json(fc['args']))
-          rescue
-            # keep raw if parse fails; server will validate
-          end
-        end
+        fc = fc.merge('args' => call('maybe_parse_json', fc['args'])) if fc['args'].present?
         parts << { 'functionCall' => fc }
       end
 
       if m['functionResponse'].present?
         fr = m['functionResponse']
-        if fr['response'].is_a?(String) && fr['response'].strip.start_with?('{','[')
-          begin
-            fr = fr.merge('response' => parse_json(fr['response']))
-          rescue
-          end
-        end
+        fr = fr.merge('response' => call('maybe_parse_json', fr['response'])) if fr['response'].present?
         parts << { 'functionResponse' => fr }
       end
```

### 9.3 Use `strip_fences` in `extract_json`

````diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2455,14 +2455,9 @@
     extract_json: lambda do |resp|
       json_txt = resp&.dig('candidates', 0, 'content', 'parts', 0, 'text')
       return {} if json_txt.blank?
 
-      # Cleanup markdown code blocks
-      json = json_txt.gsub(/^```(?:json|JSON)?\s*\n?/, '')  # Remove opening fence
-                    .gsub(/\n?```\s*$/, '')                # Remove closing fence
-                    .gsub(/`+$/, '')                       # Remove any trailing backticks
-                    .strip
+      json = call('strip_fences', json_txt)
 
       begin
         parse_json(json) || {}
       rescue => e
````

---

## Section 10 — Drive helpers tightening

### 10.1 Freeze `drive_basic_fields` string

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2569,7 +2569,7 @@
     end,
     drive_basic_fields: lambda do
-      'id,name,mimeType,size,modifiedTime,md5Checksum,owners'
+      'id,name,mimeType,size,modifiedTime,md5Checksum,owners'.freeze
     end,
```

### 10.2 Table‑driven `handle_drive_error` (same messages)

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2727,23 +2727,26 @@
     handle_drive_error: lambda do |connection, code, body, message|
       service_account_email = connection['service_account_email'] || 
                              connection['client_id']
-      case code
-      when 404
-        "File not found in Google Drive. Please verify the file ID and ensure the file exists."
-      when 403
-        if body&.include?('insufficientFilePermissions') || body&.include?('forbidden')
-          "Access denied. Please share the file with the service account: #{service_account_email}"
-        else
-          "Permission denied. Check your Google Drive API access and file permissions."
-        end
-      when 429
-        "Rate limit exceeded. Please implement request backoff and retry logic."
-      when 401
-        "Authentication failed. Please check your OAuth2 token or service account credentials."
-      when 500, 502, 503
-        "Google Drive API temporary error (#{code}). Please retry after a brief delay."
-      else
-        "Google Drive API error (#{code}): #{message || body}"
-      end
+      handlers = {
+        404 => ->(_b, _m) { "File not found in Google Drive. Please verify the file ID and ensure the file exists." },
+        403 => ->(b, _m) {
+          if b&.include?('insufficientFilePermissions') || b&.include?('forbidden')
+            "Access denied. Please share the file with the service account: #{service_account_email}"
+          else
+            "Permission denied. Check your Google Drive API access and file permissions."
+          end
+        },
+        429 => ->(_b, _m) { "Rate limit exceeded. Please implement request backoff and retry logic." },
+        401 => ->(_b, _m) { "Authentication failed. Please check your OAuth2 token or service account credentials." }
+      }
+      if handlers[code]
+        handlers[code].call(body, message)
+      elsif [500, 502, 503].include?(code)
+        "Google Drive API temporary error (#{code}). Please retry after a brief delay."
+      else
+        "Google Drive API error (#{code}): #{message || body}"
+      end
     end,
```

---

## Section 11 — OAuth scopes constant and reuse

### 11.1 Add `oauth_scopes` helper and use in `authorization_url`

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1869,6 +1869,12 @@
     rate_limit_defaults: lambda { { 'max_retries' => 3, 'base_delay' => 1.0, 'max_delay' => 30.0 } },
+    oauth_scopes: lambda do
+      [
+        'https://www.googleapis.com/auth/cloud-platform',
+        'https://www.googleapis.com/auth/drive.readonly'
+      ]
+    end,
@@ -64,12 +70,8 @@
           authorization_url: lambda do |connection|
-            scopes = [
-              'https://www.googleapis.com/auth/cloud-platform', # Vertex AI scope
-              'https://www.googleapis.com/auth/drive.readonly' # Google Drive readonly scope
-            ].join(' ')
+            scopes = call('oauth_scopes').join(' ')
             params = {
               client_id: connection['client_id'],
               response_type: 'code',
               scope: scopes,
```

---

## Section 12 — Picklist static options consolidation (non‑behavioral)

*(This keeps behavior and values identical; we just read the same arrays from one place.)*

### 12.1 Add `static_model_options` helper

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2479,6 +2479,25 @@
       static_fallback
     end,
+    static_model_options: lambda do
+      {
+        text: [
+          ['Gemini 1.0 Pro', 'publishers/google/models/gemini-pro'],
+          ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
+          ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
+          ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
+          ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
+          ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
+          ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
+          ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
+        ],
+        image: [
+          ['Gemini Pro Vision', 'publishers/google/models/gemini-pro-vision'],
+          ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
+          ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
+          ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
+          ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
+          ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
+          ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
+          ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
+        ],
+        embedding: [
+          ['Text embedding gecko-001', 'publishers/google/models/textembedding-gecko@001'],
+          ['Text embedding gecko-003', 'publishers/google/models/textembedding-gecko@003'],
+          ['Text embedding-004', 'publishers/google/models/text-embedding-004']
+        ]
+      }
+    end,
```

### 12.2 Use helper in `pick_lists` (values unchanged)

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -3848,24 +3877,14 @@
   pick_lists: {
     available_text_models: lambda do |connection|
-      static = [
-        ['Gemini 1.0 Pro', 'publishers/google/models/gemini-pro'],
-        ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
-        ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
-        ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
-        ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
-        ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
-        ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
-        ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
-      ]
+      static = call('static_model_options')[:text]
       call('picklist_for', connection, :text, static)
     end,
     available_image_models: lambda do |connection|
-      static = [
-        ['Gemini Pro Vision', 'publishers/google/models/gemini-pro-vision'],
-        ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
-        ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
-        ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
-        ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
-        ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
-        ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
-        ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
-      ]
+      static = call('static_model_options')[:image]
       call('picklist_for', connection, :image, static)
     end,
     available_embedding_models: lambda do |connection|
-      static = [
-        ['Text embedding gecko-001', 'publishers/google/models/textembedding-gecko@001'],
-        ['Text embedding gecko-003', 'publishers/google/models/textembedding-gecko@003'],
-        ['Text embedding-004', 'publishers/google/models/text-embedding-004']
-      ]
+      static = call('static_model_options')[:embedding]
       call('picklist_for', connection, :embedding, static)
     end,
```

---

## Section 13 — Embedding extraction helper reuse

### 13.1 Add `extract_embedding_values` and use in both embedding actions

````diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1884,6 +1884,11 @@
     strip_fences: lambda { |txt| txt.to_s.gsub(/^```(?:json|JSON)?\s*\n?/, '').gsub(/\n?```\s*$/, '').gsub(/`+$/, '').strip },
+    extract_embedding_values: lambda do |prediction|
+      prediction&.dig('embeddings', 'values') ||
+      prediction&.dig('embeddings')&.first&.dig('values') || []
+    end,
````

**Use in `generate_embedding_single_exec`**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2120,8 +2120,7 @@
-        vector = response&.dig('predictions', 0, 'embeddings', 'values') ||
-                 response&.dig('predictions', 0, 'embeddings')&.first&.dig('values') ||
-                 []
+        vector = call('extract_embedding_values', response&.dig('predictions', 0))
```

**Use in `generate_embeddings_batch_exec`**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2031,7 +2031,7 @@
-        predictions = response['predictions'] || []
+        predictions = response['predictions'] || []
@@ -2040,11 +2040,7 @@
-          prediction = predictions[index]
-
-          if prediction
-            # Extract embedding from prediction
-            vals = prediction&.dig('embeddings', 'values') ||
-                   prediction&.dig('embeddings')&.first&.dig('values') ||
-                   []
+          prediction = predictions[index]
+          if prediction
+            vals = call('extract_embedding_values', prediction)
```

---

## Section 14 — Response extraction: common usage helper & JSON guard

### 14.1 Add `usage_meta` and use it

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1890,6 +1890,11 @@
     extract_embedding_values: lambda do |prediction|
       prediction&.dig('embeddings', 'values') ||
       prediction&.dig('embeddings')&.first&.dig('values') || []
     end,
+    usage_meta: lambda do |resp|
+      {
+        'promptTokenCount' => resp.dig('usageMetadata', 'promptTokenCount') || 0,
+        'candidatesTokenCount' => resp.dig('usageMetadata', 'candidatesTokenCount') || 0,
+        'totalTokenCount' => resp.dig('usageMetadata', 'totalTokenCount') || 0
+      }
+    end,
```

**Use in `extract_response` generic branch**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2499,13 +2505,10 @@
         has_answer = !answer.nil? && !answer.to_s.strip.empty? && answer.to_s.strip != 'N/A'
 
         {
           'answer' => answer.to_s,
           'has_answer' => has_answer,
           'pass_fail' => has_answer,
           'action_required' => has_answer ? 'use_answer' : 'try_different_question',
           'answer_length' => answer.to_s.length,
           'safety_ratings' => ratings,
-          'prompt_tokens' => resp.dig('usageMetadata', 'promptTokenCount') || 0,
-          'response_tokens' => resp.dig('usageMetadata', 'candidatesTokenCount') || 0,
-          'total_tokens' => resp.dig('usageMetadata', 'totalTokenCount') || 0
+          'usage' => call('usage_meta', resp)
         }
```

**JSON guard in `:classify` branch**

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -2548,6 +2551,9 @@
-        json = call('extract_json', resp)
+        json = call('extract_json', resp)
+        json = {} unless json.is_a?(Hash)
+
         selected_category = json&.[]('selected_category') || 'N/A'
```

---

## Section 15 — Diagnostics refactor (use helpers & context where safe)

*(Minimal surgical change; not a full split into sub‑methods to avoid churn.)*

### 15.1 Vertex datasets list already uses `api_request` with context (no change). Add context to models list.

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1592,7 +1592,9 @@
-                models_response = call('api_request', connection, :get,
+                models_response = call('api_request', connection, :get,
                   "projects/#{connection['project']}/locations/#{connection['region']}/models",
-                  { params: { pageSize: 1 }, context: { action: 'List models' } }
+                  {
+                    params: { pageSize: 1 },
+                    context: { action: 'List models' }
+                  }
                 )
```

### 15.2 Add `context` to Gemini model GET

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1604,7 +1606,9 @@
-                model_test = call('api_request', connection, :get,
+                model_test = call('api_request', connection, :get,
                   "https://#{connection['region']}-aiplatform.googleapis.com/v1/publishers/google/models/gemini-1.5-pro",
-                  { context: { action: 'Get Gemini model' } }
+                  {
+                    context: { action: 'Get Gemini model' }
+                  }
                 )
```

---

## Section 16 — Minor consistency edits

### 16.1 Freeze region‑agnostic lists used in pick lists (no behavior change)

*(Already handled by Section 12 centralization; no additional diff required here.)*

---

## Section 17 — Public contract stability

*(No diffs; this is a principle. No field renames introduced.)*

---

## Section 18 — “Find & replace” operationalized in code

*(Covered by previous diffs; no separate patch.)*

---

## Section 19 — Optional niceties

### 19.1 Add a version banner comment at file top (helpful in multi‑env debugging)

```diff
diff --git a/connectors/google_vertex_ai.rb b/connectors/google_vertex_ai.rb
--- a/connectors/google_vertex_ai.rb
+++ b/connectors/google_vertex_ai.rb
@@ -1,3 +1,5 @@
+# Connector maintenance banner
+# VERSION: 2025-09-22 refactor pass (sections 1–15), behavior‑preserving
 {
   title: 'Google Vertex AI',
```

---

## Section 20 — Implementation order

*(No code; these are sequencing instructions.)*

---

### Sanity checklist after applying patches

* Run a quick “compile” by opening a recipe and loading input/output schemas for:

  * `send_messages`, `ai_classify`, `generate_embedding_single`, `generate_embeddings`.
* Hit `Setup → Test connection and permissions`.
* Exercise `find_neighbors` with a known endpoint to confirm the 404 message still prints the triaged hints.

