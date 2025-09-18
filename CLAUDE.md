# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

**Setup:**
- `./setup.sh` - Initial setup (installs Workato SDK and dependencies)
- `bundle install` - Install Ruby gems

**Testing:**
- `make test` - Test default connector (sample_connector)
- `make test CONNECTOR=name` - Test specific connector
- `make console` - Open Workato console for default connector
- `make console CONNECTOR=name` - Open console for specific connector

**Specialized Commands:**
- `make validate-contract CONNECTOR=name` - Validate connector contracts
- `make test-contract CONTRACT=name` - Test specific contract
- `make debug-action CONNECTOR=name ACTION=action_name` - Debug specific action
- `make diff-connectors` - Compare rag_utils.rb and vertex_ai.rb connectors

**Services:**
- `docker-compose up -d` - Start test services (MockAPI on port 3001, PostgreSQL on 5432)

## Architecture

This is a Workato connector development environment with:

- **connectors/**: Workato connector Ruby files defining APIs, actions, triggers, and object definitions
- **test/**: Test utilities including TestHelper module for contract validation
- **Makefile**: Development commands and workflows
- **docker-compose.yml**: Local test services (MockAPI, PostgreSQL)

**Connector Structure:**
Each connector file follows Workato SDK format with:
- `connection`: Authentication and base URI configuration
- `actions`: Available operations
- `triggers`: Event-based workflows
- `object_definitions`: Data schemas and contracts

**Testing Approach:**
- Use `workato exec check` for syntax validation
- Use `workato exec console` for interactive testing
- Contract validation through TestHelper.test_contract() method
- Mock services available via docker-compose for integration testing

## Project Context
Migrating Workato connectors for RAG email system (750 emails/day) with clean separation:
- RAG_Utils: Preparation layer (chunking, validation, Data Tables)
- Vertex AI: AI layer (inference, embeddings, vector search)
- Environment: GitHub Codespaces with Ruby 3.3, Workato SDK installed
- Working directory structure: /connectors/{connector_name}.rb

## Technical Constraints
- Ruby in Workato's sandboxed environment (limited gems)
- Lambda-based action definitions with call() pattern
- No direct connector-to-connector communication
- Service account authentication for Google Cloud
- Contract validation required between connectors

## Development Standards
- Test with: make test CONNECTOR=rag_utils
- Console: make console CONNECTOR=vertex_ai
- Mock API available on port 3001
- Use workato exec check for syntax validation
- Maintain backward compatibility (v1.0 → v1.1 → v2.0)

## Code Patterns
- Always use: lambda do |connection, input| ... end
- Method calls: call('method_name', connection, params)
- Error handling: error("message") not raise
- Deprecation: Add warnings, don't break existing recipes

## Active Contracts
- cleaned_text, embedding_request, classification_request
- All inter-connector data must validate contracts
- See data_contracts.md for specifications

## Current Focus
Migration Phase 1: Add contract validation and deprecation warnings
Target: 50-100 AI responses/day from 750 emails
- The RAG_Utils connector is found at "connectors/rag_utils/v2.0_proposed.rb"#
- The Vertex connector is found at "connectors/vertex/v2.0_proposed.rb"