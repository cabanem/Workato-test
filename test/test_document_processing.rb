# test_document_processing.rb
# Purpose: Test complete document processing from Drive to chunks
# Requirements tested: Document fetch, text extraction, chunking, metadata

def test_document_processing
  puts "="*50
  puts "Testing Document Processing Pipeline"
  puts "="*50
  
  # Configuration
  test_file_id = ENV['TEST_FILE_ID'] || 'your_test_file_id_here'
  expected_chunk_size = 1000
  expected_overlap = 100
  
  begin
    # Step 1: Fetch document from Drive
    puts "\n1. Fetching document from Drive..."
    doc_response = vertex_connector.fetch_drive_file({
      file_id: test_file_id,
      export_format: 'text/plain'
    })
    
    assert(doc_response['text_content'].present?, "Document content retrieved")
    assert(doc_response['checksum'].present?, "Checksum generated")
    puts "✅ Document fetched: #{doc_response['file_name']}"
    puts "   Size: #{doc_response['text_content'].length} chars"
    
    # Step 2: Process document for RAG
    puts "\n2. Processing document for RAG..."
    process_response = rag_utils.process_document_for_rag({
      document_content: doc_response['text_content'],
      file_path: doc_response['file_name'],
      file_type: doc_response['mime_type'],
      chunk_size: expected_chunk_size,
      chunk_overlap: expected_overlap,
      file_metadata: {
        file_id: doc_response['file_id'],
        checksum: doc_response['checksum']
      }
    })
    
    assert(process_response['document_id'].present?, "Document ID generated")
    assert(process_response['chunks'].any?, "Chunks created")
    assert(process_response['ready_for_embedding'], "Ready for embedding")
    
    puts "✅ Document processed:"
    puts "   Document ID: #{process_response['document_id']}"
    puts "   Chunks created: #{process_response['total_chunks']}"
    puts "   Total tokens: #{process_response['estimated_tokens']}"
    
    # Step 3: Validate chunk structure
    puts "\n3. Validating chunk structure..."
    first_chunk = process_response['chunks'].first
    
    chunk_validations = {
      "Has chunk_id" => first_chunk['chunk_id'].present?,
      "Has text content" => first_chunk['text'].present?,
      "Has metadata" => first_chunk['metadata'].present?,
      "Metadata has file_id" => first_chunk['metadata']['file_id'] == test_file_id,
      "Token count reasonable" => first_chunk['metadata']['token_count'] <= expected_chunk_size
    }
    
    chunk_validations.each do |check, passed|
      status = passed ? "✅" : "❌"
      puts "   #{status} #{check}"
    end
    
    # Step 4: Test change detection
    puts "\n4. Testing change detection..."
    change_result = rag_utils.check_document_changes({
      current_hash: doc_response['checksum'],
      previous_hash: 'different_hash_12345',
      check_type: 'hash'
    })
    
    assert(change_result['has_changed'], "Change detected correctly")
    puts "✅ Change detection working"
    
    # Return test results
    {
      success: true,
      document_id: process_response['document_id'],
      chunks: process_response['chunks'],
      metrics: {
        processing_time: Time.now - start_time,
        chunks_created: process_response['total_chunks'],
        tokens_estimated: process_response['estimated_tokens']
      }
    }
    
  rescue => e
    puts "❌ Test failed: #{e.message}"
    puts e.backtrace.first(5)
    { success: false, error: e.message }
  end
end

def assert(condition, message)
  raise "Assertion failed: #{message}" unless condition
end
