# Download Backup File

## Overview
Download a backup file using streaming for large files (gzip compressed SQL format).

## Endpoint
```
GET /api/backups/{backupId}/download?deviceId={deviceId}&deviceToken={deviceToken}
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
GET /api/backups/789/download?deviceId=550e8400-e29b-41d4-a716-446655440000&deviceToken=abc123xyz...
```

## Response

### Success Response (200 OK)
Backup file download stream.

**Content-Type:** `application/gzip`

**Response Headers:**
- `Content-Disposition`: `attachment; filename="backup_{backupId}.sql.gz"`
- `Content-Type`: `application/gzip`

**Response Body:**
Binary data (gzip compressed SQL file)

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
Backup not found or file missing.

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
- **404 Not Found**: Backup doesn't exist or backup file is missing

## Usage Notes
- Returns a streaming response for efficient handling of large files
- File is in gzip compressed SQL format
- Can be decompressed and imported into PostgreSQL
- Use appropriate streaming/chunked download on client side for large backups
- Filename includes the backup ID for easy identification
- Only file-based backups can be downloaded (not legacy JSON backups)
- Device must have access to the book associated with the backup
