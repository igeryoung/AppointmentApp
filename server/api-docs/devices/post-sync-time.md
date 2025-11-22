# Update Device Sync Time

## Overview
Update the last sync timestamp for a device.

## Endpoint
```
POST /api/devices/sync-time
```

## Authentication
Requires device credentials (deviceId and deviceToken)

## Request Parameters

### Headers
- `X-Device-ID` (string, UUID format, required): Device identifier
- `X-Device-Token` (string, required): Device authentication token

### Body (JSON)
- `deviceId` (string, UUID format, required): Device identifier (must match header)
- `deviceToken` (string, required): Device token (must match header)

**Example Request:**
```
Headers:
X-Device-ID: 550e8400-e29b-41d4-a716-446655440000
X-Device-Token: abc123xyz...

Body:
{
  "deviceId": "550e8400-e29b-41d4-a716-446655440000",
  "deviceToken": "abc123xyz..."
}
```

## Response

### Success Response (200 OK)
Sync time updated successfully.

**Response Body:**
```json
{
  "success": true,
  "message": "Sync time updated",
  "lastSyncAt": "2025-01-20T14:22:00Z"
}
```

### Error Response (403 Forbidden)
Invalid device credentials.

## Error Scenarios
- **400 Bad Request**: Missing required fields
- **403 Forbidden**: Invalid device credentials or mismatched IDs

## Usage Notes
- Updates the `lastSyncAt` timestamp in the device record
- Used to track device activity
- Both header and body credentials must match
- Timestamp is set to current server time
