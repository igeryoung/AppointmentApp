# Batch Get Notes

## Overview
Retrieve notes for multiple events in a single request.

## Endpoint
```
POST /api/notes/batch
```

## Authentication
Requires device credentials

### Headers
- `X-Device-ID` (string, UUID format, required): Device identifier
- `X-Device-Token` (string, required): Device authentication token

## Request Parameters

### Body (JSON)
- `eventIds` (array of integers, required): List of event IDs to fetch notes for

**Example Request:**
```
POST /api/notes/batch
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...

Body:
{
  "eventIds": [1, 5, 12, 42, 99]
}
```

## Response

### Success Response (200 OK)
Notes retrieved successfully.

**Response Body:**
- `success` (boolean): Always true
- `notes` (array): Array of note objects
- `count` (integer): Number of notes returned

**Note Object Fields:**
- `id` (integer): Note identifier
- `eventId` (integer): Associated event ID
- `strokesData` (string): JSON string containing stroke/drawing data
- `createdAt` (string, ISO 8601): Creation timestamp
- `updatedAt` (string, ISO 8601): Last update timestamp
- `version` (integer): Version number for optimistic locking

**Example Response:**
```json
{
  "success": true,
  "notes": [
    {
      "id": 10,
      "eventId": 1,
      "strokesData": "[{\"points\":[{\"x\":100,\"y\":200}]}]",
      "createdAt": "2025-01-15T10:30:00Z",
      "updatedAt": "2025-01-15T10:30:00Z",
      "version": 1
    },
    {
      "id": 25,
      "eventId": 42,
      "strokesData": "[{\"points\":[{\"x\":150,\"y\":250}]}]",
      "createdAt": "2025-01-16T11:00:00Z",
      "updatedAt": "2025-01-20T14:22:00Z",
      "version": 3
    }
  ],
  "count": 2
}
```

### Error Response (403 Forbidden)
Unauthorized access.

## Error Scenarios
- **400 Bad Request**: Missing eventIds or invalid format
- **403 Forbidden**: Invalid device credentials or no access to events

## Usage Notes
- Only returns notes that exist - missing notes are simply omitted from results
- Events must belong to books the device has access to
- No limit on number of event IDs, but keep requests reasonable
- More efficient than making individual GET requests for each event
- Useful for fetching notes for a date range or visible screen
- Count may be less than the number of eventIds if some events don't have notes
