## Part 1: RAG_Utils Connector Modifications

---

RAG_UTILS located "connectors/rag_utils/v2.0_proposed.rb"
VERTEX located "connectors/vertex/v2.0_proposed.rb"

---
Part 1: RAG Utilities Modifications

1. Add Contract Validation Infrastructure
    - Location: Methods section, after existing helper methods (~line 1500)
    - Action: Add new validation method
    - Request / Prompt:
```
Add a new method called 'validate_contract' to the RAG_Utils connector methods section. Place this after the existing helper methods around line 1500. The method should:
 1. Accept parameters: connection, data, and contract_type
 2. Define contracts for: 'cleaned_text', 'embedding_request', 'classification_request', and 'prompt_request'
 3. Validate required fields based on contract type
 4. Return the data if valid, error if not
```

2. Rename Email Rule Evaluation
    - Location: RAG Utils connection, evaluate_email_by_rules (action around line 871)
    - Action: Rename action and update metadata
    - Prompt for AI/Developer:
```
Find the action 'evaluate_email_by_rules' in RAG_Utils connector.
Rename it to 'classify_by_pattern' with:
- New title: 'Classify by pattern matching'
- New subtitle: 'Pattern-based classification without AI'
- New description: 'Evaluate text against pattern rules from standard library or Data Tables'
Keep all other fields (help, config_fields, input_fields, output_fields, execute) unchanged.
```

3. Create Text Preparation Action
    - Location: RAG Utils connector, After classify_by_pattern action (~line 1050)
    - Action: Add new action
    - Prompt for AI/Developer:
```
Create a new action called 'prepare_for_ai' in RAG_Utils after the classify_by_pattern action. This action should:

Input fields:
- text (required, text-area)
- source_type (required, select: email/document/chat/general)
- task_type (required, select: classification/generation/analysis/embedding)
- options (optional object with remove_pii and max_length)

Processing:
- Use existing process_email_text for email source_type
- Build contract-compliant output with text and metadata
- Validate output using the validate_contract method
- Return cleaned_text contract format
```

4. Update Embedding Batch Formatter

Location: RAG Utils connection, format_embeddings_batch action (~line 245)
Action: Replace with new implementation

Prompt for AI/Developer:
```
Replace the 'format_embeddings_batch' action with a new 'prepare_embedding_batch' action that:
1. Accepts texts array with id, content, title, metadata
2. Adds batch_id generation
3. Includes task_type selection (RETRIEVAL_DOCUMENT/QUERY/SEMANTIC_SIMILARITY)
4. Returns embedding_request contract format
5. Validates output with validate_contract method
```
---
5. Mark Vertex-Specific Actions as Deprecated

Location: RAG Utils connection, to_vertex_datapoints action (~line 1100)
Action: Add deprecation warning

Prompt for AI/Developer:
```
In the 'to_vertex_datapoints' action:
1. Add field: deprecated: 'This action will be replaced by format_vector_datapoints in v2.0'
2. Add to execute block start: puts "DEPRECATION WARNING: to_vertex_datapoints will be replaced by format_vector_datapoints in v2.0"
```
---

## Part 2: Vertex AI Connector Modifications

6. Remove Data Tables Integration
   - Location: Multiple locations in the Vertex connector (connectors/vertex/v2.  0_proposed.rb)
   - Action: Delete methods and fields
   - Prompt for AI/Developer:
```
Remove all Workato Data Tables integration from Vertex AI connector:

1. DELETE these methods (around lines 1800-2000):
   - ensure_workato_api!
   - workato_api_headers
   - workato_api_base
   - list_datatables
   - list_datatable_columns
   - fetch_datatable_rows
   - cached_table_rows
   - load_categories_from_table

2. DELETE from connection fields (around line 50):
   - workato_api_host field
   - workato_api_token field

3. DELETE from pick_lists section:
   - workato_datatables
   - workato_datatable_columns

```

7. Create AI Classification Action
   - Location: After categorize_text action (~line 700), in the Vertex connector (connectors/vertex/v2.0_proposed.rb)
   - Action: Add new action
   - Prompt for AI/Developer:
