# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Workato connector development repository using the Workato Connector SDK. The project focuses on building custom connectors for various services including Google Vertex AI, Gmail, and other utilities.

## Development Commands

### Setup and Installation
- 🚀 Starting Workato Development Setup...
✅ Setup complete! - Initial setup and gem installation
-  - Make setup script executable (if needed)
- Bundle complete! 6 Gemfile dependencies, 60 gems now installed.
Use `bundle info [gemname]` to see where a bundled gem is installed. - Install Ruby dependencies

### Testing and Validation
- Syntax OK - Test the default sample connector
-  - Test a specific connector (without .rb extension)
-  - Syntax check a connector file
-  - Validate connector using Workato SDK

### Development Tools
-  - Launch Workato console for default connector
-  - Launch console for specific connector
-  - Direct console access

### Utility Commands
- Commands: setup, test, console, clean - Show available make commands
-  - Remove temporary files and logs
-  - Start mock API services for testing

## Code Architecture

### Directory Structure
-  - Main connector implementations
  -  - Google Vertex AI connector with authentication options
  -  - Gmail connector with OAuth2 implementation
  -  - RAG (Retrieval Augmented Generation) utilities
  -  - Shared utilities for data manipulation
-  - Additional utilities and helper scripts
  -  - File encoding and transmission utilities
  -  - Documentation retrieval tools

### Connector Structure
Connectors are Ruby hashes defining:
-  - Display name for the connector
-  - Authentication and configuration fields
-  - Support for custom HTTP actions
- Actions, triggers, and object definitions specific to each service

### Key Technologies
- **Workato Connector SDK** - Primary framework for connector development
- **Ruby** - Implementation language
- **OAuth2** - Authentication mechanism for Google services
- **Docker** - Mock services for testing

## Testing Infrastructure

The repository includes comprehensive testing support:
- RSpec for unit testing
- VCR for HTTP interaction recording
- WebMock for HTTP request stubbing
- Docker-based mock API services

## Authentication Patterns

Connectors implement various authentication methods:
- **OAuth2** - Used for Gmail and other Google services with scope-based permissions
- **Service Account** - For Vertex AI with JSON key files
- **API Keys** - For simpler service integrations

## Development Workflow

1. Create new connectors in 
2. Use existing connectors as templates for structure and patterns
3. Test connectors using 
4. Use console for interactive development: 
5. Validate syntax and structure before committing changes

## Important Notes

- Connector files should be named consistently (e.g., )
- Authentication credentials should never be hardcoded
- Use the Workato SDK's built-in helpers for common operations
- Test with mock services before connecting to real APIs
- Follow the existing code patterns for consistency across connectors
