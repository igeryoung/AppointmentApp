# Create Backup

## Overview
Create a compressed file-based backup of a book including all events, notes, and drawings.

## Endpoint
```
POST /api/books/{bookId}/backup
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
- `deviceId` (string, UUID format, required): Device identifier (must match header)
- `deviceToken` (string, required): Device token (must match header)
- `backupName` (string, optional): Custom name for the backup (default: auto-generated with timestamp)

**Example Request:**
```
POST /api/books/1/backup
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...

Body:
{
  "deviceId": "550e8400-e29b-41d4-a716-446655440000",
  "deviceToken": "abc123xyz...",
  "backupName": "My Backup 2025-01-20"
}
```

## Response

### Success Response (200 OK)
Backup created successfully.

**Response Body:**
- `success` (boolean): true
- `message` (string): Success message
- `backupId` (integer): Unique identifier for the created backup

**Example Response:**
```json
{
  "success": true,
  "message": "Backup created successfully",
  "backupId": 789
}
```

### Error Response (403 Forbidden)
Unauthorized access - invalid credentials or no permission.

**Response Body:**
```json
{
  "success": false,
  "message": "Unauthorized access to book"
}
```

### Error Response (500 Internal Server Error)
Backup creation failed.

**Response Body:**
```json
{
  "success": false,
  "message": "Backup creation failed: [error details]"
}
```

## Error Scenarios
- **400 Bad Request**: Invalid bookId or missing required fields
- **403 Forbidden**: Invalid device credentials or no access to book
- **404 Not Found**: Book does not exist
- **500 Internal Server Error**: Backup creation process failed

## Usage Notes
- Creates a compressed SQL backup file (gzip format)
- Includes complete book data: book metadata, events, notes, and drawings
- Backup is stored on server and can be downloaded later
- Backup name is optional - auto-generated if not provided
- Backup files are stored in the server's backup directory
- File size information is calculated and stored
- Use the returned backupId to download or restore the backup later
- Recommended method for creating backups (replaces deprecated JSON backup)
