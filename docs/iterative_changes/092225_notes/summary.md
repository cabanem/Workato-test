## 0) Fix two correctness landmines (no behavior change intended, but they can bite)

1. **Illegal `break` in a non‑loop**
   In `fetch_publisher_models`, this line can raise a `LocalJumpError`:

   ```ruby
   break if cache_time.nil?
   ```

   **Change to:**

   ```ruby
   unless cache_time
     call('log_debug', 'Cached model list missing timestamp; refreshing…')
   else
     # keep rest of logic
   end
   ```

   or simply `# do nothing; fall through to refresh`.

2. **Undefined variable in `to_model_options`**
   You build `eligible = …` then use `filtered`. That’s a bug.

   ```ruby
   unique_models = filtered.select do |m|  # BUG
   ```

   **Change to:**

   ```ruby
   unique_models = eligible.select do |m|
   ```

---

## 1) Stop mutating shared field arrays (quiet dup everywhere)

This is the largest hidden source of “why are my fields duplicated?” complexity. Everywhere you do `object_definitions['…'].concat([...])` you’re mutating the base array that other object definitions reuse.

**Rule:** never mutate arrays returned from `object_definitions[…]`. Use `dup +` or `+` on a duped array.

Apply this pattern in all the places below.

**Edit pattern**

```ruby
# BEFORE
base_fields = object_definitions['drive_file_fields']
extended = base_fields.concat([ … ])
extended

# AFTER (no mutation)
base_fields = object_definitions['drive_file_fields'].dup
base_fields + [
  …extra fields…
]
```

**Change in these definitions:**

* `drive_file_extended` (uses `concat`)
* `send_messages_input`
* `translate_text_input`
* `summarize_text_input`
* `parse_text_input`
* `draft_email_input`
* `analyze_text_input`
* `safety_and_usage` (it does `safety.concat(usage)`) → `object_definitions['safety_rating_schema'] + object_definitions['usage_schema']`
* `parse_text_output` is fine mutating the *local* `schema`, but make sure you’re not reusing the parsed schema elsewhere in the same call.

Impact: eliminates cross‑contamination between definitions and flakey, order‑dependent field duplication.

---

## 2) Route all Gemini text actions through one path (`run_vertex`)

You already built `run_vertex`. Use it consistently to remove local “mini‑frameworks” in actions.

3. **`send_messages.execute` → one‑liner**
   Replace the custom body with a `run_vertex` call that uses the existing `:send_message` template:

   ```ruby
   # BEFORE
   call('validate_publisher_model!', connection, input['model'])
   payload = input['formatted_prompt'].presence || call('build_ai_payload', :send_message, input)
   url = "projects/#{connection['project']}/locations/#{connection['region']}/#{input['model']}:generateContent"
   response = call('rate_limited_ai_request', connection, input['model'], 'inference', url, payload)
   response

   # AFTER
   input['formatted_prompt'].present? ?
     call('rate_limited_ai_request', connection, input['model'], 'inference',
          call('vertex_url_for', connection, input['model'], :generate),
          input['formatted_prompt']) :
     call('run_vertex', connection, input, :send_message, verb: :generate)
   ```

4. **`ai_classify.execute` → one‑liner**
   Swap the manual validate/build/call/extract with:

   ```ruby
   call('run_vertex', connection, input, :ai_classify, verb: :generate, extract: { type: :classify })
   ```

5. **Use `vertex_url_for` everywhere**
   Replace hand‑built URLs in:

   * `send_messages` (after change above, covered)
   * `ai_classify` (covered)
   * `generate_embedding_single_exec`
   * `generate_embeddings_batch_exec`
   * Any other place you manually glue `projects/#{project}/locations/#{region}/#{model}:…`

   **Edit pattern**

   ```ruby
   url = call('vertex_url_for', connection, model, :predict)  # for embeddings
   ```

---

## 3) Unify HTTP/error handling and logging

6. **Use `api_request` wrapper everywhere**
   You drift between raw `get/post` with `.after_error_response` and `api_request`. Standardize on `api_request` for consistent error decoration. Targets:

   * `test_connection` action (both Vertex and Drive calls)
   * `fetch_fresh_publisher_models` listing (wrap in `api_request` to get uniform errors and context strings)
   * `validate_publisher_model!` (the GET can go through `api_request` with `context: { action: 'Get publisher model' }`)
   * All Drive calls that still use raw `get`/`post` with inline `after_error_response`

