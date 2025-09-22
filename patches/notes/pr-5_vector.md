# PR 5 — Vector Search sane defaults

## Scope

* Remove bogus “dimension” validation and incorrect stats from index check.
* Add `normalize_host` helper and use it.
* Add `to_similarity` helper and use it in neighbors transformer.

## Rationale
Stop pretending you know the index dimensionality; let the API enforce it.

## Patch

```diff
diff --git a/connector.rb b/connector.rb
@@
+    normalize_host: lambda do |host|
+      h = host.to_s.strip
+      error('Index endpoint host is required') if h.blank?
+      h = h.gsub(/^https?:\/\//i, '').gsub(/\/+$/, '')
+      error("Invalid index endpoint host format: #{h}") unless h.match?(/^[\w\-\.]+(:\d+)?$/)
+      h
+    end,
+    to_similarity: lambda do |distance, max = 2.0|
+      s = 1.0 - (distance.to_f / max.to_f)
+      s < 0 ? 0.0 : s
+    end,
@@
-        host = input['index_endpoint_host'].to_s.strip
-        # Host normalization
-        if host.blank?
-          error('Index endpoint host is required')
-        end
-        
-        # Remove protocol if present and trailing slashes
-        host = host.gsub(/^https?:\/\//i, '').gsub(/\/+$/, '')
-        
-        # Validate host format (basic check for valid domain or IP)
-        unless host.match?(/^[\w\-\.]+(:\d+)?$/)
-          error("Invalid index endpoint host format: #{host}")
-        end
+        host = call('normalize_host', input['index_endpoint_host'])
@@
-        # Check if index is deployed
+        # Check if index is deployed
         deployed_indexes = index_response['deployedIndexes'] || []
@@
-        index_stats = {
-          'index_id' => index_id.to_s,
-          'deployed_state' => 'DEPLOYED',
-          'dimensions' => index_response.dig('indexStats', 'vectorsCount')&.to_i || 0,
-          'total_datapoints' => index_response.dig('indexStats', 'shardsCount')&.to_i || 0,
+        index_stats = {
+          'index_id' => index_id.to_s,
+          'deployed_state' => 'DEPLOYED',
+          'total_datapoints' => index_response.dig('indexStats', 'vectorsCount')&.to_i,
+          'shards_count' => index_response.dig('indexStats', 'shardsCount')&.to_i,
           'display_name' => index_response['displayName'].to_s,
           'created_time' => created_time || '',
           'updated_time' => updated_time || ''
         }
@@
-              # Validate vector dimensions if we have index metadata
-              if index_stats['dimensions'] && index_stats['dimensions'] > 0
-                if dp['feature_vector'].length != index_stats['dimensions']
-                  error("Vector dimension mismatch. Expected #{index_stats['dimensions']} dimensions, got #{dp['feature_vector'].length} for datapoint '#{dp['datapoint_id']}'")
-                end
-              end
+              # Do not attempt to validate vector length here; let the API enforce it.
@@
-          # Normalize distance to similarity score (0-1)
-          # Assuming distances are typically 0-2 for cosine distance
-          max_distance = 2.0
-          similarity_score = [1.0 - (distance / max_distance), 0.0].max
+          similarity_score = call('to_similarity', distance, 2.0)
```

## Acceptance criteria

* `find_neighbors` still works; stricter host validation still passes valid inputs.
* `upsert_index_datapoints` no longer fails on fake “dimension mismatch”.
* Index stats fields reflect actual meanings.

## Test plan

* Run `find_neighbors` against a known endpoint.
* Upsert a datapoint with valid vector length and ensure success.

## Commit message

```bash
git commit -m "refactor(vector): sane defaults—host normalizer, similarity helper; drop bogus dim checks | Why: local dimension 'validation' was wrong source; let Vertex enforce it. Host parsing repeated. | What: - Add normalize_host(host) and use in find_neighbors. - Add to_similarity(distance, max=2.0) and use in response transformer. - validate_index_access: report vectorsCount/shardsCount under correct keys; remove fake dim validation. - upsert_index_datapoints: stop rejecting on local dim mismatch. | Impact: fewer false negatives; better stats semantics; clearer errors on bad hosts. | Testing: upsert with valid vectors; neighbors query returns sorted top_matches with similarity."
```

---
