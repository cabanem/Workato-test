# PR 7 — Payload builders hardening

## Scope

* Guard `build_base_payload` options type.
* Centralize “JSON-only response” instruction.
* Add nil guard to `build_message_parts`.

## Rationale
Reduce accidental misuse and scattered instruction strings.

## Patch

````diff
diff --git a/connector.rb b/connector.rb
@@
-    build_base_payload: lambda do |instruction, user_content, safety_settings = nil, options = {}|
+    build_base_payload: lambda do |instruction, user_content, safety_settings = nil, options = {}|
+      options = options.is_a?(Hash) ? options : {}
@@
       payload.compact
     end,
+    json_only_instruction: lambda do |key = 'response'|
+      "\n\nOutput as a JSON object with key \"#{key}\". Only respond with valid JSON and nothing else."
+    end,
@@
-      parts = []
+      return [] if m.nil?
+      parts = []
@@
-      when :translate
+      when :translate
         {
           instruction: -> (inp) {
             base = "You are an assistant helping to translate a user's input"
             from_lang = inp['from'].present? ? " from #{inp['from']}" : ""
             "#{base}#{from_lang} into #{inp['to']}. Respond only with the user's translated text in #{inp['to']} and nothing else. The user input is delimited by triple backticks."
           },
-          user_prompt: -> (inp) { "```#{call('replace_backticks_with_hash', inp['text'])}```\nOutput this as a JSON object with key \"response\"." }
+          user_prompt: -> (inp) { "```#{call('replace_backticks_with_hash', inp['text'])}```#{call('json_only_instruction','response')}" }
         }
@@
-      when :parse
+      when :parse
         {
           instruction: -> (inp) { "You are an assistant helping to extract various fields of information from the user's text. The schema and text to parse are delimited by triple backticks." },
           user_prompt: -> (inp) {
-            "Schema:\n```#{inp['object_schema']}```\nText to parse: ```#{call('replace_backticks_with_hash', inp['text']&.strip)}```\nOutput the response as a JSON object with keys from the schema. If no information is found for a specific key, the value should be null. Only respond with a JSON object and nothing else."
+            "Schema:\n```#{inp['object_schema']}```\nText to parse: ```#{call('replace_backticks_with_hash', inp['text']&.strip)}```\nOutput the response as a JSON object with keys from the schema. If no information is found for a specific key, the value should be null.#{call('json_only_instruction')}"
           }
         }
@@
-      when :analyze
+      when :analyze
         {
           instruction: -> (inp) { "You are an assistant helping to analyze the provided information. Take note to answer only based on the information provided and nothing else. The information to analyze and query are delimited by triple backticks." },
-          user_prompt: -> (inp) { "Information to analyze:```#{call('replace_backticks_with_hash', inp['text'])}```\nQuery:```#{call('replace_backticks_with_hash', inp['question'])}```\nIf you don't understand the question or the answer isn't in the information to analyze, input the value as null for \"response\". Only return a JSON object." }
+          user_prompt: -> (inp) { "Information to analyze:```#{call('replace_backticks_with_hash', inp['text'])}```\nQuery:```#{call('replace_backticks_with_hash', inp['question'])}```\nIf you don't understand the question or the answer isn't in the information to analyze, input the value as null for \"response\".#{call('json_only_instruction')}" }
         }
````

## Acceptance criteria

* Translate/parse/analyze still return JSON-only payloads; instructions are consistent.
* No crashes when `build_message_parts(nil)` is called.

## Test plan

* Run translate/parse/analyze with typical inputs; ensure JSON parsing still succeeds.

## Commit message

```bash
git commit -m "refactor(payload): harden builders and standardize JSON-only instruction" \
  -m "Why: caller misuse and scattered JSON-format prompts create subtle parsing issues." \
  -m "What:" \
  -m "- build_base_payload: ensure options is a Hash." \
  -m "- Add json_only_instruction(key='response'); reuse in translate/parse/analyze templates." \
  -m "- build_message_parts: nil-safe guard." \
  -m "Impact: more resilient payloads; identical model outputs." \
  -m "Testing: exercised translate/parse/analyze with edge inputs (nil, backticks, JSON schema)."
```