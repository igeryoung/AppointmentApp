# Health Check

## Overview
Check if the server and database are healthy.

## Endpoint
```
GET /health
```

## Authentication
None (public endpoint)

## Request Parameters
None

## Response

### Success Response (200 OK)
Returns server health status.

**Response Body:**
- `status` (string): "healthy" or "unhealthy"
- `service` (string): Service name ("schedule_note_sync_server")

**Example Response:**
```json
{
  "status": "healthy",
  "service": "schedule_note_sync_server"
}
```

## Error Scenarios
- If database connection fails, status will be "unhealthy" but still return 200 OK

## Usage Notes
- Use this endpoint for monitoring and health checks
- No authentication required
- Checks both server availability and database connectivity
