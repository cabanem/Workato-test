# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Vertex AI connector in this repository.

## Development Commands

**Setup:**
- `./setup.sh` - Initial setup (installs Workato SDK and dependencies)
- `bundle install` - Install Ruby gems
- `./setup-oauth.sh` - Configure OAuth2 for Google Drive

**Testing:**
- `make test CONNECTOR=vertex_ai` - Test Vertex AI connector
- `make console CONNECTOR=vertex_ai` - Open Workato console for Vertex
- `make test-drive CONNECTOR=vertex_ai` - Test Drive API connectivity
- `make test-oauth CONNECTOR=vertex_ai` - Validate OAuth2 token and scopes
- `make test-pipeline` - Test full document processing pipeline

**Validation:**
- `workato exec check connectors/vertex_ai.rb` - Syntax validation
- `make validate-contract CONNECTOR=vertex_ai` - Validate connector contracts
- `make debug-action CONNECTOR=vertex_ai ACTION=action_name` - Debug specific action

## Current State Assessment

### Critical Issues Identified

#### 1. Rate Limiting Race Condition (CRITICAL)
**PROBLEM:** Race condition risk with 60 individual cache keys; concurrent executions could miss each other's counts.
```ruby
# Current problematic implementation
60.times do |i|
  timestamp = current_time - i
  cache_key = "#{cache_prefix}_#{timestamp}"
  count = workato.cache.get(cache_key) || 0
```
**SOLUTION:** Use sliding window with atomic operations; single cache key with array of timestamps.
**Location:** `enforce_vertex_rate_limits` method (~line 4200)

#### 2. Model Validation Performance (HIGH)
**PROBLEM:** `validate_publisher_model!` makes API call per unique model per execution; doesn't persist across recipe runs due to instance variable caching (`@validated_models`).
```ruby
# Current issue
@validated_models ||= {}  # Only lives for single execution
```
**SOLUTION:** Use `workato.cache` with reasonable TTL (1 hour).
**Location:** `validate_publisher_model!` method (~line 4600)

#### 3. Batch Embedding Memory Management (HIGH)
**PROBLEM:** Processing large batches accumulates all results in memory.
```ruby
texts.each_slice(batch_size) do |batch_texts|
  # All embeddings accumulated in memory
  embeddings << result
end
```
**SOLUTION:** Add streaming/chunked processing option for large datasets.
**Location:** `generate_embeddings_batch_exec` method (~line 5000)

#### 4. Error Recovery Complexity (MEDIUM)
**PROBLEM:** Batch retry logic has complex nested structure that's hard to maintain.
```ruby
while !batch_success && retry_count <= max_retries
  begin
    # Complex nested logic
  rescue
    # More nested handling
  end
end
```
**SOLUTION:** Extract to dedicated retry handler with circuit breaker pattern.
**Location:** Multiple batch operations (~lines 5800, 5900)

### Size Optimization Opportunities

#### 5. Consolidate Response Extractors (LOW)
**PROBLEM:** Multiple similar methods doing essentially the same thing:
- `extract_generic_response`
- `extract_generated_email_response`  
- `extract_parsed_response`
- `extract_embedding_response`
- `extract_ai_classify_response`

**SOLUTION:** Single configurable extractor method.
**Potential Savings:** ~300 lines

#### 6. Consolidate Payload Builders (LOW)
**PROBLEM:** 8 separate payload methods with similar patterns.
**SOLUTION:** Template-based payload builder.
**Potential Savings:** ~400 lines

#### 7. Extract Drive Operations (MEDIUM)
**PROBLEM:** Drive functionality mixed with Vertex AI logic.
**SOLUTION:** Separate Drive module or companion connector.
**Potential Savings:** ~800 lines

## Architecture

**Connector Structure:**
- **Total Lines:** ~6,200
- **Actions:** 15 main actions + test connection
- **Key Dependencies:** Google Cloud APIs (Vertex AI, Drive)
- **Authentication:** OAuth2 + Service Account hybrid

