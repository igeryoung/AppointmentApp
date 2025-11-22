# Get Device Information

## Overview
Retrieve information about a registered device.

## Endpoint
```
GET /api/devices/{deviceId}
```

## Authentication
None (device ID in path is sufficient)

## Request Parameters

### Path Parameters
- `deviceId` (string, UUID format, required): The device identifier

**Example:**
```
GET /api/devices/550e8400-e29b-41d4-a716-446655440000
```

## Response

### Success Response (200 OK)
Device information retrieved.

**Response Body:**
- `id` (string, UUID): Device identifier
- `deviceName` (string): Device display name
- `deviceToken` (string): Authentication token
- `platform` (string): Device platform
- `registeredAt` (string, ISO 8601): Registration timestamp
- `lastSyncAt` (string, ISO 8601): Last sync timestamp
- `isActive` (boolean): Whether device is active

**Example Response:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "deviceName": "John's iPhone",
  "deviceToken": "abc123xyz...",
  "platform": "iOS",
  "registeredAt": "2025-01-15T10:30:00Z",
  "lastSyncAt": "2025-01-20T14:22:00Z",
  "isActive": true
}
```

### Error Response (404 Not Found)
Device does not exist.

## Error Scenarios
- **400 Bad Request**: Invalid UUID format
- **404 Not Found**: Device not found

## Usage Notes
- Can be used to verify device registration
- No authentication required (public device info)
- Device token is included in response but should be kept secure
- Last sync time is updated automatically by sync operations