7. **Replace every `puts` with `log_debug`**
   Files: model discovery, caching, rate limiting, circuit breaker, etc. You already defined `log_debug`.

8. **Inline error lambdas → `context:` strings**
   Where you only add a label (e.g., “List datasets”), pass `context: { action: 'List datasets' }` to `api_request` and let `handle_vertex_error` format it. This deletes a lot of tiny inline lambdas.

---

## 4) Make rate limiting and backoff plumbing simpler and consistent

9. **Remove unused `rate_limit_info` variable in `generate_embeddings_batch_exec`**
   You compute `rate_limit_info = {…}` but never set it from responses; you then return it. Either:

   * Populate it from the last batch response: `response['rate_limit_status']`, or
   * Drop it from the return payload (safer to keep for contract: set from last response).

   **Minimal change (keep field; use last response):**

   ```ruby
   last_rate = response.is_a?(Hash) ? response['rate_limit_status'] : nil
   …
   'rate_limit_status' => last_rate,
   ```

10. **Centralize per‑family RPM limits into one constant**
    Create `VERTEX_RPM = { 'gemini-pro' => 300, 'gemini-flash' => 600, 'embedding' => 600 }` and reference it both in `enforce_vertex_rate_limits` and `test_connection` (quota\_info). Deletes duplicate literals.

11. **Have `handle_429_with_backoff` also catch Retry‑After from JSON error bodies** (many Google APIs include it there). Add a tiny extraction:

```ruby
retry_after ||= (parse_json(e.response&.body)['error']['details']&.find { |d| d['@type']&.include?('RetryInfo') }&.dig('retryDelay', 'seconds') rescue nil)
```

(Keep behavior identical; this only honors a more precise hint when present.)

---

## 5) Consolidate small helpers; remove duplication

12. **Introduce `project_region_path(connection)`**
    Returns `"projects/#{project}/locations/#{region}"`. Replace all re‑builds. This collapses a dozen string interpolations.

13. **`get_export_mime_type` → map literal**
    Replace the `case` with a frozen hash lookup. Behavior identical; smaller and clearer.

    ```ruby
    EXPORTS = {
      'application/vnd.google-apps.document'    => 'text/plain',
      'application/vnd.google-apps.spreadsheet' => 'text/csv',
      'application/vnd.google-apps.presentation'=> 'text/plain'
    }.freeze
    EXPORTS[mime_type]
    ```

14. **Unify “replace backticks” utility name**
    `replace_backticks_with_hash` is specific to prompts; rename internally to `sanitize_triple_backticks` and keep an alias with the old name to avoid touching all call sites:

    ````ruby
    sanitize_triple_backticks = lambda { |t| t&.gsub('```', '####') }
    replace_backticks_with_hash = sanitize_triple_backticks
    ````

15. **Deduplicate repeated `"projects/.../datasets"` test URL**
    Use `project_region_path` + `'datasets'` with `api_request`.

---

## 6) Tighten model discovery path

16. **`dynamic_model_picklist` should return early** when dynamic disabled:

    ```
    return static_fallback unless connection['dynamic_models']
    ```

    You already log it; keep the log but return immediately.

17. **Cache guard in `fetch_publisher_models`:**
    Wrap cache read in a single `begin` / `rescue` and avoid noisy `puts` on cache miss; just log via `log_debug`. (Less code, same behavior.)

18. **Limit pages via constant; remove magic numbers**
    Extract `MAX_MODEL_LIST_PAGES = 5` and `PAGE_SIZE = 500`. Use those in `fetch_fresh_publisher_models`.

19. **Standardize all model discovery logs through `log_debug`** (see §3).

20. **`get_static_model_list` doesn’t use `publisher`;** keep param for signature compatibility, but add `_publisher` to quiet linters:

    ```ruby
    get_static_model_list: lambda do |connection, _publisher|
    ```

    (No behavior change.)

---

## 7) Make action bodies slimmer by reusing helpers

21. **`find_neighbors.execute`**

    * Use `project_region_path` for the constant segments.
    * Keep the public/PSC host normalization as‑is.
    * Route the POST via `api_request` (you already do) and pass `context:` (`{ action: 'Find neighbors' }`) instead of hand‑rolled 404 msg. Then add your friendly 404 message as a special‑case in `handle_vertex_error` when `context[:action] == 'Find neighbors'` and `code == 404`. This removes the inline error lambda.

22. **`upsert_index_datapoints.execute`**
    Already delegates to `batch_upsert_datapoints`. No change other than converting its own `api_request` calls to `api_request` wrapper if any remain (they don’t).

