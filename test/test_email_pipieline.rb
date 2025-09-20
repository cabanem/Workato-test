# test_email_pipeline.rb
# Purpose: Test complete email response generation with RAG
# Requirements tested: Email processing, RAG retrieval, response generation

def test_email_response_pipeline
  puts "="*50
  puts "Testing Complete Email Response Pipeline"
  puts "="*50
  
  # Sample email
  test_email = {
    from_email: "customer@example.com",
    subject: "Return policy question",
    body: "Hi, I bought a laptop last week and it's not working properly. Can I return it? What's your return policy for electronics?"
  }
  
  start_time = Time.now
  
  begin
    # Step 1: Clean and prepare email
    puts "\n1. Processing email..."
    cleaned_email = rag_utils.clean_email_text({
      email_body: test_email[:body],
      remove_signatures: true,
      normalize_whitespace: true
    })
    
    puts "✅ Email cleaned: #{cleaned_email['cleaned_length']} chars"
    
    # Step 2: Classify email
    puts "\n2. Classifying email..."
    classification = vertex_connector.ai_classify({
      text: cleaned_email['cleaned_text'],
      categories: [
        { key: "return_request", description: "Customer wants to return product" },
        { key: "policy_question", description: "Question about policies" },
        { key: "complaint", description: "Product complaint" },
        { key: "other", description: "Other inquiries" }
      ],
      model: "publishers/google/models/gemini-1.5-flash"
    })
    
    puts "✅ Classification: #{classification['selected_category']} (#{(classification['confidence']*100).round}% confidence)"
    
    # Step 3: Generate query embedding
    puts "\n3. Generating query embedding..."
    query_embedding = vertex_connector.generate_embedding_single({
      text: cleaned_email['cleaned_text'],
      task_type: "RETRIEVAL_QUERY"
    })
    
    # Step 4: Search for relevant documents
    puts "\n4. Searching knowledge base..."
    search_results = vertex_connector.find_neighbors({
      query_vector: query_embedding['vector'],
      index_endpoint: {
        host: ENV['INDEX_HOST'],
        endpoint_id: ENV['ENDPOINT_ID'],
        deployed_index_id: ENV['INDEX_ID']
      },
      search_params: {
        neighbor_count: 5,
        search_context: {
          search_type: "email_response"
        }
      }
    })
    
    puts "✅ Found #{search_results['matches_count']} relevant documents"
    
    # Step 5: Build RAG prompt
    puts "\n5. Building RAG prompt..."
    context_docs = search_results['top_matches'].map { |match|
      {
        content: "Retrieved content here", # Would be fetched from storage
        relevance_score: match['similarity_score'],
        source: match['datapoint_id']
      }
    }
    
    rag_prompt = rag_utils.build_rag_prompt({
      query: cleaned_email['cleaned_text'],
      context_documents: context_docs,
      prompt_template: "customer_service"
    })
    
    puts "✅ Prompt built: #{rag_prompt['token_count']} tokens"
    
    # Step 6: Generate response
    puts "\n6. Generating response..."
    response = vertex_connector.send_messages({
      model: "publishers/google/models/gemini-1.5-pro",
      formatted_prompt: rag_prompt['formatted_prompt'],
      generationConfig: {
        temperature: 0.7,
        maxOutputTokens: 500
      }
    })
    
    response_text = response.dig('candidates', 0, 'content', 'parts', 0, 'text')
    puts "✅ Response generated: #{response_text.split.length} words"
    
    # Step 7: Validate response
    puts "\n7. Validating response..."
    validation = rag_utils.validate_llm_response({
      response_text: response_text,
      original_query: cleaned_email['cleaned_text'],
      context_provided: context_docs.map { |d| d[:content] },
      min_confidence: 0.7
    })
    
    puts "✅ Validation: #{validation['confidence_score']} confidence"
    puts "   Valid: #{validation['is_valid']}"
    puts "   Human review needed: #{validation['requires_human_review']}"
    
    # Performance check
    total_time = Time.now - start_time
    performance_pass = total_time < 15 # Must complete in under 15 seconds
    
    puts "\n⏱️  Total pipeline time: #{total_time.round(2)}s"
    puts performance_pass ? "✅ Within 15s target" : "❌ Exceeded 15s target"
    
    # Display sample response
    puts "\n📧 Sample Response:"
    puts "-" * 40
    puts response_text.first(500)
    puts "-" * 40
    
    {
      success: validation['is_valid'] && performance_pass,
      metrics: {
        total_time: total_time,
        classification: classification['selected_category'],
        confidence: validation['confidence_score'],
        response_length: response_text.length
      }
    }
    
  rescue => e
    puts "❌ Test failed: #{e.message}"
    { success: false, error: e.message }
  end
end
