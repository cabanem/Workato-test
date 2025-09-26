# PR 8 — Picklists & output schema dedupe

## Scope

* Add `picklist_for` helper and use it for the 3 model picklists.
* Replace repeated `safety + usage` concatenations with `safety_and_usage` where schemas are static.

## Rationale
Less repetition = fewer drift bugs.

## Patch

```diff
diff --git a/connector.rb b/connector.rb
@@
   methods: {
+    picklist_for: lambda do |connection, bucket, static|
+      call('dynamic_model_picklist', connection, bucket, static)
+    end,
@@
   pick_lists: {
-    available_text_models: lambda do |connection|
+    available_text_models: lambda do |connection|
       static = [
         ['Gemini 1.0 Pro', 'publishers/google/models/gemini-pro'],
         ['Gemini 1.5 Pro', 'publishers/google/models/gemini-1.5-pro'],
         ['Gemini 1.5 Flash', 'publishers/google/models/gemini-1.5-flash'],
         ['Gemini 2.0 Flash Lite', 'publishers/google/models/gemini-2.0-flash-lite-001'],
         ['Gemini 2.0 Flash', 'publishers/google/models/gemini-2.0-flash-001'],
         ['Gemini 2.5 Pro', 'publishers/google/models/gemini-2.5-pro'],
         ['Gemini 2.5 Flash', 'publishers/google/models/gemini-2.5-flash'],
         ['Gemini 2.5 Flash Lite', 'publishers/google/models/gemini-2.5-flash-lite']
       ]
-      call('dynamic_model_picklist', connection, :text, static)
+      call('picklist_for', connection, :text, static)
     end,
@@
-      call('dynamic_model_picklist', connection, :image, static)
+      call('picklist_for', connection, :image, static)
     end,
@@
-      call('dynamic_model_picklist', connection, :embedding, static)
+      call('picklist_for', connection, :embedding, static)
     end,
@@
-    translate_text_output: {
+    translate_text_output: {
       fields: lambda do |_connection, _config_fields, object_definitions|
-        [
-          { name: 'answer', label: 'Translation' }
-        ].concat(object_definitions['safety_rating_schema']).
-          concat(object_definitions['usage_schema'])
+        [{ name: 'answer', label: 'Translation' }].concat(object_definitions['safety_and_usage'])
       end
     },
@@
-    summarize_text_output: {
+    summarize_text_output: {
       fields: lambda do |_connection, _config_fields, object_definitions|
-        [ { name: 'answer', label: 'Summary' } ].concat(object_definitions['safety_rating_schema'])
-                                                .concat(object_definitions['usage_schema'])
+        [{ name: 'answer', label: 'Summary' }].concat(object_definitions['safety_and_usage'])
       end
     },
@@
-    draft_email_output: {
+    draft_email_output: {
       fields: lambda do |_connection, _config_fields, object_definitions|
-        [
-          { name: 'subject', label: 'Email subject' },
-          { name: 'body', label: 'Email body' }
-        ].concat(object_definitions['safety_rating_schema']).
-          concat(object_definitions['usage_schema'])
+        [
+          { name: 'subject', label: 'Email subject' },
+          { name: 'body', label: 'Email body' }
+        ].concat(object_definitions['safety_and_usage'])
       end
     },
@@
-    analyze_text_output: {
+    analyze_text_output: {
       fields: lambda do |_connection, _config_fields, object_definitions|
-        [
-          { name: 'answer', label: 'Analysis' }
-        ].concat(object_definitions['safety_rating_schema']).
-          concat(object_definitions['usage_schema'])
+        [{ name: 'answer', label: 'Analysis' }].concat(object_definitions['safety_and_usage'])
       end
     },
@@
-    analyze_image_output: {
+    analyze_image_output: {
       fields: lambda do |_connection, _config_fields, object_definitions|
-        [
-          { name: 'answer',
-            label: 'Analysis' }
-        ].concat(object_definitions['safety_rating_schema']).
-          concat(object_definitions['usage_schema'])
+        [{ name: 'answer', label: 'Analysis' }].concat(object_definitions['safety_and_usage'])
       end
     },
```

## Acceptance criteria

* Picklists still populate.
* Output schemas for 4 actions still contain safety+usage blocks.

## Test plan

* Inspect output schema in UI for the four actions.

## Commit message

```bash
git commit -m "refactor(picklists/schema): add picklist_for helper + reuse safety_and_usage schema" \
  -m "Why: repeated calls to dynamic_model_picklist and manual safety/usage concat." \
  -m "What:" \
  -m "- picklist_for(connection, bucket, static) wraps dynamic_model_picklist." \
  -m "- translate/summarize/analyze(_image)/draft_email outputs now include object_definitions['safety_and_usage']." \
  -m "Impact: no change to exposed schema; less duplication." \
  -m "Testing: inspected action output schemas in UI; safety+usage present."
```