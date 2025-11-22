# Get Drawing

## Overview
Retrieve a schedule drawing for a specific date and view mode.

## Endpoint
```
GET /api/books/{bookId}/drawings?date={date}&viewMode={viewMode}
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
- `date` (string, ISO 8601 date format, required): The date for the drawing (e.g., "2025-01-20")
- `viewMode` (integer, required): View mode - 0=Day, 1=3-Day, 2=Week

**Example:**
```
GET /api/books/1/drawings?date=2025-01-20&viewMode=0
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...
```

## Response

### Success Response (200 OK)
Drawing retrieved successfully, or null if no drawing exists.

**Response Body:**
- `success` (boolean): Always true for successful requests
- `drawing` (object or null): Drawing data, or null if no drawing exists

**Drawing Object Fields:**
- `id` (integer): Drawing identifier
- `bookId` (integer): Associated book ID
- `date` (string, ISO 8601): Date normalized to midnight
- `viewMode` (integer): View mode (0=Day, 1=3-Day, 2=Week)
- `strokesData` (string): JSON string containing stroke/drawing data
- `createdAt` (string, ISO 8601): Creation timestamp
- `updatedAt` (string, ISO 8601): Last update timestamp
- `version` (integer): Version number for optimistic locking

**Example Response (with drawing):**
```json
{
  "success": true,
  "drawing": {
    "id": 456,
    "bookId": 1,
    "date": "2025-01-20T00:00:00Z",
    "viewMode": 0,
    "strokesData": "[{\"points\":[{\"x\":50,\"y\":100}]}]",
    "createdAt": "2025-01-20T10:15:00Z",
    "updatedAt": "2025-01-20T14:30:00Z",
    "version": 2
  }
}
```

**Example Response (no drawing):**
```json
{
  "success": true,
  "drawing": null
}
```

### Error Response (403 Forbidden)
Unauthorized access - invalid credentials or no permission.

## Error Scenarios
- **400 Bad Request**: Missing or invalid date/viewMode parameters
- **403 Forbidden**: Invalid device credentials or no access to book
- **404 Not Found**: Book does not exist

## Usage Notes
- Returns null for the drawing if no drawing exists (not an error)
- Date is normalized to midnight (00:00:00) automatically
- ViewMode values: 0=Day view, 1=3-Day view, 2=Week view
- Use the version number for optimistic locking when updating
- StrokesData is a JSON string that needs to be parsed client-side
- Different view modes can have different drawings for the same date
