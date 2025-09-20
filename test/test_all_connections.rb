# test_all_connections.rb
# Purpose: Verify Vertex AI and Google Drive connectivity
# Requirements tested: Authentication, API access, permissions

def test_all_connections
  puts "="*50
  puts "Testing All Connections"
  puts "="*50
  
  test_config = {
    test_vertex_ai: true,
    test_drive: true,
    test_models: true,
    test_index: false,  # Set true if index deployed
    verbose: true
  }
  
  # Test using the Vertex connector
  result = vertex_connector.test_connection(test_config)
  
  # Validate results
  assertions = {
    "Overall Status" => result['overall_status'] == 'healthy',
    "Vertex AI Connected" => result['tests_performed'].any? { |t| 
      t['service'] == 'Vertex AI' && t['status'] == 'connected' 
    },
    "Google Drive Connected" => result['tests_performed'].any? { |t| 
      t['service'] == 'Google Drive' && t['status'] == 'connected' 
    },
    "Drive Files Accessible" => result['tests_performed'].any? { |t| 
      t['service'] == 'Google Drive' && t['files_found'] > 0 
    },
    "Gemini Models Accessible" => result['tests_performed'].any? { |t| 
      t['service'] == 'Vertex AI' && t['gemini_access'] == true 
    }
  }
  
  # Print results
  assertions.each do |test_name, passed|
    status = passed ? "✅ PASS" : "❌ FAIL"
    puts "#{status}: #{test_name}"
  end
  
  # Print errors if any
  if result['errors'].any?
    puts "\n⚠️  Errors detected:"
    result['errors'].each { |e| puts "  - #{e}" }
  end
  
  # Print recommendations
  if result['recommendations'].any?
    puts "\n💡 Recommendations:"
    result['recommendations'].each { |r| puts "  - #{r}" }
  end
  
  # Return overall pass/fail
  assertions.values.all?
end

# Execute test
success = test_all_connections
exit(success ? 0 : 1)
