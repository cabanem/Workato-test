# scripts/validate_contract.rb
module ContractValidator
  # v2.0 Contract Definitions with backward compatibility
  CONTRACTS = {
    # Enhanced v2.0 contracts
    'cleaned_text' => {
      required: ['text', 'metadata'],
      metadata_required: ['original_length', 'cleaned_length', 'processing_applied', 'source_type'],
      # Optional document_metadata for drive_file source
      optional_fields: ['extracted_sections', 'document_metadata'],
      document_metadata_fields: ['file_id', 'file_name', 'mime_type', 'file_path', 'modified_time', 'file_hash']
    },
    
    'embedding_request' => {
      required: ['batch_id', 'texts'],
      texts_structure: ['id', 'content', 'metadata'],
      # Enhanced metadata for document tracking
      metadata_optional: ['chunk_index', 'document_id', 'file_id', 'file_name', 'file_path', 'document_type', 'last_updated'],
      optional_fields: ['task_type', 'title', 'model', 'batch_metadata']
    },
    
    # New document contracts (v2.0)
    'document_fetch_request' => {
      required: ['file_id'],
      optional_fields: ['export_format', 'include_metadata', 'version']
    },
    
    'document_fetch_response' => {
      required: ['file_id', 'content', 'content_type'],
      optional_fields: ['metadata', 'extracted_text'],
      metadata_fields: ['name', 'mime_type', 'size', 'created_time', 'modified_time', 'version', 'parents', 'web_view_link']
    },
    
    'document_chunking_request' => {
      required: ['document'],
      document_required: ['file_id', 'content', 'file_name'],
      optional_fields: ['chunking_strategy', 'metadata_to_preserve']
    },
    
    'document_chunks_response' => {
      required: ['document_id', 'file_id', 'chunks', 'stats'],
      chunk_structure: ['chunk_id', 'chunk_index', 'text', 'token_count', 'metadata'],
      stats_structure: ['total_chunks', 'total_tokens', 'average_chunk_size', 'processing_time_ms']
    },
    
    'vector_search_request' => {
      required: ['query_vector', 'index_endpoint'],
      index_endpoint_required: ['host', 'endpoint_id', 'deployed_index_id'],
      optional_fields: ['search_params'],
      # Enhanced with document filtering (v2.0)
      search_params_fields: ['neighbor_count', 'return_full_datapoint', 'filters', 'crowding']
    },
    
    'vector_search_response' => {
      required: ['neighbors'],
      neighbor_structure: ['id', 'distance'],
      # Enhanced with document info (v2.0)
      optional_neighbor_fields: ['document_info', 'datapoint'],
      document_info_fields: ['file_id', 'file_name', 'chunk_index', 'section']
    },
    
    'index_update_request' => {
      required: ['index_id', 'operation'],
      operations: ['upsert', 'delete', 'update'],
      upsert_required: ['datapoints'],
      delete_required: ['datapoint_ids'],
      datapoint_structure: ['datapoint_id', 'feature_vector']
    },
    
    'folder_monitor_request' => {
      required: ['folder_id'],
      optional_fields: ['options'],
      options_fields: ['recursive', 'file_types', 'exclude_patterns', 'modified_after', 'page_size']
    },
    
    'folder_monitor_response' => {
      required: ['folder_id', 'files'],
      file_structure: ['file_id', 'name', 'mime_type', 'size', 'modified_time', 'md5_checksum', 'status'],
      optional_fields: ['next_page_token', 'total_files']
    },
    
    'document_processing_job' => {
      required: ['job_id', 'job_type', 'status', 'source', 'pipeline'],
      job_types: ['full_sync', 'incremental', 'single_file'],
      status_types: ['pending', 'processing', 'completed', 'failed'],
      pipeline_stages: ['fetch', 'chunk', 'embed', 'index']
    }
  }
  
  def self.validate(data, contract_type, version = '2.0')
    contract = CONTRACTS[contract_type]
    return { valid: false, errors: ["Unknown contract: #{contract_type}"] } unless contract
    
    errors = []
    warnings = []
    
    # Check required fields
    contract[:required].each do |field|
      errors << "Missing required field: #{field}" unless data[field]
    end
    
    # Check metadata structure for cleaned_text
    if contract_type == 'cleaned_text' && data['metadata']
      contract[:metadata_required].each do |field|
        errors << "Missing metadata.#{field}" unless data['metadata'][field]
      end
      
      # Check for document_metadata if source_type is drive_file (v2.0)
      if data['metadata']['source_type'] == 'drive_file'
        if data['document_metadata']
          contract[:document_metadata_fields].each do |field|
            warnings << "Missing document_metadata.#{field}" unless data['document_metadata'][field]
          end
        else
          warnings << "document_metadata recommended for drive_file source"
        end
      end
    end
    
    # Check embedding request texts structure
    if contract_type == 'embedding_request' && data['texts']
      data['texts'].each_with_index do |text, idx|
        contract[:texts_structure].each do |field|
          errors << "Missing texts[#{idx}].#{field}" unless text[field]
        end
        
        # Check for enhanced metadata fields (v2.0)
        if text['metadata'] && text['metadata']['document_id']
          %w[file_id file_name].each do |field|
            warnings << "texts[#{idx}].metadata.#{field} recommended for document tracking" unless text['metadata'][field]
          end
        end
      end
    end
    
    # Check document contracts (v2.0)
    if contract_type == 'document_chunking_request' && data['document']
      contract[:document_required].each do |field|
        errors << "Missing document.#{field}" unless data['document'][field]
      end
    end
    
    if contract_type == 'vector_search_request' && data['index_endpoint']
      contract[:index_endpoint_required].each do |field|
        errors << "Missing index_endpoint.#{field}" unless data['index_endpoint'][field]
      end
    end
    
    if contract_type == 'document_chunks_response' && data['chunks']
      data['chunks'].each_with_index do |chunk, idx|
        contract[:chunk_structure].each do |field|
          errors << "Missing chunks[#{idx}].#{field}" unless chunk[field]
        end
      end
    end
    
    result = {
      valid: errors.empty?,
      errors: errors,
      warnings: warnings,
      contract_version: version
    }
    
    if result[:valid]
      if warnings.empty?
        "✓ Valid (v#{version})"
      else
        "✓ Valid with warnings: #{warnings.join(', ')}"
      end
    else
      "✗ Errors: #{errors.join(', ')}"
    end
  end
  
  def self.validate_compatibility(data, contract_type)
    # Check backward compatibility with v1.0
    v1_result = validate_v1(data, contract_type)
    v2_result = validate(data, contract_type, '2.0')
    
    {
      v1_compatible: v1_result[:valid],
      v2_compatible: v2_result[:valid],
      migration_ready: v1_result[:valid] && v2_result[:valid]
    }
  end
  
  private
  
  def self.validate_v1(data, contract_type)
    # Simplified v1.0 validation for backward compatibility testing
    case contract_type
    when 'cleaned_text'
      required = ['text', 'metadata']
      errors = required.select { |f| !data[f] }.map { |f| "Missing #{f}" }
    when 'embedding_request'
      required = ['batch_id', 'texts']
      errors = required.select { |f| !data[f] }.map { |f| "Missing #{f}" }
    else
      errors = ["Not a v1.0 contract type"]
    end
    
    { valid: errors.empty?, errors: errors }
  end
end

# For Workato console testing
if defined?(actions)
  puts "=" * 80
  puts "CONTRACT VALIDATOR v2.0"
  puts "=" * 80
  puts "Connector actions: #{actions.keys.join(', ')}"
  puts
  puts "Available contracts:"
  ContractValidator::CONTRACTS.keys.each do |contract|
    puts "  - #{contract}"
  end
  puts
  puts "Usage:"
  puts "  ContractValidator.validate(data, 'cleaned_text')"
  puts "  ContractValidator.validate(data, 'document_fetch_response', '2.0')"
  puts "  ContractValidator.validate_compatibility(data, 'cleaned_text')"
  puts "=" * 80
end