23. **`monitor_drive_changes`**
    Replace raw URLs with `drive_api_url(:start_token)` and `drive_api_url(:changes)` for symmetry. You already defined those. Drops a couple of literals.

---

## 8) Simplify and quarantine “legacy” action

24. **`get_prediction.sample_output` must be static**
    It currently *calls* Vertex in sample output. That’s surprising and slow in design‑time. Replace with a deterministic JSON sample. Functionality of the action doesn’t change; only the sample fixture is now real sample data.

25. **Mark action as deprecated in help**
    You already say “legacy”; add a first line in help: “**Deprecated:** kept for backward compatibility.” (No behavior change, less confusion.)

---

## 9) Hardening/parsing cleanups that shrink code paths

26. **In `build_conversation_payload`: parse tool/function params only when they look like JSON**
    You already gate on `start_with?('{','[')`. Extract a 2‑line helper `maybe_parse_json(str)` and reuse it for both `functionDeclarations.parameters` and `functionResponse.response`. Removes duplicate begin/rescue blocks.

27. **`extract_json`**
    Collapse the triple‑backtick cleanup to a tiny helper `strip_fences(text)` and call it once. Shorter and easier to test.

28. **`check_finish_reason`**
    Convert to a small map look‑up instead of a long `case`, but preserve messages verbatim. Same behavior, less code.

---

## 10) Drive helpers: fewer variations, same result

29. **`drive_basic_fields`**: freeze the returned string (tiny, but locks the constant):

    ```ruby
    'id,name,mimeType,size,modifiedTime,md5Checksum,owners'.freeze
    ```

30. **`build_drive_query`**
    Build with an array + `compact` + `join(' and ')`. You already do that pattern; it’s fine. Just use short helpers for date filters to make the method 6–8 lines.

31. **`handle_drive_error`**
    Convert to a small table of lambdas keyed by code; you can still interpolate service account into 403. Same behavior, cleaner.

---

## 11) Trim repetition in connection/auth section

32. **Factor OAuth scopes into a constant**

    ```
    OAUTH_SCOPES = [
      'https://www.googleapis.com/auth/cloud-platform',
      'https://www.googleapis.com/auth/drive.readonly'
    ].freeze
    ```

    and do `scopes = OAUTH_SCOPES.join(' ')`.

33. **DRY the OAuth token POST body**
    Build a small `token_payload(common_overrides)` helper to cut duplicate fields between `acquire` and `refresh`.

34. **`base_uri` is defined—use it**
    Where you currently interpolate `https://#{region}-aiplatform.googleapis.com/#{version}/…`, prefer `connection['base_uri']` + relative path. You can add:

    ```ruby
    project_region_path = "projects/#{connection['project']}/locations/#{connection['region']}"
    ```

    and then `connection['base_uri'] + "#{project_region_path}/…"`
    (Behavior identical; fewer string templates.)

---

## 12) Make picklists thinner but equally capable

35. **Use one static map for model picklist fallbacks**
    Define:

    ```ruby
    STATIC_MODEL_OPTIONS = {
      text: [
        ['Gemini 1.0 Pro','publishers/google/models/gemini-pro'],
        ['Gemini 1.5 Pro','publishers/google/models/gemini-1.5-pro'],
        ['Gemini 1.5 Flash','publishers/google/models/gemini-1.5-flash'],
        ['Gemini 2.0 Flash Lite','publishers/google/models/gemini-2.0-flash-lite-001'],
        ['Gemini 2.0 Flash','publishers/google/models/gemini-2.0-flash-001'],
        ['Gemini 2.5 Pro','publishers/google/models/gemini-2.5-pro'],
        ['Gemini 2.5 Flash','publishers/google/models/gemini-2.5-flash'],
        ['Gemini 2.5 Flash Lite','publishers/google/models/gemini-2.5-flash-lite']
      ],
      image: (same list as text for now),
      embedding: [
        ['Text embedding gecko-001','publishers/google/models/textembedding-gecko@001'],
        ['Text embedding gecko-003','publishers/google/models/textembedding-gecko@003'],
        ['Text embedding-004','publishers/google/models/text-embedding-004']
      ]
    }.freeze
    ```

    Then your three pick\_lists become one‑liners that call `picklist_for` with `STATIC_MODEL_OPTIONS[bucket]`.

36. **Region list → constant**
    Move the long region array to `REGION_OPTIONS = [[label, value], …].freeze` and reference it from the connection field. No behavior change; easier to maintain.

