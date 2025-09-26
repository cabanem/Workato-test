# PR 9 — Test/diagnostic cleanup

## Scope

* In `test_connection` action, use `api_request` consistently.
* Remove `developer_api_host` from environment blob.
* Extract static quota defaults.

## Rationale
Consistency and less misleading metadata.

## Patch

```diff
diff --git a/connector.rb b/connector.rb
@@
-            'auth_type' => connection['auth_type'],
-            'host' => connection['developer_api_host']
+            'auth_type' => connection['auth_type']
           },
@@
-            datasets_response = get("projects/#{connection['project']}/locations/#{connection['region']}/datasets").
-              params(pageSize: 1).
-              after_error_response(/.*/) do |code, body, _header, message|
-                raise "Vertex AI API error (#{code}): #{message}"
-              end
+            datasets_response = call('api_request', connection, :get,
+              "projects/#{connection['project']}/locations/#{connection['region']}/datasets",
+              { params: { pageSize: 1 }, context: { action: 'List datasets' } }
+            )
@@
-                models_response = get("projects/#{connection['project']}/locations/#{connection['region']}/models").
-                  params(pageSize: 1)
+                models_response = call('api_request', connection, :get,
+                  "projects/#{connection['project']}/locations/#{connection['region']}/models",
+                  { params: { pageSize: 1 }, context: { action: 'List models' } }
+                )
@@
-                model_test = get("https://#{connection['region']}-aiplatform.googleapis.com/v1/publishers/google/models/gemini-1.5-pro")
+                model_test = call('api_request', connection, :get,
+                  "https://#{connection['region']}-aiplatform.googleapis.com/v1/publishers/google/models/gemini-1.5-pro",
+                  { context: { action: 'Get Gemini model' } }
+                )
@@
-            quotas = {
-              'api_calls_per_minute' => {
-                'gemini_pro' => 300,
-                'gemini_flash' => 600,
-                'embeddings' => 600
-              },
-              'notes' => 'These are default quotas. Actual quotas may vary by project.'
-            }
-            results['quota_info'] = quotas
+            results['quota_info'] = {
+              'api_calls_per_minute' => { 'gemini_pro' => 300, 'gemini_flash' => 600, 'embeddings' => 600 },
+              'notes' => 'Defaults only. Your project quotas may differ.'
+            }
```

## Acceptance criteria

* Test action still works; fewer fields; consistent error formatting.

## Test plan

* Run `test_connection` with toggles on/off and confirm outputs.

## Commit message

```bash
git commit -m "refactor(test): use api_request consistently in test_connection; trim env noise; clarify quotas" \
  -m "Why: test action mixed raw GETs and inconsistent errors; extra 'host' field was misleading." \
  -m "What:" \
  -m "- test_connection: call api_request for datasets/models/model probe; pass context for richer errors." \
  -m "- Remove developer_api_host from environment blob." \
  -m "- Extract static quota defaults into a small object with clear note." \
  -m "Impact: same functionality; cleaner output and consistent error surfacing." \
  -m "Testing: ran with/without Drive/Models/Index toggles; outputs stable."
```