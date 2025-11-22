# Batch Get Drawings

## Overview
Retrieve drawings for a date range and view mode in a single request.

## Endpoint
```
POST /api/drawings/batch
```

## Authentication
Requires device credentials

### Headers
- `X-Device-ID` (string, UUID format, required): Device identifier
- `X-Device-Token` (string, required): Device authentication token

## Request Parameters

### Body (JSON)
- `bookId` (integer, required): Book identifier
- `dateRange` (object, required): Date range specification
  - `start` (string, ISO 8601 date format, required): Start date (inclusive)
  - `end` (string, ISO 8601 date format, required): End date (inclusive)
- `viewMode` (integer, required): View mode - 0=Day, 1=3-Day, 2=Week

**Example Request:**
```
POST /api/drawings/batch
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...

Body:
{
  "bookId": 1,
  "dateRange": {
    "start": "2025-01-15",
    "end": "2025-01-21"
  },
  "viewMode": 0
}
```

## Response

### Success Response (200 OK)
Drawings retrieved successfully.

**Response Body:**
- `success` (boolean): Always true
- `drawings` (array): Array of drawing objects
- `count` (integer): Number of drawings returned

**Drawing Object Fields:**
- `id` (integer): Drawing identifier
- `bookId` (integer): Associated book ID
- `date` (string, ISO 8601): Date normalized to midnight
- `viewMode` (integer): View mode (0=Day, 1=3-Day, 2=Week)
- `strokesData` (string): JSON string containing stroke/drawing data
- `createdAt` (string, ISO 8601): Creation timestamp
- `updatedAt` (string, ISO 8601): Last update timestamp
- `version` (integer): Version number for optimistic locking

**Example Response:**
```json
{
  "success": true,
  "drawings": [
    {
      "id": 456,
      "bookId": 1,
      "date": "2025-01-15T00:00:00Z",
      "viewMode": 0,
      "strokesData": "[{\"points\":[{\"x\":50,\"y\":100}]}]",
      "createdAt": "2025-01-15T10:00:00Z",
      "updatedAt": "2025-01-15T10:00:00Z",
      "version": 1
    },
    {
      "id": 457,
      "bookId": 1,
      "date": "2025-01-20T00:00:00Z",
      "viewMode": 0,
      "strokesData": "[{\"points\":[{\"x\":75,\"y\":125}]}]",
      "createdAt": "2025-01-20T14:30:00Z",
      "updatedAt": "2025-01-20T14:30:00Z",
      "version": 1
    }
  ],
  "count": 2
}
```

### Error Response (403 Forbidden)
Unauthorized access.

## Error Scenarios
- **400 Bad Request**: Missing required fields, invalid date format, or invalid viewMode
- **403 Forbidden**: Invalid device credentials or no access to book
- **404 Not Found**: Book does not exist

## Usage Notes
- Only returns drawings that exist within the date range
- Date range is inclusive of both start and end dates
- Only returns drawings matching the specified viewMode
- Count may be less than the number of dates if some dates don't have drawings
- More efficient than making individual GET requests for each date
- Useful for fetching drawings for a visible date range (week/month view)
- No limit on date range size, but keep requests reasonable
- Dates are normalized to midnight automatically
