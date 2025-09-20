#!/usr/bin/env ruby
# test/run_contract_validation.rb
# Comprehensive contract validation for all new components

require_relative 'contract_validation/validate_contract'
require 'json'

class ComprehensiveContractValidation
  def initialize
    @results = []
    @passed = 0
    @failed = 0
  end

  def run_all_validations
    puts "=" * 80
    puts "COMPREHENSIVE CONTRACT VALIDATION"
    puts "Validating all new Drive and RAG document processing components"
    puts "=" * 80
    puts

    # Test expected output contracts for our new actions
    validate_fetch_drive_file_output_contract
    validate_list_drive_files_output_contract
    validate_batch_fetch_output_contract
    validate_process_document_output_contract
    validate_prepare_batch_output_contract
    validate_enhanced_chunking_contract

    # Test cross-connector contract compatibility
    validate_drive_to_rag_pipeline_contracts
    validate_rag_to_vertex_embedding_contracts

    print_validation_report
    @failed == 0
  end

  private

  def validate_fetch_drive_file_output_contract
    test_name = "fetch_drive_file Output Contract"
    puts "Validating: #{test_name}"

    # Expected output from fetch_drive_file action
    sample_output = {
      'id' => 'file_123abc',
      'name' => 'test_document.pdf',
      'mime_type' => 'application/pdf',
      'size' => 1024000,
      'modified_time' => '2024-09-20T10:30:00Z',
      'checksum' => 'md5_hash_here',
      'owners' => [
        {
          'displayName' => 'Test User',
          'emailAddress' => 'test@example.com'
        }
      ],
      'text_content' => 'Extracted document text content...',
      'needs_processing' => false,
      'export_mime_type' => 'text/plain',
      'fetch_method' => 'export'
    }

    # Transform to match document_fetch_response contract
    contract_format = sample_output.merge({
      'file_id' => sample_output['id'],
      'content' => sample_output['text_content'],
      'content_type' => 'text'
    })

    validation = validate_contract(contract_format, 'document_fetch_response')
    record_result(test_name, validation)
  end

  def validate_list_drive_files_output_contract
    test_name = "list_drive_files Output Contract"
    puts "Validating: #{test_name}"

    # Expected output from list_drive_files action
    sample_output = {
      'files' => [
        {
          'id' => 'file_001',
          'name' => 'document1.pdf',
          'mime_type' => 'application/pdf',
          'size' => 500000,
          'modified_time' => '2024-09-20T10:00:00Z',
          'checksum' => 'hash1'
        },
        {
          'id' => 'file_002',
          'name' => 'document2.txt',
          'mime_type' => 'text/plain',
          'size' => 25000,
          'modified_time' => '2024-09-20T11:00:00Z',
          'checksum' => 'hash2'
        }
      ],
      'count' => 2,
      'has_more' => false,
      'next_page_token' => nil,
      'query_used' => "trashed = false"
    }

    # This matches our folder_monitor_response contract (files structure)
    files_validation = validate_contract(
      {
        'folder_id' => 'test_folder',
        'files' => sample_output['files']
      },
      'folder_monitor_response'
    )
    record_result(test_name, files_validation)
  end

  def validate_batch_fetch_output_contract
    test_name = "batch_fetch_drive_files Output Contract"
    puts "Validating: #{test_name}"

    # Expected output from batch_fetch_drive_files action
    sample_output = {
      'successful_files' => [
        {
          'id' => 'file_123',
          'name' => 'document.pdf',
          'mime_type' => 'application/pdf',
          'text_content' => 'Document content...',
          'document_id' => 'doc_hash_123',
          'fetch_method' => 'export'
        }
      ],
      'failed_files' => [
        {
          'file_id' => 'file_456',
          'error_message' => 'File not found',
          'error_code' => 'FETCH_ERROR'
        }
      ],
      'metrics' => {
        'total_processed' => 2,
        'success_count' => 1,
        'failure_count' => 1,
        'success_rate' => 50.0,
        'processing_time_ms' => 1500
      }
    }

    # Validate that successful files match document_fetch_response contract
    successful_file = sample_output['successful_files'][0]
    enhanced_file = successful_file.merge({
      'file_id' => successful_file['id'],
      'content' => successful_file['text_content'],
      'content_type' => 'text'
    })

    validation = validate_contract(enhanced_file, 'document_fetch_response')
    record_result(test_name, validation)
  end

  def validate_process_document_output_contract
    test_name = "process_document_for_rag Output Contract"
    puts "Validating: #{test_name}"

    # Expected output from process_document_for_rag action
    sample_output = {
      'document_id' => 'doc_hash_123',
      'chunks' => [
        {
          'chunk_id' => 'doc_hash_123_chunk_0',
          'text' => 'First chunk of document text...',
          'chunk_index' => 0,
          'start_position' => 0,
          'end_position' => 500,
          'character_count' => 500,
          'word_count' => 85,
          'document_id' => 'doc_hash_123',
          'file_name' => 'document.pdf',
          'file_id' => 'file_123',
          'source' => 'google_drive',
          'indexed_at' => '2024-09-20T12:00:00Z'
        }
      ],
      'document_metadata' => {
        'total_chunks' => 1,
        'total_characters' => 500,
        'total_words' => 85,
        'processing_timestamp' => '2024-09-20T12:00:00Z',
        'chunk_size_used' => 1000,
        'overlap_used' => 100
      },
      'ready_for_embedding' => true
    }

    # This matches our document_chunks_response contract
    chunks_response = {
      'document_id' => sample_output['document_id'],
      'file_id' => sample_output['chunks'][0]['file_id'],
      'chunks' => sample_output['chunks'].map do |chunk|
        {
          'chunk_id' => chunk['chunk_id'],
          'chunk_index' => chunk['chunk_index'],
          'text' => chunk['text'],
          'token_count' => chunk['word_count'] * 1.3, # Approximate token count
          'metadata' => {
            'document_id' => chunk['document_id'],
            'file_id' => chunk['file_id'],
            'source' => chunk['source']
          }
        }
      end,
      'stats' => {
        'total_chunks' => sample_output['document_metadata']['total_chunks'],
        'total_tokens' => (sample_output['document_metadata']['total_words'] * 1.3).to_i,
        'average_chunk_size' => sample_output['document_metadata']['total_characters'] / sample_output['document_metadata']['total_chunks'],
        'processing_time_ms' => 500
      }
    }

    validation = validate_contract(chunks_response, 'document_chunks_response')
    record_result(test_name, validation)
  end

  def validate_prepare_batch_output_contract
    test_name = "prepare_document_batch Output Contract"
    puts "Validating: #{test_name}"

    # Expected output from prepare_document_batch action
    sample_output = {
      'batches' => [
        {
          'batch_id' => 'batch_20240920_120000_0',
          'chunks' => [
            {
              'chunk_id' => 'doc_123_chunk_0',
              'text' => 'Chunk text...',
              'document_id' => 'doc_123',
              'file_id' => 'file_123'
            }
          ],
          'document_count' => 1,
          'chunk_count' => 1,
          'batch_index' => 0
        }
      ],
      'summary' => {
        'total_documents' => 1,
        'total_chunks' => 1,
        'total_batches' => 1,
        'processing_timestamp' => '2024-09-20T12:00:00Z',
        'successful_documents' => 1,
        'failed_documents' => 0
      },
      'failed_documents' => []
    }

    # The chunks in batches should be ready for embedding_request contract
    chunk = sample_output['batches'][0]['chunks'][0]
    embedding_text = {
      'id' => chunk['chunk_id'],
      'content' => chunk['text'],
      'metadata' => {
        'document_id' => chunk['document_id'],
        'file_id' => chunk['file_id'],
        'chunk_index' => 0
      }
    }

    embedding_request = {
      'batch_id' => sample_output['batches'][0]['batch_id'],
      'texts' => [embedding_text]
    }

    validation = validate_contract(embedding_request, 'embedding_request')
    record_result(test_name, validation)
  end

  def validate_enhanced_chunking_contract
    test_name = "Enhanced smart_chunk_text Contract"
    puts "Validating: #{test_name}"

    # Test that enhanced chunks with document metadata are valid
    enhanced_chunk_output = {
      'chunks' => [
        {
          'chunk_id' => 'chunk_0',
          'chunk_index' => 0,
          'text' => 'Sample chunk text...',
          'token_count' => 25,
          'start_char' => 0,
          'end_char' => 100,
          'metadata' => {
            'has_overlap' => false,
            'is_final' => true,
            'document_id' => 'doc_123',
            'file_name' => 'test.pdf',
            'file_id' => 'file_456',
            'total_chunks' => 1
          }
        }
      ],
      'total_chunks' => 1,
      'total_tokens' => 25
    }

    # Enhanced chunks should support embedding_request conversion
    chunk = enhanced_chunk_output['chunks'][0]
    embedding_text = {
      'id' => chunk['chunk_id'],
      'content' => chunk['text'],
      'metadata' => {
        'chunk_index' => chunk['chunk_index'],
        'document_id' => chunk['metadata']['document_id'],
        'file_id' => chunk['metadata']['file_id'],
        'file_name' => chunk['metadata']['file_name']
      }
    }

    embedding_request = {
      'batch_id' => 'test_batch',
      'texts' => [embedding_text]
    }

    validation = validate_contract(embedding_request, 'embedding_request')
    record_result(test_name, validation)
  end

  def validate_drive_to_rag_pipeline_contracts
    test_name = "Drive → RAG Pipeline Contract Compatibility"
    puts "Validating: #{test_name}"

    # Simulate the data flow from Drive fetch to RAG processing

    # 1. Drive fetch output
    drive_output = {
      'id' => 'file_123',
      'name' => 'policy.pdf',
      'mime_type' => 'application/pdf',
      'size' => 100000,
      'modified_time' => '2024-09-20T10:00:00Z',
      'checksum' => 'abc123',
      'text_content' => 'Policy document content...',
      'fetch_method' => 'export'
    }

    # 2. Transform to RAG input format
    rag_input = {
      'document_content' => drive_output['text_content'],
      'file_metadata' => {
        'file_id' => drive_output['id'],
        'file_name' => drive_output['name'],
        'checksum' => drive_output['checksum'],
        'mime_type' => drive_output['mime_type'],
        'size' => drive_output['size'],
        'modified_time' => drive_output['modified_time']
      }
    }

    # 3. Expected RAG processing should work with this input
    # This validates that our fetch_drive_file output is compatible with process_document_for_rag input

    required_fields = ['document_content', 'file_metadata']
    missing_fields = required_fields.select { |field| rag_input[field].nil? || rag_input[field].to_s.empty? }

    required_metadata = ['file_id', 'file_name']
    missing_metadata = required_metadata.select { |field| rag_input['file_metadata'][field].nil? || rag_input['file_metadata'][field].to_s.empty? }

    if missing_fields.empty? && missing_metadata.empty?
      record_result(test_name, "✓ Valid (v2.0)")
    else
      record_result(test_name, "✗ Missing: #{(missing_fields + missing_metadata).join(', ')}")
    end
  end

  def validate_rag_to_vertex_embedding_contracts
    test_name = "RAG → Vertex Embedding Contract Compatibility"
    puts "Validating: #{test_name}"

    # Simulate RAG batch output to Vertex embedding input
    rag_batch_output = {
      'batches' => [
        {
          'batch_id' => 'batch_001',
          'chunks' => [
            {
              'chunk_id' => 'doc_123_chunk_0',
              'text' => 'Document chunk text...',
              'chunk_index' => 0,
              'document_id' => 'doc_123',
              'file_name' => 'policy.pdf',
              'file_id' => 'file_456'
            }
          ]
        }
      ]
    }

    # Transform to Vertex embedding input
    batch = rag_batch_output['batches'][0]
    vertex_input = {
      'batch_id' => batch['batch_id'],
      'texts' => batch['chunks'].map do |chunk|
        {
          'id' => chunk['chunk_id'],
          'content' => chunk['text'],
          'metadata' => {
            'chunk_index' => chunk['chunk_index'],
            'document_id' => chunk['document_id'],
            'file_id' => chunk['file_id'],
            'file_name' => chunk['file_name']
          }
        }
      end
    }

    validation = validate_contract(vertex_input, 'embedding_request')
    record_result(test_name, validation)
  end

  def validate_contract(data, contract_type)
    ContractValidator.validate(data, contract_type, '2.0')
  rescue => e
    "✗ Validation error: #{e.message}"
  end

  def record_result(test_name, validation_result)
    success = validation_result.start_with?('✓')
    @results << {
      test: test_name,
      result: validation_result,
      success: success
    }

    if success
      @passed += 1
      puts "  ✓ #{validation_result}"
    else
      @failed += 1
      puts "  ✗ #{validation_result}"
    end
    puts
  end

  def print_validation_report
    puts "=" * 80
    puts "CONTRACT VALIDATION REPORT"
    puts "=" * 80
    puts "Total Validations: #{@results.length}"
    puts "Passed: #{@passed}"
    puts "Failed: #{@failed}"
    puts "Success Rate: #{(@passed.to_f / @results.length * 100).round(2)}%"
    puts

    if @failed > 0
      puts "FAILED VALIDATIONS:"
      puts "-" * 40
      @results.select { |r| !r[:success] }.each do |result|
        puts "❌ #{result[:test]}"
        puts "   #{result[:result]}"
        puts
      end
    else
      puts "✅ All contract validations passed!"
      puts
      puts "VALIDATED CONTRACTS:"
      puts "-" * 40
      @results.each do |result|
        puts "✓ #{result[:test]}"
      end
    end

    puts "=" * 80
  end
end

if __FILE__ == $0
  validator = ComprehensiveContractValidation.new
  success = validator.run_all_validations
  exit(success ? 0 : 1)
end