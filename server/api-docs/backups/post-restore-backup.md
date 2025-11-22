# Restore from Backup

## Overview
Restore a book from a backup (supports both file-based and legacy JSON backups).

## Endpoint
```
POST /api/backups/{backupId}/restore
```

## Authentication
Requires device credentials

### Headers
- `X-Device-ID` (string, UUID format, required): Device identifier
- `X-Device-Token` (string, required): Device authentication token

## Request Parameters

### Path Parameters
- `backupId` (integer, required): Backup identifier

### Body (JSON)
No body required.

**Example Request:**
```
POST /api/backups/789/restore
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...
```

## Response

### Success Response (200 OK)
Book restored successfully.

**Response Body:**
- `success` (boolean): true
- `message` (string): Success message with restoration details

**Example Response:**
```json
{
  "success": true,
  "message": "Book restored successfully from backup 789"
}
```

### Error Response (403 Forbidden)
Unauthorized access.

**Response Body:**
```json
{
  "success": false,
  "message": "Unauthorized access to backup"
}
```

### Error Response (404 Not Found)
Backup not found.

**Response Body:**
```json
{
  "success": false,
  "message": "Backup not found"
}
```

### Error Response (500 Internal Server Error)
Restore operation failed.

**Response Body:**
```json
{
  "success": false,
  "message": "Restore failed: [error details]"
}
```

## Error Scenarios
- **400 Bad Request**: Invalid backupId
- **401 Unauthorized**: Missing device credentials in headers
- **403 Forbidden**: Invalid device credentials or no access to backup
- **404 Not Found**: Backup doesn't exist
- **500 Internal Server Error**: Restore process failed (database error, corrupted backup, etc.)

## Usage Notes
- Replaces existing book data if the book ID matches
- For file-based backups, decompresses and executes the SQL file
- For legacy JSON backups, uses JSON restore logic
- Operation is performed in a database transaction
- All existing data for the book will be replaced (destructive operation)
- Updates the backup's `restoredAt` timestamp
- Cannot be undone - create a backup before restoring if needed
- May take time for large books - ensure adequate timeout settings
- Device must have access to the book being restored
