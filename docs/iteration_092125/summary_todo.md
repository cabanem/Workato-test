# Priorities for Iteration 09/23/25

## 0) **Fix-first (low risk, correctness + complexity)**

These are mechanical and safe; they eliminate confusion and cascade bugs that increase perceived complexity.

1. **Typos in field definitions**

   * **Edit:** In `connection.authorization.options.custom.fields` fix `ontrol_type` → `control_type` for `private_key`.
   * **Edit:** In `object_definitions.analyze_text_input`, fix `ptional: false` → `optional: false`.
   * **Impact:** Prevents silent UI/DSL misbehavior; reduces head‑scratching.

2. **Undefined method in `send_messages`**

   * **Problem:** `execute` calls `payload_for_send_message`, which does not exist.
   * **Edit:** Replace:

     ```ruby
     payload = if input['formatted_prompt'].present?
       input['formatted_prompt']
     else
       call('payload_for_send_message', input)
     end
     ```

     with:

     ```ruby
     payload = input['formatted_prompt'].presence || call('build_ai_payload', :send_message, input)
     ```
   * **Impact:** Removes a dead reference and uses the existing unified builder.

3. **Bad call to internal method**

   * **Problem:** In `methods.extract_response`, this line:

     ```ruby
     return standard_error_response(type, ratings) if ratings.blank?
     ```

     must be:

     ```ruby
     return call('standard_error_response', type, ratings) if ratings.blank?
     ```
   * **Impact:** Fixes a NameError path; keeps intended behavior.

4. **Wrong paging param casing (Google APIs)**

   * **Problem:** `fetch_fresh_publisher_models`/`fetch_publisher_models_minimal` use `page_size`/`page_token`; Google expects `pageSize`/`pageToken`.
   * **Edit:** Replace params keys accordingly in both methods.
   * **Impact:** Avoids intermittent listing failures; prevents fallback churn.

5. **Wrong response key in `fetch_publisher_models_minimal`**

   * **Problem:** Reads `resp['models']`; v1beta1 returns `publisherModels`.
   * **Edit:** Use:

     ```ruby
     models = resp['publisherModels'] || []
     ```
   * **Impact:** Eliminates inconsistent “zero models” edge case.

6. **Set without require**

   * **Problem:** `to_model_options` uses `Set` without `require 'set'`.
   * **Edit (simpler):** Replace with a Hash guard:

     ```ruby
     seen_ids = {}
     unique_models = filtered.select do |m|
       id = m['name'].to_s.split('/').last
       next false if seen_ids[id]
       seen_ids[id] = true
     end
     ```
   * **Impact:** Removes dependency; fewer surprises.

7. **`batch_fetch_drive_files` loop bug**

   * **Problem:** Uses `each_slice(5)` but references `file_id_input` that isn’t defined inside the slice.
   * **Edit:** Either revert to simple loop:

     ```ruby
     file_ids.each do |file_id_input|
       # existing file processing
     end
     ```

     or iterate the slice:

     ```ruby
     file_ids.each_slice(5) do |batch|
       batch.each do |file_id_input|
         # existing file processing
       end
     end
     ```
   * **Impact:** Fixes runtime errors; keeps logic simple.

8. **Leaked/undefined variable in `generate_embedding_single_exec`**

   * **Problem:** Returns `rate_limit_status: rate_limit_info` but never defines `rate_limit_info`.
   * **Edit:** After the API call:

     ```ruby
     rate = response.is_a?(Hash) ? response['rate_limit_status'] : nil
     ```

     and return `rate_limit_status: rate`.
   * **Impact:** Stops NameError; preserves telemetry.

9. **Model list cache freshness guard**

   * **Problem:** `Time.parse(cached_data['cached_at'])` can raise.
   * **Edit:** Wrap parse in a rescue and treat malformed cache as miss.
   * **Impact:** Avoids rare hard failures; simplifies retry path.

10. **Consistent error interface**

    * **Problem:** Mixed `raise` and `error(...)` (Workato DSL).
    * **Edit:** Replace remaining raw `raise` in connector code paths with `error(...)`, except inside `rescue => e` branches where re‑raise is intended via `error`.
    * **Impact:** One idiom = fewer branches to reason about.

---

## 1) **Unify the Vertex request “happy path”**

Reduce copy/paste across 6+ actions.

11. **Introduce a single URL helper**

* **Add:**

  ```ruby
  vertex_url_for = lambda do |connection, model, verb|
    base = "projects/#{connection['project']}/locations/#{connection['region']}"
    case verb.to_s
    when 'generate' then "#{base}/#{model}:generateContent"
    when 'predict'  then "#{base}/#{model}:predict"
    else error("Unsupported Vertex verb: #{verb}")
    end
  end
  ```
