# Contract Validation Test Suite

This directory contains integration tests for validating data contracts between RAG_Utils and Vertex connectors.

## Contract Validation Test

The `contract_validation_test.rb` file validates that data flows correctly between connectors and meets contract requirements.

### Test Cases

1. **Valid cleaned_text → ai_classify**: Tests successful data flow from RAG_Utils text preparation to Vertex AI classification
2. **Invalid cleaned_text → ai_classify**: Validates that malformed data is properly rejected
3. **Valid embedding_request → generate_embeddings**: Tests batch embedding generation workflow
4. **Invalid embedding_request → generate_embeddings**: Validates rejection of incomplete embedding requests
5. **Prepared prompt integration**: Tests RAG_Utils → Vertex send_messages integration
6. **Batch embedding integration**: Tests RAG_Utils prepare_embedding_batch → Vertex generate_embeddings flow

### Running the Tests

```bash
# Run all contract validation tests
cd test
ruby contract_validation_test.rb

# Check syntax only
ruby -c contract_validation_test.rb
```

### Test Coverage

The test suite validates:
- ✅ Contract field requirements (required vs optional)
- ✅ Field type validation (String, Array, Hash, Integer, Float)
- ✅ Data structure integrity
- ✅ Error handling for invalid data
- ✅ Integration between connector actions
- ✅ Backward compatibility preservation

### Contract Types Tested

| Contract | Source | Target | Purpose |
|----------|--------|--------|---------|
| `cleaned_text` | RAG_Utils | Vertex ai_classify | Text preparation to classification |
| `embedding_request` | RAG_Utils | Vertex generate_embeddings | Text to embedding generation |
| `classification_response` | Vertex | RAG_Utils | Classification results |
| `formatted_prompt` | RAG_Utils | Vertex send_messages | Prepared prompts |

### Expected Output

A successful test run shows:
- ✅ All contract validations passed
- 100% success rate
- No contract violations

Failed tests indicate:
- ❌ Contract violations with specific error messages
- Missing required fields
- Type mismatches
- Integration failures

This test suite ensures reliable data exchange between connectors and validates the v2.0 migration path.