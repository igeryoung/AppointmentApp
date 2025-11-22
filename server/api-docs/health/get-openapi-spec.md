# OpenAPI Specification

## Overview
Download the complete OpenAPI 3.0 specification for this API.

## Endpoint
```
GET /openapi.yaml
```

## Authentication
None (public endpoint)

## Request Parameters
None

## Response

### Success Response (200 OK)
Returns the OpenAPI specification file.

**Content-Type:** `text/yaml`

**Response Body:**
Complete OpenAPI 3.0 specification in YAML format

## Error Scenarios
- **404 Not Found**: If the openapi.yaml file is missing from the server

## Usage Notes
- Use this to import the API into tools like Postman, Insomnia, or code generators
- The specification includes all endpoints, request/response schemas, and authentication details
- Can be used with OpenAPI Generator to create client libraries
- No authentication required
