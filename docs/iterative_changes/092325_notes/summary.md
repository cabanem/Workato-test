# Refactor plan
## Make a composable _request pipeline_

### 1. A single resilience wrapper
- Unify rate limiting and retries (429 and 5xx), circuit breaker, timing, correlation id (`with_resilience`)
- Replace the separate paths (`handle_429_with_backoff` and `circuit_breaker_retry`) with a single path

#### New method

** Method**
```ruby
with_resilience = lambda do |connection, key:, model: nil, retry_on: [429, 500, 502, 503, 504], &block|
  # 1) rate limiting (if enabled)
  rl = call('enforce_vertex_rate_limits', connection, model || key, 'inference')

  # 2) correlation id + timing
  correlation_id = SecureRandom.uuid
  start = Time.now

  begin
    result = call('circuit_breaker_retry', connection, key, { retry_on: retry_on }) { block.call(correlation_id) }
    duration_ms = ((Time.now - start) * 1000).round
    # attach minimal telemetry to result if Hash
    result.is_a?(Hash) ? result.merge({ 'trace' => { 'correlation_id' => correlation_id, 'duration_ms' => duration_ms }, 'rate_limit_status' => rl }) : result
  rescue => e
    # enrich errors once, centrally
    raise e
  end
end
```

**Implementation**
```ruby
call('with_resilience', connection, key: 'vertex.generate', model: input['model]) do |cid|
    call('api_request', connection, :post, url, { payload: payload, headers: { 'X-Correlation-Id': cid } })
end
```

## 2. Make `api_request` the solitary choke point

- Enhance `api_request` to accept `headers:` and to always attach `context` (action, model, endpoint)
- Add timing to the method

**Method**
```ruby
api_request: lambda do |connection, method, url, options = {}|
  req = case method.to_sym
        when :get  then get(url)
        when :post then post(url, options[:payload])
        when :put  then put(url, options[:payload])
        when :delete then delete(url)
        else error("Unsupported HTTP method: #{method}")
        end
  req = req.params(options[:params]) if options[:params]
  req = req.headers(options[:headers]) if options[:headers]

  started = Time.now
  req.after_error_response(/.*/) do |code, body, _header, message|
    (options[:error_handler] || lambda { |c,b,m| call('handle_vertex_error', connection, c, b, m, options[:context] || {}) })
      .call(code, body, message)
  end
end
```

## 3. Collapse Vertex request orchestration into a single functional pipeline
- Retain `run_vertex`, but have it call `with_resilience` and return a standard response envelope.
- Actions can expect uniformity in outputs (`trace`, `vertex_response_id`, `rate_limit_status`)

**Method**
```ruby
run_vertex: lambda do |connection, input, template, verb:, extract: {}|
  call('validate_publisher_model!', connection, input['model'])
  payload = input['formatted_prompt'].presence || call('build_ai_payload', template, input, connection)
  url = call('vertex_url_for', connection, input['model'], verb)

  resp = call('with_resilience', connection, key: "vertex.#{verb}", model: input['model']) do |cid|
    call('api_request', connection, :post, url, { payload: payload, headers: { 'X-Correlation-Id': cid } })
  end

  extracted = extract.present? ? call('extract_response', resp, extract) : resp
  # Standard envelope: same shape across actions
  extracted.merge({
    'trace' => (resp['trace'] || {}),
    'vertex' => { 'response_id' => resp['responseId'], 'model_version' => resp['modelVersion'] }
  }.compact)
end
```

## 4. Standardize outputs with an envelope
- Return a consistent block from all generative/analysis actions

```ruby
envelope = {
  'answer'           => ...,              # if applicable
  'has_answer'       => true/false,       # consistent decision bit
  'pass_fail'        => true/false,       # same bit across actions
  'action_required'  => 'use_answer'|'retry'|...,
  'safety_ratings'   => {...},
  'usage'            => {...},
  'trace'            => { 'correlation_id' => ..., 'duration_ms' => ... },
  'vertex'           => { 'response_id' => ..., 'model_version' => ... },
  'rate_limit_status'=> {...}
}
```

## 5. Normalize `findNeighbors` as a dedicated client
- Extract a client from the existing Find Neighbors action, methods

**Methods**
```ruby
vindex_url = lambda do |connection, host, path|
  version = connection['version'].presence || 'v1'
  "https://#{call('normalize_host', host)}/#{version}/projects/#{connection['project']}/locations/#{connection['region']}/#{path}"
end

vindex_find_neighbors = lambda do |connection, host, endpoint_id, payload|
  url = call(vindex_url, connection, host, "indexEndpoints/#{endpoint_id}:findNeighbors")
  call('with_resilience', connection, key: 'vertex.find_neighbors') do |cid|
    call('api_request', connection, :post, url, {
      payload: payload,
      headers: { 'X-Correlation-Id': cid },
      context: { action: 'Find neighbors', endpoint_id: endpoint_id }
    })
  end
end
```

**Implementation**
```ruby
payload  = call('build_ai_payload', :find_neighbors, input, connection)
resp     = call('vindex_find_neighbors', connection, input['index_endpoint_host'], input['index_endpoint_id'], payload)
call('transform_find_neighbors_response', resp)
  .merge('trace' => resp['trace'])
```

## 6. Make Drive calls use the same resilience and envelope
- Route all Drive HTTP through `with_resilience(... key: 'drive.get')`
- Add correlation id; return trace in outputs of `fetch_drive_file`, `list_drive_file`, `batch_fetch_drive_files`, `monitor_drive_changes`

**Mechanical change**
```ruby
resp = call('with_resilience', connection, key: 'drive.files.get') do |cid|
  call('api_request', connection, :get, call('drive_api_url', :file, file_id),
      params: { fields: call('drive_basic_fields') },
      headers: { 'X-Correlation-Id': cid },
      error_handler: ->(code, body, message) { error(call('handle_drive_error', connection, code, body, message)) })
end
```

## 7. Small changes
- Unify retry lists
    - Define a single constant in `rate_limit_defaults` and use it from `with_resilience`
- Expose `responseId` everywhere
- Negative caching for model validation
    - Cache 403/404 for short TTL in `validate_publisher_model!`
    - Avoid repeated failing calls during misconfiguration
- One place for finish-reason mapping
    - Modify `check_finish_reason` to return a structured object, `{ code:, actionable_hint: }`
- Consistent action summaries