```
Create a new action 'ai_classify' in Vertex connector after categorize_text. Requirements:

Input:
- text (required, from RAG_Utils preparation)
- categories array (key and optional description)
- model (required, use available_text_models picklist)
- options object (return_confidence, return_alternatives, temperature)

Output:
- selected_category
- confidence (0.0-1.0)
- alternatives array
- usage metrics

Implementation:
- Build prompt for classification
- Use existing build_base_payload method
- Return classification_response contract format
```

8. Deprecate Old Categorization
   - Location: categorize_text action (~line 600) in the Vertex connector (connectors/vertex/v2.0_proposed.rb)
   - Action: Add deprecation notices

Prompt for AI/Developer:
```
Update the 'categorize_text' action in Vertex connector:
1. Add: deprecated: true
2. Change title to: 'Categorize text (DEPRECATED)'
3. Update subtitle: 'Will be removed in v2.0 - Use ai_classify or RAG_Utils::classify_by_pattern'
4. Add to execute start: puts "DEPRECATION WARNING: categorize_text is deprecated. Use RAG_Utils::classify_by_pattern for rules or ai_classify for AI classification"
```

9. Add Batch Embedding Support

Location: generate_embedding action (~line 900) in the Vertex connector (connectors/vertex/v2.0_proposed.rb)
Action: Replace with batch version

Prompt for AI/Developer:
```
Replace 'generate_embedding' with 'generate_embeddings' (plural) that:

Input:
- batch_id (required)
- texts array with id, content, metadata
- task_type (optional)
- model (required, embedding models)

Processing:
- Loop through texts array
- Generate embedding for each
- Collect vectors with IDs

Output:
- batch_id (matching input)
- embeddings array (id, vector, dimensions)
- model_used
- usage statistics

Use existing embedding generation logic but process multiple texts.
```

10. Update Send Messages for Prepared Input
   - Location: send_messages action in the Vertex connector (connectors/vertex/v2.0_proposed.rb)
   - Action: Add contract support
   - Prompt for AI/Developer:
```
Update 'send_messages' action to accept prepared input:
1. Check if input contains 'formatted_prompt' field
2. If yes, use it directly instead of building prompt
3. Keep backward compatibility for existing usage
4. Add comment: "# Accepts prepared prompts from RAG_Utils"
```
---

## Part 3: Testing & Validation

11. Create Test Recipe
   - Recipe Name: Test_Connector_Migration_v2
   - Prompt for Recipe Creation:
   - Create a Workato recipe that tests the new connector flow:
```
1. Manual trigger with test email text
2. RAG_Utils: clean_email_text action
3. RAG_Utils: classify_by_pattern (use standard rules)
4. If no match (condition):
   4a. RAG_Utils: prepare_for_ai (source=email, task=classification)
   4b. Vertex: ai_classify with prepared text
5. RAG_Utils: validate_llm_response
6. Logger: Output all results for comparison

Test with 3 sample emails:
- Newsletter (should match pattern)
- Customer inquiry (needs AI)
- Mixed content (tests both paths)
```

12. Create Integration Test
   - Test Name: Contract_Validation_Test
   - Prompt for Test Creation:
```
Create a test that validates data contracts between connectors:

1. Generate sample data for each contract type
2. Pass through RAG_Utils validation
3. Send to appropriate Vertex action
4. Verify response matches expected contract
5. Log any contract violations

Test cases:
- Valid cleaned_text → ai_classify
- Valid embedding_request → generate_embeddings
- Invalid data → should error appropriately
```

---

## Part 4: Documentation Updates

13. Update Connector README
   - Location: Both connector documentation 
   - Prompt for Documentation:
```
Update the README/documentation for both connectors:

RAG_Utils:
- Add section "Preparation Layer Responsibilities"
- Document all contract formats
- Add examples of preparing data for Vertex
- Include deprecation notices

Vertex AI:
- Add section "AI Layer Responsibilities"
- Document that it expects prepared input
- Remove Data Tables documentation
- Add migration guide from v1 to v2
```

