# List Backups for Book

## Overview
Get all backups for a specific book.

## Endpoint
```
GET /api/books/{bookId}/backups?deviceId={deviceId}&deviceToken={deviceToken}
```

## Authentication
Requires device credentials

### Query Parameters
- `deviceId` (string, UUID format, required): Device identifier
- `deviceToken` (string, required): Device authentication token

## Request Parameters

### Path Parameters
- `bookId` (integer, required): Book identifier

**Example:**
```
GET /api/books/1/backups?deviceId=550e8400-e29b-41d4-a716-446655440000&deviceToken=abc123xyz...
```

## Response

### Success Response (200 OK)
List of backups retrieved successfully.

**Response Body:**
- `success` (boolean): true
- `backups` (array): Array of backup objects

**Backup Object Fields:**
- `id` (integer): Backup identifier
- `bookId` (integer): Associated book ID
- `bookUuid` (string, UUID): Book UUID
- `backupName` (string): Backup name
- `backupType` (string): Type of backup (e.g., "file" or "json")
- `status` (string): Backup status (e.g., "completed", "pending")
- `sizeBytes` (integer): Backup file size in bytes
- `sizeMB` (string): Backup file size in MB (formatted)
- `isFileBased` (boolean): Whether this is a file-based backup
- `createdAt` (string, ISO 8601): Creation timestamp
- `restoredAt` (string or null, ISO 8601): Last restore timestamp (null if never restored)

**Example Response:**
```json
{
  "success": true,
  "backups": [
    {
      "id": 789,
      "bookId": 1,
      "bookUuid": "abc12345-e29b-41d4-a716-446655440001",
      "backupName": "My Backup 2025-01-20",
      "backupType": "file",
      "status": "completed",
      "sizeBytes": 1048576,
      "sizeMB": "1.00 MB",
      "isFileBased": true,
      "createdAt": "2025-01-20T10:00:00Z",
      "restoredAt": null
    },
    {
      "id": 788,
      "bookId": 1,
      "bookUuid": "abc12345-e29b-41d4-a716-446655440001",
      "backupName": "Auto Backup 2025-01-15",
      "backupType": "file",
      "status": "completed",
      "sizeBytes": 524288,
      "sizeMB": "0.50 MB",
      "isFileBased": true,
      "createdAt": "2025-01-15T08:30:00Z",
      "restoredAt": "2025-01-18T14:20:00Z"
    }
  ]
}
```

### Error Response (403 Forbidden)
Unauthorized access.

**Response Body:**
```json
{
  "success": false,
  "message": "Unauthorized access to book"
}
```

## Error Scenarios
- **400 Bad Request**: Missing deviceId or deviceToken, or invalid bookId
- **403 Forbidden**: Invalid device credentials or no access to book
- **404 Not Found**: Book does not exist

## Usage Notes
- Returns only backups for the specified book
- Backups are ordered by creation date (newest first)
- Shows both file-based and legacy JSON backups
- File size information helps estimate download time
- restoredAt field tracks when a backup was last used for restoration
- Empty array returned if no backups exist (not an error)
