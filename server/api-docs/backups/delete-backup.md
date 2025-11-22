# Delete Backup

## Overview
Delete a backup (marks as deleted in database and removes the backup file from storage).

## Endpoint
```
DELETE /api/backups/{backupId}?deviceId={deviceId}&deviceToken={deviceToken}
```

## Authentication
Requires device credentials

### Query Parameters
- `deviceId` (string, UUID format, required): Device identifier
- `deviceToken` (string, required): Device authentication token

## Request Parameters

### Path Parameters
- `backupId` (integer, required): Backup identifier

**Example:**
```
DELETE /api/backups/789?deviceId=550e8400-e29b-41d4-a716-446655440000&deviceToken=abc123xyz...
```

## Response

### Success Response (200 OK)
Backup deleted successfully.

**Response Body:**
- `success` (boolean): true
- `message` (string): Success message

**Example Response:**
```json
{
  "success": true,
  "message": "Backup deleted successfully"
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

## Error Scenarios
- **400 Bad Request**: Missing deviceId or deviceToken
- **403 Forbidden**: Invalid device credentials or no access to backup
- **404 Not Found**: Backup doesn't exist or already deleted

## Usage Notes
- Performs soft delete in database (marks is_deleted flag)
- Also removes the physical backup file from storage
- Cannot be undone - the backup file is permanently deleted
- Does not affect the original book data
- Attempting to delete an already deleted backup returns 404
- Device must have access to the book associated with the backup
- File deletion errors are logged but don't fail the operation
