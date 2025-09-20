# test_performance.rb
# Purpose: Test system performance under load
# Requirements tested: Processing speed, cost optimization, rate limits

def test_performance_metrics
  puts "="*50
  puts "Testing Performance & Scale"
  puts "="*50
  
  metrics = {
    document_processing: [],
    embedding_generation: [],
    vector_search: [],
    response_generation: []
  }
  
  # Test document processing throughput
  puts "\n1. Testing document processing throughput..."
  10.times do |i|
    start = Time.now
    result = rag_utils.smart_chunk_text({
      text: "Sample text " * 1000, # ~3000 words
      chunk_size: 1000,
      chunk_overlap: 100
    })
    metrics[:document_processing] << Time.now - start
    print "."
  end
  
  avg_doc_time = metrics[:document_processing].sum / metrics[:document_processing].length
  puts "\n✅ Avg document processing: #{(avg_doc_time * 1000).round}ms"
  
  # Test embedding generation rate
  puts "\n2. Testing embedding generation rate..."
  batch_sizes = [1, 5, 10, 25]
  batch_sizes.each do |size|
    texts = size.times.map { |i| 
      { id: "test_#{i}", content: "Test content #{i}" * 10 }
    }
    
    start = Time.now
    result = vertex_connector.generate_embeddings({
      batch_id: "perf_test_#{size}",
      texts: texts,
      model: "publishers/google/models/text-embedding-004"
    })
    time_taken = Time.now - start
    
    puts "   Batch size #{size}: #{time_taken.round(2)}s (#{(time_taken/size*1000).round}ms per item)"
    metrics[:embedding_generation] << { size: size, time: time_taken }
  end
  
  # Test vector search latency
  puts "\n3. Testing vector search latency..."
  test_vector = Array.new(768) { rand }
  
  5.times do
    start = Time.now
    result = vertex_connector.find_neighbors({
      query_vector: test_vector,
      index_endpoint: {
        host: ENV['INDEX_HOST'],
        endpoint_id: ENV['ENDPOINT_ID'],
        deployed_index_id: ENV['INDEX_ID']
      },
      search_params: { neighbor_count: 10 }
    })
    metrics[:vector_search] << Time.now - start
  end
  
  avg_search_time = metrics[:vector_search].sum / metrics[:vector_search].length
  puts "✅ Avg vector search: #{(avg_search_time * 1000).round}ms"
  
  # Calculate cost estimates
  puts "\n💰 Cost Estimates (per day):"
  daily_emails = 750
  filtered_emails = 100
  api_calls = {
    classifications: filtered_emails,
    embeddings: filtered_emails * 5, # Avg 5 chunks per email
    searches: filtered_emails,
    generations: 50 # Actual responses
  }
  
  costs = {
    "Gemini Flash (classification)" => api_calls[:classifications] * 0.00001,
    "Embeddings" => api_calls[:embeddings] * 0.00001,
    "Vector Search" => api_calls[:searches] * 0.00002,
    "Gemini Pro (generation)" => api_calls[:generations] * 0.00125
  }
  
  total_cost = costs.values.sum
  costs.each { |service, cost| puts "   #{service}: $#{cost.round(4)}" }
  puts "   TOTAL: $#{total_cost.round(2)}/day"
  
  # Performance validations
  performance_checks = {
    "Document processing < 100ms" => avg_doc_time < 0.1,
    "Vector search < 500ms" => avg_search_time < 0.5,
    "Batch embeddings efficient" => metrics[:embedding_generation].last[:time] / metrics[:embedding_generation].last[:size] < 0.2,
    "Daily cost < $2" => total_cost < 2
  }
  
  puts "\n📊 Performance Summary:"
  performance_checks.each do |check, passed|
    status = passed ? "✅" : "❌"
    puts "   #{status} #{check}"
  end
  
  {
    success: performance_checks.values.all?,
    metrics: {
      avg_doc_processing_ms: (avg_doc_time * 1000).round,
      avg_search_ms: (avg_search_time * 1000).round,
      daily_cost: total_cost.round(2)
    }
  }
end
