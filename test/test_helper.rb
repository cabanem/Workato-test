# test/test_helper.rb
require 'json'

module TestHelper
  def self.load_connector(name)
    path = File.join(__dir__, '..', 'connectors', "#{name}.rb")
    eval(File.read(path))
  end

  def self.test_contract(connector, action, input, expected_contract)
    conn = load_connector(connector)
    result = conn[:actions][action][:execute].call({}, input)
    
    # Validate against contract
    puts "Testing #{connector}::#{action}"
    puts "Input: #{input.to_json}"
    puts "Output: #{result.to_json}"
    puts "Valid: #{validate_contract(result, expected_contract)}"
  end
end