# test_batch_processing.rb
# Purpose: Test batch document processing capabilities
# Requirements tested: Batch fetch, parallel processing, error handling

def test_batch_document_processing
  puts "="*50
  puts "Testing Batch Document Processing"
  puts "="*50
  
  # Test configuration
  test_folder_id = ENV['TEST_FOLDER_ID'] || 'your_folder_id_here'
  max_documents = 5
  
  begin
    # Step 1: List files from folder
    puts "\n1. Listing files from Drive folder..."
    list_response = vertex_connector.list_drive_files({
      folder_id: test_folder_id,
      mime_types: ['application/pdf', 'application/vnd.google-apps.document'],
      max_results: max_documents
    })
    
    file_count = list_response['count']
    puts "✅ Found #{file_count} files"
    
    assert(file_count > 0, "Files found in folder")
    
    # Step 2: Batch fetch files
    file_ids = list_response['files'].map { |f| f['id'] }
    puts "\n2. Batch fetching #{file_ids.length} files..."
    
    batch_response = vertex_connector.batch_fetch_drive_files({
      file_ids: file_ids,
      skip_errors: true,
      export_format: 'text/plain'
    })
    
    puts "✅ Batch fetch complete:"
    puts "   Successful: #{batch_response['successful_files'].length}"
    puts "   Failed: #{batch_response['failed_files'].length}"
    puts "   Success rate: #{(batch_response['success_rate'] * 100).round(1)}%"
    
    # Step 3: Process documents in batch
    puts "\n3. Processing documents for RAG..."
    batch_process_response = rag_utils.prepare_document_batch({
      documents: batch_response['successful_files'].map { |f| 
        {
          content: f['text_content'],
          path: f['file_name'],
          type: f['mime_type']
        }
      },
      batch_size: 25
    })
    
    puts "✅ Batch processing complete:"
    puts "   Batches created: #{batch_process_response['batches'].length}"
    puts "   Total chunks: #{batch_process_response['total_chunks']}"
    
    # Step 4: Validate batch structure
    puts "\n4. Validating batch structure..."
    first_batch = batch_process_response['batches'].first
    
    batch_validations = {
      "Has batch_id" => first_batch['batch_id'].present?,
      "Has chunks" => first_batch['chunks'].any?,
      "Batch size <= 25" => first_batch['chunks'].length <= 25
    }
    
    batch_validations.each do |check, passed|
      status = passed ? "✅" : "❌"
      puts "   #{status} #{check}"
    end
    
    # Performance check
    processing_time = Time.now - start_time
    performance_pass = processing_time < 60 # Should process in under 60 seconds
    
    puts "\n⏱️  Performance: #{processing_time.round(2)}s"
    puts performance_pass ? "✅ Within 60s target" : "❌ Exceeded 60s target"
    
    {
      success: batch_validations.values.all? && performance_pass,
      metrics: {
        files_processed: batch_response['successful_files'].length,
        total_chunks: batch_process_response['total_chunks'],
        processing_time: processing_time
      }
    }
    
  rescue => e
    puts "❌ Test failed: #{e.message}"
    { success: false, error: e.message }
  end
end
