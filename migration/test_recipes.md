# Test Recipes for Contract Validation

## Test Recipe 1: Cleaned Text Contract
**Recipe Name:** `TEST_Contract_CleanedText_v2`

```yaml
Recipe Configuration:
  Trigger: Manual with test data
  Description: Validates cleaned_text contract between RAG preparation and Vertex consumption

Steps:
  1. Trigger - Manual:
      test_email: |
        Hello Support,
        
        I need help with my account.
        
        Thanks,
        John Doe
        --
        Sent from my iPhone
      test_document: "This is a sample document with normal text."
      test_mode: "both" # email, document, or both

  2. RAG_Utils - Prepare for AI (Email):
      condition: trigger.test_mode == "email" or trigger.test_mode == "both"
      input:
        text: trigger.test_email
        source_type: "email"
        task_type: "classification"
        options:
          remove_pii: false
          max_length: 32000

  3. Contract Validator - Email:
      condition: Step 2 executed
      ruby_code: |
        # Validate cleaned_text contract
        data = input['step2_output']
        errors = []
        
        # Required fields
        errors << "Missing 'text' field" unless data['text'].present?
        errors << "Missing 'metadata' field" unless data['metadata'].present?
        
        # Metadata required fields
        if data['metadata']
          meta = data['metadata']
          errors << "Missing 'original_length'" unless meta['original_length'].is_a?(Integer)
          errors << "Missing 'cleaned_length'" unless meta['cleaned_length'].is_a?(Integer)
          errors << "Missing 'processing_applied'" unless meta['processing_applied'].is_a?(Array)
          errors << "Missing 'source_type'" unless meta['source_type'].present?
        end
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          data_structure: data.keys,
          metadata_structure: data['metadata']&.keys
        }

  4. RAG_Utils - Prepare for AI (Document):
      condition: trigger.test_mode == "document" or trigger.test_mode == "both"
      input:
        text: trigger.test_document
        source_type: "document"
        task_type: "generation"

  5. Contract Validator - Document:
      condition: Step 4 executed
      ruby_code: |
        # Same validation as Step 3 but for document
        # [Same validation code]

  6. Vertex - AI Classify:
      condition: Step 2 or Step 4 succeeded
      input:
        text: (Step 2 output.text OR Step 4 output.text)
        categories: [
          {key: "support", description: "Customer support inquiry"},
          {key: "sales", description: "Sales related"},
          {key: "other", description: "Other inquiries"}
        ]
        model: "publishers/google/models/gemini-1.5-flash"

  7. Logger - Results:
      message: |
        Test Results:
        - Email Contract Valid: {Step 3.contract_valid}
        - Email Errors: {Step 3.errors}
        - Document Contract Valid: {Step 5.contract_valid}
        - Document Errors: {Step 5.errors}
        - Vertex Response: {Step 6}
```

## Test Recipe 2: Embedding Contract
**Recipe Name:** `TEST_Contract_Embeddings_v2`

