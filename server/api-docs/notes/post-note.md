# Create or Update Note

## Overview
Create a new handwriting note or update an existing one with optimistic locking support.

## Endpoint
```
POST /api/books/{bookId}/events/{eventId}/note
```

## Authentication
Requires device credentials

### Headers
- `X-Device-ID` (string, UUID format, required): Device identifier
- `X-Device-Token` (string, required): Device authentication token

## Request Parameters

### Path Parameters
- `bookId` (integer, required): Book identifier
- `eventId` (integer, required): Event identifier

### Body (JSON)
- `pagesData` (string, optional): JSON string containing multi-page note data (preferred, new format)
- `strokesData` (string, optional): JSON string containing stroke/drawing data (legacy format, for backward compatibility)
- `version` (integer, optional): Expected version number for optimistic locking (required for updates)
- `eventData` (object, optional): Event data for auto-creating event if it doesn't exist

**Note:** Either `pagesData` or `strokesData` must be provided. `pagesData` is preferred for new implementations.

**EventData Object Fields (all optional, used for event auto-creation):**
- `id` (integer): Event identifier (must match eventId in path)
- `book_id` (integer): Book identifier (must match bookId in path)
- `name` (string): Event name
- `record_number` (string): Record number
- `event_type` (string): Event type (e.g., "appointment")
- `start_time` (integer): Start time in Unix seconds
- `end_time` (integer): End time in Unix seconds (optional)
- `created_at` (integer): Creation timestamp in Unix seconds
- `updated_at` (integer): Last update timestamp in Unix seconds
- `is_removed` (boolean): Whether event is removed
- `removal_reason` (string): Reason for removal (optional)
- `original_event_id` (integer): Original event ID if rescheduled (optional)
- `new_event_id` (integer): New event ID if rescheduled (optional)

**Example Request (create new note with pagesData):**
```
POST /api/books/1/events/42/note
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...

Body:
{
  "pagesData": "[{\"page\":1,\"strokes\":[{\"points\":[{\"x\":100,\"y\":200}]}]}]"
}
```

**Example Request (create note with legacy strokesData):**
```json
{
  "strokesData": "[{\"points\":[{\"x\":100,\"y\":200}]}]"
}
```

**Example Request (update existing note):**
```json
{
  "pagesData": "[{\"page\":1,\"strokes\":[{\"points\":[{\"x\":150,\"y\":250}]}]}]",
  "version": 3
}
```

**Example Request (create note with event auto-creation):**
```json
{
  "pagesData": "[{\"page\":1,\"strokes\":[{\"points\":[{\"x\":100,\"y\":200}]}]}]",
  "eventData": {
    "id": 42,
    "book_id": 1,
    "name": "Patient Appointment",
    "record_number": "REC001",
    "event_type": "appointment",
    "start_time": 1705838400,
    "end_time": 1705842000,
    "created_at": 1705838000,
    "updated_at": 1705838000,
    "is_removed": false
  }
}
```

## Response

### Success Response (200 OK)
Note created or updated successfully.

**Response Body:**
- `success` (boolean): Always true
- `note` (object): The saved note data
- `version` (integer): New version number

**Example Response:**
```json
{
  "success": true,
  "note": {
    "id": 123,
    "eventId": 42,
    "strokesData": "[{\"points\":[{\"x\":150,\"y\":250}]}]",
    "createdAt": "2025-01-15T10:30:00Z",
    "updatedAt": "2025-01-20T14:22:00Z",
    "version": 4
  },
  "version": 4
}
```

### Error Response (409 Conflict)
Version conflict - the note was modified by another device.

**Response Body:**
- `success` (boolean): false
- `conflict` (boolean): true
- `serverVersion` (integer): Current version on server
- `serverNote` (object): Current note data on server

**Example Response:**
```json
{
  "success": false,
  "conflict": true,
  "serverVersion": 5,
  "serverNote": {
    "id": 123,
    "eventId": 42,
    "strokesData": "[{\"points\":[{\"x\":200,\"y\":300}]}]",
    "version": 5
  }
}
```

### Error Response (403 Forbidden)
Unauthorized access.

## Error Scenarios
- **400 Bad Request**: Missing strokesData or invalid format
- **403 Forbidden**: Invalid device credentials or no access to book
- **404 Not Found**: Book or event does not exist
- **409 Conflict**: Version mismatch (optimistic locking failure)

## Usage Notes
- For creating a new note, omit the `version` parameter
- For updating, always include the current `version` to prevent conflicts
- On conflict (409), fetch the latest note, merge if needed, and retry with correct version
- Use `pagesData` for new implementations (supports multi-page notes)
- `strokesData` is maintained for backward compatibility with older clients
- Both `pagesData` and `strokesData` should be valid JSON strings
- Server automatically increments version on each save
- First save creates version 1
- **Event Auto-Creation**: If the event doesn't exist and `eventData` is provided, the server will automatically create the event before saving the note. This is useful for offline-first scenarios where notes are created before events are synced to the server.
