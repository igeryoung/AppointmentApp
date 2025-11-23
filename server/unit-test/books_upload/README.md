# Books Upload API Unit Tests

Unit tests for the `/api/books/upload` JSON-based backup API endpoint.

## Overview

The `/api/books/upload` endpoint allows devices to upload complete book backups in JSON format.

## Running Tests

```bash
cd server
dart test unit-test/books_upload/books_upload_test.dart
```

## Test Coverage

- **Request Validation**: Required fields, data types, structure
- **Response Structure**: Success and error response formats
- **Security**: SQL injection and XSS prevention
- **Data Handling**: Empty data, complex data serialization

## API Usage

### Request
```bash
curl -X POST https://localhost:8080/api/books/upload \
  -H "Content-Type: application/json" \
  -H "x-device-id: your-device-id" \
  -H "x-device-token: your-device-token" \
  -d '{
    "bookId": 1,
    "backupName": "My Backup",
    "backupData": {
      "book": {...},
      "events": [...],
      "notes": [...],
      "drawings": [...]
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

### Error Response (401)
```json
{
  "success": false,
  "error": "MISSING_CREDENTIALS",
  "message": "Authentication required"
}
```

## Related Endpoints

- `POST /api/books/{bookUuid}/backup` - File-based backup (compressed SQL)
- `GET /api/books/list` - List JSON-based backups
- `GET /api/books/download/{backupId}` - Download JSON backup data
- `POST /api/books/restore/{backupId}` - Restore from backup
