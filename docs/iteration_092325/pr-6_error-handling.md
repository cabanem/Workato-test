# PR 6 — Error handling & rate limit coherence

## Scope

* Centralize retry/backoff constants.
* Teach `api_request` to pass `context` through to central handler when no custom handler is provided.
* Make rate‑limit model family classification 2.5‑aware.
* Add `log_debug` wrapper and use it instead of raw `puts` in a few hot spots.

## Rationale
One place to tune, richer errors, less log spam drift.

## Patch

```diff
diff --git a/connector.rb b/connector.rb
@@
   methods: {
+    log_debug: lambda { |msg| puts(msg) },
+    rate_limit_defaults: lambda { { 'max_retries' => 3, 'base_delay' => 1.0, 'max_delay' => 30.0 } },
@@
-      request.after_error_response(/.*/) do |code, body, _header, message|
+      request.after_error_response(/.*/) do |code, body, _header, message|
         # Check if custom error handler provided
         if options[:error_handler]
           options[:error_handler].call(code, body, message)
         else
-          call('handle_vertex_error', connection, code, body, message)
+          call('handle_vertex_error', connection, code, body, message, options[:context] || {})
         end
       end
     end,
@@
-      model_family = case model.to_s.downcase
-      when /gemini.*pro/
+      model_family = case model.to_s.downcase
+      when /gemini.*(2\.5\-)?pro/
         'gemini-pro'
-      when /gemini.*flash/
+      when /gemini.*(2\.5\-)?flash/
         'gemini-flash'
       when /embedding/
         'embedding'
       else
         'gemini-pro' # default to most restrictive
       end
@@
-          puts "Rate limit reached for #{model_family} (#{timestamps.length}/#{limit}). Sleeping #{total_sleep.round(2)}s"
+          call('log_debug', "Rate limit reached for #{model_family} (#{timestamps.length}/#{limit}). Sleeping #{total_sleep.round(2)}s")
@@
-        puts "Rate limit cache operation failed: #{e.message}"
+        call('log_debug', "Rate limit cache operation failed: #{e.message}")
         return { requests_last_minute: 0, limit: limit, throttled: false, sleep_ms: 0 }
       end
     end,
@@
-      max_retries = 3
-      base_delay = 1.0
+      cfg = call('rate_limit_defaults')
+      max_retries = cfg['max_retries']
+      base_delay = cfg['base_delay']
@@
-              puts "429 rate limit hit for #{model} (attempt #{attempt + 1}/#{max_retries}). Retrying in #{actual_delay}s"
+              call('log_debug', "429 rate limit hit for #{model} (attempt #{attempt + 1}/#{max_retries}). Retrying in #{actual_delay}s")
@@
-      max_retries = options[:max_retries] || 3
+      defaults = call('rate_limit_defaults')
+      max_retries = options[:max_retries] || defaults['max_retries']
-      base_delay = options[:base_delay] || 1.0
-      max_delay = options[:max_delay] || 30.0
+      base_delay = options[:base_delay] || defaults['base_delay']
+      max_delay = options[:max_delay] || defaults['max_delay']
@@
-            puts "Circuit breaker for #{operation_name}: transitioning to half-open"
+            call('log_debug', "Circuit breaker for #{operation_name}: transitioning to half-open")
@@
-              workato.cache.set(circuit_key, { 'failures' => 0, 'state' => 'closed' }, 3600)
-              puts "Circuit breaker for #{operation_name}: reset to closed state"
+              workato.cache.set(circuit_key, { 'failures' => 0, 'state' => 'closed' }, 3600)
+              call('log_debug', "Circuit breaker for #{operation_name}: reset to closed state")
@@
-              puts "#{operation_name} failed (attempt #{attempt + 1}/#{max_retries}): #{e.message}. Retrying in #{delay.round(2)}s"
+              call('log_debug', "#{operation_name} failed (attempt #{attempt + 1}/#{max_retries}): #{e.message}. Retrying in #{delay.round(2)}s")
@@
-                puts "Circuit breaker for #{operation_name}: OPENED due to repeated failures"
+                call('log_debug', "Circuit breaker for #{operation_name}: OPENED due to repeated failures")
@@
-        puts "Circuit breaker cache error: #{cache_error.message}"
+        call('log_debug', "Circuit breaker cache error: #{cache_error.message}")
         # Fallback to simple retry without circuit breaker
         return block.call
```

## Acceptance criteria

* Rate-limit logs are visible but centralized.
* Errors from `api_request` now include context when provided.

## Test plan

* Intentionally hammer an endpoint to observe backoff logs.
* Trigger a 403 with `api_request(context: {action: 'X'})` and verify message includes “X”.

## Commit message

```bash
git commit -m "refactor(errors/limits): centralize backoff defaults, pass context through, tidy logs" \
  -m "Why: scattered retry constants and ad-hoc logging increase drift; errors lacked action context." \
  -m "What:" \
  -m "- Add rate_limit_defaults and use in 429/backoff + circuit breaker." \
  -m "- api_request now forwards options[:context] to handle_vertex_error." \
  -m "- Rate-limit model family aware of 2.5-* names." \
  -m "- Add log_debug wrapper; replace puts in hot paths." \
  -m "Impact: same behavior, clearer diagnostics, single place to tune retries." \
  -m "Testing: forced 429 to observe structured backoff logs; 403 shows action context."
```