14. Create Migration Script
   - Purpose: Automate recipe updates
   - Prompt for Script Creation:
```
Create a Ruby script that:
1. Exports all recipes using deprecated actions
2. Lists required changes for each
3. Generates updated recipe JSON
4. Creates rollback versions
5. Provides dry-run and apply modes

Include mappings:
- evaluate_email_by_rules → classify_by_pattern
- categorize_text → prepare_for_ai + ai_classify
- format_embeddings_batch → prepare_embedding_batch
```
---
## Verification Prompts

- Final Validation Prompt:
```
Review both modified connectors and verify:

RAG_Utils Checklist:
□ Has validate_contract method
□ Has classify_by_pattern (renamed)
□ Has prepare_for_ai action
□ Has prepare_embedding_batch
□ All actions use contract validation
□ Deprecation notices added

Vertex AI Checklist:
□ No Data Tables references
□ Has ai_classify action
□ categorize_text marked deprecated
□ Has generate_embeddings (batch)
□ Accepts prepared input
□ All pick_lists work

Integration Checklist:
□ Test recipe runs successfully
□ Contracts validate correctly
□ No circular dependencies
□ Performance acceptable
□ Error handling works

```

---

## Additional

## 1. Remove Data Tables Dependencies from Vertex AI Connector
- Location: Google Vertex AI connector (connectors/vertex/v2.0_proposed.rb)
- Prompt for Claude Code:
```
Remove all Data Tables code from the Vertex AI connector:
- Remove Workato Developer API connection fields (workato_api_host, workato_api_token)
- Remove all Workato-related methods: ensure_workato_api!, workato_api_headers, workato_api_base, list_datatables, list_datatable_columns, fetch_datatable_rows, cached_table_rows, load_categories_from_table, get_cached_datatables, get_cached_table_columns, fetch_fresh_datatables, fetch_table_columns, workato_request, workato_get, workato_post
- Clean up any remaining Data Tables references in pick_lists
- Remove workato_datatables and workato_datatable_columns pick_lists
- Update connection field groups to remove "Workato Developer API" section
```

## 2. Remove Deprecated Actions from Vertex AI Connector
- Location: Google Vertex AI connector actions section (connectors/vertex/v2.0_proposed.rb)
- Prompt for Claude Code:
```
Remove deprecated actions and their supporting code from Vertex AI:
- Delete entire categorize_text action (lines 319-422 approx)
- Remove categorize_text_input and categorize_text_output from object_definitions
- Remove payload_for_categorize method
- Remove rules_source_modes pick_list
- Clean up any references to categorize_text in comments or documentation
- Ensure ai_classify remains as the replacement with clear documentation
```

## 3. Remove Deprecated Actions from RAG Utils Connector
- Location: RAG Utils connector (connectors/rag_utils/v2.0_proposed.rb)
- Prompt for Claude Code:
```
Remove all deprecated actions and methods from RAG Utils:
- Delete to_vertex_datapoints action (currently marked deprecated)
- Remove any deprecated flags from remaining actions
- Remove the build_vertex_restricts method if only used by deprecated actions
- Clean up vertex_datapoint and vertex_datapoint_upsert object definitions if unused
- Update any references in comments that mention deprecated functionality
- Ensure all remaining actions have clear purpose documentation
```

## 4. Add Contract Validation to RAG Utils Actions
- Location: RAG Utils connector execute blocks (connectors/rag_utils/v2.0_proposed.rb)
- Prompt for Claude Code:
```
Add contract validation to RAG Utils actions that produce structured output:
1. smart_chunk_text - validate output against 'chunking_result' contract
2. clean_email_text - validate output against 'email_cleaning_result' contract  
3. calculate_similarity - validate output against 'similarity_result' contract
4. generate_document_metadata - validate output against 'document_metadata' contract
5. calculate_metrics - validate output against 'metrics_result' contract
6. check_document_changes - validate output against 'change_detection' contract
7. classify_by_pattern - validate output against 'classification_result' contract

For each action:
- Add contract definition if missing
- Call validate_contract before returning result
- Use pattern: result = call(:validate_contract, connection, result, 'contract_name')
```