```yaml
Recipe Configuration:
  Trigger: Manual
  Description: Validates embedding request/response contract

Steps:
  1. Trigger - Manual:
      test_texts: 
        - "First chunk of document about RAG systems"
        - "Second chunk discussing embedding generation"
        - "Third chunk about vector databases"

  2. RAG_Utils - Prepare Embedding Batch:
      input:
        texts:
          - id: "doc_001_chunk_0"
            content: trigger.test_texts[0]
            title: "RAG Systems Overview"
            metadata:
              document_id: "doc_001"
              chunk_index: 0
              source: "test_document.pdf"
          - id: "doc_001_chunk_1"
            content: trigger.test_texts[1]
            metadata:
              document_id: "doc_001"
              chunk_index: 1
          - id: "doc_001_chunk_2"
            content: trigger.test_texts[2]
            metadata:
              document_id: "doc_001"
              chunk_index: 2
        task_type: "RETRIEVAL_DOCUMENT"
        batch_size: 25

  3. Contract Validator - Request:
      ruby_code: |
        data = input['step2_output']
        errors = []
        
        # Validate embedding_request contract
        errors << "Missing 'batch_id'" unless data['batch_id'].present?
        errors << "Missing 'texts'" unless data['texts'].is_a?(Array)
        
        # Validate each text object
        data['texts']&.each_with_index do |text, idx|
          errors << "Text #{idx} missing 'id'" unless text['id'].present?
          errors << "Text #{idx} missing 'content'" unless text['content'].present?
          errors << "Text #{idx} missing 'metadata'" unless text['metadata'].is_a?(Hash)
        end
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          batch_id: data['batch_id'],
          text_count: data['texts']&.length
        }

  4. Vertex - Generate Embeddings:
      input:
        batch_id: Step 2.batch_id
        texts: Step 2.texts
        task_type: Step 2.task_type
        model: "publishers/google/models/text-embedding-004"

  5. Contract Validator - Response:
      ruby_code: |
        data = input['step4_output']
        errors = []
        
        # Validate embedding_response contract
        errors << "Missing 'batch_id'" unless data['batch_id'].present?
        errors << "Batch ID mismatch" unless data['batch_id'] == input['step2_output']['batch_id']
        errors << "Missing 'embeddings'" unless data['embeddings'].is_a?(Array)
        errors << "Missing 'model_used'" unless data['model_used'].present?
        
        # Validate each embedding
        data['embeddings']&.each_with_index do |emb, idx|
          errors << "Embedding #{idx} missing 'id'" unless emb['id'].present?
          errors << "Embedding #{idx} missing 'vector'" unless emb['vector'].is_a?(Array)
          errors << "Embedding #{idx} missing 'dimensions'" unless emb['dimensions'].is_a?(Integer)
          errors << "Embedding #{idx} dimension mismatch" unless emb['vector']&.length == emb['dimensions']
        end
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          embedding_count: data['embeddings']&.length,
          dimensions: data['embeddings']&.first&.dig('dimensions')
        }

  6. Logger - Results:
      message: |
        Embedding Contract Test:
        - Request Valid: {Step 3.contract_valid}
        - Response Valid: {Step 5.contract_valid}
        - Batch ID Match: {Step 4.batch_id == Step 2.batch_id}
        - Embeddings Generated: {Step 5.embedding_count}
        - Vector Dimensions: {Step 5.dimensions}
```

## Test Recipe 3: Classification Contract
**Recipe Name:** `TEST_Contract_Classification_v2`

```yaml
Recipe Configuration:
  Trigger: Manual
  Description: Validates classification request/response contract

Steps:
  1. Trigger - Manual:
      test_text: "I need to return a product I bought last week"
      test_mode: "ai" # "rules", "ai", or "hybrid"

  2. RAG_Utils - Prepare for AI:
      input:
        text: trigger.test_text
        source_type: "general"
        task_type: "classification"

  3. Build Classification Request:
      ruby_code: |
        {
          text: input['step2_output']['text'],
          classification_mode: input['trigger']['test_mode'],
          categories: [
            {
              key: "returns",
              description: "Product returns and refunds",
              examples: ["return product", "get refund", "exchange item"]
            },
            {
              key: "shipping",
              description: "Shipping and delivery",
              examples: ["track package", "delivery date", "shipping cost"]
            },
            {
              key: "support",
              description: "General customer support",
              examples: []
            }
          ],
          options: {
            return_confidence: true,
            return_alternatives: 2,
            temperature: 0.1,
            max_tokens: 100
          }
        }

  4. Contract Validator - Request:
      ruby_code: |
        data = input['step3_output']
        errors = []
        
        # Validate classification_request contract
        errors << "Missing 'text'" unless data['text'].present?
        errors << "Missing 'classification_mode'" unless data['classification_mode'].present?
        errors << "Invalid mode" unless ['rules', 'ai', 'hybrid'].include?(data['classification_mode'])
        errors << "Missing 'categories'" unless data['categories'].is_a?(Array)
        
        data['categories']&.each_with_index do |cat, idx|
          errors << "Category #{idx} missing 'key'" unless cat['key'].present?
        end
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          category_count: data['categories']&.length
        }

  5. Vertex - AI Classify:
      condition: Step 3.classification_mode == "ai"
      input:
        text: Step 3.text
        categories: Step 3.categories
        model: "publishers/google/models/gemini-1.5-flash"
        options: Step 3.options

  6. Contract Validator - Response:
      condition: Step 5 executed
      ruby_code: |
        data = input['step5_output']
        errors = []
        
        # Validate classification_response contract
        errors << "Missing 'selected_category'" unless data['selected_category'].present?
        errors << "Missing 'confidence'" unless data['confidence'].is_a?(Numeric)
        errors << "Invalid confidence range" unless (0..1).include?(data['confidence'].to_f)
        
        if input['step3_output']['options']['return_alternatives'] > 0
          errors << "Missing 'alternatives'" unless data['alternatives'].is_a?(Array)
        end
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          selected: data['selected_category'],
          confidence: data['confidence']
        }

  7. Logger - Results:
      message: |
        Classification Contract Test:
        - Request Valid: {Step 4.contract_valid}
        - Response Valid: {Step 6.contract_valid}
        - Selected Category: {Step 6.selected}
        - Confidence: {Step 6.confidence}
```

