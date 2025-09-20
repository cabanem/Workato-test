#!/usr/bin/env ruby

# Contract Validation Test Suite v2.0
# Tests data contracts between RAG_Utils and Vertex connectors
# Includes document processing pipeline validation

require 'json'
require 'time'

class ContractValidationTest
  def initialize
    @test_results = []
    @passed_tests = 0
    @failed_tests = 0
    @contract_violations = []
    @version = '2.0'
  end

  def run_all_tests
    puts "=" * 80
    puts "CONTRACT VALIDATION TEST SUITE v#{@version}"
    puts "Testing data contracts including Google Drive document processing"
    puts "=" * 80
    puts

    # Original tests (backward compatibility)
    test_cleaned_text_to_ai_classify_valid
    test_cleaned_text_to_ai_classify_invalid
    test_embedding_request_to_generate_embeddings_valid
    test_embedding_request_to_generate_embeddings_invalid
    test_prepared_prompt_integration
    test_batch_embedding_integration

    # New v2.0 document processing tests
    test_document_fetch_contract
    test_document_chunking_contract
    test_enhanced_embedding_with_documents
    test_vector_search_with_filters
    test_document_processing_pipeline
    test_folder_monitoring_contract

    # Print results
    print_test_summary
  end

  private

  # [Previous test methods remain the same...]
  # Adding new v2.0 test methods:

  def test_document_fetch_contract
    test_name = "Document Fetch Contract (Drive → RAG)"
    puts "Testing: #{test_name}"

    begin
      # Test request contract
      fetch_request = {
        'file_id' => 'drive_file_123',
        'export_format' => 'text/plain',
        'include_metadata' => true
      }

      request_valid = validate_contract(fetch_request, 'document_fetch_request')

      if request_valid[:valid]
        # Test response contract
        fetch_response = {
          'file_id' => 'drive_file_123',
          'content' => 'Document content here...',
          'content_type' => 'text',
          'metadata' => {
            'name' => 'Policy_2024.pdf',
            'mime_type' => 'application/pdf',
            'size' => 1024000,
            'created_time' => '2024-01-01T00:00:00Z',
            'modified_time' => '2024-09-19T10:00:00Z',
            'version' => '123'
          }
        }

        response_valid = validate_contract(fetch_response, 'document_fetch_response')

        if response_valid[:valid]
          record_test_result(test_name, true, "Document fetch contract valid")
        else
          record_test_result(test_name, false, "Response validation failed: #{response_valid[:errors]}")
        end
      else
        record_test_result(test_name, false, "Request validation failed: #{request_valid[:errors]}")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  def test_document_chunking_contract
    test_name = "Document Chunking Contract (RAG internal)"
    puts "Testing: #{test_name}"

    begin
      # Test chunking request
      chunking_request = {
        'document' => {
          'file_id' => 'drive_file_123',
          'content' => 'Long document content...',
          'file_name' => 'Policy_2024.pdf'
        },
        'chunking_strategy' => {
          'method' => 'token',
          'chunk_size' => 1000,
          'chunk_overlap' => 100
        }
      }

      request_valid = validate_contract(chunking_request, 'document_chunking_request')

      if request_valid[:valid]
        # Test chunks response
        chunks_response = {
          'document_id' => 'doc_123',
          'file_id' => 'drive_file_123',
          'chunks' => [
            {
              'chunk_id' => 'doc_123_chunk_0',
              'chunk_index' => 0,
              'text' => 'First chunk of text...',
              'token_count' => 250,
              'metadata' => {
                'document_id' => 'doc_123',
                'file_id' => 'drive_file_123',
                'chunk_index' => 0,
                'total_chunks' => 4
              }
            }
          ],
          'stats' => {
            'total_chunks' => 4,
            'total_tokens' => 1000,
            'average_chunk_size' => 250,
            'processing_time_ms' => 150
          }
        }

        response_valid = validate_contract(chunks_response, 'document_chunks_response')

        if response_valid[:valid]
          record_test_result(test_name, true, "Document chunking contract valid")
        else
          record_test_result(test_name, false, "Chunks response validation failed: #{response_valid[:errors]}")
        end
      else
        record_test_result(test_name, false, "Chunking request validation failed: #{request_valid[:errors]}")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  def test_enhanced_embedding_with_documents
    test_name = "Enhanced Embedding with Document Metadata (v2.0)"
    puts "Testing: #{test_name}"

    begin
      # Generate embedding request with document metadata
      embedding_request = {
        'batch_id' => 'batch_doc_001',
        'texts' => [
          {
            'id' => 'doc_123_chunk_0',
            'content' => 'First chunk content...',
            'metadata' => {
              'chunk_index' => 0,
              'document_id' => 'doc_123',
              'file_id' => 'drive_file_123',
              'file_name' => 'Policy_2024.pdf',
              'file_path' => '/policies/2024/Policy_2024.pdf',
              'document_type' => 'policy',
              'last_updated' => '2024-09-19T10:00:00Z'
            }
          }
        ],
        'task_type' => 'RETRIEVAL_DOCUMENT',
        'batch_metadata' => {
          'source' => 'drive_sync',
          'processing_id' => 'job_456',
          'total_documents' => 1
        }
      }

      validation = validate_contract(embedding_request, 'embedding_request')

      if validation[:valid]
        record_test_result(test_name, true, "Enhanced embedding contract valid")
      else
        record_test_result(test_name, false, "Validation failed: #{validation[:errors]}")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  def test_vector_search_with_filters
    test_name = "Vector Search with Document Filters (v2.0)"
    puts "Testing: #{test_name}"

    begin
      # Test search request with filters
      search_request = {
        'query_vector' => Array.new(768, 0.1),
        'index_endpoint' => {
          'host' => '1234.us-central1.vdb.vertexai.goog',
          'endpoint_id' => 'endpoint_xyz',
          'deployed_index_id' => 'deployed_index_123'
        },
        'search_params' => {
          'neighbor_count' => 10,
          'filters' => {
            'restricts' => [
              {
                'namespace' => 'document_type',
                'allowList' => ['policy', 'faq']
              }
            ]
          },
          'crowding' => {
            'per_crowding_attribute_count' => 2
          }
        }
      }

      request_valid = validate_contract(search_request, 'vector_search_request')

      if request_valid[:valid]
        # Test enhanced response
        search_response = {
          'neighbors' => [
            {
              'id' => 'doc_123_chunk_0',
              'distance' => 0.15,
              'document_info' => {
                'file_id' => 'drive_file_123',
                'file_name' => 'Policy_2024.pdf',
                'chunk_index' => 0,
                'section' => 'Return Policy'
              }
            }
          ],
          'stats' => {
            'documents_searched' => 100,
            'unique_documents' => 25,
            'filters_applied' => ['document_type']
          }
        }

        response_valid = validate_contract(search_response, 'vector_search_response')

        if response_valid[:valid]
          record_test_result(test_name, true, "Enhanced vector search contract valid")
        else
          record_test_result(test_name, false, "Response validation failed: #{response_valid[:errors]}")
        end
      else
        record_test_result(test_name, false, "Request validation failed: #{request_valid[:errors]}")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  def test_document_processing_pipeline
    test_name = "Complete Document Processing Pipeline"
    puts "Testing: #{test_name}"

    begin
      # Test job contract
      job = {
        'job_id' => 'job_001',
        'job_type' => 'full_sync',
        'status' => 'processing',
        'source' => {
          'type' => 'google_drive_vertex',
          'folder_id' => 'folder_123'
        },
        'pipeline' => {
          'fetch' => { 'total' => 10, 'completed' => 5 },
          'chunk' => { 'total_documents' => 5, 'total_chunks' => 50, 'completed' => 3 },
          'embed' => { 'total_batches' => 2, 'completed_batches' => 1, 'total_embeddings' => 50 },
          'index' => { 'total_datapoints' => 50, 'successfully_indexed' => 25 }
        }
      }

      validation = validate_contract(job, 'document_processing_job')

      if validation[:valid]
        record_test_result(test_name, true, "Document processing pipeline contract valid")
      else
        record_test_result(test_name, false, "Validation failed: #{validation[:errors]}")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  def test_folder_monitoring_contract
    test_name = "Folder Monitoring Contract (Drive)"
    puts "Testing: #{test_name}"

    begin
      # Test monitor request
      monitor_request = {
        'folder_id' => 'folder_123',
        'options' => {
          'recursive' => true,
          'file_types' => ['application/pdf', 'text/plain'],
          'modified_after' => '2024-09-01T00:00:00Z'
        }
      }

      request_valid = validate_contract(monitor_request, 'folder_monitor_request')

      if request_valid[:valid]
        # Test monitor response
        monitor_response = {
          'folder_id' => 'folder_123',
          'files' => [
            {
              'file_id' => 'file_001',
              'name' => 'Document.pdf',
              'mime_type' => 'application/pdf',
              'size' => 1024000,
              'modified_time' => '2024-09-19T10:00:00Z',
              'md5_checksum' => 'abc123',
              'status' => 'modified'
            }
          ],
          'next_page_token' => 'token_xyz',
          'total_files' => 25
        }

        response_valid = validate_contract(monitor_response, 'folder_monitor_response')

        if response_valid[:valid]
          record_test_result(test_name, true, "Folder monitoring contract valid")
        else
          record_test_result(test_name, false, "Response validation failed: #{response_valid[:errors]}")
        end
      else
        record_test_result(test_name, false, "Request validation failed: #{request_valid[:errors]}")
      end

    rescue => e
      record_test_result(test_name, false, "Exception: #{e.message}")
    end

    puts "  #{@test_results.last[:status] == :passed ? '✓' : '✗'} #{@test_results.last[:message]}"
    puts
  end

  # Contract validation helper using ContractValidator module
  def validate_contract(data, contract_type)
    require_relative './validate_contract'
    result = ContractValidator.validate(data, contract_type, @version)
    
    if result.is_a?(String)
      { valid: result.start_with?('✓'), errors: result }
    else
      result
    end
  rescue => e
    { valid: false, errors: ["Validation error: #{e.message}"] }
  end

  # [Previous helper methods remain the same...]

  def print_test_summary
    puts "=" * 80
    puts "TEST SUMMARY (v#{@version})"
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
