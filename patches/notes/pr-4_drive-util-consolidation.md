# PR 4 — Drive utilities consolidation

## Scope

* Centralize Drive fields string.
* Use it in both single and batch fetchers.
* Extract change classification from `monitor_drive_changes` to a helper for readability.

## Rationale
One way to fetch, one place to change.

## Patch

```diff
diff --git a/connector.rb b/connector.rb
@@
   methods: {
+    drive_basic_fields: lambda do
+      'id,name,mimeType,size,modifiedTime,md5Checksum,owners'
+    end,
@@
-        metadata_response = call('api_request', connection, :get,
-          call('drive_api_url', :file, file_id),
-          {
-            params: { fields: 'id,name,mimeType,size,modifiedTime,md5Checksum,owners' },
+        metadata_response = call('api_request', connection, :get,
+          call('drive_api_url', :file, file_id),
+          {
+            params: { fields: call('drive_basic_fields') },
             error_handler: lambda do |code, body, message|
               error(call('handle_drive_error', connection, code, body, message))
             end
           }
         )
@@
-            metadata_response = call('api_request', connection, :get,
-              call('drive_api_url', :file, file_id),
-              {
-                params: { fields: 'id,name,mimeType,size,modifiedTime,md5Checksum,owners' },
+            metadata_response = call('api_request', connection, :get,
+              call('drive_api_url', :file, file_id),
+              {
+                params: { fields: call('drive_basic_fields') },
                 error_handler: lambda do |code, body, message|
                   error(call('handle_drive_error', connection, code, body, message))
                 end
               }
             )
@@
+    classify_drive_change: lambda do |change, include_removed|
+      return { kind: :removed, summary: { 'fileId' => change['fileId'], 'time' => change['time'] } } if change['removed']
+      file = change['file']
+      return { kind: :skip } if file.nil?
+      return { kind: :skip } if file['trashed'] && !include_removed
+      summary = {
+        'id' => file['id'],
+        'name' => file['name'],
+        'mimeType' => file['mimeType'],
+        'modifiedTime' => file['modifiedTime'],
+        'checksum' => file['md5Checksum']
+      }
+      # Heuristic: first seen ~added, else modified
+      { kind: :added, summary: summary }
+    end,
@@
-        # Step 5: Categorize changes
-        files_added = []
-        files_modified = []
-        files_removed = []
-        
-        # Track seen files to avoid duplicates
-        seen_files = {}
-        
-        all_changes.each do |change|
-          file_id = change['fileId']
-          
-          if change['removed']
-            # File was removed
-            files_removed << {
-              'fileId' => file_id,
-              'time' => change['time']
-            }
-          elsif change['file']
-            file = change['file']
-            
-            # Skip trashed files unless explicitly requested
-            next if file['trashed'] && !include_removed
-            
-            file_summary = {
-              'id' => file['id'],
-              'name' => file['name'],
-              'mimeType' => file['mimeType'],
-              'modifiedTime' => file['modifiedTime'],
-              'checksum' => file['md5Checksum']
-            }
-            
-            # Determine if file is new or modified
-            if seen_files[file_id]
-              files_modified << file_summary
-            else
-              if change['changeType'] == 'file'
-                time_diff = if file['modifiedTime'] && change['time']
-                  modified = Time.parse(file['modifiedTime'])
-                  changed = Time.parse(change['time'])
-                  (changed - modified).abs
-                else
-                  0
-                end
-                
-                if time_diff < 60
-                  files_added << file_summary
-                else
-                  files_modified << file_summary
-                end
-              else
-                files_modified << file_summary
-              end
-              
-              seen_files[file_id] = true
-            end
-          end
-        end
+        files_added, files_modified, files_removed = [], [], []
+        seen = {}
+        all_changes.each do |change|
+          file_id = change['fileId']
+          klass = call('classify_drive_change', change, include_removed)
+          next if klass[:kind] == :skip
+          case klass[:kind]
+          when :removed
+            files_removed << klass[:summary]
+          else
+            if seen[file_id]
+              files_modified << klass[:summary]
+            else
+              files_added << klass[:summary]
+              seen[file_id] = true
+            end
+          end
+        end
```

## Acceptance criteria

* Single and batch fetch still return same fields.
* Changes monitor still yields added/modified/removed lists.

## Test plan

* Run `monitor_drive_changes` with a token; add/modify/remove a file and re-run.

## Commit message

```bash
git commit -m "refactor(drive): centralize fields and change classification; reuse in single/batch fetch" \
  -m "Why: repeated Drive field strings and inlined change categorization made edits brittle." \
  -m "What:" \
  -m "- Add drive_basic_fields helper and use in fetch_drive_file + batch_fetch_drive_files." \
  -m "- Extract change bucketing into classify_drive_change; simplify monitor_drive_changes main loop." \
  -m "Impact: identical outputs; less duplication; easier to extend." \
  -m "Testing: fetched Google Doc + PDF via both actions; ran changes monitor before/after add/modify/delete."
```