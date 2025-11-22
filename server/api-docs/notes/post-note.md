# Create or Update Note

## Overview
Create a new handwriting note or update an existing one with optimistic locking support.

## Endpoint
```
POST /api/books/{bookId}/events/{eventId}/note
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

### Body (JSON)
- `strokesData` (string, required): JSON string containing stroke/drawing data
- `version` (integer, optional): Expected version number for optimistic locking (required for updates)

**Example Request (create new note):**
```
POST /api/books/1/events/42/note
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...

Body:
{
  "strokesData": "[{\"points\":[{\"x\":100,\"y\":200}]}]"
}
```

**Example Request (update existing note):**
```json
{
  "strokesData": "[{\"points\":[{\"x\":150,\"y\":250}]}]",
  "version": 3
}
```

## Response

### Success Response (200 OK)
Note created or updated successfully.

**Response Body:**
- `success` (boolean): Always true
- `note` (object): The saved note data
- `version` (integer): New version number

**Example Response:**
```json
{
  "success": true,
  "note": {
    "id": 123,
    "eventId": 42,
    "strokesData": "[{\"points\":[{\"x\":150,\"y\":250}]}]",
    "createdAt": "2025-01-15T10:30:00Z",
    "updatedAt": "2025-01-20T14:22:00Z",
    "version": 4
  },
  "version": 4
}
```

### Error Response (409 Conflict)
Version conflict - the note was modified by another device.

**Response Body:**
- `success` (boolean): false
- `conflict` (boolean): true
- `serverVersion` (integer): Current version on server
- `serverNote` (object): Current note data on server

**Example Response:**
```json
{
  "success": false,
  "conflict": true,
  "serverVersion": 5,
  "serverNote": {
    "id": 123,
    "eventId": 42,
    "strokesData": "[{\"points\":[{\"x\":200,\"y\":300}]}]",
    "version": 5
  }
}
```

### Error Response (403 Forbidden)
Unauthorized access.

## Error Scenarios
- **400 Bad Request**: Missing strokesData or invalid format
- **403 Forbidden**: Invalid device credentials or no access to book
- **404 Not Found**: Book or event does not exist
- **409 Conflict**: Version mismatch (optimistic locking failure)

## Usage Notes
- For creating a new note, omit the `version` parameter
- For updating, always include the current `version` to prevent conflicts
- On conflict (409), fetch the latest note, merge if needed, and retry with correct version
- StrokesData should be a valid JSON string
- Server automatically increments version on each save
- First save creates version 1