## Test Recipe 4: Prompt Contract
**Recipe Name:** `TEST_Contract_Prompt_v2`

```yaml
Recipe Configuration:
  Trigger: Manual
  Description: Validates prompt request/generation response contract

Steps:
  1. Trigger - Manual:
      user_query: "What is the return policy?"
      context_docs:
        - content: "Returns accepted within 30 days with receipt"
          relevance_score: 0.92
        - content: "Items must be unused and in original packaging"
          relevance_score: 0.88

  2. RAG_Utils - Build Prompt:
      input:
        query: trigger.user_query
        context_documents: trigger.context_docs
        prompt_template: "standard"
        advanced_settings:
          max_context_length: 3000
          include_metadata: false

  3. Format Prompt Request:
      ruby_code: |
        {
          prompt_type: "rag_response",
          formatted_prompt: input['step2_output']['formatted_prompt'],
          system_instruction: {
            role: "model",
            parts: [{
              text: "You are a helpful customer service assistant. Answer based only on the provided context."
            }]
          },
          context_documents: input['trigger']['context_docs'],
          generation_config: {
            temperature: 0.3,
            maxOutputTokens: 500,
            responseMimeType: "application/json"
          },
          response_schema: {
            type: "object",
            properties: {
              answer: { type: "string" },
              confidence: { type: "number" },
              sources_used: { type: "array", items: { type: "integer" } }
            },
            required: ["answer"]
          }
        }

  4. Contract Validator - Prompt Request:
      ruby_code: |
        data = input['step3_output']
        errors = []
        
        # Validate prompt_request contract
        errors << "Missing 'prompt_type'" unless data['prompt_type'].present?
        errors << "Missing 'formatted_prompt'" unless data['formatted_prompt'].present?
        
        if data['response_schema']
          errors << "Invalid response_schema" unless data['response_schema']['type'].present?
        end
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          has_schema: data['response_schema'].present?,
          prompt_length: data['formatted_prompt']&.length
        }

  5. Vertex - Send Messages:
      input:
        # Use prepared prompt
        model: "publishers/google/models/gemini-1.5-pro"
        message_type: "single_message"
        messages:
          message: Step 3.formatted_prompt
        systemInstruction: Step 3.system_instruction
        generationConfig: Step 3.generation_config

  6. Contract Validator - Generation Response:
      ruby_code: |
        data = input['step5_output']
        errors = []
        
        # Extract actual response from Vertex format
        response_text = data.dig('candidates', 0, 'content', 'parts', 0, 'text')
        finish_reason = data.dig('candidates', 0, 'finishReason')
        
        # Validate generation_response contract
        errors << "Missing content" unless response_text.present?
        errors << "Missing finish_reason" unless finish_reason.present?
        
        # Try to parse JSON if expected
        if input['step3_output']['generation_config']['responseMimeType'] == 'application/json'
          begin
            parsed = JSON.parse(response_text)
            errors << "Missing required 'answer' field" unless parsed['answer'].present?
          rescue
            errors << "Response is not valid JSON"
          end
        end
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          finish_reason: finish_reason,
          has_usage: data['usageMetadata'].present?
        }

  7. Logger - Results:
      message: |
        Prompt Contract Test:
        - Request Valid: {Step 4.contract_valid}
        - Response Valid: {Step 6.contract_valid}
        - Has Schema: {Step 4.has_schema}
        - Finish Reason: {Step 6.finish_reason}
```

