# Makefile for Workato RAG Email Response System
CONNECTOR ?= sample_connector
VERSION ?= vertex-ai
CONTRACT ?= cleaned_text
ACTION ?= 
DATA ?= {}

# Service ports
MOCK_API_PORT ?= 3001
MOCK_DRIVE_PORT ?= 3002

.PHONY: help setup test console clean

# Basic Commands
help:
	@echo "==================================="
	@echo "Workato RAG Connector Development"
	@echo "==================================="
	@echo "Basic Commands:"
	@echo "  make setup                   - Initial setup"
	@echo "  make test CONNECTOR=name     - Test connector"
	@echo "  make console CONNECTOR=name  - Open console"
	@echo "  make clean                   - Clean temp files"
	@echo ""
	@echo "Testing Commands:"
	@echo "  make test-contracts          - Run all contract tests"
	@echo "  make test-drive              - Test Drive integration"
	@echo "  make test-pipeline           - Test full pipeline"
	@echo "  make test-all                - Run all tests"
	@echo ""
	@echo "Mock Services:"
	@echo "  make mock-start              - Start all mock services"
	@echo "  make mock-stop               - Stop all mock services"
	@echo "  make mock-drive              - Start Drive mock only"
	@echo ""
	@echo "Connectors: rag_utils, vertex"
	@echo "Version: v2.0_proposed (default)"

setup:
	@./setup.sh
	@echo "Installing mock service dependencies..."
	@cd test/mock_services/drive && npm install
	@echo "Setup complete!"

# Connector Testing (updated for subdirectory structure)
test:
	@echo "Testing $(CONNECTOR)/$(VERSION).rb..."
	@ruby -c connectors/$(CONNECTOR)/$(VERSION).rb && \
	workato exec check connectors/$(CONNECTOR)/$(VERSION).rb

console:
	@echo "Opening console for $(CONNECTOR)/$(VERSION).rb..."
	@workato exec console connectors/$(CONNECTOR)/$(VERSION).rb

clean:
	@rm -rf tmp/ *.log
	@echo "Cleaned temporary files"

# Contract Validation
.PHONY: validate-contract test-contracts test-contract-specific test-with-fixtures test-v2-compatibility test-all-contracts

validate-contract:
	@workato exec console connectors/$(CONNECTOR)/$(VERSION).rb -c "load 'scripts/validate_contract.rb'"

test-contracts:
	@echo "Running contract validation tests..."
	@ruby test/contract_validation/contract_validation_test.rb

test-contract-specific:
	@echo "Testing specific contract: $(CONTRACT)"
	@ruby -r ./test/contract_validation/validate_contract.rb -e "puts ContractValidator.validate($(DATA), '$(CONTRACT)')"

test-with-fixtures:
	@echo "Running tests with fixtures..."
	@USE_FIXTURES=true ruby test/contract_validation/contract_validation_test.rb

test-v2-compatibility:
	@echo "Testing v2.0 backward compatibility..."
	@ruby test/contract_validation/contract_validation_test.rb --compatibility-check

test-all-contracts: test-contracts test-v2-compatibility
	@echo "All contract tests completed"

# Drive Integration Testing
.PHONY: test-drive test-oauth test-drive-fetch test-drive-list test-drive-batch

test-drive:
	@echo "Testing Google Drive integration..."
	@make mock-drive
	@sleep 2
	@workato exec console connectors/vertex/$(VERSION).rb -c "actions[:test_connection].execute(connection.merge('test_drive' => true), {})"
	@make mock-stop

test-oauth:
	@echo "Testing OAuth2 configuration..."
	@workato exec console connectors/vertex/$(VERSION).rb -c "connection[:authorization][:oauth2][:authorization_url].call(connection)"

test-drive-fetch:
	@echo "Testing fetch_drive_file action..."
	@make mock-drive
	@sleep 2
	@workato exec console connectors/vertex/$(VERSION).rb -c "actions[:fetch_drive_file].execute(connection, {'file_id' => 'test_123'})"
	@make mock-stop

test-drive-list:
	@echo "Testing list_drive_files action..."
	@make mock-drive
	@sleep 2
	@workato exec console connectors/vertex/$(VERSION).rb -c "actions[:list_drive_files].execute(connection, {'folder_id' => 'test_folder'})"
	@make mock-stop

test-drive-batch:
	@echo "Testing batch_fetch_drive_files action..."
	@make mock-drive
	@sleep 2
	@workato exec console connectors/vertex/$(VERSION).rb -c "actions[:batch_fetch_drive_files].execute(connection, {'file_ids' => ['f1', 'f2', 'f3']})"
	@make mock-stop

# Pipeline Testing
.PHONY: test-pipeline test-chunking test-embedding test-indexing

test-pipeline:
	@echo "Testing complete document processing pipeline..."
	@./scripts/run_tests.sh

test-chunking:
	@echo "Testing document chunking..."
	@workato exec console connectors/rag_utils/$(VERSION).rb -c "actions[:process_document_for_rag].execute(connection, {'document_content' => 'Test content', 'file_path' => 'test.txt'})"

