# Books Upload API Unit Tests

Unit tests for the `/api/books/upload` JSON-based backup API endpoint.

## Overview

The `/api/books/upload` endpoint allows devices to upload complete book backups in JSON format. This is one of two backup methods supported by the server:

1. **JSON-based backup** (`POST /api/books/upload`) - Stores backup data as JSONB in PostgreSQL
2. **File-based backup** (`POST /api/books/{bookId}/backup`) - Stores compressed SQL files on disk

Both methods are fully supported and serve different use cases.

## Test Coverage

### Authentication & Authorization
- ✅ Missing device ID header (401)
- ✅ Missing device token header (401)
- ✅ Invalid device credentials (403)

### Request Validation
- ✅ Missing required fields (`bookId`, `backupName`, `backupData`)
- ✅ Invalid field types
- ✅ Data structure validation (book, events, notes, drawings)

### Success Scenarios
- ✅ Valid backup upload returns 200 with backupId
- ✅ Correct response structure
- ✅ Proper Content-Type header

### Error Handling
- ✅ Database connection failures (500)
- ✅ Malformed JSON requests
- ✅ Large backup data
- ✅ Empty backup data

### Security
- ✅ SQL injection prevention
- ✅ XSS prevention
- ✅ Device ownership validation

### Performance
- ✅ Handle 100+ events
- ✅ Handle complex note data with 1000+ points

## Running the Tests

### Run all unit tests
```bash
cd /home/user/AppointmentApp/server
dart test unit-test/books_upload/books_upload_test.dart
```

### Run specific test group
```bash
dart test unit-test/books_upload/books_upload_test.dart --name "Authentication"
```

### Run with verbose output
```bash
dart test unit-test/books_upload/books_upload_test.dart --reporter expanded
```

## API Usage Example

### Request

```bash
curl -X POST https://localhost:8080/api/books/upload \
  -H "Content-Type: application/json" \
  -H "x-device-id: a1b2c3d4-e5f6-7890-abcd-ef1234567890" \
  -H "x-device-token: your-secure-token" \
  -d '{
    "bookId": 1,
    "backupName": "My Schedule Backup 2025-11-23",
    "backupData": {
      "book": {
        "id": 1,
        "device_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "My Schedule",
        "book_uuid": "book-uuid-123",
        "created_at": "2025-11-01T00:00:00Z",
        "updated_at": "2025-11-23T00:00:00Z",
        "synced_at": "2025-11-23T00:00:00Z",
        "version": 1,
        "is_deleted": false
      },
      "events": [
        {
          "id": 1,
          "book_id": 1,
          "device_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
          "name": "Meeting with Team",
          "record_number": "REC001",
          "event_type": "appointment",
          "start_time": "2025-11-23T10:00:00Z",
          "end_time": "2025-11-23T11:00:00Z",
          "created_at": "2025-11-20T00:00:00Z",
          "updated_at": "2025-11-20T00:00:00Z",
          "synced_at": "2025-11-20T00:00:00Z",
          "version": 1,
          "is_deleted": false
        }
      ],
      "notes": [
        {
          "id": 1,
          "event_id": 1,
          "strokes_data": "[{\"points\":[{\"x\":100,\"y\":200}]}]",
          "created_at": "2025-11-20T00:00:00Z",
          "updated_at": "2025-11-20T00:00:00Z",
          "version": 1,
          "is_deleted": false
        }
      ],
      "drawings": [
        {
          "id": 1,
          "book_id": 1,
          "date": "2025-11-23T00:00:00Z",
          "view_mode": 0,
          "strokes_data": "[{\"points\":[{\"x\":50,\"y\":100}]}]",
          "created_at": "2025-11-20T00:00:00Z",
          "updated_at": "2025-11-20T00:00:00Z",
          "version": 1,
          "is_deleted": false
        }
      ]
    }
  }'
```

### Success Response (200)

```json
{
  "success": true,
  "message": "Backup uploaded successfully",
  "backupId": 123
}
```

### Error Response (401 - Missing Credentials)

```json
{
  "success": false,
  "message": "Missing device credentials"
}
```

### Error Response (403 - Invalid Credentials)

```json
{
  "success": false,
  "message": "Invalid device credentials"
}
```

### Error Response (500 - Upload Failed)

```json
{
  "success": false,
  "message": "Failed to upload backup: Database connection error"
}
```

## Data Structure Requirements

### backupData Object

```typescript
{
  book: {
    id: number,
    device_id: string,
    name: string,
    book_uuid: string,
    created_at: string (ISO 8601),
    updated_at: string (ISO 8601),
    synced_at: string (ISO 8601),
    version: number,
    is_deleted: boolean
  },
  events: Array<{
    id: number,
    book_id: number,
    device_id: string,
    name: string,
    record_number: string,
    event_type: string,
    start_time: string (ISO 8601),
    end_time: string (ISO 8601),
    created_at: string (ISO 8601),
    updated_at: string (ISO 8601),
    synced_at: string (ISO 8601),
    version: number,
    is_deleted: boolean
  }>,
  notes: Array<{
    id: number,
    event_id: number,
    strokes_data: string (JSON),
    created_at: string (ISO 8601),
    updated_at: string (ISO 8601),
    version: number,
    is_deleted: boolean
  }>,
  drawings: Array<{
    id: number,
    book_id: number,
    date: string (ISO 8601),
    view_mode: number (0=Day, 1=3-Day, 2=Week),
    strokes_data: string (JSON),
    created_at: string (ISO 8601),
    updated_at: string (ISO 8601),
    version: number,
    is_deleted: boolean
  }>
}
```

## Related Endpoints

- `GET /api/books/list` - List all JSON-based backups
- `GET /api/books/download/{backupId}` - Download JSON backup data
- `POST /api/books/restore/{backupId}` - Restore from JSON backup
- `DELETE /api/books/{backupId}` - Delete backup

## Alternative: File-Based Backup API

For larger backups, consider using the file-based backup API:

- `POST /api/books/{bookId}/backup` - Create compressed SQL backup
- `GET /api/books/{bookId}/backups` - List file-based backups
- `GET /api/backups/{backupId}/download` - Download backup file (streaming)
- `POST /api/backups/{backupId}/restore` - Restore from file backup
- `DELETE /api/backups/{backupId}` - Delete file backup

## Implementation Details

### Server Code
- `server/lib/routes/book_backup_routes.dart` - Route handlers
- `server/lib/services/book_backup_service.dart` - Business logic

### Database
- Table: `book_backups`
- Stores backup metadata and JSON data in JSONB column

### Security
- Device authentication via `x-device-id` and `x-device-token` headers
- Device ownership validation for book access
- SQL injection prevention via parameterized queries
- XSS prevention via proper JSON encoding

## Notes

- The `/api/books/upload` endpoint is **NOT deprecated** (as of 2025-11-23)
- Both JSON-based and file-based backup methods are fully supported
- Choose JSON-based for smaller backups or when you need to query backup data
- Choose file-based for larger backups or better compression
