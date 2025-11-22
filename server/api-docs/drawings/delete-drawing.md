# Delete Drawing

## Overview
Soft delete a schedule drawing.

## Endpoint
```
DELETE /api/books/{bookId}/drawings?date={date}&viewMode={viewMode}
```

## Authentication
Requires device credentials

### Headers
- `X-Device-ID` (string, UUID format, required): Device identifier
- `X-Device-Token` (string, required): Device authentication token

## Request Parameters

### Path Parameters
- `bookId` (integer, required): Book identifier

### Query Parameters
- `date` (string, ISO 8601 date format, required): The date for the drawing
- `viewMode` (integer, required): View mode - 0=Day, 1=3-Day, 2=Week

**Example:**
```
DELETE /api/books/1/drawings?date=2025-01-20&viewMode=0
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...
```

## Response

### Success Response (200 OK)
Drawing deleted successfully.

**Response Body:**
```json
{
  "success": true,
  "message": "Drawing deleted successfully"
}
```

### Error Response (404 Not Found)
Drawing does not exist or already deleted.

**Response Body:**
```json
{
  "success": false,
  "message": "Drawing not found"
}
```

### Error Response (403 Forbidden)
Unauthorized access.

## Error Scenarios
- **400 Bad Request**: Missing or invalid date/viewMode parameters
- **403 Forbidden**: Invalid device credentials or no access to book
- **404 Not Found**: Drawing does not exist or already deleted

## Usage Notes
- This is a soft delete - the drawing is marked as deleted but not removed from database
- Deleted drawings will not appear in future GET requests
- Cannot restore a deleted drawing through the API (database-level operation)
- Deleting a non-existent drawing returns 404
- No version checking required for deletion
- Must specify exact date and viewMode to identify the drawing
- Date is normalized to midnight automatically
