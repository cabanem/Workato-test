#!/usr/bin/env ruby

# Contract Validation Test
# Tests data contracts between RAG_Utils and Vertex connectors
# Validates that data flows correctly and meets contract requirements

require 'json'
require 'time'

class ContractValidationTest
  def initialize
    @test_results = []
    @passed_tests = 0
    @failed_tests = 0
    @contract_violations = []
  end

  def run_all_tests
    puts "=" * 80
    puts "CONTRACT VALIDATION TEST SUITE"
    puts "Testing data contracts between RAG_Utils and Vertex connectors"
    puts "=" * 80
    puts

    # Test cases
    test_cleaned_text_to_ai_classify_valid
    test_cleaned_text_to_ai_classify_invalid
    test_embedding_request_to_generate_embeddings_valid
    test_embedding_request_to_generate_embeddings_invalid
    test_prepared_prompt_integration
    test_batch_embedding_integration

    # Print results
    print_test_summary
  end

  private

  # Test Case 1: Valid cleaned_text → ai_classify
  def test_cleaned_text_to_ai_classify_valid
    test_name = "Valid cleaned_text → ai_classify"
    puts "Testing: #{test_name}"

    begin
      # Generate sample cleaned_text data
      cleaned_text_data = generate_cleaned_text_sample(valid: true)

      # Validate against RAG_Utils contract
      validation_result = validate_rag_utils_contract(cleaned_text_data, 'cleaned_text')

      if validation_result[:valid]
        # Prepare for ai_classify action
        ai_classify_input = {
          'text' => cleaned_text_data['text'],
          'categories' => [
            { 'key' => 'urgent', 'description' => 'Urgent emails requiring immediate attention' },
            { 'key' => 'normal', 'description' => 'Regular business emails' },
            { 'key' => 'informational', 'description' => 'Informational emails for reference' }
          ],
          'model' => 'publishers/google/models/gemini-pro',
          'options' => {
            'return_confidence' => true,
            'return_alternatives' => true,
            'temperature' => 0.1
          }
        }

        # Validate ai_classify input structure
        classification_valid = validate_ai_classify_input(ai_classify_input)

        if classification_valid
          # Simulate ai_classify response
          simulated_response = simulate_ai_classify_response(ai_classify_input)

          # Validate response against classification_response contract
          response_validation = validate_rag_utils_contract(simulated_response, 'classification_response')

          if response_validation[:valid]
            record_test_result(test_name, true, "Contract validation successful")
          else
            record_test_result(test_name, false, "Response contract validation failed: #{response_validation[:errors]}")
          end
        else
          record_test_result(test_name, false, "ai_classify input validation failed")
        end
      else
        record_test_result(test_name, false, "RAG_Utils contract validation failed: #{validation_result[:errors]}")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  # Test Case 2: Invalid cleaned_text → ai_classify
  def test_cleaned_text_to_ai_classify_invalid
    test_name = "Invalid cleaned_text → ai_classify (should error)"
    puts "Testing: #{test_name}"

    begin
      # Generate invalid cleaned_text data (missing required fields)
      invalid_data = {
        'text' => 'Some text',
        # missing: removed_sections, word_count, cleaning_applied
      }

      # Validate against RAG_Utils contract - should fail
      validation_result = validate_rag_utils_contract(invalid_data, 'cleaned_text')

      if !validation_result[:valid]
        record_test_result(test_name, true, "Correctly rejected invalid data: #{validation_result[:errors]}")
      else
        record_test_result(test_name, false, "Failed to reject invalid data")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  # Test Case 3: Valid embedding_request → generate_embeddings
  def test_embedding_request_to_generate_embeddings_valid
    test_name = "Valid embedding_request → generate_embeddings"
    puts "Testing: #{test_name}"

    begin
      # Generate sample embedding_request data
      embedding_requests = generate_embedding_request_sample(valid: true)

      # Validate against RAG_Utils contract
      validation_results = embedding_requests.map do |req|
        validate_rag_utils_contract(req, 'embedding_request')
      end

      if validation_results.all? { |r| r[:valid] }
        # Prepare for generate_embeddings action
        batch_input = {
          'batch_id' => 'test_batch_001',
          'texts' => embedding_requests.map.with_index do |req, idx|
            {
              'id' => "text_#{idx + 1}",
              'content' => req['text'],
              'metadata' => req['metadata']
            }
          end,
          'model' => 'publishers/google/models/text-embedding-004',
          'task_type' => 'SEMANTIC_SIMILARITY'
        }

        # Validate batch input structure
        batch_valid = validate_batch_embedding_input(batch_input)

        if batch_valid
          # Simulate generate_embeddings response
          simulated_response = simulate_batch_embedding_response(batch_input)

          # Validate response structure
          response_valid = validate_batch_embedding_response(simulated_response)

          if response_valid
            record_test_result(test_name, true, "Batch embedding contract validation successful")
          else
            record_test_result(test_name, false, "Batch embedding response validation failed")
          end
        else
          record_test_result(test_name, false, "Batch embedding input validation failed")
        end
      else
        failed_validations = validation_results.select { |r| !r[:valid] }
        record_test_result(test_name, false, "Embedding request validation failed: #{failed_validations}")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  # Test Case 4: Invalid embedding_request → generate_embeddings
  def test_embedding_request_to_generate_embeddings_invalid
    test_name = "Invalid embedding_request → generate_embeddings (should error)"
    puts "Testing: #{test_name}"

    begin
      # Generate invalid embedding_request data
      invalid_data = {
        'text' => 'Some text',
        # missing: metadata (required field)
      }

      # Validate against RAG_Utils contract - should fail
      validation_result = validate_rag_utils_contract(invalid_data, 'embedding_request')

      if !validation_result[:valid]
        record_test_result(test_name, true, "Correctly rejected invalid embedding request: #{validation_result[:errors]}")
      else
        record_test_result(test_name, false, "Failed to reject invalid embedding request")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  # Test Case 5: Prepared prompt integration
  def test_prepared_prompt_integration
    test_name = "Prepared prompt integration (RAG_Utils → Vertex send_messages)"
    puts "Testing: #{test_name}"

    begin
      # Generate prepared prompt data
      prepared_prompt = generate_prepared_prompt_sample

      # Prepare for send_messages action with formatted_prompt
      send_messages_input = {
        'model' => 'publishers/google/models/gemini-pro',
        'formatted_prompt' => prepared_prompt
      }

      # Validate input structure
      input_valid = validate_send_messages_input(send_messages_input)

      if input_valid
        record_test_result(test_name, true, "Prepared prompt integration successful")
      else
        record_test_result(test_name, false, "Prepared prompt validation failed")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  # Test Case 6: Batch embedding integration
  def test_batch_embedding_integration
    test_name = "Batch embedding integration (RAG_Utils prepare_embedding_batch → Vertex generate_embeddings)"
    puts "Testing: #{test_name}"

    begin
      # Generate sample batch data from RAG_Utils prepare_embedding_batch
      batch_data = generate_batch_embedding_sample

      # Validate batch structure
      batch_valid = validate_batch_embedding_output(batch_data)

      if batch_valid
        # Extract data for Vertex generate_embeddings
        vertex_input = {
          'batch_id' => batch_data['batches'][0]['batch_id'],
          'texts' => batch_data['batches'][0]['requests'].map.with_index do |req, idx|
            {
              'id' => "extracted_#{idx}",
              'content' => req['text'],
              'metadata' => req['metadata']
            }
          end,
          'model' => 'publishers/google/models/text-embedding-004',
          'task_type' => batch_data['task_type']
        }

        # Validate transformed input
        input_valid = validate_batch_embedding_input(vertex_input)

        if input_valid
          record_test_result(test_name, true, "Batch embedding integration successful")
        else
          record_test_result(test_name, false, "Transformed batch input validation failed")
        end
      else
        record_test_result(test_name, false, "Batch embedding output validation failed")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  # Sample Data Generators
  def generate_cleaned_text_sample(valid: true)
    if valid
      {
        'text' => 'Hello team, I need help with the project analysis. Can you please review the attached documents?',
        'removed_sections' => ['--\nJohn Doe\nSenior Analyst'],
        'word_count' => 16,
        'cleaning_applied' => {
          'source_type' => 'email',
          'task_type' => 'classification',
          'operations' => ['remove_signatures', 'normalize_whitespace'],
          'original_length' => 120,
          'final_length' => 85,
          'reduction_percentage' => 29.17
        }
      }
    else
      {
        'text' => 'Incomplete data'
        # Missing required fields
      }
    end
  end

  def generate_embedding_request_sample(valid: true)
    if valid
      [
        {
          'text' => 'Product Overview: This is a comprehensive guide to our latest product features.',
          'metadata' => {
            'id' => 'doc_001',
            'title' => 'Product Overview',
            'source' => 'documentation'
          }
        },
        {
          'text' => 'Technical Specifications: Detailed technical requirements and implementation notes.',
          'metadata' => {
            'id' => 'doc_002',
            'title' => 'Technical Specifications',
            'source' => 'documentation'
          }
        }
      ]
    else
      [
        {
          'text' => 'Incomplete request'
          # Missing metadata
        }
      ]
    end
  end

  def generate_prepared_prompt_sample
    {
      'contents' => [
        {
          'role' => 'user',
          'parts' => [
            {
              'text' => 'Based on the following context documents, please answer the user question:\n\nContext: Sample context here\n\nQuestion: What is the main topic?'
            }
          ]
        }
      ],
      'systemInstruction' => {
        'parts' => [
          {
            'text' => 'You are a helpful assistant that answers questions based on provided context.'
          }
        ]
      },
      'generationConfig' => {
        'temperature' => 0.7,
        'maxOutputTokens' => 1024
      }
    }
  end

  def generate_batch_embedding_sample
    {
      'batches' => [
        {
          'batch_id' => 'emb_batch_0_20241215103000',
          'batch_number' => 0,
          'requests' => [
            {
              'text' => 'Product Overview: This is a sample product description for testing.',
              'metadata' => {
                'id' => 'doc_123',
                'title' => 'Product Overview',
                'task_type' => 'RETRIEVAL_DOCUMENT',
                'batch_id' => 'emb_batch_0_20241215103000'
              }
            }
          ],
          'size' => 1
        }
      ],
      'total_batches' => 1,
      'total_texts' => 1,
      'task_type' => 'RETRIEVAL_DOCUMENT',
      'batch_generation_timestamp' => Time.now.utc.iso8601
    }
  end

  # Contract Validation Methods
  def validate_rag_utils_contract(data, contract_type)
    contracts = {
      'cleaned_text' => {
        required_fields: ['text', 'removed_sections', 'word_count', 'cleaning_applied'],
        field_types: {
          'text' => String,
          'removed_sections' => Array,
          'word_count' => Integer,
          'cleaning_applied' => Hash
        }
      },
      'embedding_request' => {
        required_fields: ['text', 'metadata'],
        field_types: {
          'text' => String,
          'metadata' => Hash
        }
      },
      'classification_response' => {
        required_fields: ['selected_category', 'confidence'],
        field_types: {
          'selected_category' => String,
          'confidence' => Float,
          'alternatives' => Array,
          'usage_metrics' => Hash
        }
      }
    }

    contract = contracts[contract_type]
    return { valid: false, errors: ["Unknown contract type: #{contract_type}"] } unless contract

    errors = []

    # Check required fields
    missing_fields = contract[:required_fields].select { |field| !data.key?(field) }
    errors << "Missing required fields: #{missing_fields.join(', ')}" unless missing_fields.empty?

    # Check field types
    contract[:field_types].each do |field, expected_type|
      next unless data.key?(field) && data[field]

      actual_value = data[field]
      unless actual_value.is_a?(expected_type)
        errors << "Field '#{field}' should be #{expected_type}, got #{actual_value.class}"
      end
    end

    { valid: errors.empty?, errors: errors }
  end

  def validate_ai_classify_input(input)
    required_fields = ['text', 'categories', 'model']
    missing_fields = required_fields.select { |field| !input.key?(field) }

    return false unless missing_fields.empty?
    return false unless input['categories'].is_a?(Array)
    return false if input['categories'].empty?

    # Validate category structure
    input['categories'].all? do |cat|
      cat.is_a?(Hash) && cat.key?('key')
    end
  end

  def validate_batch_embedding_input(input)
    required_fields = ['batch_id', 'texts', 'model']
    missing_fields = required_fields.select { |field| !input.key?(field) }

    return false unless missing_fields.empty?
    return false unless input['texts'].is_a?(Array)

    # Validate text structure
    input['texts'].all? do |text|
      text.is_a?(Hash) && text.key?('id') && text.key?('content')
    end
  end

  def validate_batch_embedding_output(output)
    required_fields = ['batches', 'total_batches', 'total_texts', 'task_type']
    missing_fields = required_fields.select { |field| !output.key?(field) }

    return false unless missing_fields.empty?
    return false unless output['batches'].is_a?(Array)

    # Validate batch structure
    output['batches'].all? do |batch|
      batch.is_a?(Hash) &&
        batch.key?('batch_id') &&
        batch.key?('requests') &&
        batch['requests'].is_a?(Array)
    end
  end

  def validate_send_messages_input(input)
    return false unless input.key?('model')
    return false unless input.key?('formatted_prompt') || input.key?('messages')

    if input.key?('formatted_prompt')
      prompt = input['formatted_prompt']
      return false unless prompt.is_a?(Hash)
      return false unless prompt.key?('contents')
    end

    true
  end

  def validate_batch_embedding_response(response)
    required_fields = ['batch_id', 'embeddings', 'model_used', 'total_processed']
    missing_fields = required_fields.select { |field| !response.key?(field) }

    return false unless missing_fields.empty?
    return false unless response['embeddings'].is_a?(Array)

    # Validate embedding structure
    response['embeddings'].all? do |emb|
      emb.is_a?(Hash) &&
        emb.key?('id') &&
        emb.key?('vector') &&
        emb.key?('dimensions')
    end
  end

  # Simulation Methods
  def simulate_ai_classify_response(input)
    {
      'selected_category' => input['categories'][0]['key'],
      'confidence' => 0.85,
      'alternatives' => [
        { 'category' => input['categories'][1]['key'], 'confidence' => 0.15 }
      ],
      'usage_metrics' => {
        'prompt_token_count' => 45,
        'candidates_token_count' => 12,
        'total_token_count' => 57
      }
    }
  end

  def simulate_batch_embedding_response(input)
    {
      'batch_id' => input['batch_id'],
      'embeddings' => input['texts'].map do |text|
        {
          'id' => text['id'],
          'vector' => Array.new(768) { rand(-1.0..1.0).round(6) },
          'dimensions' => 768,
          'metadata' => text['metadata'] || {}
        }
      end,
      'model_used' => input['model'],
      'total_processed' => input['texts'].length,
      'usage_statistics' => {
        'total_requests' => input['texts'].length,
        'successful_requests' => input['texts'].length,
        'failed_requests' => 0,
        'total_tokens' => input['texts'].length * 20
      }
    }
  end

  # Test Management
  def record_test_result(test_name, passed, message)
    result = {
      test_name: test_name,
      status: passed ? :passed : :failed,
      message: message,
      timestamp: Time.now
    }

    @test_results << result

    if passed
      @passed_tests += 1
    else
      @failed_tests += 1
      @contract_violations << result
    end
  end

  def print_test_summary
    puts "=" * 80
    puts "TEST SUMMARY"
    puts "=" * 80
    puts "Total Tests: #{@test_results.length}"
    puts "Passed: #{@passed_tests}"
    puts "Failed: #{@failed_tests}"
    puts "Success Rate: #{(@passed_tests.to_f / @test_results.length * 100).round(2)}%"
    puts

    if @contract_violations.any?
      puts "CONTRACT VIOLATIONS:"
      puts "-" * 40
      @contract_violations.each do |violation|
        puts "❌ #{violation[:test_name]}"
        puts "   #{violation[:message]}"
        puts
      end
    else
      puts "✅ All contract validations passed!"
    end

    puts "=" * 80
  end
end

# Run the tests if this file is executed directly
if __FILE__ == $0
  test_suite = ContractValidationTest.new
  test_suite.run_all_tests
end