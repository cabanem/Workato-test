#!/bin/bash

echo "================================"
echo "Running Contract Validation Suite"
echo "================================"

# Set test environment
export TEST_ENV=true
export CONTRACT_VERSION=2.0

# Run contract validation tests
echo -e "\n[1/3] Running contract validation tests..."
ruby test/contract_validation/contract_validation_test.rb

# Run compatibility tests
echo -e "\n[2/3] Running backward compatibility tests..."
ruby test/contract_validation/contract_validation_test.rb --compatibility-check

# Run connector syntax checks
echo -e "\n[3/3] Running connector syntax validation..."
workato exec check connectors/rag_utils/v2.0_proposed.rb
workato exec check connectors/vertex/v2.0_proposed.rb

echo -e "\n================================"
echo "Test suite completed"
echo "================================"