---

## 13) Embeddings: share payload/extraction and tighten batch loop

37. **Use `vertex_url_for` in both embedding actions** (covered in §2/§5).

38. **Single place to extract embedding arrays**
    You have similar extraction logic in multiple places. Extract to `extract_embedding_values(prediction)` that returns `Array(Float)` using the two existing paths:

    ```ruby
    prediction&.dig('embeddings', 'values') ||
    prediction&.dig('embeddings')&.first&.dig('values') || []
    ```

    Use in `generate_embedding_single_exec` and `generate_embeddings_batch_exec`.

39. **Delete unused `streaming_mode` scaffolding for now**
    It logs “streaming mode” but never streams/output increments. If you want to keep the flag for future, at least remove the branch that pushes to nowhere and the metrics that imply streaming. That’s \~10 lines gone with zero user‑visible change.

40. **`api_calls_saved` calc**
    Keep the existing formula to avoid contract change, but add a one‑line comment that it’s a heuristic. (Prevents a future “fix” that changes outputs.)

---

## 14) Response extraction: fewer special cases

41. **`extract_response`**

    * Move the common token usage extraction into a helper `usage_meta(resp)`.
    * Keep the “ratings blank → standard error response” logic, but document it inline so no one “fixes” it later.

42. **Add a tiny guard for JSON outputs**
    If `extract_json` returns `{}`, still return the existing shape with `N/A` like you already do in `:classify`. Keeps outputs consistent and avoids downstream nil checks.

---

## 15) Diagnostics (`test_connection`) slimming

43. **Use `api_request` + `context` for every sub‑check**
    Replaces 3 different inline `after_error_response` blocks.

44. **Extract each sub‑test to small methods**

    * `diagnose_vertex(connection, test_models:)`
    * `diagnose_drive(connection, verbose:)`
    * `diagnose_index(connection, index_id:)`
      The main `execute` just orchestrates and builds the summary. Zero behavior change, sizable readability win.

45. **One source of quotas** (see §4‑10). Use the constant for both “notes” and “quota\_info”.

46. **Remove duplicated setting of `region` inside `validate_publisher_model!`**
    You set it twice; set once at top.

---

## 16) Minor consistency edits (trim code without altering IO)

47. **Normalize all string interpolations** to use `project_region_path` helper.
48. **Freeze constant strings/arrays** used across methods (e.g., safety categories) to signal intent and avoid accidental mutation.
49. **Prefer symbol keys in local hashes you fully control** (e.g., internal metrics) to cut noise; keep external payloads as strings to match API casing.
50. **Rename local variables for clarity** where two similarly named “model” variables appear (e.g., `model_name` vs `model` in methods that also reference `input['model']`). No external effect, fewer footguns.

---

## 17) Keep the public contract stable

51. **Do not rename any input or output field names** in actions. All changes above respect that.
52. **Preserve `sample_output` shapes**; only remove the live API call in the legacy action.
53. **Keep deprecation additive** (doc only), not functional.

---

## 18) Quick “find & replace” cheatsheet

* `object_definitions['…'].concat(` → `object_definitions['…'].dup + (`
* `puts(` → `call('log_debug', `
* Hand‑built `"projects/#{…}/locations/#{…}"` → `call('project_region_path', connection)`
* Hand‑built Gemini URLs → `call('vertex_url_for', connection, model, :generate|:predict)`
* Inline `after_error_response` with only message formatting → `api_request(..., context: { action: '...' })`
* The two bugs: `break` (remove) and `filtered`→`eligible`

---

## 19) Optional, nice to have (no functional shift, but you may defer)

54. **Group related methods by domain** with comment headers (`# -- Vertex :: …`, `# -- Drive :: …`) to make the file skimmable.
55. **Add an internal `VERSION` comment** at top of connector and bump when you touch “framework” parts; helps debugging when multiple envs run different copies.
56. **Tiny unit tests in a scratch recipe** for the two bugs and the non‑mutating object definitions (invoke any action twice and ensure fields don’t duplicate).

---

## 20) Implementation order (safe sequence)

1. Land §0 (two bugs) + §1 (no‑mutation dups).
2. Apply §2 (route actions through `run_vertex`) + §5 (URL builder helper).
3. Standardize errors/logging (§3).
4. Rate limit constant + minor backoff tweak (§4).
5. Model discovery cleanup (§6).
6. Diagnostics slimming (§15).
7. Static legacy sample (§8).
8. Remaining polish items (§9–§16).


