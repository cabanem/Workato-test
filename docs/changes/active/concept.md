# Conceptual Analysis

## Core Methods

Core methods can be reused throughout the connector.

```
HTTP_REQUEST
---
purpose: Make an HTTP request
--- 
@param:  method
@param:  url
@param:  payload
@param:  headers
```

```
BUILD_PAYLOAD
---
purpose: Build a payload
---
@param:  template
@param:  variables
@param:  format
```

```
EXTRACT_RESPONSE
---
purpose: Extract response body
---
@param:  data
@param:  path
@param:  format
```

```
WITH_RESILIENCE
---
purpose: Handle errors
---
@param:  operation
@param:  &block
```

```
PROCESS_BATCH
---
purpose: Process data as a batch
---
@param:  items
@param:  batch_size
@param:  &processor
```

```
TRANSFORM_DATA
---
purpose: Transform data safely
---
@param:  input
@param:  from_format
@param:  to_format
```

```
VALIDATE_INPUT
---
purpose: Validate input
---
@param:  data
@param:  schema
@param:  constraints
```

```
ENRICH_RESPONSE
---
purpose: Add metadata
---
@param:  response
@param:  metadata
```

---
## Universal Execution Pipeline

All actions will process input in the same manner, using configuration elements to achieve specificity.

Most actions follow a similar pattern:
    `validate` &rarr; `build` &rarr; `execute` &rarr; `extract` &rarr; `enrich`

1. Validate input

```ruby
call('validate'
    data:           input,
    schema:         config['validate']['schema']
    constraints:    config['validate']['constraints']
)
```

2. Transform input

```ruby
if config['transform_input']
    config['transform_input'].each do |field, transform|
        input['field] = call('transform_data',
           input:          input['field'],
           from_format:    transform['from']
           to_format:      transform['to']
        )
    end
end
```

3. Build payload

```ruby
payload = call('build_payload',
    template:   config['payload']['template']
    variables:  input.merge('system' => config['payload']['system']),
    format:     config['payload']['format']
)
```

4. Execute (with resilience)

```ruby
response = call('with_resilience',
    operation:  operation,
    config:     config['resilience']
) do
    url = call('build_url, connection, config['endpoint'], input)
    
    call('http_request',
        method:     config['endpoint']['method'],
        url:        url,
        payload:    payload,
        headers:    call('build_headers', connection)
    )
end
```

5. Extract response

```ruby
extracted = call('extract_response',
    data:   response,
    path:   config['extract']['path'],
    format: config['extract']['format']
)
```

6. Post-process (as required)

```ruby
if config['post_response']
    extracted = call(config['post_process'], extracted, input)
end
```

7. Enrich with metadata

```ruby
call('enrich_response',
    response: extracted,
    metadata: {
        'operation' => operation,
        'model'     => input['model']
    }
)
```
---
## Configuration by Operation

| ACTION | CONFIG_KEY | PROCESSING |
| :---   | :---       | :---       |
| send_messages | conversation | direct payload, pass through |
| tranlate_text | translate | template interpolation |
| summarize_text | summarize | word count in template |
| parse_text | parse | dynamic schema extraction |
| classify | classify | confidence post-processing |
| analyze_text | analyze | q/a template |
| draft_email | email | subject/body extraction |
| analyze_image | image | base63 encoding |
| generate_embeddings | embed_batch | batch processing |
| find_neighbors | vector_search | distance transformation |
| fetch_drive_file | fetch_file | content fetching |
| list_drive_files | list_files | query building |

## Configuration Registry

Given the constraints posed by the Workato environment, configuration will be accessible via a method.

```ruby
methods: {
    # Operation configurations as data
    get_operation_config: lambda do |operation|
        {
            # Test operations
            'translate' => {
                'endpoint' => { 'path' => ':generateContent', 'method' => 'POST' },
                'payload'  => {
                    'format'    => 'vertex_prompt',
                    'template'  => 'Translate from {from} to {to}:\n```{text}```',
                    'system'    => 'You are a professional translator.'
                },
                'extract' => {
                    'format' => 'vertex_json',
                    'path'   => 'response'
                },
                'validate' => {
                    'schema' => [
                        { 'name' => 'text', 'required' => true },
                        { 'name' => 'to', 'required' => true }
                    ]
                },
                'resilience' => {
                    'rate_limit' => { 'rpm' => 60 },
                    'max_retries' => 3
                }
            }, 

            'classify' => { ... }
        }
    end
}
```

## Methods

1. HTTP request execution
    - Universal HTTP handler w/built-in resilience mechanism
    - PARAMS:    method, url, payload, headers, retry_config
2. Payload builder
    - PARAMS:   template, variables, format
    - Build Vertex AI prompt structure as directed by configuration (e.g., direct json payload, batch)
3. Extract response
    - PARAMS:   data, path, format
    - Configuration directed extraction (e.g., JSON field, array, standard response body)
4. Error recovery
    - PARAMS:   operation, configuration, calling block
    - Implements rate limiting, circuit-breaker pattern, retries
    - Evaluates conditions (e.g., rate limit, circuit breaker)
5. Transform data
    - PARAMS:   input, from_format, to_format
    - Handles data transformation in various forms (e.g., url encoding, k-nn scoring, formatting)
6. Input validation
    - PARAMS:   data, schema, constraints
    - Validates configuration elements (schema, constraint)
7. Batch processing
    - PARAMS:   items, batch_size, processor, aggregator
    - Iterates through batches, checks for aggregator, and aggregates upon completion as required.
8. Enrich metadata
    - PARAMS:  response, metadata
    - Append metadata, trace information, or custom elements as required