test-embedding:
	@echo "Testing embedding generation..."
	@workato exec console connectors/vertex/$(VERSION).rb -c "actions[:generate_embeddings].execute(connection, {'batch_id' => 'test', 'texts' => [{'id' => '1', 'content' => 'test'}]})"

test-indexing:
	@echo "Testing vector index operations..."
	@workato exec console connectors/vertex/$(VERSION).rb -c "actions[:upsert_index_datapoints].execute(connection, {'index_id' => 'test_index', 'datapoints' => []})"

# Mock Services Management
.PHONY: mock-start mock-stop mock-drive mock-api mock-status mock-logs

mock-start:
	@echo "Starting all mock services..."
	@make mock-api
	@make mock-drive
	@echo "All mock services started"

mock-stop:
	@echo "Stopping all mock services..."
	@-pkill -f "node.*mock" 2>/dev/null || true
	@-docker-compose down 2>/dev/null || true
	@echo "All mock services stopped"

mock-drive:
	@echo "Starting mock Drive service on port $(MOCK_DRIVE_PORT)..."
	@cd test/mock_services/drive && node server.js > drive.log 2>&1 &
	@echo "Mock Drive service started (PID: $$!)"

mock-api:
	@echo "Starting mock API service..."
	@docker-compose up -d mockapi
	@echo "Mock API service started on port $(MOCK_API_PORT)"

mock-status:
	@echo "Checking mock services status..."
	@-curl -s http://localhost:$(MOCK_API_PORT)/health | jq '.' || echo "Mock API: Not running"
	@-curl -s http://localhost:$(MOCK_DRIVE_PORT)/health | jq '.' || echo "Mock Drive: Not running"

mock-logs:
	@echo "=== Mock Drive Logs ==="
	@-tail -20 test/mock_services/drive/drive.log 2>/dev/null || echo "No logs found"
	@echo ""
	@echo "=== Docker Services Logs ==="
	@docker-compose logs --tail=20

# Debugging Commands
.PHONY: debug-action diff-connectors test-action compare-versions

debug-action:
	@echo "Debugging action: $(ACTION) in $(CONNECTOR)"
	@workato exec console connectors/$(CONNECTOR)/$(VERSION).rb -c "puts actions[:$(ACTION)].to_yaml"

diff-connectors:
	@echo "Comparing RAG Utils and Vertex connectors..."
	@diff -u connectors/rag_utils/$(VERSION).rb connectors/vertex/$(VERSION).rb | head -100

test-action:
	@echo "Testing specific action: $(ACTION)"
	@workato exec console connectors/$(CONNECTOR)/$(VERSION).rb -c "actions[:$(ACTION)].execute(connection, {})"

compare-versions:
	@echo "Comparing connector versions..."
	@diff -u connectors/$(CONNECTOR)/v1.0.rb connectors/$(CONNECTOR)/$(VERSION).rb | head -100

# Development Helpers
.PHONY: watch lint format check-syntax

watch:
	@echo "Watching for changes..."
	@fswatch -o connectors/ | xargs -n1 -I{} make test CONNECTOR=$(CONNECTOR)

lint:
	@echo "Linting Ruby code..."
	@rubocop connectors/$(CONNECTOR)/$(VERSION).rb

format:
	@echo "Formatting Ruby code..."
	@rubocop -a connectors/$(CONNECTOR)/$(VERSION).rb

check-syntax:
	@echo "Checking syntax for all connectors..."
	@for conn in rag_utils vertex; do \
		echo "Checking $$conn..."; \
		ruby -c connectors/$$conn/$(VERSION).rb || exit 1; \
	done
	@echo "All connectors have valid syntax"

# Complete Test Suite
.PHONY: test-all test-integration test-unit test-performance

test-all: check-syntax test-contracts test-v2-compatibility test-integration
	@echo "======================================="
	@echo "All tests completed successfully!"
	@echo "======================================="

test-integration: mock-start
	@echo "Running integration tests..."
	@make test-drive
	@make test-pipeline
	@make mock-stop

test-unit:
	@echo "Running unit tests..."
	@ruby test/unit/rag_utils_test.rb
	@ruby test/unit/vertex_test.rb

test-performance:
	@echo "Running performance tests..."
	@ruby test/performance/benchmark_chunking.rb
	@ruby test/performance/benchmark_embedding.rb

# Quick Commands (aliases)
.PHONY: tc td tp ms

tc: test-contracts
td: test-drive  
tp: test-pipeline
ms: mock-status

# Usage Examples
.PHONY: examples

examples:
	@echo "Common Usage Examples:"
	@echo "----------------------"
	@echo "Test RAG Utils:        make test CONNECTOR=rag_utils"
	@echo "Test Vertex:           make test CONNECTOR=vertex"
	@echo "Open console:          make console CONNECTOR=vertex"
	@echo "Test contracts:        make test-contracts"
	@echo "Test Drive:            make test-drive"
	@echo "Start mocks:           make mock-start"
	@echo "Check mock status:     make mock-status"
	@echo "Test specific action:  make test-action CONNECTOR=vertex ACTION=fetch_drive_file"
	@echo "Debug action:          make debug-action CONNECTOR=rag_utils ACTION=smart_chunk_text"
	@echo "Run all tests:         make test-all"

# Default target
.DEFAULT_GOAL := help