* **Use:** Replace all hardcoded `.../#{model}:generateContent` and `...:predict` with `call('vertex_url_for', connection, input['model'], :generate)` or `:predict`.
* **Impact:** One place to change path/version nuances.

12. **One runner for “validate → build → call → extract”**

* **Add method:**

  ```ruby
  run_vertex = lambda do |connection, input, template, verb:, extract: {}|
    call('validate_publisher_model!', connection, input['model'])
    payload = call('build_ai_payload', template, input, connection)
    url = call('vertex_url_for', connection, input['model'], verb)
    resp = call('rate_limited_ai_request', connection, input['model'], verb, url, payload)
    extract.present? ? call('extract_response', resp, extract) : resp
  end
  ```
* **Use:** In actions:

  * `translate_text`: `call('run_vertex', connection, input, :translate, verb: :generate, extract: {type: :generic, json_response: true})`
  * `summarize_text`: `... extract: {type: :generic}`
  * `parse_text`: `... extract: {type: :parsed}`
  * `draft_email`: `... extract: {type: :email}`
  * `analyze_text`: `... extract: {type: :generic, json_response: true}`
  * `analyze_image`: keep its custom builder, but still call via `run_vertex` with `template: :analyze_image`.
* **Impact:** Deletes 40–60 lines of repetitive code; lowers cognitive load.

13. **Retire `build_gemini_payload`**

* **Edit:** Move its JSON‑output behavior into `build_ai_payload :translate` (already done there) and update the one action using it to `run_vertex` (above).
* **Impact:** One payload system for everything.

14. **Delete dead builders**

