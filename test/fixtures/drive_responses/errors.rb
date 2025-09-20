# test/fixtures/drive_responses/errors.rb
DRIVE_ERROR_FIXTURES = {
  not_found: {
    code: 404,
    body: {
      "error": {
        "code": 404,
        "message": "File not found: invalid_file_id",
        "status": "NOT_FOUND"
      }
    }
  },
  
  rate_limit: {
    code: 429,
    body: {
      "error": {
        "code": 429,
        "message": "Rate Limit Exceeded",
        "status": "RESOURCE_EXHAUSTED"
      }
    },
    headers: { "Retry-After" => "60" }
  },
  
  insufficient_permissions: {
    code: 403,
    body: {
      "error": {
        "code": 403,
        "message": "The caller does not have permission",
        "status": "PERMISSION_DENIED"
      }
    }
  }
}
