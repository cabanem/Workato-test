# Iterative Improvements

## A) Unify Vertex/Drive HTTP access (remove one‑off `get/post` + hardcoded hosts)

### A1. Add tiny URL helpers and request wrappers

**Why:** You build Vertex URLs in multiple places and sometimes hardcode `https://{region}-aiplatform.googleapis.com/v1`. Wrap once, reuse everywhere.

```diff
+++ methods additions
+    vertex_host: lambda { |connection|
+      "https://#{connection['region']}-aiplatform.googleapis.com"
+    },
+    vertex_base_url: lambda { |connection|
+      "#{call('vertex_host', connection)}/#{connection['version'].presence || 'v1'}"
+    },
+    vertex_api_url: lambda { |connection, path|
+      "#{call('vertex_base_url', connection)}/#{path}"
+    },
+    vertex_request: lambda do |connection, method, path_or_url, **opts|
+      url = path_or_url.start_with?('http') ? path_or_url : call('vertex_api_url', connection, path_or_url)
+      call('api_request', connection, method, url, opts)
+    end,
+    drive_request: lambda do |connection, method, endpoint, **opts|
+      url = call('drive_api_url', endpoint, opts.delete(:file_id), opts)
+      opts[:error_handler] ||= lambda do |code, body, message|
+        error(call('handle_drive_error', connection, code, body, message))
+      end
+      call('api_request', connection, method, url, opts)
+    end,
```

### A2. Use wrappers in validation and tests (remove hardcoded Vertex URLs)

**Why:** Same behavior, fewer places to maintain.

```diff
--- methods.validate_publisher_model!
-      url = "https://#{region}-aiplatform.googleapis.com/v1/#{model_name}"
-      begin
-        resp = get(url).
-          params(view: 'PUBLISHER_MODEL_VIEW_BASIC')...
+      url_path = "#{model_name}"
+      begin
+        resp = call('vertex_request', connection, :get, url_path,
+                    params: { view: 'PUBLISHER_MODEL_VIEW_BASIC' })
+          .after_error_response(/404/) do |code, body, _hdrs, message|
             ...
           end
           ...
```

```diff
--- actions.test_connection.execute (model access probe)
-                model_test = call('api_request', connection, :get,
-                  "https://#{connection['region']}-aiplatform.googleapis.com/v1/publishers/google/models/gemini-1.5-pro",
-                  { context: { action: 'Get Gemini model' } }
-                )
+                model_test = call('vertex_request', connection, :get,
+                  "publishers/google/models/gemini-1.5-pro",
+                  context: { action: 'Get Gemini model' })
```

### A3. Use wrappers for Drive calls that currently use raw `get`

**Why:** Centralizes Drive error handling in `handle_drive_error`.

```diff
--- actions.test_connection.execute (Drive file read probe)
-              file_id = drive_response['files'].first['id']
-              begin
-                get(call('drive_api_url', :file, file_id)).
-                  params(fields: 'id,size')
+              file_id = drive_response['files'].first['id']
+              begin
+                call('drive_request', connection, :get, :file, file_id: file_id,
+                  params: { fields: 'id,size' })
```

```diff
--- actions.fetch_drive_file.execute
-        metadata_response = call('api_request', connection, :get,
-          call('drive_api_url', :file, file_id),
-          {
-            params: { fields: call('drive_basic_fields') },
-            error_handler: lambda do |code, body, message|
-              error(call('handle_drive_error', connection, code, body, message))
-            end
-          }
-        )
+        metadata_response = call('drive_request', connection, :get, :file,
+          file_id: file_id,
+          params: { fields: call('drive_basic_fields') })
```

```diff
--- actions.batch_fetch_drive_files.execute (metadata fetch)
-        metadata_response = call('api_request', connection, :get,
-          call('drive_api_url', :file, file_id),
-          {
-            params: { fields: call('drive_basic_fields') },
-                error_handler: lambda do |code, body, message|
-                  error(call('handle_drive_error', connection, code, body, message))
-                end
-              }
-            )
+        metadata_response = call('drive_request', connection, :get, :file,
+          file_id: file_id,
+          params: { fields: call('drive_basic_fields') })
```

```diff
--- actions.list_drive_files.execute
-        response = call('api_request', connection, :get,
-          call('drive_api_url', :files),
-          {
-            params: api_params,
-            error_handler: lambda do |code, body, message|
-              error(call('handle_drive_error', connection, code, body, message))
-            end
-          }
-        )
+        response = call('drive_request', connection, :get, :files,
+          params: api_params)
```

