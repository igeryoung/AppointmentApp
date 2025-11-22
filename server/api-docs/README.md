# API Documentation

Complete API reference for the Schedule Note Sync Server.

## Overview

This API enables synchronization of schedule data, handwriting notes, and drawings across devices. The server uses device-based authentication and supports optimistic locking for conflict resolution.

**Base URL:** `http://localhost:8080` (development)

**Authentication:** Device credentials via headers (`X-Device-ID` and `X-Device-Token`)

## API Groups

### Health & Information (4 endpoints)
Server health, metadata, and documentation endpoints.

- [GET /health](health/get-health.md) - Health check
- [GET /](health/get-root.md) - Server information
- [GET /openapi.yaml](health/get-openapi-spec.md) - OpenAPI specification
- [GET /docs](health/get-docs.md) - Swagger UI documentation

### Device Management (3 endpoints)
Device registration and credential management.

- [POST /api/devices/register](devices/post-register.md) - Register a new device
- [GET /api/devices/{deviceId}](devices/get-device-info.md) - Get device information
- [POST /api/devices/sync-time](devices/post-sync-time.md) - Update device sync time

### Notes API (4 endpoints)
Server-Store API for handwriting notes (1:1 with events).

- [GET /api/books/{bookId}/events/{eventId}/note](notes/get-note.md) - Get note for event
- [POST /api/books/{bookId}/events/{eventId}/note](notes/post-note.md) - Create or update note
- [DELETE /api/books/{bookId}/events/{eventId}/note](notes/delete-note.md) - Delete note
- [POST /api/notes/batch](notes/post-batch-notes.md) - Batch get notes

### Drawings API (4 endpoints)
Server-Store API for schedule overlay drawings.

- [GET /api/books/{bookId}/drawings](drawings/get-drawing.md) - Get drawing
- [POST /api/books/{bookId}/drawings](drawings/post-drawing.md) - Create or update drawing
- [DELETE /api/books/{bookId}/drawings](drawings/delete-drawing.md) - Delete drawing
- [POST /api/drawings/batch](drawings/post-batch-drawings.md) - Batch get drawings

### Backups API (5 endpoints)
File-based backup and restore operations.

- [POST /api/books/{bookId}/backup](backups/post-create-backup.md) - Create backup
- [GET /api/books/{bookId}/backups](backups/get-list-backups.md) - List backups for book
- [GET /api/backups/{backupId}/download](backups/get-download-backup.md) - Download backup file
- [POST /api/backups/{backupId}/restore](backups/post-restore-backup.md) - Restore from backup
- [DELETE /api/backups/{backupId}](backups/delete-backup.md) - Delete backup

### Batch Operations (1 endpoint)
Atomic batch save operations.

- [POST /api/batch/save](batch/post-batch-save.md) - Batch save notes and drawings

## Quick Start

### 1. Register a Device
```bash
curl -X POST http://localhost:8080/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "deviceName": "My Device",
    "platform": "iOS",
    "password": "your-server-password"
  }'
```

Save the returned `deviceId` and `deviceToken`.

### 2. Use Device Credentials
Include credentials in subsequent requests:
```bash
curl -X GET http://localhost:8080/api/books/1/events/42/note \
  -H "X-Device-ID: your-device-id" \
  -H "X-Device-Token: your-device-token"
```

## Key Concepts

### Authentication
- All protected endpoints require device credentials
- Pass credentials via `X-Device-ID` and `X-Device-Token` headers
- Registration password is configured server-side

### Optimistic Locking
- Notes and drawings use version numbers for conflict detection
- Include current version when updating
- Server returns 409 Conflict if version doesn't match
- On conflict, fetch latest version, merge changes, and retry

### Soft Deletes
- DELETE operations mark items as deleted (is_deleted flag)
- Deleted items don't appear in GET requests
- Data is retained in database for recovery

### Data Format
- StrokesData fields contain JSON strings
- Dates use ISO 8601 format
- IDs are integers except deviceId (UUID)

### View Modes
For drawings:
- 0 = Day view
- 1 = 3-Day view
- 2 = Week view

## Error Handling

Common HTTP status codes:
- **200 OK** - Request succeeded
- **400 Bad Request** - Invalid parameters or missing required fields
- **401 Unauthorized** - Missing authentication
- **403 Forbidden** - Invalid credentials or unauthorized access
- **404 Not Found** - Resource doesn't exist
- **409 Conflict** - Version conflict (optimistic locking)
- **413 Payload Too Large** - Request exceeds size limits
- **500 Internal Server Error** - Server error

## Additional Resources

- **OpenAPI Spec:** [/openapi.yaml](http://localhost:8080/openapi.yaml)
- **Interactive Docs:** [/docs](http://localhost:8080/docs)
- **Architecture Documentation:** `/doc/Server-Store/`
- **Server README:** `/server/README.md`

## Notes

- This documentation covers current (non-deprecated) APIs only
- Legacy sync API and deprecated JSON backup endpoints are excluded
- For complete API history, see `/server/openapi.yaml`
- Server runs on port 8080 by default