* **Remove:** `payload_for_ai_classify` (unused after #12) and `payload_for_text_embedding` if you move both embedding actions to `build_ai_payload :text_embedding`.
* **Impact:** Fewer code paths that drift.

15. **Align `build_classify_payload` signature**

* **Problem:** It passes a 5th argument to `build_base_payload` (a float), which that method interprets as `options` (Hash).
* **Edit:** Build then set temperature:

  ```ruby
  payload = call('build_base_payload', instruction, user_prompt, input['safetySettings'])
  payload['generationConfig'] ||= {}
  payload['generationConfig']['temperature'] = temperature
  payload
  ```
* **Impact:** Removes an implicit, ambiguous arity contract.

---

## 2) **Tighten model discovery + picklists**

Make the dynamic list smaller/safer and the code clearer.

16. **Single “model fetch” with clear fallbacks**

* Keep `fetch_fresh_publisher_models` + `get_static_model_list`.
* **Simplify `cascade_model_discovery`:**

  * First: fresh in chosen region.
  * Second: fresh in `us-central1`.
  * Finally: static list.
  * **Drop** `fetch_publisher_models_minimal` branch (complexity > value).
* **Impact:** 1 fewer API pattern to maintain, clearer logs.

17. **Filter once, not thrice**

* `to_model_options` currently filters retired, bucket, and preview inside the map pipeline.
* **Edit:** Pre‑filter the raw array first into `eligible`, then do the unique + label map. The logic is clearer and faster.

18. **Label function: small guard**

* **Edit:** In `create_model_label`, guard against NIL `model_id` cleanly and return `''` to avoid strange labels.

19. **Return rate-limit friendly buckets**

* `enforce_vertex_rate_limits`’s family detection uses substring checks. Add `'2.5'` models to the same families (`gemini-pro` vs `gemini-flash`) so limits apply consistently:

  ```ruby
  when /gemini.*(pro|2\.5\-pro)/
  when /gemini.*(flash|2\.5\-flash)/
  ```
* **Impact:** Less surprise throttling, simpler mental model.

---

## 3) **Drive utilities: unify and simplify**

Keep behavior, shrink surface area.

20. **One `download_or_export` path already exists—lean into it**

* You’ve got `fetch_file_content`. Ensure both `fetch_drive_file` and `batch_fetch_drive_files` call *only* that method for content decisions. They do—keep it that way, don’t duplicate MIME logic anywhere else.

21. **Normalize ID extraction everywhere**

* You already have `extract_drive_file_id`. Use it in *all* Drive actions (`list_drive_files` when `folder_id` provided; `monitor_drive_changes` for folder arg; `batch_fetch_drive_files`—done). Remove any inline regex repeats elsewhere (none currently—but keep this rule).

22. **Centralize fields lists**

* The fields string for Drive metadata appears multiple times. Add:

  ```ruby
  drive_fields_basic = 'id,name,mimeType,size,modifiedTime,md5Checksum,owners'
  ```

  and reference in both `fetch_drive_file` and `batch_fetch_drive_files`.
* **Impact:** Single source of truth.

23. **`monitor_drive_changes` clarity pass**

* Keep behavior; just clarify the intent:

  * **Comment** that folder filtering is done post‑fetch for non‑shared drive mode and is best‑effort (Drive API doesn’t filter changes by folder).
  * Extract the added/modified/removed classification into a private helper `classify_change(change, include_removed)`.
* **Impact:** Less inline branching inside `execute`.

---

## 4) **Vector Search: reduce cognitive load**

24. **Remove bogus “dimension” validation**

* **Problem:** `validate_index_access` sets `dimensions` from `indexStats.vectorsCount` (that’s a count of *datapoints*, not vector dimensionality), then `batch_upsert_datapoints` rejects writes on “mismatch”.
* **Edit:** Drop the dimension check entirely (the service will 400 for true mismatches) **or** gate it behind a presence of an actual dimension value if you have a reliable source.
* **Impact:** Fewer false errors; eliminates a brittle branch.

25. **Normalize stats naming to what they are**

* In `validate_index_access`, set:

  ```ruby
  index_stats = {
    'index_id'        => index_id.to_s,
    'deployed_state'  => 'DEPLOYED',
    'total_datapoints'=> index_response.dig('indexStats', 'vectorsCount')&.to_i,
    'shards_count'    => index_response.dig('indexStats', 'shardsCount')&.to_i,
    # do not invent 'dimensions'
  }.merge(...)
  ```
* **Impact:** Names match meaning; fewer misreads.

26. **Host normalization in one helper**

* You’ve got this logic inline in `find_neighbors.execute`. Extract to `normalize_host(host)` method and reuse if you add more index endpoints later.
* **Impact:** Makes `execute` read top‑down.

27. **Response flattener: tiny helper**

* The neighbor flattening lives in `transform_find_neighbors_response`. It’s good. Add a 1‑liner helper `to_similarity(distance, max: 2.0)` so the intent is explicit and re‑usable.

---

## 5) **Error handling: one brain**

28. **`api_request` always wins**

* Replace scattered direct `get/post` calls (+ inline `after_error_response`) with `call('api_request', ...)` everywhere except where you *must* special‑case 404/403 messaging (you already do that in a few spots). Add an optional `context: {action: '...'}` param and pass it so `handle_vertex_error` can compose richer messages.

29. **Unify rate-limit backoff knobs**

* Put `MAX_RETRIES`, `BASE_DELAY`, `MAX_DELAY` as top‑level constants (or frozen fields inside the method). Both `handle_429_with_backoff` and `circuit_breaker_retry` should read them rather than embedding divergent defaults.
* **Impact:** One place to tune; fewer surprises.

30. **Consistent messages**

* Ensure `handle_vertex_error` and `handle_drive_error` produce similarly structured messages (first line: human label; second: suggested fix; third: actionable hint when `verbose_errors`). Add a tiny `format_hint(text)` helper if you want, or just keep the writeup consistent.

---

## 6) **Payload builders: one pattern**

31. **`build_base_payload` options contract**

* The current signature `(instruction, user_content, safety_settings = nil, options = {})` and the line `options.except('generationConfig')` imply a hash. Make this explicit:

  * **Edit:** Guard: `options = options.is_a?(Hash) ? options : {}`
  * **Impact:** Eliminates accidental float/strings creeping in (#15).

32. **Stop duplicating “JSON only output” instructions**

* You’ve embedded JSON‑only response text in multiple cases. Centralize into a helper:

  ```ruby
  def json_only_instruction(key='response')
    "\n\nOutput as a JSON object with key \"#{key}\". Only respond with valid JSON and nothing else."
  end
  ```

  Use it in translate/parse/analyze/classify builders.
* **Impact:** One edit = all aligned.

33. **`build_message_parts` parsing guards**

* Already robust. Add short‑circuit return `[]` for nil `m` to avoid oddities.
* **Impact:** Fewer nil checks upstream.

---

## 7) **Picklists & object defs: remove duplication**

34. **Model picklists share one dynamic path**

* `available_text_models`, `available_image_models`, `available_embedding_models` are identical patterns. Create:

  ```ruby
  def picklist_for(bucket, static, connection)
    call('dynamic_model_picklist', connection, bucket, static)
  end
  ```

  and call it in each list lambda.
* **Impact:** Keeps the three lists tiny.

35. **Shared `safety_and_usage` is present—use it**

* In outputs where you currently re‑concat `safety_rating_schema` + `usage_schema`, replace with one line concat of `object_definitions['safety_and_usage']`.
* **Impact:** Shorter, less chance of drift.

36. **Consistent group/label strings**

* Some actions (“Subtitle”, “Group” labels) vary slightly. Standardize group names: **Model**, **Prompt/Task input**, **Generation**, **Safety**, **Advanced**. This affects only connector UI metadata; not runtime.

---

## 8) **Tests & diagnostics: smaller surface, same value**

37. **`test_connection`: use `api_request` and shared URL helper**

* Replace bespoke `get(...)` with `api_request`. Build model probe URL via `vertex_url_for` with a known model name (or skip if you don’t want to maintain it).
* **Impact:** Removes one-off request code.

38. **Environment report: remove unused `developer_api_host`**

* It’s not a connection field. Drop it from the `environment` hash to avoid confusion.

39. **Quota info: mark as static**

* The “quotas” block is static text. Move it into a `QUOTA_DEFAULTS` constant. That communicates intent (not live).

---

## 9) **Small cleanups that help future readers**

40. **Consistent logging**

* Replace `puts` with a thin wrapper `log_debug(msg)` so you can easily keep/strip logs. At minimum, prefix logs with feature tags: `[models]`, `[rate_limit]`, `[drive]`.

41. **Trim duplicate synonyms in language list**

* `Chinese`, `Mandarin`, and `Mandarin Chinese` will lead to selection ambiguity. Keep as‑is for compatibility if users rely on them, but **comment** why they appear multiple times to avoid “cleanup” PRs re‑adding confusion.

42. **Remove unused helpers**

* `truthy?` appears unused. Delete it.
* **Impact:** One less micro‑concept.

43. **Normalize symbol/string handling**

* Where you accept enums (e.g., `verb`), coerce to string once at the helper boundary instead of calling `.to_s` scattered throughout.

---

## 10) **Minimal code snippets to apply (copy/paste)**

These make several items above concrete.

**A) `send_messages.execute`**

```ruby
execute: lambda do |connection, input, _eis, _eos|
  call('validate_publisher_model!', connection, input['model'])

  payload = input['formatted_prompt'].presence || call('build_ai_payload', :send_message, input)
  url = call('vertex_url_for', connection, input['model'], :generate)

  call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
end
```

**B) Fix `extract_response` call**