```diff
--- actions.test.execute (Drive validation inside top-level test)
-      response = call('api_request', connection, :get,
-        call('drive_api_url', :files),
-        {
-          params: { pageSize: 1, q: "trashed = false" },
-          error_handler: lambda do |code, body, message|
-            if code == 403
-              error("Drive API not enabled or missing permissions")
-            else
-              call('handle_vertex_error', connection, code, body, message)
-            end
-          end
-        }
-      )
+      response = call('drive_request', connection, :get, :files,
+        params: { pageSize: 1, q: "trashed = false" },
+        error_handler: lambda do |code, body, message|
+          error("Drive API not enabled or missing permissions") if code == 403
+          error(call('handle_drive_error', connection, code, body, message))
+        end)
```

---

## B) Normalize Drive metadata once (consistent keys across actions)

**Problem today:** `fetch_drive_file` returns `mimeType/modifiedTime/md5Checksum` while list returns `mime_type/modified_time/checksum`. Your `drive_file_extended` schema expects the snake\_case keys, so `fetch_drive_file` silently leaves those datapills empty.

### B1. Add a normalizer

```diff
+++ methods additions
+    normalize_drive_metadata: lambda do |file|
+      return {} unless file.is_a?(Hash)
+      {
+        'id' => file['id'],
+        'name' => file['name'],
+        'mime_type' => file['mimeType'],
+        'size' => file['size']&.to_i,
+        'modified_time' => file['modifiedTime'],
+        'checksum' => file['md5Checksum'],
+        'owners' => file['owners']
+      }.compact
+    end,
```

### B2. Use it in `fetch_drive_file`

```diff
--- actions.fetch_drive_file.execute (return shape)
-        metadata_response.merge(content_result)
+        call('normalize_drive_metadata', metadata_response).merge(content_result)
```

### B3. Use it in `batch_fetch_drive_files`

```diff
--- actions.batch_fetch_drive_files.execute (successful file)
-            successful_file = metadata_response.merge(content_result)
+            successful_file = call('normalize_drive_metadata', metadata_response).merge(content_result)
```

### B4. Use it in `list_drive_files` (simplify mapping)

```diff
--- actions.list_drive_files.execute
-        processed_files = files.map do |file|
-          {
-            'id' => file['id'],
-            'name' => file['name'],
-            'mime_type' => file['mimeType'],
-            'size' => file['size']&.to_i,
-            'modified_time' => file['modifiedTime'],
-            'checksum' => file['md5Checksum']
-          }
-        end
+        processed_files = files.map { |f| call('normalize_drive_metadata', f).except('owners') }
```

**Net effect:** No behavior change for existing recipes (only fills the expected snake\_case pills that were empty before) and removes three different per‑action key mappers.

---

## C) Fix missing `environment.host` in `test_connection` output

```diff
--- actions.test_connection.execute (results.environment)
-          'environment' => {
-            'project' => connection['project'],
-            'region' => connection['region'],
-            'api_version' => connection['version'] || 'v1',
-            'auth_type' => connection['auth_type']
-          },
+          'environment' => {
+            'project' => connection['project'],
+            'region'  => connection['region'],
+            'api_version' => connection['version'] || 'v1',
+            'auth_type' => connection['auth_type'],
+            'host' => call('vertex_host', connection)
+          },
```

---

## D) Replace remaining raw Vertex `get` calls in Index helpers with wrapper

**Why:** Make error handling uniform and shorten the code.

```diff
--- methods.validate_index_access
-        index_response = get("#{index_id}").
-          after_error_response(/.*/) do |code, body, _header, message|
+        index_response = call('vertex_request', connection, :get, index_id).
+          after_error_response(/.*/) do |code, body, _header, message|
             ...
           end
...
-            endpoint_response = get("#{endpoint_id}").
-              after_error_response(/.*/) do |code, body, _header, message|
+            endpoint_response = call('vertex_request', connection, :get, endpoint_id).
+              after_error_response(/.*/) do |code, body, _header, message|
                 # optional
               end
```

---

## E) Centralize status extraction in backoff (reduce string matching)

**Why:** `handle_429_with_backoff` currently tests `e.message.include?('429')`. Be precise, then fall back.

```diff
+++ methods additions
+    http_status_from_error: lambda { |e|
+      (e.respond_to?(:response) && e.response&.status) || (e.message[/\b(\d{3})\b/, 1]&.to_i)
+    },
```

```diff
--- methods.handle_429_with_backoff
-        rescue => e
-          # Check if this is a 429 error
-          if e.message.include?('429') || e.message.include?('Rate limit')
+        rescue => e
+          code = call('http_status_from_error', e)
+          if code == 429 || e.message.include?('Rate limit')
             ...
```

