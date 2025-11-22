# Batch Save Notes and Drawings

## Overview
Save multiple notes and drawings in a single atomic transaction. All operations succeed or all fail together.

## Endpoint
```
POST /api/batch/save
```

## Authentication
Requires device credentials

### Headers
- `X-Device-ID` (string, UUID format, required): Device identifier
- `X-Device-Token` (string, required): Device authentication token

## Request Parameters

### Body (JSON)
- `notes` (array, optional): Array of note save operations
- `drawings` (array, optional): Array of drawing save operations

**Note Object Fields:**
- `eventId` (integer, required): Event ID this note belongs to
- `bookId` (integer, required): Book ID for authorization
- `strokesData` (string, required): JSON string of stroke data
- `version` (integer, optional): Expected version for optimistic locking (for updates)

**Drawing Object Fields:**
- `bookId` (integer, required): Book ID
- `date` (string, ISO 8601 date format, required): Date for the drawing
- `viewMode` (integer, required): View mode (0=Day, 1=3-Day, 2=Week)
- `strokesData` (string, required): JSON string of stroke data
- `version` (integer, optional): Expected version for optimistic locking (for updates)

**Example Request:**
```
POST /api/batch/save
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...

Body:
{
  "notes": [
    {
      "eventId": 1,
      "bookId": 1,
      "strokesData": "[{\"points\":[{\"x\":100,\"y\":200}]}]",
      "version": 2
    },
    {
      "eventId": 2,
      "bookId": 1,
      "strokesData": "[{\"points\":[{\"x\":150,\"y\":250}]}]"
    }
  ],
  "drawings": [
    {
      "bookId": 1,
      "date": "2025-01-20",
      "viewMode": 0,
      "strokesData": "[{\"points\":[{\"x\":50,\"y\":100}]}]",
      "version": 1
    }
  ]
}
```

## Response

### Success Response (200 OK)
All operations succeeded.

**Response Body:**
- `success` (boolean): true
- `results` (object): Summary of operations
  - `notes` (object): Note operation results
    - `succeeded` (integer): Number of notes successfully saved
    - `failed` (integer): Always 0 in all-or-nothing mode
  - `drawings` (object): Drawing operation results
    - `succeeded` (integer): Number of drawings successfully saved
    - `failed` (integer): Always 0 in all-or-nothing mode

**Example Response:**
```json
{
  "success": true,
  "results": {
    "notes": {
      "succeeded": 2,
      "failed": 0
    },
    "drawings": {
      "succeeded": 1,
      "failed": 0
    }
  }
}
```

### Error Response (400 Bad Request)
Validation error or invalid data.

**Response Body:**
```json
{
  "success": false,
  "message": "Event does not belong to book: eventId=123, bookId=456",
  "results": {
    "notes": {
      "succeeded": 0,
      "failed": 2
    },
    "drawings": {
      "succeeded": 0,
      "failed": 1
    }
  }
}
```

### Error Response (409 Conflict)
Version conflict - optimistic locking failure.

**Response Body:**
```json
{
  "success": false,
  "message": "Version conflict: eventId=1, expected=2, server=3"
}
```

### Error Response (413 Payload Too Large)
Too many items in batch.

**Response Body:**
```json
{
  "success": false,
  "message": "Payload too large: maximum 1000 items allowed (got 1500)"
}
```

## Error Scenarios
- **400 Bad Request**: Missing required fields, invalid format, or validation failure
- **401 Unauthorized**: Missing authentication headers
- **403 Forbidden**: Invalid credentials or unauthorized access to book
- **409 Conflict**: Version mismatch on any item
- **413 Payload Too Large**: More than 1000 total items (notes + drawings)
- **500 Internal Server Error**: Database or server error

## Usage Notes
- Maximum 1000 items total (notes + drawings combined)
- All-or-nothing strategy: entire batch succeeds or entire batch fails
- Performed in a single database transaction
- If any item fails, transaction is rolled back and nothing is saved
- More efficient than individual save operations for multiple items
- Supports both creating new items and updating existing items
- Version conflicts on any single item will fail the entire batch
- Device must have access to all books referenced in the batch
- Use for saving multiple changes at once (e.g., on screen close or periodic save)
- For updates, include version number to enable conflict detection
- Omit version for new items
