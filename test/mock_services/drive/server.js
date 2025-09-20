// test/mock_services/drive/server.js

const express = require('express');
const fs = require('fs');
const path = require('path');
const bodyParser = require('body-parser');

const app = express();
const PORT = process.env.PORT || 3002;

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.path}`);
  next();
});

// Load fixtures
const FIXTURES_PATH = path.join(__dirname, '../../fixtures/drive_responses');

function loadFixture(name) {
  try {
    const filePath = path.join(FIXTURES_PATH, `${name}.json`);
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    console.error(`Failed to load fixture ${name}:`, error);
    return null;
  }
}

// OAuth2 endpoints
app.post('/oauth2/v4/token', (req, res) => {
  const { grant_type, refresh_token } = req.body;
  
  if (grant_type === 'refresh_token' && refresh_token) {
    res.json({
      access_token: 'mock_access_token_' + Date.now(),
      token_type: 'Bearer',
      expires_in: 3600,
      refresh_token: refresh_token
    });
  } else {
    res.status(400).json({ error: 'invalid_grant' });
  }
});

// Drive API endpoints
app.get('/drive/v3/files', (req, res) => {
  const { q, pageSize, pageToken } = req.query;
  const fixture = loadFixture('list_files') || {
    files: [
      {
        id: 'mock_file_1',
        name: 'Mock Document 1.pdf',
        mimeType: 'application/pdf',
        modifiedTime: new Date().toISOString(),
        size: 1024000
      },
      {
        id: 'mock_file_2',
        name: 'Mock Document 2.txt',
        mimeType: 'text/plain',
        modifiedTime: new Date().toISOString(),
        size: 2048
      }
    ]
  };
  
  // Apply query filter if provided
  let files = fixture.files;
  if (q) {
    // Simple mock filtering
    if (q.includes('modifiedTime')) {
      // Filter by modified time
      const match = q.match(/modifiedTime\s*>\s*'([^']+)'/);
      if (match) {
        const filterDate = new Date(match[1]);
        files = files.filter(f => new Date(f.modifiedTime) > filterDate);
      }
    }
  }
  
  // Apply pagination
  const size = pageSize ? parseInt(pageSize) : 100;
  const startIndex = pageToken ? parseInt(pageToken) : 0;
  const paginatedFiles = files.slice(startIndex, startIndex + size);
  
  const response = {
    files: paginatedFiles
  };
  
  // Add next page token if there are more files
  if (startIndex + size < files.length) {
    response.nextPageToken = String(startIndex + size);
  }
  
  res.json(response);
});

app.get('/drive/v3/files/:fileId', (req, res) => {
  const { fileId } = req.params;
  const { fields } = req.query;
  
  const fixture = loadFixture('file_metadata');
  if (fixture) {
    fixture.id = fileId;
    res.json(fixture);
  } else {
    res.json({
      id: fileId,
      name: `Mock File ${fileId}.txt`,
      mimeType: 'text/plain',
      size: 1024,
      createdTime: new Date().toISOString(),
      modifiedTime: new Date().toISOString()
    });
  }
});

app.get('/drive/v3/files/:fileId/export', (req, res) => {
  const { fileId } = req.params;
  const { mimeType } = req.query;
  
  // Return mock content based on mime type
  if (mimeType === 'text/plain') {
    const content = fs.readFileSync(
      path.join(__dirname, '../../fixtures/documents/sample_policy.txt'),
      'utf8'
    );
    res.type('text/plain').send(content);
  } else {
    res.type('text/plain').send(`Mock exported content for file ${fileId}`);
  }
});

app.post('/batch/drive/v3', (req, res) => {
  // Mock batch API response
  const { requests } = req.body;
  
  const responses = requests.map((request, index) => {
    const mockResponse = {
      id: request.id || index,
      status: 200,
      headers: { 'Content-Type': 'application/json' },
      body: {
        id: `file_${index}`,
        name: `Mock File ${index}.txt`,
        mimeType: 'text/plain'
      }
    };
    
    // Simulate some failures
    if (index % 10 === 9) {
      mockResponse.status = 404;
      mockResponse.body = { error: { code: 404, message: 'File not found' } };
    }
    
    return mockResponse;
  });
  
  res.json({ responses });
});

// Changes API for incremental sync
app.get('/drive/v3/changes', (req, res) => {
  const { pageToken } = req.query;
  
  res.json({
    changes: [
      {
        fileId: 'changed_file_1',
        removed: false,
        file: {
          id: 'changed_file_1',
          name: 'Recently Changed.pdf',
          modifiedTime: new Date().toISOString()
        }
      }
    ],
    newStartPageToken: 'next_token_' + Date.now(),
    nextPageToken: null
  });
});

app.get('/drive/v3/changes/startPageToken', (req, res) => {
  res.json({
    startPageToken: 'start_token_' + Date.now()
  });
});

// Error simulation endpoint
app.get('/drive/v3/test/error/:code', (req, res) => {
  const { code } = req.params;
  const errorCode = parseInt(code);
  
  switch (errorCode) {
    case 429:
      res.status(429).set('Retry-After', '60').json({
        error: {
          code: 429,
          message: 'Rate limit exceeded',
          status: 'RESOURCE_EXHAUSTED'
        }
      });
      break;
    case 403:
      res.status(403).json({
        error: {
          code: 403,
          message: 'Insufficient permissions',
          status: 'PERMISSION_DENIED'
        }
      });
      break;
    default:
      res.status(errorCode).json({
        error: {
          code: errorCode,
          message: `Test error ${errorCode}`
        }
      });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    service: 'mock_drive',
    timestamp: new Date().toISOString()
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`Mock Google Drive server running on http://localhost:${PORT}`);
  console.log(`Fixtures loaded from: ${FIXTURES_PATH}`);
});
