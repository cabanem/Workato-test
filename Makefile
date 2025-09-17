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
