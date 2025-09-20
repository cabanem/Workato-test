# Test Suite Usage and Setup Instructions

## Environment variables

```bash
export PROJECT="your-gcp-project"
export REGION="us-central1"
export TEST_FILE_ID="your-test-file-id"
export TEST_FOLDER_ID="your-test-folder-id"
export INDEX_HOST="1234.us-central1.vdb.vertexai.goog"
export ENDPOINT_ID="your-endpoint-id"
export INDEX_ID="your-index-id"
export ENVIRONMENT="development"
```

## Running tests

```bash
# Run connection test
ruby test_all_connections.rb

# Run document processing test
ruby test_document_processing.rb

# Run all tests
ruby run_all_tests.rb
```

## Expected output

- All tests should complete within specified time limits
- Daily cost should be under $2
- Success rate should be > 90%
- Performance metrics should meet SLA requirements
