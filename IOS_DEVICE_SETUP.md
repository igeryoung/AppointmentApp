# iOS Physical Device - Sync Setup Guide

## Problem Fixed

The sync system was only accessible via `localhost:8080`, which doesn't work for physical devices. Now the server binds to `0.0.0.0` and accepts connections from any device on your network.

---

## Step-by-Step Instructions

### 1. Find Your Mac's IP Address

**Option A: System Preferences**
1. Open System Preferences → Network
2. Select your active connection (Wi-Fi or Ethernet)
3. Look for "IP Address" - it should be something like:
   - `192.168.1.x` (common home routers)
   - `10.0.x.x` (some routers)
   - `169.254.x.x` (link-local, may work)

**Option B: Terminal**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

Your current IP appears to be: **169.254.230.40**

---

### 2. Verify Server is Running

Server should be running on `0.0.0.0:8080` (all interfaces).

Check server logs for:
```
✅ Server listening on 0.0.0.0:8080
```

If you see `localhost:8080`, restart the server:
```bash
cd server
dart run main.dart --dev
```

---

### 3. Test Network Connectivity

**From your Mac**, test the server:
```bash
curl http://169.254.230.40:8080/health
```

Should return:
```json
{"status": "healthy", "service": "schedule_note_sync_server"}
```

---

### 4. Configure iOS App

1. **Deploy app to your iPhone/iPad**
   ```bash
   flutter run -d <your-device-id>
   ```

2. **Open Sync Test Screen**
   - Tap the sync icon (🔄) in the app bar

3. **Enter Server URL**
   - In the "Server URL" field, enter:
   ```
   http://169.254.230.40:8080
   ```
   - Tap "Update Server URL"

4. **Register Device**
   - Tap "1. Register Device"
   - Should see: "Device registered! ID: xxxxxxxx..."

---

### 5. Test Sync

Now test the sync workflow:

1. **Create Test Data** - Tap "2. Create Test Data"
2. **Push Changes** - Tap "3. Push Changes"
3. **Pull Changes** - Tap "4. Pull Changes"
4. **Full Sync** - Tap "5. Full Sync (Push + Pull)"

---

## Troubleshooting

### Registration Fails - "Connection refused"

**Cause:** iOS device can't reach your Mac

**Solutions:**
1. Ensure both devices are on the **same WiFi network**
2. Check macOS firewall:
   - System Preferences → Security & Privacy → Firewall
   - Allow incoming connections for `dart`
3. Try pinging from iOS (use a network utility app)

---

### Registration Fails - "Timeout"

**Cause:** Server not responding

**Solutions:**
1. Verify server is running: `curl http://169.254.230.40:8080/health`
2. Check server logs for errors
3. Restart server

---

### Wrong IP Address

If `169.254.230.40` doesn't work, your Mac might have multiple interfaces.

**Find the correct IP:**
```bash
ifconfig | grep "inet "
```

Look for an IP that matches your WiFi router's subnet (usually `192.168.x.x` or `10.0.x.x`).

---

### macOS Firewall Blocking

If firewall is enabled:

1. System Preferences → Security & Privacy → Firewall
2. Click "Firewall Options"
3. Find `dart` in the list
4. Set to "Allow incoming connections"
5. Or temporarily disable firewall for testing

---

## Network Architecture

```
┌─────────────────┐                    ┌──────────────────┐
│   iPhone/iPad   │                    │   Mac (Server)   │
│   (iOS)         │◄──── WiFi ────────►│   0.0.0.0:8080   │
│                 │                    │   PostgreSQL     │
│ App sends to:   │                    │   169.254.230.40 │
│ 169.254.230.40  │                    │                  │
└─────────────────┘                    └──────────────────┘
```

**Before:** Server listened on `localhost` (127.0.0.1) only
**After:** Server listens on `0.0.0.0` (all network interfaces)

---

## Testing Checklist

- [ ] Server running on 0.0.0.0:8080
- [ ] Found Mac's IP address (169.254.230.40)
- [ ] Both devices on same WiFi
- [ ] Can curl server from Mac
- [ ] macOS firewall allows dart
- [ ] iOS app deployed to physical device
- [ ] Server URL updated in app
- [ ] Device registration successful
- [ ] Sync operations working

---

## Quick Test Script

From your Mac:
```bash
# 1. Check server
curl http://169.254.230.40:8080/health

# 2. Register a test device
curl -X POST http://169.254.230.40:8080/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "iOS Device", "platform": "ios"}'

# 3. Check PostgreSQL
psql -p 5433 -d schedule_note_dev -c "SELECT * FROM devices;"
```

---

## Production Notes

For production deployment:

1. **Use HTTPS** - Don't use http:// in production
2. **Deploy to cloud** - DigitalOcean, AWS, etc.
3. **Use domain name** - Not IP address
4. **Add authentication** - User accounts + device tokens
5. **Rate limiting** - Prevent abuse

---

## Success!

Once you see "Device registered!" on your iOS device, the sync system is working!

Next steps:
- Create data on iOS → should sync to server
- Create data on server → should pull to iOS
- Test multi-device sync (iOS + macOS simultaneously)

Happy syncing! 🎉