```ruby
return call('standard_error_response', type, ratings) if ratings.blank?
```

**C) `fetch_fresh_publisher_models` params casing**

```ruby
resp = get(url).params(
  pageSize: 500,
  pageToken: page_token,
  view: 'PUBLISHER_MODEL_VIEW_BASIC'
)
```

**D) `batch_fetch_drive_files` loop**

```ruby
file_ids.each do |file_id_input|
  file_id = call('extract_drive_file_id', file_id_input)
  # existing metadata + content fetch
end
```

**E) `generate_embedding_single_exec` telemetry**

```ruby
resp = call('rate_limited_ai_request', connection, model, 'embedding', url, payload)
vector = resp&.dig('predictions', 0, 'embeddings', 'values') || resp&.dig('predictions', 0, 'embeddings')&.first&.dig('values') || []
rate  = resp.is_a?(Hash) ? resp['rate_limit_status'] : nil
{
  'vector' => vector,
  'dimensions' => vector.length,
  'model_used' => model,
  'token_count' => token_count,
  'rate_limit_status' => rate
}
```

**F) Drop bad “dimension” validation**

* In `validate_index_access`, remove the `'dimensions'` and `'total_datapoints'` misassignment.
* In `batch_upsert_datapoints`, delete the vector length check block.

---

## 11) **What to delete (safe)**

* `payload_for_ai_classify` (duplicated logic).
* `fetch_publisher_models_minimal` (after #16).
* `truthy?` (unused).
* The stray reference to `developer_api_host` in test output.
* (Optional) The `embedding` branch inside `extract_response` if no action uses it—otherwise leave it.

---

## 12) **Regression checklist (fast, practical)**

Run these after each thematic PR:

* **Auth**

  * OAuth2 and Service Account both: `test` succeeds; Drive list returns ≥0 files.
* **Chat/generation**

  * `send_messages`, `translate_text`, `summarize_text`, `parse_text`, `draft_email`, `analyze_text`, `analyze_image` each: non‑empty response, token usage present when API returns it.
* **Embeddings**

  * Single & batch: dimensions match returned vector length; `embeddings_json` parses.
* **Vector Search**

  * `find_neighbors`: accepts host with/without protocol, returns flattened `top_matches` sorted by score.
  * `upsert_index_datapoints`: succeeds for a known index (with dimension check removed).
* **Drive**

  * `fetch_drive_file`: Google Doc exported; binary file downloaded; `needs_processing` true for PDFs.
  * `batch_fetch_drive_files`: mixed IDs; succeeds + aggregates metrics; fail‑fast mode works.
  * `monitor_drive_changes`: initial token path returns `is_initial_token: true`; incremental path classifies added/modified/removed; `new_page_token` advances.

---

### Net effect

* **Fewer code paths:** one payload builder, one Vertex runner, one URL helper, one error path.
* **Less drift:** no duplicate classification/email/translate logic.
* **Fewer brittle assumptions:** no fake “dimensions”, no hidden NameErrors, no missing methods.
* **Same functionality:** every action still exists and behaves the same—just simpler to reason about and safer to evolve.
