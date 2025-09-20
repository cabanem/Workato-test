# test_vector_search.rb
# Purpose: Test vector search with document filtering
# Requirements tested: Document-aware search, relevance scoring, filtering

def test_vector_search
  puts "="*50
  puts "Testing Vector Search with Document Filtering"
  puts "="*50
  
  # Configuration
  index_endpoint = {
    host: ENV['INDEX_HOST'] || "1234.us-central1.vdb.vertexai.goog",
    endpoint_id: ENV['ENDPOINT_ID'] || "endpoint_123",
    deployed_index_id: ENV['INDEX_ID'] || "index_456"
  }
  
  begin
    # Step 1: Generate query embedding
    puts "\n1. Generating query embedding..."
    query_text = "What is the return policy for electronics?"
    query_embedding = vertex_connector.generate_embedding_single({
      text: query_text,
      task_type: "RETRIEVAL_QUERY",
      model: "publishers/google/models/text-embedding-004"
    })
    
    puts "✅ Query embedding generated"
    
    # Step 2: Search without filters
    puts "\n2. Searching without filters..."
    search_response = vertex_connector.find_neighbors({
      query_vector: query_embedding['vector'],
      index_endpoint: index_endpoint,
      search_params: {
        neighbor_count: 10,
        return_full_datapoint: false
      }
    })
    
    puts "✅ Search complete:"
    puts "   Matches found: #{search_response['matches_count']}"
    puts "   Best match score: #{search_response['best_match_score']}"
    
    # Step 3: Search with document filters
    puts "\n3. Searching with document filters..."
    filtered_response = vertex_connector.find_neighbors({
      query_vector: query_embedding['vector'],
      index_endpoint: index_endpoint,
      search_params: {
        neighbor_count: 10,
        document_filters: {
          file_types: ["pdf"],
          modified_after: 30.days.ago.iso8601
        },
        search_context: {
          search_type: "email_response",
          include_chunk_neighbors: true
        }
      }
    })
    
    puts "✅ Filtered search complete:"
    puts "   Matches found: #{filtered_response['matches_count']}"
    puts "   Document groups: #{filtered_response['document_groups']&.length || 0}"
    
    # Step 4: Validate search results
    puts "\n4. Validating search results..."
    
    search_validations = {
      "Has matches" => filtered_response['matches_count'] > 0,
      "Has relevance scores" => filtered_response['top_matches'].all? { |m| 
        m['similarity_score'].between?(0, 1) 
      },
      "Results grouped by document" => filtered_response['document_groups'].present?,
      "Response time < 500ms" => filtered_response['search_time_ms'] < 500
    }
    
    search_validations.each do |check, passed|
      status = passed ? "✅" : "❌"
      puts "   #{status} #{check}"
    end
    
    # Display top results
    puts "\n📊 Top 3 Results:"
    filtered_response['top_matches'].first(3).each_with_index do |match, i|
      puts "   #{i+1}. Score: #{match['similarity_score'].round(3)} - ID: #{match['datapoint_id']}"
    end
    
    {
      success: search_validations.values.all?,
      query: query_text,
      matches: filtered_response['matches_count'],
      best_score: filtered_response['best_match_score']
    }
    
  rescue => e
    puts "❌ Test failed: #{e.message}"
    { success: false, error: e.message }
  end
end
