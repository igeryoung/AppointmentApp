# Register Device

## Overview
Register a new device and receive credentials for subsequent API calls.

## Endpoint
```
POST /api/devices/register
```

## Authentication
Requires server registration password (configured on server)

## Request Parameters

### Body (JSON)
- `deviceName` (string, required): Display name for the device
- `platform` (string, optional): Device platform (e.g., "iOS", "Android", "Web")
- `password` (string, required): Server registration password

**Example Request:**
```json
{
  "deviceName": "John's iPhone",
  "platform": "iOS",
  "password": "your-server-password"
}
```

## Response

### Success Response (200 OK)
Device registered successfully.

**Response Body:**
- `deviceId` (string, UUID format): Unique device identifier
- `deviceToken` (string): Authentication token for API calls
- `message` (string): Success message

**Example Response:**
```json
{
  "deviceId": "550e8400-e29b-41d4-a716-446655440000",
  "deviceToken": "abc123xyz...",
  "message": "Device registered successfully"
}
```

### Error Response (401 Unauthorized)
Invalid registration password.

**Response Body:**
```json
{
  "success": false,
  "message": "Invalid registration password"
}
```

## Error Scenarios
- **400 Bad Request**: Missing required fields (deviceName or password)
- **401 Unauthorized**: Incorrect registration password

## Usage Notes
- Save the `deviceId` and `deviceToken` securely on the device
- These credentials are required for all subsequent API calls
- Registration password is configured on the server (not per-device)
- Device name can be changed later
- Each device should register separately
