# test_embeddings.rb
# Purpose: Test embedding generation for documents
# Requirements tested: Batch embeddings, metadata preservation, vector dimensions

def test_embedding_generation
  puts "="*50
  puts "Testing Embedding Generation"
  puts "="*50
  
  # Prepare test data
  test_chunks = [
    {
      id: "test_chunk_1",
      content: "This is a test document about return policies.",
      metadata: {
        file_id: "drive_123",
        file_name: "return_policy.pdf",
        chunk_index: 0
      }
    },
    {
      id: "test_chunk_2", 
      content: "Customers can return items within 30 days.",
      metadata: {
        file_id: "drive_123",
        file_name: "return_policy.pdf",
        chunk_index: 1
      }
    }
  ]
  
  begin
    # Step 1: Prepare embedding batch
    puts "\n1. Preparing embedding batch..."
    batch_response = rag_utils.prepare_embedding_batch({
      texts: test_chunks,
      task_type: "RETRIEVAL_DOCUMENT",
      batch_size: 25,
      batch_prefix: "test_embed"
    })
    
    puts "✅ Batch prepared: #{batch_response['batch_id']}"
    
    # Step 2: Generate embeddings
    puts "\n2. Generating embeddings..."
    embedding_response = vertex_connector.generate_embeddings({
      batch_id: batch_response['batch_id'],
      texts: batch_response['batches'].first['requests'],
      model: "publishers/google/models/text-embedding-004"
    })
    
    puts "✅ Embeddings generated:"
    puts "   Count: #{embedding_response['embeddings_count']}"
    puts "   Model: #{embedding_response['model_used']}"
    puts "   Tokens used: #{embedding_response['total_tokens']}"
    
    # Step 3: Validate embeddings
    puts "\n3. Validating embeddings..."
    first_embedding = embedding_response['embeddings'].first
    
    embedding_validations = {
      "Has vector" => first_embedding['vector'].is_a?(Array),
      "Vector dimensions = 768" => first_embedding['dimensions'] == 768,
      "Metadata preserved" => first_embedding['metadata']['file_id'] == "drive_123",
      "All chunks embedded" => embedding_response['embeddings_count'] == test_chunks.length
    }
    
    embedding_validations.each do |check, passed|
      status = passed ? "✅" : "❌"
      puts "   #{status} #{check}"
    end
    
    # Step 4: Test single embedding (for queries)
    puts "\n4. Testing single embedding for query..."
    query_response = vertex_connector.generate_embedding_single({
      text: "What is the return policy?",
      model: "publishers/google/models/text-embedding-004",
      task_type: "RETRIEVAL_QUERY"
    })
    
    assert(query_response['vector'].length == 768, "Query embedding has correct dimensions")
    puts "✅ Query embedding generated"
    
    {
      success: embedding_validations.values.all?,
      embeddings: embedding_response['embeddings'],
      query_vector: query_response['vector']
    }
    
  rescue => e
    puts "❌ Test failed: #{e.message}"
    { success: false, error: e.message }
  end
end
