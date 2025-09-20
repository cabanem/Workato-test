# test/helpers/test_helper.rb
require 'json'
require 'time'
require 'fileutils'
require 'net/http'
require 'uri'

module TestHelper
  PROJECT_ROOT = File.expand_path('../..', __dir__)
  TEST_ROOT = File.join(PROJECT_ROOT, 'test')
  FIXTURES_PATH = File.join(TEST_ROOT, 'fixtures')
  CONNECTORS_PATH = File.join(PROJECT_ROOT, 'connectors')
  
  # Mock service URLs
  MOCK_API_URL = 'http://localhost:3001'
  MOCK_DRIVE_URL = 'http://localhost:3002'
  
  class << self
    # Load a connector for testing
    def load_connector(name, version = 'v2.0_proposed')
      path = File.join(CONNECTORS_PATH, name, "#{version}.rb")
      unless File.exist?(path)
        # Try without version subdirectory
        path = File.join(CONNECTORS_PATH, "#{name}.rb")
      end
      
      raise "Connector not found: #{path}" unless File.exist?(path)
      eval(File.read(path))
    end
    
    # Load fixture data
    def load_fixture(relative_path, format = :auto)
      path = fixture_path(relative_path)
      raise "Fixture not found: #{path}" unless File.exist?(path)
      
      content = File.read(path)
      
      case format
      when :json
        JSON.parse(content)
      when :text, :txt
        content
      when :ruby
        eval(content)
      when :auto
        case File.extname(path)
        when '.json'
          JSON.parse(content)
        when '.rb'
          eval(content)
        else
          content
        end
      else
        content
      end
    end
    
    # Get fixture path
    def fixture_path(relative_path)
      File.join(FIXTURES_PATH, relative_path)
    end
    
    # Create temporary test file
    def create_temp_file(name, content)
      temp_dir = File.join(TEST_ROOT, 'tmp')
      FileUtils.mkdir_p(temp_dir)
      
      path = File.join(temp_dir, name)
      File.write(path, content)
      path
    end
    
    # Clean up temporary files
    def cleanup_temp_files
      temp_dir = File.join(TEST_ROOT, 'tmp')
      FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
    end
    
    # Mock HTTP response
    def mock_response(status = 200, body = {}, headers = {})
      MockResponse.new(status, body, headers)
    end
    
    # Test contract validation
    def test_contract(data, contract_type, version = '2.0')
      require_relative '../contract_validation/validate_contract'
      ContractValidator.validate(data, contract_type, version)
    end
    
    # Check if mock services are running
    def check_mock_services
      services = {
        mock_api: check_service(MOCK_API_URL),
        mock_drive: check_service(MOCK_DRIVE_URL)
      }
      
      services
    end
    
    # Start mock services
    def start_mock_services
      system("docker-compose up -d mockapi mockdrive")
      sleep(2) # Give services time to start
      check_mock_services
    end
    
    # Stop mock services
    def stop_mock_services
      system("docker-compose down")
    end
    
    # Generate sample data
    def generate_sample_document(type = 'policy')
      case type
      when 'policy'
        load_fixture('documents/sample_policy.txt')
      when 'faq'
        load_fixture('documents/sample_faq.txt')
      else
        "Sample document content for type: #{type}"
      end
    end
    
    def generate_sample_embedding(dimensions = 768)
      Array.new(dimensions) { rand(-1.0..1.0).round(6) }
    end
    
    def generate_drive_file_metadata(options = {})
      defaults = {
        'id' => "file_#{SecureRandom.hex(8)}",
        'name' => 'test_document.txt',
        'mimeType' => 'text/plain',
        'size' => 1024,
        'createdTime' => (Time.now - 86400).iso8601,
        'modifiedTime' => Time.now.iso8601,
        'md5Checksum' => SecureRandom.hex(16),
        'parents' => ['folder_123']
      }
      
      defaults.merge(options)
    end
    
    # Validate action input/output
    def validate_action_io(connector, action_name, input, expected_output_keys = [])
      action = connector[:actions][action_name.to_sym]
      raise "Action not found: #{action_name}" unless action
      
      # Execute action
      result = action[:execute].call(connector[:connection], input)
      
      # Validate output has expected keys
      missing_keys = expected_output_keys - result.keys
      extra_keys = result.keys - expected_output_keys
      
      {
        success: missing_keys.empty?,
        result: result,
        missing_keys: missing_keys,
        extra_keys: extra_keys
      }
    end
    
    private
    
    def check_service(url)
      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)
      response.code == '200'
    rescue
      false
    end
  end
  
  # Mock response class for testing
  class MockResponse
    attr_reader :code, :body, :headers
    
    def initialize(code, body, headers = {})
      @code = code.to_s
      @body = body.is_a?(Hash) ? body.to_json : body.to_s
      @headers = headers
    end
    
    def [](key)
      @body[key] if @body.is_a?(Hash)
    end
    
    def to_h
      JSON.parse(@body) rescue {}
    end
  end
  
  # Test assertions
  module Assertions
    def assert_equal(expected, actual, message = nil)
      unless expected == actual
        msg = message || "Expected #{expected.inspect}, got #{actual.inspect}"
        raise AssertionError, msg
      end
      true
    end
    
    def assert_not_nil(value, message = nil)
      if value.nil?
        msg = message || "Expected non-nil value, got nil"
        raise AssertionError, msg
      end
      true
    end
    
    def assert_includes(collection, item, message = nil)
      unless collection.include?(item)
        msg = message || "Expected #{collection.inspect} to include #{item.inspect}"
        raise AssertionError, msg
      end
      true
    end
    
    def assert_contract_valid(data, contract_type, version = '2.0')
      result = TestHelper.test_contract(data, contract_type, version)
      unless result.start_with?('✓')
        raise AssertionError, "Contract validation failed: #{result}"
      end
      true
    end
  end
  
  class AssertionError < StandardError; end
end

# Include assertions in test classes
if defined?(RSpec)
  RSpec.configure do |config|
    config.include TestHelper::Assertions
  end
end
