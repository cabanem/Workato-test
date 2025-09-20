# test_oauth_scopes.rb
# Purpose: Ensure OAuth has correct scopes for Drive and Vertex AI
# Requirements tested: OAuth2 configuration

def test_oauth_scopes
  puts "Testing OAuth2 Scopes..."
  
  required_scopes = [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/drive.readonly'
  ]
  
  # Test by attempting operations requiring each scope
  tests = {
    vertex_scope: -> {
      # Try to list datasets (requires cloud-platform scope)
      vertex_connector.get("projects/#{PROJECT}/locations/#{REGION}/datasets", page_size: 1)
      true
    },
    drive_scope: -> {
      # Try to list files (requires drive.readonly scope)
      vertex_connector.list_drive_files(max_results: 1)
      true
    }
  }
  
  results = {}
  tests.each do |scope_name, test_fn|
    begin
      test_fn.call
      results[scope_name] = "✅ PASS"
    rescue => e
      results[scope_name] = "❌ FAIL: #{e.message}"
    end
  end
  
  results.each { |scope, status| puts "#{scope}: #{status}" }
  results.values.all? { |v| v.include?("PASS") }
end
