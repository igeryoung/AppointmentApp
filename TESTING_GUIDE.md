# Schedule Note Sync - Complete Testing Guide

**Time Required:** 10-15 minutes
**Difficulty:** Easy (copy-paste commands)

This guide walks you through setting up and testing the complete sync system from scratch.

---

## Prerequisites Check

Your system already has:
- ✅ PostgreSQL 14 installed at `/opt/homebrew/bin/psql`
- ✅ Dart SDK 3.9.2
- ✅ Flutter 3.35.4

---

## Step 1: Start PostgreSQL Service

```bash
# Start PostgreSQL service
brew services start postgresql@14

# Verify it's running (should show "started")
brew services list | grep postgresql

# Expected output:
# postgresql@14 started ...
```

**Wait 2-3 seconds for PostgreSQL to fully start.**

---

## Step 2: Create Database

```bash
# Create the database
createdb schedule_note_dev

# Verify database was created
psql -l | grep schedule_note_dev

# Expected output:
# schedule_note_dev | yangping | UTF8 | ...

# Optional: Connect to database to verify
psql schedule_note_dev

# Inside psql, type:
\dt
# Should show: "Did not find any relations." (empty database, which is correct)

# Exit psql:
\q
```

**Troubleshooting:**
- If `createdb` fails with "already exists", that's OK! Skip to Step 3.
- If connection refused, wait 5 seconds and try again (PostgreSQL still starting)

---

## Step 3: Setup Server

```bash
# Navigate to server directory
cd server

# Install dependencies (if not already done)
dart pub get

# Expected output:
# Resolving dependencies...
# Got dependencies!
```

---

## Step 4: Run Database Migrations

```bash
# Still in server/ directory
dart run main.dart --dev --migrate

# Expected output:
# 🚀 Starting Schedule Note Sync Server
#    Mode: Development
#    ServerConfig(host: localhost, port: 8080, isDevelopment: true)
#    DatabaseConfig(host: localhost, port: 5432, database: schedule_note_dev, user: postgres)
# 🔍 Checking database connection...
# ✅ Database connection established
# 🔄 Running database migrations...
# ✅ Migrations completed successfully
# ✅ Server listening on localhost:8080
```

**Important:** Keep this terminal window open! The server is now running.

**Troubleshooting:**
- If connection refused: Check PostgreSQL is running (`brew services list`)
- If authentication failed: Check your PostgreSQL user/password in `server/config/database_config.dart`

---

## Step 5: Verify Server is Running

Open a **new terminal window** (keep the server running in the first one):

```bash
# Test health check endpoint
curl http://localhost:8080/health

# Expected output:
# {"status": "healthy", "service": "schedule_note_sync_server"}

# Test root endpoint
curl http://localhost:8080/

# Expected output:
# {"message": "Schedule Note Sync Server", "version": "1.0.0"}
```

If you see these responses, **the server is working! ✅**

---

## Step 6: Test Device Registration

```bash
# Register a test device
curl -X POST http://localhost:8080/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "deviceName": "Test Device",
    "platform": "macos"
  }'

# Expected output (save the deviceId and deviceToken!):
# {
#   "deviceId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "deviceToken": "long_hash_string_here...",
#   "message": "Device registered successfully"
# }
```

**Copy the `deviceId` and `deviceToken` - you'll need them for testing!**

---

## Step 7: Verify Data in PostgreSQL

```bash
# Connect to database
psql schedule_note_dev

# Inside psql, run these queries:

-- Check devices table
SELECT device_id, device_name, platform, registered_at FROM devices;

-- Expected: One row with your test device

-- Check all tables exist
\dt

-- Expected output:
--  Schema |       Name         | Type  |  Owner
-- --------+--------------------+-------+----------
--  public | books              | table | yangping
--  public | devices            | table | yangping
--  public | events             | table | yangping
--  public | notes              | table | yangping
--  public | schedule_drawings  | table | yangping
--  public | sync_log           | table | yangping

-- Exit psql
\q
```

---

## Step 8: Test Sync with Flutter App

Now let's test the sync from your Flutter app. Create a test file or add this to your existing code:

### 8.1: Create Test File (Optional)

Create `lib/test_sync.dart`:

```dart
import 'package:flutter/material.dart';
import 'services/sync_service.dart';
import 'services/api_client.dart';
import 'services/prd_database_service.dart';
import 'models/book.dart';
import 'models/event.dart';

class SyncTestScreen extends StatefulWidget {
  @override
  _SyncTestScreenState createState() => _SyncTestScreenState();
}

class _SyncTestScreenState extends State<SyncTestScreen> {
  late SyncService syncService;
  String _status = 'Ready';
  bool _isRegistered = false;

  @override
  void initState() {
    super.initState();
    syncService = SyncService(
      dbService: PRDDatabaseService(),
      apiClient: ApiClient(baseUrl: 'http://localhost:8080'),
    );
    _checkRegistration();
  }

  Future<void> _checkRegistration() async {
    final deviceInfo = await syncService.getDeviceInfo();
    setState(() {
      _isRegistered = deviceInfo != null;
      _status = deviceInfo != null
        ? 'Device registered: ${deviceInfo.deviceId}'
        : 'Device not registered';
    });
  }

  Future<void> _registerDevice() async {
    setState(() => _status = 'Registering device...');
    try {
      final deviceInfo = await syncService.registerDevice(
        deviceName: 'Flutter Test Device',
        serverUrl: 'http://localhost:8080',
      );
      setState(() {
        _status = 'Device registered!\nID: ${deviceInfo.deviceId}';
        _isRegistered = true;
      });
    } catch (e) {
      setState(() => _status = 'Registration failed: $e');
    }
  }

  Future<void> _createTestData() async {
    setState(() => _status = 'Creating test data...');
    try {
      final dbService = PRDDatabaseService();

      // Create a book
      final book = await dbService.createBook('Test Book ${DateTime.now().second}');

      // Create an event
      final event = await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'E001',
        eventType: 'Meeting',
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Mark as dirty for sync
      await syncService.markDirty('books', book.id!);
      await syncService.markDirty('events', event.id!);

      setState(() => _status = 'Created: Book #${book.id}, Event #${event.id}');
    } catch (e) {
      setState(() => _status = 'Create failed: $e');
    }
  }

  Future<void> _syncAll() async {
    setState(() => _status = 'Syncing...');
    try {
      final result = await syncService.syncAll();

      setState(() {
        _status = '''
Sync ${result.success ? 'SUCCESS' : 'FAILED'}!
Applied: ${result.changesApplied}
Pushed: ${result.changesPushed}
Conflicts: ${result.conflicts.length}
Message: ${result.message}
''';
      });
    } catch (e) {
      setState(() => _status = 'Sync failed: $e');
    }
  }

  Future<void> _pullChanges() async {
    setState(() => _status = 'Pulling...');
    try {
      final result = await syncService.pullChanges();
      setState(() => _status = 'Pulled ${result.changesApplied} changes');
    } catch (e) {
      setState(() => _status = 'Pull failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sync Test')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(_status, style: TextStyle(fontFamily: 'monospace')),
              ),
            ),
            SizedBox(height: 16),
            if (!_isRegistered)
              ElevatedButton(
                onPressed: _registerDevice,
                child: Text('1. Register Device'),
              ),
            if (_isRegistered) ...[
              ElevatedButton(
                onPressed: _createTestData,
                child: Text('2. Create Test Data'),
              ),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: _syncAll,
                child: Text('3. Sync All'),
              ),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: _pullChanges,
                child: Text('4. Pull Changes'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

### 8.2: Run Test in Flutter App

```bash
# In a new terminal (from project root)
flutter run

# Or if you have devices running already, hot reload
# Press 'r' in the terminal where flutter run is active
```

### 8.3: Test Sequence

1. **Tap "1. Register Device"**
   - Should see: "Device registered! ID: xxx-xxx-xxx"

2. **Tap "2. Create Test Data"**
   - Should see: "Created: Book #1, Event #1"

3. **Tap "3. Sync All"**
   - Should see: "Sync SUCCESS! Applied: 0, Pushed: 2"

4. **Check server logs** (in the server terminal)
   - Should see: "✅ Full sync: 2 applied, 0 sent, 0 conflicts"

---

## Step 9: Verify Data Synced to Server

```bash
# Connect to database
psql schedule_note_dev

-- Check books table
SELECT id, name, device_id, version, is_deleted FROM books;

-- Expected: One row with your test book

-- Check events table
SELECT id, name, book_id, device_id, version FROM events;

-- Expected: One row with your test event

-- Check sync log
SELECT operation, table_name, status, synced_at FROM sync_log ORDER BY synced_at DESC LIMIT 5;

-- Expected: Recent sync operations with status 'success'