## Test Recipe 5: Vector Search Contract
**Recipe Name:** `TEST_Contract_VectorSearch_v2`

```yaml
Recipe Configuration:
  Trigger: Manual
  Description: Validates vector search request/response contract

Steps:
  1. Trigger - Manual:
      query_text: "How do I return a product?"
      index_endpoint_host: "1234.us-central1.vdb.vertexai.goog"
      index_endpoint_id: "test_endpoint_123"
      deployed_index_id: "deployed_index_456"

  2. Generate Query Embedding:
      # First generate embedding for query
      Vertex - Generate Embeddings:
        input:
          batch_id: "query_batch_001"
          texts:
            - id: "query_001"
              content: trigger.query_text
          task_type: "RETRIEVAL_QUERY"
          model: "publishers/google/models/text-embedding-004"

  3. Build Vector Search Request:
      ruby_code: |
        {
          query_vector: input['step2_output']['embeddings'][0]['vector'],
          index_endpoint: {
            host: input['trigger']['index_endpoint_host'],
            endpoint_id: input['trigger']['index_endpoint_id'],
            deployed_index_id: input['trigger']['deployed_index_id']
          },
          search_params: {
            neighbor_count: 10,
            return_full_datapoint: false,
            filters: {
              restricts: [
                {
                  namespace: "category",
                  allowList: ["returns", "policy"],
                  denyList: []
                }
              ],
              numericRestricts: [
                {
                  namespace: "relevance_score",
                  op: "GREATER",
                  value: 0.7
                }
              ]
            }
          }
        }

  4. Contract Validator - Search Request:
      ruby_code: |
        data = input['step3_output']
        errors = []
        
        # Validate vector_search_request contract
        errors << "Missing 'query_vector'" unless data['query_vector'].is_a?(Array)
        errors << "Missing 'index_endpoint'" unless data['index_endpoint'].is_a?(Hash)
        
        endpoint = data['index_endpoint']
        if endpoint
          errors << "Missing endpoint host" unless endpoint['host'].present?
          errors << "Missing endpoint_id" unless endpoint['endpoint_id'].present?
          errors << "Missing deployed_index_id" unless endpoint['deployed_index_id'].present?
        end
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          vector_dimensions: data['query_vector']&.length,
          has_filters: data.dig('search_params', 'filters').present?
        }

  5. Vertex - Find Neighbors:
      input:
        index_endpoint_host: Step 3.index_endpoint.host
        index_endpoint_id: Step 3.index_endpoint.endpoint_id
        deployedIndexId: Step 3.index_endpoint.deployed_index_id
        returnFullDatapoint: Step 3.search_params.return_full_datapoint
        queries:
          - datapoint:
              featureVector: Step 3.query_vector
              restricts: Step 3.search_params.filters.restricts
              numericRestricts: Step 3.search_params.filters.numericRestricts
            neighborCount: Step 3.search_params.neighbor_count

  6. Contract Validator - Search Response:
      ruby_code: |
        data = input['step5_output']
        errors = []
        
        # Validate vector_search_response contract
        neighbors = data.dig('nearestNeighbors', 0, 'neighbors') || []
        
        errors << "Missing neighbors array" unless neighbors.is_a?(Array)
        
        neighbors.each_with_index do |neighbor, idx|
          errors << "Neighbor #{idx} missing 'distance'" unless neighbor['distance'].is_a?(Numeric)
          errors << "Neighbor #{idx} missing 'datapoint'" unless neighbor['datapoint'].is_a?(Hash)
        end
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          neighbors_found: neighbors.length,
          top_distance: neighbors.first&.dig('distance')
        }

  7. Logger - Results:
      message: |
        Vector Search Contract Test:
        - Request Valid: {Step 4.contract_valid}
        - Response Valid: {Step 6.contract_valid}
        - Vector Dimensions: {Step 4.vector_dimensions}
        - Neighbors Found: {Step 6.neighbors_found}
        - Top Distance: {Step 6.top_distance}
```

