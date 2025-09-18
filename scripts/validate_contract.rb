# scripts/validate_contract.rb
module ContractValidator
  CONTRACTS = {
    'cleaned_text' => {
      required: ['text', 'metadata'],
      metadata_required: ['original_length', 'cleaned_length', 'processing_applied', 'source_type']
    },
    'embedding_request' => {
      required: ['batch_id', 'texts'],
      texts_structure: ['id', 'content', 'metadata']
    }
  }

  def self.validate(data, contract_type)
    contract = CONTRACTS[contract_type]
    return "Unknown contract: #{contract_type}" unless contract
    
    errors = []
    contract[:required].each do |field|
      errors << "Missing #{field}" unless data[field]
    end
    
    errors.empty? ? "✓ Valid" : "✗ Errors: #{errors.join(', ')}"
  end
end

# For Workato console testing
if defined?(actions)
  puts "Connector actions: #{actions.keys.join(', ')}"
  puts "Validate with: ContractValidator.validate(data, 'cleaned_text')"
end