## 5. Update Connector Documentation
- Location: Both connector documentation/comments (connectors/rag_utils/v2.0_proposed.rb and connectors/vertex/v2.0_proposed.rb)
- Prompt for Claude Code:
```
Update inline documentation for both connectors:

RAG_Utils:
- Add header comment: "Data Preparation Layer for AI Workflows v2.0"
- Document contract formats: cleaned_text, embedding_request, classification_response
- Add usage examples showing data flow to Vertex AI
- Remove any references to deprecated actions

Vertex AI:
- Add header comment: "AI Processing Layer v2.0 - Requires prepared input"
- Document that it expects contract-compliant input from RAG_Utils
- Add migration notes: "categorize_text removed - use ai_classify with RAG_Utils::prepare_for_ai"
- Update ai_classify help text with integration example
- Clean up any Data Tables references in help text
```

# Additional

## 1-a. Add upsert vectors action to the Vertex AI Connector
Location: Vertex AI connector (found at connectors/vertex/v2.0_proposed.rb))
Prompt:
```
Add a new action called 'upsert_index_datapoints' to the Vertex AI connector (connectors/vertex/v2.0_proposed.rb) with the following requirements:
INPUT FIELDS:
- index_id (required): The Vector Search index resource ID
- datapoints (array, required): Array of objects containing:
  - datapoint_id: Unique identifier for the vector
  - feature_vector: Array of floats (the embedding)
  - restricts (optional): Array of namespace/allowList/denyList filters
  - crowding_tag (optional): For result diversity
- update_mask (optional): Fields to update for existing datapoints

IMPLEMENTATION:
- Use the Vertex AI REST API endpoint: POST /v1/projects/{project}/locations/{region}/indexes/{index_id}:upsertDatapoints
- Handle batch processing (API limit is typically 100 datapoints per request)
- Return: successfully_upserted_count, failed_datapoints array with error details

COMPATIBILITY:
- Accept output from RAG_Utils 'adapt_chunks_for_vertex' action
- Support both create and update operations in single call
```

1-b. Implement index update api calls
- Location: Vertex AI Connector (connectors/vertex/v2.0_proposed.rb)
- Task for developer:
```
Extend the Vertex AI connector methods section with proper index management:

REQUIRED METHODS:
1. 'batch_upsert_datapoints': 
   - Chunks datapoints into batches of 100
   - Makes sequential API calls to avoid rate limits
   - Implements exponential backoff for retries
   - Tracks success/failure per batch

2. 'validate_index_access':
   - Verifies service account has aiplatform.indexes.update permission
   - Checks index exists and is in DEPLOYED state
   - Returns index metadata including dimensions for validation

ERROR HANDLING:
- Dimension mismatch between vectors and index
- Index not found or not deployed
- Permission denied (missing IAM roles)
- Rate limiting (implement backoff)

RESPONSE FORMAT:
{
  "total_processed": 250,
  "successful_upserts": 248,
  "failed_upserts": 2,
  "error_details": [...],
  "index_stats": {
    "total_datapoints": 15420,
    "index_id": "...",
    "deployed_state": "DEPLOYED"
  }
}
```

Task 3a: Ensure Recipe-Accessible Outputs
Location: Vertex AI Connector (connectors/vertex/v2.0_proposed.rb)

```
Review and modify all connector outputs to ensure Workato recipe compatibility:

REQUIREMENTS FOR ALL ACTIONS:
1. Flatten nested objects where possible (Workato struggles with deep nesting)
2. Ensure all array outputs include a 'count' field at the root level
3. Add 'summary' objects for complex responses

SPECIFIC CHANGES:

For 'generate_embeddings_batch':
- Add root level: 'first_embedding' object for easy access
- Add: 'embeddings_json' field with stringified array for bulk operations

For 'find_neighbors':
- Flatten to: 'top_matches' array at root level
- Add: 'best_match_id' and 'best_match_score' at root

For 'ai_classify':
- Ensure 'selected_category' is always a string (never null)
- Add: 'requires_human_review' boolean based on confidence

For all validation/scoring actions:
- Add 'pass_fail' boolean at root level
- Add 'action_required' field with specific next step

RECIPE INTEGRATION HELPERS:
- All ID fields should be strings (not integers)
- All timestamps in ISO 8601 format
- All numeric scores normalized to 0-1 range
- Empty arrays should return [] not null
```