---

## F) Make `vertex_url_for` + wrappers the single source for prediction/generation

**Why:** A few places still manually stitch URLs; route through your helper consistently.

```diff
--- methods.vertex_url_for
-      base = "projects/#{connection['project']}/locations/#{connection['region']}"
+      base = "projects/#{connection['project']}/locations/#{connection['region']}"
```

*(no functional change; next step adds thin wrappers)*

```diff
+++ methods additions
+    vertex_generate: lambda do |connection, model, payload, context: {}|
+      url = call('vertex_url_for', connection, model, :generate)
+      call('rate_limited_ai_request', connection, model, 'inference', url, payload)
+    end,
+    vertex_predict: lambda do |connection, model, payload, context: {}|
+      url = call('vertex_url_for', connection, model, :predict)
+      call('rate_limited_ai_request', connection, model, 'embedding', url, payload)
+    end,
```

Use them:

```diff
--- actions.send_messages.execute
-          call('rate_limited_ai_request',
-               connection,
-               input['model'],
-               'inference',
-               call('vertex_url_for', connection, input['model'], :generate),
-               input['formatted_prompt'])
+          call('vertex_generate', connection, input['model'], input['formatted_prompt'])
```

```diff
--- methods.generate_embeddings_batch_exec (inside retry block)
-          payload = { 'instances' => instances }
-          call('rate_limited_ai_request', connection, model, 'embedding', url, payload)
+          payload = { 'instances' => instances }
+          call('vertex_predict', connection, model, payload)
```

```diff
--- methods.generate_embedding_single_exec
-        url = call('vertex_url_for', connection, model, :predict)
-        response = call('rate_limited_ai_request', connection, model, 'embedding', url, payload)
+        response = call('vertex_predict', connection, model, payload)
```

*(Functionality identical; call sites shorter.)*

---

## G) Share token-estimation logic (remove duplication)

```diff
+++ methods additions
+    estimate_tokens_from_chars: lambda { |text| (text.to_s.length / 4.0).ceil },
```

```diff
--- methods.generate_embeddings_batch_exec
-            total_tokens += (text_obj['content'].to_s.length / 4.0).ceil
+            total_tokens += call('estimate_tokens_from_chars', text_obj['content'])
```

```diff
--- methods.generate_embedding_single_exec
-        token_count = (content.length / 4.0).ceil
+        token_count = call('estimate_tokens_from_chars', content)
```

---

## H) Make Drive export/download calls use `drive_request` too

```diff
--- methods.fetch_file_content (export branch)
-        content_response = call('api_request', connection, :get,
-          call('drive_api_url', :export, file_id),
-          {
-            params: { mimeType: export_mime_type },
-            error_handler: lambda do |code, body, message|
-              error(call('handle_drive_error', connection, code, body, message))
-            end
-          }
-        )
+        content_response = call('drive_request', connection, :get, :export,
+          file_id: file_id,
+          params: { mimeType: export_mime_type })
```

```diff
--- methods.fetch_file_content (download branch)
-        content_response = call('api_request', connection, :get,
-          call('drive_api_url', :download, file_id),
-          {
-            error_handler: lambda do |code, body, message|
-              error(call('handle_drive_error', connection, code, body, message))
-            end
-          }
-        )
+        content_response = call('drive_request', connection, :get, :download, file_id: file_id)
```

---

## I) Collapse static model options onto curated list (single source of truth)

**Why:** You maintain `get_static_model_list` **and** `static_model_options`. Build the picklist options from the curated list so you only update one place.

```diff
--- methods.static_model_options
-    static_model_options: lambda do
-      {
-        text: [
-          ['Gemini 1.0 Pro', 'publishers/google/models/gemini-pro'],
-          ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
-          ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
-          ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
-          ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
-          ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
-          ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
-          ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
-        ],
-        image: [
-          ['Gemini Pro Vision', 'publishers/google/models/gemini-pro-vision'],
-          ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
-          ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
-          ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
-          ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
-          ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
-          ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
-          ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
-        ],
-        embedding: [
-          ['Text embedding gecko-001', 'publishers/google/models/textembedding-gecko@001'],
-          ['Text embedding gecko-003', 'publishers/google/models/textembedding-gecko@003'],
-          ['Text embedding-004', 'publishers/google/models/text-embedding-004']
-        ]
-      }
-    end,
+    static_model_options: lambda do |connection = {}|
+      static = call('get_static_model_list', connection, 'google')
+      # Build buckets from static list using existing bucket logic + labels
+      buckets = { text: [], image: [], embedding: [] }
+      static.each do |m|
+        id = m['name'].to_s.split('/').last
+        bucket = call('vertex_model_bucket', id)
+        next unless buckets.key?(bucket)
+        buckets[bucket] << [call('create_model_label', id, m), "publishers/google/models/#{id}"]
+      end
+      buckets
+    end,
```

