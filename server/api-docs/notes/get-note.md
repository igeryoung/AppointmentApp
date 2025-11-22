# Get Note for Event

## Overview
Retrieve the handwriting note associated with a specific event.

## Endpoint
```
GET /api/books/{bookId}/events/{eventId}/note
```

## Authentication
Requires device credentials

### Headers
- `X-Device-ID` (string, UUID format, required): Device identifier
- `X-Device-Token` (string, required): Device authentication token

## Request Parameters

### Path Parameters
- `bookId` (integer, required): Book identifier
- `eventId` (integer, required): Event identifier

**Example:**
```
GET /api/books/1/events/42/note
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...
```

## Response

### Success Response (200 OK)
Note retrieved successfully, or null if no note exists.

**Response Body:**
- `success` (boolean): Always true for successful requests
- `note` (object or null): Note data, or null if no note exists

**Note Object Fields:**
- `id` (integer): Note identifier
- `eventId` (integer): Associated event ID
- `strokesData` (string): JSON string containing stroke/drawing data
- `createdAt` (string, ISO 8601): Creation timestamp
- `updatedAt` (string, ISO 8601): Last update timestamp
- `version` (integer): Version number for optimistic locking

**Example Response (with note):**
```json
{
  "success": true,
  "note": {
    "id": 123,
    "eventId": 42,
    "strokesData": "[{\"points\":[{\"x\":100,\"y\":200}]}]",
    "createdAt": "2025-01-15T10:30:00Z",
    "updatedAt": "2025-01-20T14:22:00Z",
    "version": 3
  }
}
```

**Example Response (no note):**
```json
{
  "success": true,
  "note": null
}
```

### Error Response (403 Forbidden)
Unauthorized access - invalid credentials or no permission.

## Error Scenarios
- **400 Bad Request**: Invalid bookId or eventId format
- **403 Forbidden**: Invalid device credentials
- **404 Not Found**: Book or event does not exist

## Usage Notes
- Returns null for the note if no note exists (not an error)
- Use the version number for optimistic locking when updating
- StrokesData is a JSON string that needs to be parsed client-side
- Only authorized devices can access notes
