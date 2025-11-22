# Delete Note

## Overview
Soft delete a handwriting note for an event.

## Endpoint
```
DELETE /api/books/{bookId}/events/{eventId}/note
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
DELETE /api/books/1/events/42/note
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...
```

## Response

### Success Response (200 OK)
Note deleted successfully.

**Response Body:**
```json
{
  "success": true,
  "message": "Note deleted successfully"
}
```

### Error Response (404 Not Found)
Note does not exist or already deleted.

**Response Body:**
```json
{
  "success": false,
  "message": "Note not found"
}
```

### Error Response (403 Forbidden)
Unauthorized access.

## Error Scenarios
- **400 Bad Request**: Invalid bookId or eventId format
- **403 Forbidden**: Invalid device credentials or no access to book
- **404 Not Found**: Note does not exist or already deleted

## Usage Notes
- This is a soft delete - the note is marked as deleted but not removed from database
- Deleted notes will not appear in future GET requests
- Cannot restore a deleted note through the API (database-level operation)
- Deleting a non-existent note returns 404
- No version checking required for deletion