-- Exit
\q
```

If you see your data here, **sync is working! 🎉**

---

## Step 10: Test Multi-Device Sync (Simulated)

Let's simulate a second device by modifying data directly in PostgreSQL and pulling it to your Flutter app.

### 10.1: Insert Data as "Another Device"

```bash
psql schedule_note_dev
```

```sql
-- Get your device_id first
SELECT id FROM devices LIMIT 1;
-- Copy the device_id (it's a UUID)

-- Register a fake "second device"
INSERT INTO devices (id, device_name, device_token, platform, registered_at, is_active)
VALUES (
  gen_random_uuid(),
  'Fake Device 2',
  'fake_token_12345',
  'ios',
  CURRENT_TIMESTAMP,
  true
);

-- Get the new device ID
SELECT id, device_name FROM devices ORDER BY registered_at DESC LIMIT 1;
-- Copy the second device_id

-- Insert a book from the second device
INSERT INTO books (device_id, name, created_at, updated_at, synced_at, version, is_deleted)
VALUES (
  'paste_second_device_id_here',
  'Book from Device 2',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP,
  1,
  false
);

-- Verify
SELECT id, name, device_id FROM books;

-- Exit
\q
```

### 10.2: Pull Changes in Flutter App

1. **Tap "4. Pull Changes"** in your test app
2. Should see: "Pulled 1 changes"
3. Navigate to your book list screen
4. **You should see "Book from Device 2"!** 🎉

---

## Step 11: Test Conflict Detection

Let's create a conflict by modifying the same record on both server and client.

### 11.1: Modify on Client (Don't Sync Yet)

In your Flutter app:
```dart
// Manually update a book
final dbService = PRDDatabaseService();
final db = await dbService.database;

await db.rawUpdate('''
  UPDATE books
  SET name = 'Modified on Client', is_dirty = 1
  WHERE id = 1
''');
```

### 11.2: Modify on Server

```bash
psql schedule_note_dev
```

```sql
-- Update the same book
UPDATE books
SET name = 'Modified on Server',
    version = version + 1,
    updated_at = CURRENT_TIMESTAMP
WHERE id = 1;
```

### 11.3: Try to Sync

In Flutter app, **Tap "3. Sync All"**

**Expected Result:**
```
Sync FAILED!
Applied: 0
Pushed: 0
Conflicts: 1
Message: Full sync completed with conflicts
```

**This is correct!** The version mismatch was detected as a conflict.

---

## Step 12: Cleanup (Optional)

```bash
# Stop the server
# In the server terminal, press Ctrl+C

# Stop PostgreSQL (if desired)
brew services stop postgresql@14

# Drop test database (if desired)
dropdb schedule_note_dev
```

---

## Verification Checklist

✅ **Server Setup**
- [ ] PostgreSQL service started
- [ ] Database created
- [ ] Migrations ran successfully
- [ ] Server responds to `/health`

✅ **Device Registration**
- [ ] Device registered via curl
- [ ] Device visible in PostgreSQL `devices` table
- [ ] Device registered via Flutter app

✅ **Sync Operations**
- [ ] Created test data in Flutter
- [ ] Pushed data to server successfully
- [ ] Data visible in PostgreSQL tables
- [ ] Pulled server data to client
- [ ] Sync log shows operations

✅ **Multi-Device**
- [ ] Simulated second device
- [ ] Pulled data from "other device"
- [ ] Data appears in Flutter app

✅ **Conflict Detection**
- [ ] Created version conflict
- [ ] Conflict detected by sync system
- [ ] Conflict reported in result

---

## Quick Reference Commands

### Server Control
```bash
# Start server
cd server && dart run main.dart --dev

# With migrations
cd server && dart run main.dart --dev --migrate
```

### Database Queries
```bash
# Connect
psql schedule_note_dev

# Quick checks
SELECT count(*) FROM books;
SELECT count(*) FROM events;
SELECT * FROM sync_log ORDER BY synced_at DESC LIMIT 5;
SELECT device_name, last_sync_at FROM devices;
```

### API Testing
```bash
# Health check
curl http://localhost:8080/health

# Register device
curl -X POST http://localhost:8080/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "Test", "platform": "macos"}'
```

---

## Troubleshooting Common Issues

### Issue: "Connection refused" to PostgreSQL
**Solution:**
```bash
# Check if running
brew services list | grep postgresql

# Start if not running
brew services start postgresql@14

# Wait 5 seconds and try again
```

### Issue: "Database does not exist"
**Solution:**
```bash
createdb schedule_note_dev
```

### Issue: Server fails to start
**Solution:**
1. Check port 8080 is free: `lsof -i :8080`
2. Kill existing process: `kill -9 <PID>`
3. Check PostgreSQL credentials in `server/config/database_config.dart`

### Issue: Flutter app can't connect to server
**Solution:**
1. Verify server is running: `curl http://localhost:8080/health`
2. If testing on iOS Simulator: use `http://localhost:8080`
3. If testing on Android Emulator: use `http://10.0.2.2:8080`
4. If testing on physical device: use your Mac's IP address `http://192.168.x.x:8080`

### Issue: "Device not registered" error
**Solution:**
```bash
# Check device_info table in SQLite
flutter run
# Then in Dart/Flutter:
final db = await PRDDatabaseService().database;
final result = await db.query('device_info');
print(result);

# If empty, register device again
```

---

## Testing Tips

1. **Use PostgreSQL GUI**: Install pgAdmin or Postico for easier database inspection
2. **Server Logs**: Keep server terminal visible to see sync operations in real-time
3. **Flutter DevTools**: Use to inspect SQLite database state
4. **Network Inspector**: Use to see HTTP requests/responses
5. **Multiple Devices**: Test on iOS Simulator + Android Emulator simultaneously

---

## Success Criteria

Your sync system is working correctly if:

✅ Data created on client appears in PostgreSQL
✅ Data created in PostgreSQL appears in client
✅ Changes sync in both directions
✅ Conflicts are detected when they occur
✅ Sync log records all operations
✅ Multiple devices can sync independently

---

**Congratulations!** 🎉 Your PostgreSQL-based sync system is now fully tested and operational!

Next steps:
- Deploy server to production
- Add more devices
- Implement conflict resolution UI
- Set up automatic background sync

Refer to `SYNC_GUIDE.md` for production deployment and advanced features.
