#!/usr/bin/env ruby
# test/test_new_components_contracts.rb
# Contract validation for all newly implemented components

require_relative 'contract_validation/validate_contract'
require_relative 'helpers/test_helper'

class NewComponentsContractTest
  include TestHelper::Assertions

  def self.run_all_tests
    puts "=== Contract Validation for New Components ==="
    puts "Testing all Drive actions and RAG document processing components"
    puts

    tester = new
    tester.setup

    tests = [
      :test_drive_helper_outputs,
      :test_fetch_drive_file_contracts,
      :test_list_drive_files_contracts,
      :test_batch_fetch_drive_files_contracts,
      :test_document_helper_outputs,
      :test_process_document_for_rag_contracts,
      :test_prepare_document_batch_contracts,
      :test_enhanced_smart_chunk_text_contracts
    ]

    passed = 0
    failed = 0

    tests.each do |test|
      begin
        print "#{test.to_s.gsub('_', ' ').capitalize}... "
        tester.send(test)
        puts "✓ PASS"
        passed += 1
      rescue => e
        puts "✗ FAIL: #{e.message}"
        puts "  #{e.backtrace.first}" if ENV['DEBUG']
        failed += 1
      end
    end

    puts
    puts "New Components Contract Results: #{passed} passed, #{failed} failed"
    puts

    failed == 0
  end

  def setup
    @vertex_connector = TestHelper.load_connector('vertex')
    @rag_connector = TestHelper.load_connector('rag_utils')
  end

  def test_drive_helper_outputs
    # Test extract_drive_file_id output contract
    extract_method = @vertex_connector[:methods][:extract_drive_file_id]
    file_id = extract_method.call("https://drive.google.com/file/d/1ABC123DEF456/view")

    assert file_id.is_a?(String)
    assert_equal "1ABC123DEF456", file_id

    # Test get_export_mime_type output contract
    export_method = @vertex_connector[:methods][:get_export_mime_type]
    mime_type = export_method.call('application/vnd.google-apps.document')

    assert mime_type.is_a?(String) || mime_type.nil?
    assert_equal 'text/plain', mime_type

    # Test build_drive_query output contract
    query_method = @vertex_connector[:methods][:build_drive_query]
    query = query_method.call({ folder_id: 'test123' })

    assert query.is_a?(String)
    assert_includes query, 'trashed = false'

    # Test handle_drive_error output contract
    error_method = @vertex_connector[:methods][:handle_drive_error]
    error_msg = error_method.call({}, 404, 'Not found', 'File missing')

    assert error_msg.is_a?(String)
    assert_includes error_msg, 'File not found'

    puts "    ✓ All helper method outputs match expected contracts"
  end

  def test_fetch_drive_file_contracts
    # Mock the HTTP responses for testing
    mock_connection = create_mock_connection

    # Test input contract validation
    valid_input = {
      'file_id' => '1ABC123DEF456',
      'include_content' => true
    }

    # We can't execute the full action without mocking HTTP, but we can validate structure
    action = @vertex_connector[:actions][:fetch_drive_file]
    assert_not_nil action[:input_fields]
    assert_not_nil action[:output_fields]
    assert_not_nil action[:execute]

    # Validate expected output structure matches our contract
    expected_output_keys = [
      'id', 'name', 'mime_type', 'size', 'modified_time', 'checksum',
      'owners', 'text_content', 'needs_processing', 'export_mime_type', 'fetch_method'
    ]

    output_fields = action[:output_fields].call({})
    output_field_names = output_fields.map { |f| f[:name] }

    expected_output_keys.each do |key|
      assert_includes output_field_names, key, "Missing expected output field: #{key}"
    end

    puts "    ✓ Fetch drive file action structure validates"
  end

  def test_list_drive_files_contracts
    action = @vertex_connector[:actions][:list_drive_files]

    # Validate action structure
    assert_not_nil action[:input_fields]
    assert_not_nil action[:output_fields]
    assert_not_nil action[:execute]

    # Check expected output structure
    expected_output_keys = ['files', 'count', 'has_more', 'next_page_token', 'query_used']

    output_fields = action[:output_fields].call({})
    output_field_names = output_fields.map { |f| f[:name] }

    expected_output_keys.each do |key|
      assert_includes output_field_names, key, "Missing expected output field: #{key}"
    end

    # Validate files array structure
    files_field = output_fields.find { |f| f[:name] == 'files' }
    assert_not_nil files_field[:properties]

    expected_file_props = ['id', 'name', 'mime_type', 'size', 'modified_time', 'checksum']
    file_prop_names = files_field[:properties].map { |p| p[:name] }

    expected_file_props.each do |prop|
      assert_includes file_prop_names, prop, "Missing file property: #{prop}"
    end

    puts "    ✓ List drive files action structure validates"
  end

  def test_batch_fetch_drive_files_contracts
    action = @vertex_connector[:actions][:batch_fetch_drive_files]

    # Validate action structure
    assert_not_nil action[:input_fields]
    assert_not_nil action[:output_fields]
    assert_not_nil action[:execute]

    # Check expected output structure
    expected_output_keys = ['successful_files', 'failed_files', 'metrics']

    output_fields = action[:output_fields].call({})
    output_field_names = output_fields.map { |f| f[:name] }

    expected_output_keys.each do |key|
      assert_includes output_field_names, key, "Missing expected output field: #{key}"
    end

    # Validate metrics structure
    metrics_field = output_fields.find { |f| f[:name] == 'metrics' }
    expected_metrics = ['total_processed', 'success_count', 'failure_count', 'success_rate', 'processing_time_ms']
    metrics_prop_names = metrics_field[:properties].map { |p| p[:name] }

    expected_metrics.each do |metric|
      assert_includes metrics_prop_names, metric, "Missing metric: #{metric}"
    end

    puts "    ✓ Batch fetch drive files action structure validates"
  end

  def test_document_helper_outputs
    # Test generate_document_id contract
    doc_id_method = @rag_connector[:methods][:generate_document_id]
    doc_id = doc_id_method.call("test.txt", "checksum123")

    assert doc_id.is_a?(String)
    assert_equal 64, doc_id.length  # SHA256 hex length
    assert doc_id.match?(/^[a-f0-9]{64}$/)

    # Test calculate_chunk_boundaries contract
    boundaries_method = @rag_connector[:methods][:calculate_chunk_boundaries]
    boundaries = boundaries_method.call("Test sentence. Another sentence.", 20, 5)

    assert boundaries.is_a?(Array)
    boundaries.each do |boundary|
      assert boundary.key?('start')
      assert boundary.key?('end')
      assert boundary['start'].is_a?(Integer)
      assert boundary['end'].is_a?(Integer)
    end

    # Test merge_document_metadata contract
    merge_method = @rag_connector[:methods][:merge_document_metadata]
    merged = merge_method.call(
      { 'chunk_id' => 'test_chunk' },
      { 'file_name' => 'test.txt' },
      { document_id: 'doc_123' }
    )

    assert merged.is_a?(Hash)
    assert_equal 'google_drive', merged['source']
    assert_not_nil merged['indexed_at']
    assert merged['indexed_at'].match?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)

    puts "    ✓ All document helper outputs match expected contracts"
  end

  def test_process_document_for_rag_contracts
    action = @rag_connector[:actions][:process_document_for_rag]

    # Validate action structure
    assert_not_nil action[:input_fields]
    assert_not_nil action[:output_fields]
    assert_not_nil action[:execute]

    # Check expected output structure
    expected_output_keys = ['document_id', 'chunks', 'document_metadata', 'ready_for_embedding']

    output_fields = action[:output_fields].call({})
    output_field_names = output_fields.map { |f| f[:name] }

    expected_output_keys.each do |key|
      assert_includes output_field_names, key, "Missing expected output field: #{key}"
    end

    # Validate chunks structure matches document_chunks_response contract
    chunks_field = output_fields.find { |f| f[:name] == 'chunks' }
    expected_chunk_props = ['chunk_id', 'text', 'chunk_index', 'document_id', 'file_name', 'file_id', 'source']
    chunk_prop_names = chunks_field[:properties].map { |p| p[:name] }

    expected_chunk_props.each do |prop|
      assert_includes chunk_prop_names, prop, "Missing chunk property: #{prop}"
    end

    # Validate document_metadata structure
    doc_meta_field = output_fields.find { |f| f[:name] == 'document_metadata' }
    expected_doc_props = ['total_chunks', 'total_characters', 'total_words', 'processing_timestamp']
    doc_prop_names = doc_meta_field[:properties].map { |p| p[:name] }

    expected_doc_props.each do |prop|
      assert_includes doc_prop_names, prop, "Missing document metadata property: #{prop}"
    end

    puts "    ✓ Process document for RAG action structure validates"
  end

  def test_prepare_document_batch_contracts
    action = @rag_connector[:actions][:prepare_document_batch]

    # Validate action structure
    assert_not_nil action[:input_fields]
    assert_not_nil action[:output_fields]
    assert_not_nil action[:execute]

    # Check expected output structure
    expected_output_keys = ['batches', 'summary', 'failed_documents']

    output_fields = action[:output_fields].call({})
    output_field_names = output_fields.map { |f| f[:name] }

    expected_output_keys.each do |key|
      assert_includes output_field_names, key, "Missing expected output field: #{key}"
    end

    # Validate batches structure
    batches_field = output_fields.find { |f| f[:name] == 'batches' }
    expected_batch_props = ['batch_id', 'chunks', 'document_count', 'chunk_count', 'batch_index']
    batch_prop_names = batches_field[:properties].map { |p| p[:name] }

    expected_batch_props.each do |prop|
      assert_includes batch_prop_names, prop, "Missing batch property: #{prop}"
    end

    # Validate summary structure
    summary_field = output_fields.find { |f| f[:name] == 'summary' }
    expected_summary_props = ['total_documents', 'total_chunks', 'total_batches', 'processing_timestamp']
    summary_prop_names = summary_field[:properties].map { |p| p[:name] }

    expected_summary_props.each do |prop|
      assert_includes summary_prop_names, prop, "Missing summary property: #{prop}"
    end

    puts "    ✓ Prepare document batch action structure validates"
  end

  def test_enhanced_smart_chunk_text_contracts
    action = @rag_connector[:actions][:smart_chunk_text]

    # Validate action structure
    assert_not_nil action[:input_fields]
    assert_not_nil action[:output_fields]
    assert_not_nil action[:execute]

    # Check that document_metadata input field was added
    input_fields = action[:input_fields].call({}, {}, {})
    input_field_names = input_fields.map { |f| f[:name] }

    assert_includes input_field_names, 'document_metadata', "Missing document_metadata input field"

    # Validate document_metadata structure
    doc_meta_field = input_fields.find { |f| f[:name] == 'document_metadata' }
    assert_equal true, doc_meta_field[:optional]
    assert_not_nil doc_meta_field[:properties]

    expected_doc_props = ['document_id', 'file_name', 'file_id']
    doc_prop_names = doc_meta_field[:properties].map { |p| p[:name] }

    expected_doc_props.each do |prop|
      assert_includes doc_prop_names, prop, "Missing document metadata property: #{prop}"
    end

    puts "    ✓ Enhanced smart chunk text action structure validates"
  end

  private

  def create_mock_connection
    {
      'project' => 'test-project',
      'region' => 'us-central1',
      'auth_type' => 'oauth2',
      'oauth_token' => 'mock_token'
    }
  end

  def validate_contract_structure(data, contract_type)
    result = ContractValidator.validate(data, contract_type)
    result.start_with?('✓')
  rescue => e
    puts "Contract validation error: #{e.message}"
    false
  end
end

if __FILE__ == $0
  NewComponentsContractTest.run_all_tests
end