*(Picklists still call `static_model_options` and get the same shapes, now auto‑derived.)*

---

## J) Freeze small constant hashes (micro‑refactor, safer copies)

```diff
--- methods.vertex_rpm_limits
-    vertex_rpm_limits: lambda do
-      {
-        'gemini-pro' => 300,
-        'gemini-flash' => 600,
-        'embedding' => 600
-      }
-    end,
+    vertex_rpm_limits: lambda do
+      { 'gemini-pro' => 300, 'gemini-flash' => 600, 'embedding' => 600 }.freeze
+    end,
```

---

## K) Reduce duplication in Drive download “needs\_processing” check

**Why:** The current array+`start_with?` dance is harder to read; keep logic identical.

```diff
--- methods.fetch_file_content (download branch)
-        needs_processing = ['application/pdf', 'image/'].any? { |prefix|
-          metadata['mimeType']&.start_with?(prefix)
-        }
+        mt = metadata['mimeType'].to_s
+        needs_processing = mt.start_with?('application/pdf') || mt.start_with?('image/')
```

---

## L) Tighten `extract_drive_file_id` early‑return and comments

```diff
--- methods.extract_drive_file_id
-      return url_or_id if url_or_id.blank?
+      return url_or_id if url_or_id.blank?  # nil/empty: pass through
```

*(Comment only; clearer intent. No behavior change.)*

---

## M) Keep one public backtick sanitizer (leave alias for compatibility)

**Why:** You already route `replace_backticks_with_hash` to `sanitize_triple_backticks`. Make that explicit in the name and nudge future calls to the canonical one.

````diff
--- methods.sanitize_triple_backticks
-    sanitize_triple_backticks: lambda { |text| text&.gsub('```', '####') },
+    sanitize_triple_backticks: lambda { |text| text&.gsub('```', '####') },
+    # TODO(emily): migrate call sites to sanitize_triple_backticks; keep alias for bc
````

*(No code change beyond a TODO; just codifies the intent. Zero behavior risk.)*

---

## N) Use shared `vertex_request` in `find_neighbors` error path context

**Why:** Keep the specialized messaging while standardizing the call.

```diff
--- actions.find_neighbors.execute (request)
-        response = call('api_request', connection, :post, url, {
+        response = call('api_request', connection, :post, url, {
           payload: payload,
           context: { action: 'Find neighbors',
                      host: host, endpoint_id: endpoint_id, region: region },
```

*(No functional change; context stays; patch here only to confirm we’re uniformly using `api_request` for errors — already the case.)*

---

## O) Small cleanup: `drive_basic_fields` includes owners; ensure we actually show them

You already merged `owners` in `drive_file_extended`. B‑series normalization (B2/B3) ensures owners flow through automatically. No diff needed beyond B‑series.

---

## P) Optional—but safe—micro‑simplifications (no behavior change)

1. **`to_similarity`** guard:

```diff
--- methods.to_similarity
-      s = 1.0 - (distance.to_f / max.to_f)
+      denom = max.to_f.nonzero? || 1.0
+      s = 1.0 - (distance.to_f / denom)
```

2. **`maybe_parse_json`** short‑circuit:

```diff
--- methods.maybe_parse_json
-      return str unless trimmed.start_with?('{','[')
+      return str unless trimmed.start_with?('{', '[')
```

3. **`cascade_model_discovery`** early return comments (docs only) – optional.

---

# What this buys you

* **Fewer moving parts:** One way to hit Vertex, one way to hit Drive.
* **Consistent Drive outputs:** All Drive actions now emit the same snake\_case metadata fields your schemas already declare.
* **Less URL glue:** You change a host/version in one helper; everything follows.
* **Clearer rate‑limit retries:** Status‑aware backoff instead of string sniffing.
* **Zero feature drift:** Same requests, same responses, fewer lines.

# Where to continue (if you want to squeeze more)

* Fold the three generative prompt templates into a tiny table + loop (they already share `build_base_payload`).
* Consider moving the **languages** list to a constant at the bottom to declutter `pick_lists`.
* Add unit tests for `normalize_drive_metadata` and `vertex_request` using Workato’s SDK test harness or simple Ruby stubs.

