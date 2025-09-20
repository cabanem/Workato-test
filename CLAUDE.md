# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

**Setup:**
- `./setup.sh` - Initial setup (installs Workato SDK and dependencies)
- `bundle install` - Install Ruby gems
- `./setup-oauth.sh` - Configure OAuth2 for Google Drive (NEW)

**Testing:**
- `make test` - Test default connector (sample_connector)
- `make test CONNECTOR=name` - Test specific connector
- `make console` - Open Workato console for default connector
- `make console CONNECTOR=name` - Open console for specific connector

**Specialized Commands:**
- `make validate-contract CONNECTOR=name` - Validate connector contracts
- `make test-contract CONTRACT=name` - Test specific contract (v2.0 contracts)
- `make debug-action CONNECTOR=name ACTION=action_name` - Debug specific action
- `make diff-connectors` - Compare rag_utils.rb and vertex_ai.rb connectors
- `make test-drive CONNECTOR=vertex_ai` - Test Drive API connectivity (NEW)
- `make test-oauth CONNECTOR=vertex_ai` - Validate OAuth2 token and scopes (NEW)
- `make test-pipeline` - Test full document processing pipeline (NEW)

**Services:**
- `docker-compose up -d` - Start test services (MockAPI on port 3001, PostgreSQL on 5432)
- `docker-compose up mockdrive -d` - Start mock Google Drive service on port 3002 (NEW)

## Architecture

This is a Workato connector development environment with:
- **connectors/**: Workato connector Ruby files defining APIs, actions, triggers, and object definitions
- **test/**: Test utilities including TestHelper module for contract validation
- **Makefile**: Development commands and workflows
- **docker-compose.yml**: Local test services (MockAPI, PostgreSQL, MockDrive)

**Connector Structure:**
Each connector file follows Workato SDK format with:
- `connection`: Authentication and base URI configuration (NOW includes OAuth2 for Drive)
- `actions`: Available operations (EXPANDED with Drive operations)
- `triggers`: Event-based workflows
- `object_definitions`: Data schemas and contracts (v2.0 with document metadata)
- `methods`: Helper functions (NEW Drive utilities section)

**Testing Approach:**
- Use `workato exec check` for syntax validation
- Use `workato exec console` for interactive testing
- Contract validation through TestHelper.test_contract() method (v2.0 contracts)
- Mock services available via docker-compose for integration testing
- Drive API testing through mock service on port 3002 (NEW)

## Project Context

**Current Phase: Google Drive Integration (Phase 2 of 6)**
Migrating Workato connectors for RAG email system (750 emails/day) with enhanced document processing:
- RAG_Utils: Preparation layer (chunking, validation, Data Tables, document processing)
- Vertex AI: AI layer (inference, embeddings, vector search, Drive access)
- Environment: GitHub Codespaces with Ruby 3.3, Workato SDK installed
- Working directory structure: /connectors/{connector_name}/v2.0_proposed.rb

**Integration Status:**
- ✅ Base connectors (v1.0)
- ✅ Contract definitions (v2.0)
- 🚧 Google Drive OAuth2 setup
- 🚧 Document fetch/list actions
- ⏳ Batch processing actions
- ⏳ Change monitoring
- ⏳ Recipe migration

## Technical Constraints

- Ruby in Workato's sandboxed environment (limited gems)
- Lambda-based action definitions with call() pattern
- No direct connector-to-connector communication
- Service account + OAuth2 authentication for Google Cloud (UPDATED)
- Contract validation required between connectors (v2.0)
- Google Drive API rate limits: 12,000 requests/minute
- Vertex AI embedding batch limit: 25 texts per request
- Vector index update batch limit: 100 datapoints

## OAuth2 Configuration

**Required Scopes:**
```ruby
scopes = [
  'https://www.googleapis.com/auth/cloud-platform',     # Vertex AI
  'https://www.googleapis.com/auth/drive.readonly'      # Google Drive (NEW)
]
```

**Authentication Strategy:**
- OAuth2 for Drive access (user-delegated permissions)
- Service account for Vertex AI operations (when OAuth not available)
- Fallback: Share files with service account email

## Development Standards

- Test with: make test CONNECTOR=rag_utils
- Console: make console CONNECTOR=vertex_ai
- Mock API available on port 3001
- Mock Drive available on port 3002 (NEW)
- Use workato exec check for syntax validation
- Maintain backward compatibility (v1.0 → v1.5 → v2.0)
- Test Drive operations: make test-drive CONNECTOR=vertex_ai (NEW)

## Code Patterns

**Standard Patterns:**
- Always use: lambda do |connection, input| ... end
- Method calls: call('method_name', connection, params)
- Error handling: error("message") not raise
- Deprecation: Add warnings, don't break existing recipes

**Drive-Specific Patterns (NEW):**
```ruby
# OAuth token refresh
call('refresh_drive_token', connection) if connection['oauth_token_expired']

# Drive API error handling
after_error_response(/404/) do |code, body, _header, message|
  error("File not found in Drive: #{message}")
end

# Batch processing
call('batch_with_retry', connection, file_ids, batch_size: 10)
```

## Active Contracts (v2.0)

**Core Contracts:**
- cleaned_text (enhanced with document_metadata)
- embedding_request (enhanced with file tracking)
- classification_request (unchanged)

**New Document Contracts:**
- document_fetch_request/response
- document_chunking_request/response
- folder_monitor_request/response
- document_processing_job
- vector_index_request/response

See data_contracts_v2.md for complete specifications

## Current Focus

**Migration Phase 2: Document Processing Pipeline**
Target: Process 100+ Drive documents → chunks → embeddings → vector index

**Priority Actions:**
1. vertex::fetch_drive_file (CRITICAL)
2. vertex::list_drive_files (CRITICAL)
3. rag::process_document_for_rag (CRITICAL)
4. vertex::batch_fetch_drive_files (HIGH)
5. vertex::test_connection (HIGH)

**Testing Checklist:**
- [ ] OAuth2 token acquisition and refresh
- [ ] Single file fetch with text extraction
- [ ] Folder listing with filtering
- [ ] Document chunking with metadata
- [ ] Embedding generation with document tracking
- [ ] Vector index update with restricts
- [ ] Search with document filters

## Migration Notes

**Breaking Changes (v2.0):**
- OAuth2 re-authentication required for Drive scope
- Vector search response structure enhanced
- Index datapoints require document metadata

**Backward Compatibility:**
- All v1.0 actions continue to work
- New fields are optional unless marked required
- Gradual migration path over 3 months

**Rollback Strategy:**
- Feature flags for new capabilities
- Compatibility mode for 3 months
- Fallback to manual upload if Drive unavailable

## File Locations

- RAG_Utils connector: `connectors/rag_utils/v2.0_proposed.rb`
- Vertex connector: `connectors/vertex/v2.0_proposed.rb`
- Data contracts: `docs/data/data_contracts_v2.md`
  - Validation script:

- Migration map: `docs/migration/migration_map.md`
- Test fixtures: `test/fixtures/drive_responses/`
- Please maintain a changelog at /.claude/CHANGELOG.txt.