## Test Recipe 6: Validation Contract
**Recipe Name:** `TEST_Contract_Validation_v2`

```yaml
Recipe Configuration:
  Trigger: Manual
  Description: Validates the validation request/result contract

Steps:
  1. Trigger - Manual:
      test_response: "You can return products within 30 days."
      original_query: "What is the return window?"
      context_used: 
        - "Returns accepted within 30 days"
        - "Must have original receipt"

  2. RAG_Utils - Build Validation Request:
      ruby_code: |
        {
          response: input['trigger']['test_response'],
          original_query: input['trigger']['original_query'],
          context_provided: input['trigger']['context_used'],
          expected_format: "text",
          validation_rules: [
            {
              rule_type: "contains",
              rule_value: "30 days"
            },
            {
              rule_type: "length",
              rule_value: { min: 10, max: 500 }
            }
          ]
        }

  3. Contract Validator - Validation Request:
      ruby_code: |
        data = input['step2_output']
        errors = []
        
        # Validate validation_request contract
        errors << "Missing 'response'" unless data['response'].present?
        errors << "Missing 'original_query'" unless data['original_query'].present?
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          has_rules: data['validation_rules']&.any?
        }

  4. RAG_Utils - Validate AI Response:
      input:
        response_text: Step 2.response
        original_query: Step 2.original_query
        context_provided: Step 2.context_provided
        validation_rules: Step 2.validation_rules
        min_confidence: 0.7

  5. Contract Validator - Validation Result:
      ruby_code: |
        data = input['step4_output']
        errors = []
        
        # Validate validation_result contract
        errors << "Missing 'is_valid'" unless [true, false].include?(data['is_valid'])
        errors << "Missing 'confidence_score'" unless data['confidence_score'].is_a?(Numeric)
        errors << "Invalid confidence range" unless (0..1).include?(data['confidence_score'].to_f)
        
        {
          contract_valid: errors.empty?,
          errors: errors,
          validation_passed: data['is_valid'],
          confidence: data['confidence_score']
        }

  6. Logger - Results:
      message: |
        Validation Contract Test:
        - Request Valid: {Step 3.contract_valid}
        - Result Valid: {Step 5.contract_valid}
        - Validation Passed: {Step 5.validation_passed}
        - Confidence Score: {Step 5.confidence}
```

## Master Test Recipe: End-to-End Contract Flow
**Recipe Name:** `TEST_Contract_E2E_Flow_v2`

```yaml
Recipe Configuration:
  Trigger: Manual
  Description: Tests complete flow through all contracts

Steps:
  1. Trigger - Manual:
      email_text: |
        Subject: Return Request
        
        Hi,
        I bought a laptop last week but it's not working properly.
        Can I return it for a refund?
        
        Thanks,
        Customer

  2-15: [Combination of all above contract tests in sequence]
  
  16. Summary Report:
      ruby_code: |
        {
          all_contracts_valid: [
            step3_valid, step5_valid, step7_valid, 
            step9_valid, step11_valid, step13_valid
          ].all?,
          total_errors: [errors from all steps].flatten.count,
          execution_time_ms: (Time.now - start_time) * 1000,
          tokens_used: [all usage metrics].sum
        }
```
