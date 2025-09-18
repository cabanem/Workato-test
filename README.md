# Workato Connector Repo

## Quick Start
1. Run `chmod +x ./setup.sh`, then `./setup.sh`
2. Test: `make test`
3. Console: `make console`

## Structure
- `connectors/` - Your connector files
- `test/` - Test files
- `docker-compose.yml` - Local test services

## Commands
- `make help` - Show commands
- `make test CONNECTOR=name` - Test connector
- `docker-compose up -d` - Start test services

---

# Devcontainer

- Remove unused packages
```bash
sudo apt autoremove && sudo apt clean
```

- Clear npm cache
```bash
npm cache clean --force
```

- Remove old gems
```bash
gem cleanup
```

- Delete temporary files
```bash
rm -rf /tmp/*
```

- Prune Docker images/containers
```bash
docker system prune -af
```

---

# Claude

## When starting a new conversation about this project begin with:

```
Working on Workato connector migration in Codespaces.
Context: RAG_Utils + Vertex separation, contract validation
Current task: [specific task]
File: connectors/[rag_utils|vertex_ai].rb
Testing with: make test CONNECTOR=[name]
```

## Conversation starters
```ruby
# For debugging Workato SDK issues
"In Workato SDK, getting error: [error]
Connector: connectors/rag_utils.rb
Action: prepare_for_ai
Line: [number]
Input: [sample]"
```

```ruby
# For implementation help  
"Implement contract validation for [action_name]:
Current code: [paste]
Contract type: cleaned_text
Required fields: text, metadata"
```

```ruby
# For testing
"Create Workato console test for:
Connector: rag_utils
Action: classify_by_pattern  
Test contract: classification_request"
```
