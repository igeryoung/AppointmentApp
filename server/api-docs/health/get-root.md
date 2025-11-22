# Server Information

## Overview
Get basic server information including version and documentation link.

## Endpoint
```
GET /
```

## Authentication
None (public endpoint)

## Request Parameters
None

## Response

### Success Response (200 OK)
Returns server information.

**Response Body:**
- `message` (string): Server name
- `version` (string): API version
- `docs` (string): Path to API documentation

**Example Response:**
```json
{
  "message": "Schedule Note Sync Server",
  "version": "1.0.0",
  "docs": "/docs"
}
```

## Error Scenarios
None - this endpoint always returns successfully

## Usage Notes
- Use this endpoint to verify server availability
- No authentication required
- Returns basic server metadata
