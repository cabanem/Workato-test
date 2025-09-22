# PR 3 — Model discovery simplification

## Scope

* Simplify `cascade_model_discovery` (primary region → us‑central1 → static).
* Remove `fetch_publisher_models_minimal`.
* Clarify/centralize filtering in `to_model_options`.
* Guard in `create_model_label`.

## Rationale
Fewer paths = fewer weird edge failures.

## Patch

```diff
diff --git a/connector.rb b/connector.rb
@@
-    cascade_model_discovery: lambda do |connection, publisher, region|
-      # Strategy 1: Try primary API endpoint
-      begin
-        puts "Model discovery: trying primary API endpoint..."
-        models = call('fetch_fresh_publisher_models', connection, publisher, region)
-        if models.present?
-          puts "Model discovery: primary API succeeded (#{models.length} models)"
-          models.each { |m| m['source'] = 'primary_api' }
-          return models
-        end
-      rescue => e
-        puts "Model discovery: primary API failed: #{e.message}"
-      end
-      # Strategy 2: Try alternative region if not us-central1
-      if region != 'us-central1'
-        begin
-          puts "Model discovery: trying fallback region (us-central1)..."
-          models = call('fetch_fresh_publisher_models', connection, publisher, 'us-central1')
-          if models.present?
-            puts "Model discovery: fallback region succeeded (#{models.length} models)"
-            models.each { |m| m['source'] = 'fallback_region' }
-            return models
-          end
-        rescue => e
-          puts "Model discovery: fallback region failed: #{e.message}"
-        end
-      end
-      # Strategy 3: Try different view parameter
-      begin
-        puts "Model discovery: trying minimal view mode..."
-        models = call('fetch_publisher_models_minimal', connection, publisher, region)
-        if models.present?
-          puts "Model discovery: minimal view succeeded (#{models.length} models)"
-          models.each { |m| m['source'] = 'minimal_view' }
-          return models
-        end
-      rescue => e
-        puts "Model discovery: minimal view failed: #{e.message}"
-      end
-      # Strategy 4: Use static curated list as final fallback
+    cascade_model_discovery: lambda do |connection, publisher, region|
+      begin
+        puts "Model discovery: primary API..."
+        models = call('fetch_fresh_publisher_models', connection, publisher, region)
+        if models.present?
+          models.each { |m| m['source'] = 'primary_api' }
+          return models
+        end
+      rescue => e
+        puts "Model discovery: primary failed: #{e.message}"
+      end
+      if region != 'us-central1'
+        begin
+          puts "Model discovery: fallback us-central1..."
+          models = call('fetch_fresh_publisher_models', connection, publisher, 'us-central1')
+          if models.present?
+            models.each { |m| m['source'] = 'fallback_region' }
+            return models
+          end
+        rescue => e
+          puts "Model discovery: fallback failed: #{e.message}"
+        end
+      end
+      # Final: static curated list
       begin
         puts "Model discovery: using static curated list as final fallback"
         models = call('get_static_model_list', connection, publisher)
         models.each { |m| m['source'] = 'static_fallback' }
         puts "Model discovery: static fallback provided #{models.length} models"
         return models
       rescue => e
         puts "Model discovery: static fallback failed: #{e.message}"
         return []
       end
     end,
@@
-    fetch_publisher_models_minimal: lambda do |connection, publisher, region|
-      ...
-    end,
+    # (Removed) fetch_publisher_models_minimal
@@
-    to_model_options: lambda do |models, bucket:, include_preview: false|
+    to_model_options: lambda do |models, bucket:, include_preview: false|
       return [] if models.blank?
-      # Pre-compile the regex for retired models to avoid recompiling
-      retired_pattern = /(^|-)1\.0-|text-bison|chat-bison/
-    
-      # Filter models efficiently
-      filtered = models.select do |m|
-        model_id = m['name'].to_s.split('/').last
-        next false if model_id.blank?
-        
-        # Skip retired models
-        next false if model_id =~ retired_pattern
-        
-        # Check bucket match
-        next false unless call('vertex_model_bucket', model_id) == bucket
-        
-        # Check GA status if needed
-        if !include_preview
-          stage = m['launchStage'].to_s
-          next false unless stage == 'GA' || stage.blank?
-        end
-        
-        true
-      end
+      retired_pattern = /(^|-)1\.0-|text-bison|chat-bison/
+      eligible = models.select do |m|
+        id = m['name'].to_s.split('/').last
+        next false if id.blank?
+        next false if id =~ retired_pattern
+        next false unless call('vertex_model_bucket', id) == bucket
+        if !include_preview
+          stage = m['launchStage'].to_s
+          next false unless stage == 'GA' || stage.blank?
+        end
+        true
+      end
@@
-      unique_models = filtered.select do |m|
+      unique_models = eligible.select do |m|
         id = m['name'].to_s.split('/').last
         next false if id.blank?
         next false if seen_ids[id]
         seen_ids[id] = true
       end
@@
-    create_model_label: lambda do |model_id, model_metadata = {}|
+    create_model_label: lambda do |model_id, model_metadata = {}|
+      return '' if model_id.to_s.strip.empty?
```

## Acceptance criteria

* Dynamic picklists still populate with reasonable lists.
* No references to `fetch_publisher_models_minimal`.

## Test plan

* Toggle `dynamic_models` on/off; compare picklists with/without preview.

## Commit message

```bash
git commit -m "refactor(models): simplify discovery cascade and tighten filtering" \
  -m "Why: too many discovery branches increased drift and opaque failures." \
  -m "What:" \
  -m "- cascade_model_discovery now tries: region → us-central1 → static fallback." \
  -m "- Remove fetch_publisher_models_minimal (unused with new cascade)." \
  -m "- to_model_options: single filter pass (bucket, retired ids, GA gating) + dedupe." \
  -m "- create_model_label: nil/empty guard." \
  -m "Impact: same visible picklist behavior; fewer code paths; easier logs." \
  -m "Testing: toggled dynamic_models & include_preview; verified text/image/embedding picklists populate."
```

---
