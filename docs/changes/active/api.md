# API

## Consolidated Endpoints

```ruby
API_ENDPOINTS = {
  # Vertex - AI - Generation
  'vertex_generate' => {
    method: 'POST',
    url_template: '{vertex_base}/publishers/google/models/{model}:generateContent',
    actions: ['translate', 'summarize', 'parse', 'classify', 'analyze', 'email', 'conversation', 'image_analysis']
  },
  
  # Vertex - AI - Prediction (embeddings)
  'vertex_predict' => {
    method: 'POST',
    url_template: '{vertex_base}/publishers/google/models/{model}:predict',
    actions: ['embed_single', 'embed_batch']
  },
  
  # Vertex - Vector - Search
  'vector_search' => {
    method: 'POST',
    url_template: 'https://{custom_host}/v1/projects/{project}/locations/{region}/indexEndpoints/{endpoint}:findNeighbors',
    actions: ['find_neighbors']
  },
  
  # Vertex - Vector - Upsert
  'vector_upsert' => {
    method: 'POST',
    url_template: '{vertex_base}/indexes/{index_id}:upsertDatapoints',
    actions: ['upsert_datapoints']
  },
  
  # Drive - Fetch metadata
  'drive_metadata' => {
    method: 'GET',
    url_template: 'https://www.googleapis.com/drive/v3/files/{file_id}',
    actions: ['fetch_file', 'batch_fetch']
  },
  
  # Drive - Fetch Content - Text
  'drive_export' => {
    method: 'GET',
    url_template: 'https://www.googleapis.com/drive/v3/files/{file_id}/export',
    actions: ['fetch_file_content']
  },
  
  # Drive - Fetch Content - Image/PDF
  'drive_download' => {
    method: 'GET', 
    url_template: 'https://www.googleapis.com/drive/v3/files/{file_id}?alt=media',
    actions: ['fetch_file_content']
  },
  
  # Drive - List Files
  'drive_list' => {
    method: 'GET',
    url_template: 'https://www.googleapis.com/drive/v3/files',
    actions: ['list_files']
  },
  
  # Drive - Monitor for Changes
  'drive_changes' => {
    method: 'GET',
    url_template: 'https://www.googleapis.com/drive/v3/changes',
    actions: ['monitor_changes']
  }
}
```