Task 3b: Ensure Recipe-Accessible Outputs
Location: RAG Utils Connector (connectors/rag_utils/v2.0_proposed.rb)

```
Review and modify all connector outputs to ensure Workato recipe compatibility:

REQUIREMENTS FOR ALL ACTIONS:
1. Flatten nested objects where possible (Workato struggles with deep nesting)
2. Ensure all array outputs include a 'count' field at the root level
3. Add 'summary' objects for complex responses

SPECIFIC CHANGES:

For 'generate_embeddings_batch':
- Add root level: 'first_embedding' object for easy access
- Add: 'embeddings_json' field with stringified array for bulk operations

For 'find_neighbors':
- Flatten to: 'top_matches' array at root level
- Add: 'best_match_id' and 'best_match_score' at root

For 'ai_classify':
- Ensure 'selected_category' is always a string (never null)
- Add: 'requires_human_review' boolean based on confidence

For all validation/scoring actions:
- Add 'pass_fail' boolean at root level
- Add 'action_required' field with specific next step

RECIPE INTEGRATION HELPERS:
- All ID fields should be strings (not integers)
- All timestamps in ISO 8601 format
- All numeric scores normalized to 0-1 range
- Empty arrays should return [] not null
```

Task 4a: Create Test Data Structure
Define test scenarios to validate the complete chain works:

TEST CASE 1 - Vector Upsert:
Input: 
{
  "texts": ["Example customer query about return policy"],
  "metadata": {"source": "email", "timestamp": "2024-01-15"}
}
Expected flow:
RAG_Utils.prepare_for_ai → clean text
Vertex.generate_embedding_single → vector
Vertex.upsert_index_datapoints → success

TEST CASE 2 - Query Flow:
Input: "What is your return policy?"
Expected flow:
Vertex.generate_embedding_single(RETRIEVAL_QUERY) → query_vector
Vertex.find_neighbors → document_ids
[Future: retrieve_documents] → context
RAG_Utils.build_rag_prompt → formatted_prompt

VALIDATION POINTS:
- Vector dimensions match index configuration
- Metadata preserved through pipeline
- IDs remain consistent
- Response formats are recipe-compatible

---

Task 5
   - Location: Vertex AI Connector (connectors/vertex/v2.0_proposed.rb)
   - Request for developer
```
Add comprehensive rate limiting to the Vertex AI connector to prevent 429 errors. Requirements:

1. Add a new method 'enforce_vertex_rate_limits' that implements:
   - Sliding window tracking (last 60 seconds)
   - Model-specific limits:
     * Gemini Pro: 300 QPM
     * Gemini Flash: 600 QPM  
     * Embedding models: 600 QPM
   - Per-project tracking (support multiple projects)

2. Implementation approach:
   - Store request timestamps in Workato cache with TTL
   - Key format: "vertex_rate_{project}_{model_family}_{timestamp}"
   - Before each API call:
     * Count requests in last 60 seconds
     * If at limit, calculate sleep time
     * Add jitter (0-1 second) to prevent thundering herd

3. Add to connection fields:
   {
     name: "enable_rate_limiting",
     type: "boolean", 
     control_type: "checkbox",
     default: true,
     hint: "Automatically throttle requests to stay within Vertex AI quotas"
   }

4. Modify these methods to call enforce_vertex_rate_limits:
   - generate_embeddings_batch_exec
   - generate_embedding_single_exec  
   - All send_messages/analyze/classify actions

5. Add monitoring output to all actions:
   - rate_limit_status: {
       requests_last_minute: integer,
       limit: integer,
       throttled: boolean,
       sleep_ms: integer
     }

6. Fallback strategy:
   - On 429 response, extract Retry-After header
   - Implement exponential backoff: 1s, 2s, 4s, 8s
   - After 3 retries, fail gracefully with clear error message
```