# Create or Update Drawing

## Overview
Create a new schedule drawing or update an existing one with optimistic locking support.

## Endpoint
```
POST /api/books/{bookId}/drawings
```

## Authentication
Requires device credentials

### Headers
- `X-Device-ID` (string, UUID format, required): Device identifier
- `X-Device-Token` (string, required): Device authentication token

## Request Parameters

### Path Parameters
- `bookId` (integer, required): Book identifier

### Body (JSON)
- `date` (string, ISO 8601 date format, required): The date for the drawing
- `viewMode` (integer, required): View mode - 0=Day, 1=3-Day, 2=Week
- `strokesData` (string, required): JSON string containing stroke/drawing data
- `version` (integer, optional): Expected version number for optimistic locking (required for updates)

**Example Request (create new drawing):**
```
POST /api/books/1/drawings
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...

Body:
{
  "date": "2025-01-20",
  "viewMode": 0,
  "strokesData": "[{\"points\":[{\"x\":50,\"y\":100}]}]"
}
```

**Example Request (update existing drawing):**
```json
{
  "date": "2025-01-20",
  "viewMode": 0,
  "strokesData": "[{\"points\":[{\"x\":75,\"y\":125}]}]",
  "version": 2
}
```

## Response

### Success Response (200 OK)
Drawing created or updated successfully.

**Response Body:**
- `success` (boolean): Always true
- `drawing` (object): The saved drawing data
- `version` (integer): New version number

**Example Response:**
```json
{
  "success": true,
  "drawing": {
    "id": 456,
    "bookId": 1,
    "date": "2025-01-20T00:00:00Z",
    "viewMode": 0,
    "strokesData": "[{\"points\":[{\"x\":75,\"y\":125}]}]",
    "createdAt": "2025-01-20T10:15:00Z",
    "updatedAt": "2025-01-20T14:30:00Z",
    "version": 3
  },
  "version": 3
}
```

### Error Response (409 Conflict)
Version conflict - the drawing was modified by another device.

**Response Body:**
- `success` (boolean): false
- `conflict` (boolean): true
- `serverVersion` (integer): Current version on server
- `serverDrawing` (object): Current drawing data on server

**Example Response:**
```json
{
  "success": false,
  "conflict": true,
  "serverVersion": 4,
  "serverDrawing": {
    "id": 456,
    "bookId": 1,
    "date": "2025-01-20T00:00:00Z",
    "viewMode": 0,
    "strokesData": "[{\"points\":[{\"x\":100,\"y\":150}]}]",
    "version": 4
  }
}
```

### Error Response (403 Forbidden)
Unauthorized access.

## Error Scenarios
- **400 Bad Request**: Missing required fields or invalid format
- **403 Forbidden**: Invalid device credentials or no access to book
- **404 Not Found**: Book does not exist
- **409 Conflict**: Version mismatch (optimistic locking failure)

## Usage Notes
- For creating a new drawing, omit the `version` parameter
- For updating, always include the current `version` to prevent conflicts
- On conflict (409), fetch the latest drawing, merge if needed, and retry with correct version
- Date is automatically normalized to midnight (00:00:00)
- Different view modes are treated as separate drawings for the same date
- StrokesData should be a valid JSON string
- Server automatically increments version on each save
- First save creates version 1