**Performance Characteristics:**
- Rate limits: Gemini Pro (300/min), Flash (600/min), Embeddings (600/min)
- Batch limits: 25 texts per embedding request, 100 datapoints per index update
- Cache usage: Model list (1hr), rate limiting (90s), validation (proposed 1hr)

## Code Patterns

**Current Anti-patterns to Fix:**
```ruby
# DON'T: Multiple cache keys for rate limiting
60.times do |i|
  cache_key = "#{cache_prefix}_#{timestamp}"
end

# DO: Single sliding window
cache_key = "vertex_rate_#{project}_#{model_family}_window"
window_data = workato.cache.get(cache_key) || { 'timestamps' => [] }
```

**Recommended Patterns:**
```ruby
# Circuit breaker for retries
call('circuit_breaker_retry', connection, {
  circuit_name: "operation_name",
  max_retries: 3,
  retry_on: [429, 500, 502, 503]
}) do
  # Operation logic
end

# Unified response extraction
call('extract_response', response, {
  type: :json,
  json_key: 'response',
  recipe_friendly: true
})
```

## Testing Protocol

**Before Making Changes:**
1. Create connector backup
2. Document current functionality
3. Export working recipes
4. Note current line count

**After Each Change:**
1. Syntax check: `workato exec check`
2. Action test: Test modified action
3. Recipe test: Run existing recipes
4. Performance check: Monitor latency

**Critical Test Cases:**
- [ ] Rate limiting under concurrent load
- [ ] Model validation cache persistence
- [ ] Large batch embedding processing (>100 items)
- [ ] Circuit breaker state management
- [ ] Error message consistency

## Implementation Priority

### Phase 1: Critical Fixes (Immediate)
1. Fix rate limiting race condition
2. Implement persistent model validation cache

### Phase 2: Performance (This Week)
3. Add streaming for large batches
4. Implement circuit breaker pattern

### Phase 3: Maintenance (Next Week)
5. Consolidate response extractors
6. Consolidate payload builders

### Phase 4: Architecture (Next Sprint)
7. Extract Drive operations
8. Optimize field definitions

## Migration Notes

**Breaking Changes to Avoid:**
- Keep all action names identical
- Maintain exact input/output field structures
- Preserve error message formats
- Keep backward compatibility for 3 months

**Safe Optimizations:**
- Internal method consolidation
- Cache improvements
- Performance enhancements
- Code organization

## Rollback Strategy

**If Issues Arise:**
1. Revert to backup version immediately
2. Identify specific failure point
3. Apply fix in isolation
4. Re-test comprehensively
5. Deploy with feature flag if uncertain

**Monitoring:**
- Track API call success rates
- Monitor memory usage trends  
- Watch rate limit hit frequency
- Measure action latency

## Constants to Define

```ruby
# Add at top of methods section
RATE_LIMIT_WINDOW = 60
CACHE_TTL_MODEL_LIST = 3600
CACHE_TTL_MODEL_VALIDATION = 3600
CACHE_TTL_CIRCUIT = 300
MAX_BATCH_SIZE_EMBEDDING = 25
MAX_BATCH_SIZE_INDEX = 100
DEFAULT_RETRY_COUNT = 3
BACKOFF_BASE_DELAY = 1.0
BACKOFF_MAX_DELAY = 30.0
```

## File Locations

- Vertex connector: `connectors/vertex_ai.rb` (6,200 lines)
- Test suite: `test/vertex_ai_test.rb`
- Migration backup: `connectors/vertex_ai_backup_[date].rb`
- Performance logs: `logs/vertex_performance.log`

## Changelog

Please maintain a detailed changelog at `/.claude/CHANGELOG_VERTEX.txt` documenting:
- Each optimization applied
- Lines saved/added
- Performance improvements measured
- Any behavioral changes