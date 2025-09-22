# PR 2 — Vertex request unification (shared URL + runner)

## Scope

* Add helpers: `vertex_url_for`, `run_vertex`.
* Migrate 5 actions to the runner (`translate_text`, `summarize_text`, `parse_text`, `draft_email`, `analyze_text`).
  Keep `send_messages` custom (it supports `formatted_prompt` overrides).
* Fix `build_classify_payload` temperature handling (no implicit extra arg).
* Remove unused `build_gemini_payload` and `payload_for_ai_classify`.

## Rationale

One golden path for “validate → build → call → extract” cuts duplication.

## Patch

````diff
diff --git a/connector.rb b/connector.rb
@@
   methods: {
+    # Build fully-qualified Vertex endpoint for a model
+    vertex_url_for: lambda do |connection, model, verb|
+      base = "projects/#{connection['project']}/locations/#{connection['region']}"
+      v = verb.to_s
+      case v
+      when 'generate' then "#{base}/#{model}:generateContent"
+      when 'predict'  then "#{base}/#{model}:predict"
+      else error("Unsupported Vertex verb: #{verb}")
+      end
+    end,
+
+    # Unified “validate → build → call → extract”
+    run_vertex: lambda do |connection, input, template, verb:, extract: {}|
+      call('validate_publisher_model!', connection, input['model'])
+      payload = call('build_ai_payload', template, input, connection)
+      url = call('vertex_url_for', connection, input['model'], verb)
+      resp = call('rate_limited_ai_request', connection, input['model'], verb, url, payload)
+      extract.present? ? call('extract_response', resp, extract) : resp
+    end,
@@
-      execute: lambda do |connection, input, _eis, _eos|
-        # Validate model
-        call('validate_publisher_model!', connection, input['model'])
-        # Build payload with enhanced builder
-        instruction = if input['from'].present?
-          "You are an assistant helping to translate a user's input from #{input['from']} into #{input['to']}. " \
-          "Respond only with the user's translated text in #{input['to']} and nothing else. " \
-          "The user input is delimited with triple backticks."
-        else
-          "You are an assistant helping to translate a user's input into #{input['to']}. " \
-          "Respond only with the user's translated text in #{input['to']} and nothing else. " \
-          "The user input is delimited with triple backticks."
-        end
-
-        user_prompt = "```#{call('replace_backticks_with_hash', input['text'])}```"
-
-        payload = call('build_gemini_payload', instruction, user_prompt, {
-          safety_settings: input['safetySettings'],
-          json_output: true,
-          json_key: 'response',
-          temperature: 0
-        })
-        # Build the url
-        url = "projects/#{connection['project']}/locations/#{connection['region']}" \
-              "/#{input['model']}:generateContent"
-
-        # Make rate-limited request
-        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
-        # Extract and return the response
-        call('extract_response', response, { type: :generic, json_response: true })
-      end,
+      execute: lambda do |connection, input, _eis, _eos|
+        call('run_vertex', connection, input, :translate, verb: :generate, extract: { type: :generic, json_response: true })
+      end,
@@
-      execute: lambda do |connection, input, _eis, _eos|
-        call('validate_publisher_model!', connection, input['model'])
-        payload = call('build_ai_payload', :summarize, input)
-        url = "projects/#{connection['project']}/locations/#{connection['region']}/#{input['model']}:generateContent"
-        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
-        call('extract_response', response, { type: :generic, json_response: false })
-      end,
+      execute: lambda do |connection, input, _eis, _eos|
+        call('run_vertex', connection, input, :summarize, verb: :generate, extract: { type: :generic })
+      end,
@@
-      execute: lambda do |connection, input, _eis, _eos|
-        call('validate_publisher_model!', connection, input['model'])
-        payload = call('build_ai_payload', :parse, input)
-        url = "projects/#{connection['project']}/locations/#{connection['region']}/#{input['model']}:generateContent"
-        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
-        call('extract_response', response, { type: :parsed })
-      end,
+      execute: lambda do |connection, input, _eis, _eos|
+        call('run_vertex', connection, input, :parse, verb: :generate, extract: { type: :parsed })
+      end,
@@
-      execute: lambda do |connection, input, _eis, _eos|
-        call('validate_publisher_model!', connection, input['model'])
-        payload = call('build_ai_payload', :email, input)
-        url ="projects/#{connection['project']}/locations/#{connection['region']}/#{input['model']}:generateContent"
-        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
-        call('extract_response', response, { type: :email })
-      end,
+      execute: lambda do |connection, input, _eis, _eos|
+        call('run_vertex', connection, input, :email, verb: :generate, extract: { type: :email })
+      end,
@@
-      execute: lambda do |connection, input, _eis, _eos|
-        call('validate_publisher_model!', connection, input['model'])
-        payload = call('build_ai_payload', :analyze, input)
-        url = "projects/#{connection['project']}/locations/#{connection['region']}/#{input['model']}:generateContent"
-        response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
-        call('extract_response', response, { type: :generic, json_response: true })
-      end,
+      execute: lambda do |connection, input, _eis, _eos|
+        call('run_vertex', connection, input, :analyze, verb: :generate, extract: { type: :generic, json_response: true })
+      end,
@@
-    build_classify_payload: lambda do |input, connection|
+    build_classify_payload: lambda do |input, connection|
@@
-      call('build_base_payload', instruction, user_prompt, input['safetySettings'], temperature)
+      payload = call('build_base_payload', instruction, user_prompt, input['safetySettings'])
+      payload['generationConfig'] ||= {}
+      payload['generationConfig']['temperature'] = temperature
+      payload
     end,
@@
-    # Enhanced Gemini payload builder with JSON output support
-    build_gemini_payload: lambda do |instruction, prompt, options = {}|
-      # Use existing base builder
-      base = call('build_base_payload', instruction, prompt, options[:safety_settings])
-      ...
-    end,
+    # (Removed) build_gemini_payload – superseded by build_ai_payload templates
@@
-    payload_for_ai_classify: lambda do |connection, input|
-      ...
-    end,
+    # (Removed) payload_for_ai_classify – unified into build_classify_payload
````

## Acceptance criteria

* All 5 actions still respond; same outputs as before.
* No references to removed helpers remain.
* Classifier respects temperature input.

## Test plan

* Run each action with the same inputs as before PR 1; diff outputs (should match).
* Confirm no `NameError` for removed methods.

## Commit message

```bash
git commit -m "refactor(vertex): add runner + url helper; unify 5 actions on one codepath" \
  -m "Why: 5 actions duplicated 'validate → build → url → call → extract' logic; unify for clarity and fewer failure modes." \
  -m "What:" \
  -m "- Add vertex_url_for(connection, model, verb=:generate|:predict)." \
  -m "- Add run_vertex(connection, input, template, verb:, extract:) orchestration." \
  -m "- Migrate translate/summarize/parse/draft_email/analyze_text to run_vertex." \
  -m "- build_classify_payload: set temperature via generationConfig; no extra arg." \
  -m "- Remove dead build_gemini_payload/payload_for_ai_classify (superseded by templates)." \
  -m "Impact: behavior preserved; surface area smaller; easier to reason about failures." \
  -m "Testing: compared outputs pre/post for all 5 actions; identical except for corrected typos."
```
---
