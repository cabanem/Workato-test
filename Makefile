CONNECTOR ?= sample_connector
.PHONY: help setup test console

help:
	@echo "Commands: setup, test, console, clean"

setup:
	@./setup.sh

test:
	@ruby -c connectors/$(CONNECTOR).rb && workato exec check connectors/$(CONNECTOR).rb

console:
	@workato exec console connectors/$(CONNECTOR).rb

clean:
	@rm -rf tmp/ *.log

# For Claude
.PHONY: validate-contract diff-connectors test-contract debug-action

validate-contract:
	@workato exec console connectors/$(CONNECTOR).rb -c "load 'scripts/validate_contract.rb'"

diff-connectors:
	@git diff --no-index connectors/rag_utils.rb connectors/vertex_ai.rb | head -100

test-contract:
	@ruby test/contracts/$(CONTRACT)_test.rb

debug-action:
	@workato exec console connectors/$(CONNECTOR).rb -c "puts actions[:$(ACTION)]"

# Usage comment for Claude context
# make test CONNECTOR=rag_utils
# make validate-contract CONNECTOR=rag_utils  
# make test-contract CONTRACT=cleaned_text