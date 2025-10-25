# Schedule Note - Multi-Device Sync Guide

Complete guide for setting up and using PostgreSQL-based multi-device synchronization.

## Architecture

```
┌─────────────────┐                    ┌──────────────────┐                    ┌─────────────────┐
│   Device A      │                    │  Server          │                    │   Device B      │
│   (SQLite)      │◄──── REST API ────►│  (PostgreSQL)    │◄──── REST API ────►│   (SQLite)      │
│                 │                    │                  │                    │                 │
│ • Books         │  Push Changes      │ • Books          │  Pull Changes      │ • Books         │
│ • Events        │  Pull Changes      │ • Events         │  Push Changes      │ • Events        │
│ • Notes         │  Conflict Detect   │ • Notes          │  Conflict Resolve  │ • Notes         │
│ • Drawings      │                    │ • Drawings       │                    │ • Drawings      │
└─────────────────┘                    └──────────────────┘                    └─────────────────┘
```

## Features

✅ **Bidirectional Sync** - Automatic push/pull in both directions
✅ **Conflict Detection** - Version-based conflict tracking
✅ **Offline-First** - Works without connection, syncs when available
✅ **Multi-Device** - Sync data across iOS, Android, Web, Desktop
✅ **Incremental Sync** - Only sync changes since last sync
✅ **Transaction Safety** - Atomic operations with rollback
✅ **Audit Trail** - Complete sync history logging

## Prerequisites

### Server
- PostgreSQL 13+ installed
- Dart SDK 3.9.2+ installed
- Network accessible server (or localhost for testing)

### Client
- Flutter app with the sync-enabled codebase
- Network connectivity
- Device registration

## Setup Instructions

### Step 1: Server Setup

#### 1.1 Install PostgreSQL

**macOS:**
```bash
brew install postgresql@15
brew services start postgresql@15
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
```

#### 1.2 Create Database

```bash
# Connect to PostgreSQL
psql postgres

# Create database
CREATE DATABASE schedule_note_dev;

# Create user (optional)
CREATE USER schedule_note WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE schedule_note_dev TO schedule_note;

# Exit
\q
```

#### 1.3 Install Server Dependencies

```bash
cd server
dart pub get
```

#### 1.4 Run Migrations

```bash
dart run main.dart --dev --migrate
```

#### 1.5 Start Server

```bash
# Development mode (localhost:8080)
dart run main.dart --dev

# Production mode (reads from environment variables)
dart run main.dart
```

Server should now be running on `http://localhost:8080`

### Step 2: Client Setup

The client is already set up in your Flutter app! Just need to configure it.

#### 2.1 Configure Server URL

Create a configuration file or use environment variables:

```dart
// lib/config/sync_config.dart
class SyncConfig {
  static const String serverUrl = 'http://localhost:8080';  // Development
  // static const String serverUrl = 'https://your-server.com';  // Production
}
```

#### 2.2 Initialize Sync Service

In your app initialization (e.g., `main.dart` or app startup):

```dart
import 'package:schedule_note_app/services/sync_service.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/prd_database_service.dart';

// Initialize services
final dbService = PRDDatabaseService();
final apiClient = ApiClient(baseUrl: SyncConfig.serverUrl);
final syncService = SyncService(
  dbService: dbService,
  apiClient: apiClient,
);
```

## Usage

### Register Device (First Time Only)

Each device needs to register once:

```dart
try {
  final deviceInfo = await syncService.registerDevice(
    deviceName: 'My iPhone',  // or Platform.localHostname
    serverUrl: SyncConfig.serverUrl,
  );

  print('Device registered: ${deviceInfo.deviceId}');
} catch (e) {
  print('Registration failed: $e');
}
```

### Perform Full Sync

Sync all changes in both directions:

```dart
final result = await syncService.syncAll();

if (result.success) {
  print('Sync completed!');
  print('Changes applied: ${result.changesApplied}');
  print('Changes pushed: ${result.changesPushed}');
} else {
  print('Sync failed: ${result.message}');
}

// Handle conflicts
if (result.hasConflicts) {
  for (final conflict in result.conflicts) {
    print('Conflict: ${conflict.tableName}/${conflict.recordId}');
    // Show conflict resolution UI to user
  }
}
```

### Pull Only (Download Server Changes)

```dart
final result = await syncService.pullChanges();
print('Pulled ${result.changesApplied} changes');
```

### Push Only (Upload Local Changes)

```dart
final result = await syncService.pushChanges();
print('Pushed ${result.changesPushed} changes');
```

### Automatic Sync

Set up periodic sync:

```dart
import 'dart:async';

Timer? _syncTimer;

void startAutoSync() {
  // Sync every 5 minutes
  _syncTimer = Timer.periodic(Duration(minutes: 5), (_) async {
    final deviceInfo = await syncService.getDeviceInfo();
    if (deviceInfo != null) {
      await syncService.syncAll();
    }
  });
}

void stopAutoSync() {
  _syncTimer?.cancel();
  _syncTimer = null;
}
```

### Sync on App Resume

```dart
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late SyncService syncService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize sync service
    syncService = SyncService(
      dbService: PRDDatabaseService(),
      apiClient: ApiClient(baseUrl: SyncConfig.serverUrl),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground, sync
      syncService.syncAll();
    }
  }

  // ...
}
```

## Conflict Resolution

When conflicts occur, you'll receive them in the `SyncResult`:

```dart
final result = await syncService.syncAll();

if (result.hasConflicts) {
  for (final conflict in result.conflicts) {
    // Show UI for user to choose resolution
    await showConflictDialog(
      context: context,
      conflict: conflict,
      onResolve: (resolution) async {
        final deviceInfo = await syncService.getDeviceInfo();

        await apiClient.resolveConflict(
          deviceId: deviceInfo!.deviceId,
          deviceToken: deviceInfo.deviceToken,
          tableName: conflict.tableName,
          recordId: conflict.recordId,
          resolution: resolution,  // 'use_local', 'use_server', 'merge'
        );

        // Re-sync after resolution
        await syncService.syncAll();
      },
    );
  }
}
```

## Monitoring and Debugging

### Check Sync Status

```dart
final deviceInfo = await syncService.getDeviceInfo();
if (deviceInfo == null) {
  print('Device not registered');
} else {
  print('Device ID: ${deviceInfo.deviceId}');
  print('Server: ${deviceInfo.serverUrl}');
}
```

### Server Logs

The server logs all sync operations. Check the console output:

```
✅ Device registered: abc-123 (iPhone 15)
🔄 Full sync: 5 applied, 10 sent, 0 conflicts
✅ Pull: 15 changes sent to device xyz-456
```

### Database Inspection

**Server (PostgreSQL):**
```sql
-- View sync log
SELECT * FROM sync_log ORDER BY synced_at DESC LIMIT 10;

-- View devices
SELECT * FROM devices WHERE is_active = true;

-- Check data counts
SELECT 'books' as table_name, count(*) FROM books
UNION ALL
SELECT 'events', count(*) FROM events
UNION ALL
SELECT 'notes', count(*) FROM notes;
```

**Client (SQLite):**
```dart
final db = await dbService.database;

// Check dirty records
final dirtyBooks = await db.query('books', where: 'is_dirty = 1');
print('Dirty books: ${dirtyBooks.length}');

// Check device info
final deviceInfo = await db.query('device_info');
print('Device: $deviceInfo');
```

## Best Practices

### 1. Sync Timing
- ✅ Sync when app starts
- ✅ Sync when app resumes from background
- ✅ Sync after major data changes
- ✅ Periodic background sync (every 5-15 minutes)
- ❌ Don't sync on every single change (too frequent)

### 2. Error Handling
```dart
try {
  final result = await syncService.syncAll();
  if (!result.success) {
    // Show user-friendly error message
    showSnackBar('Sync failed: ${result.message}');
  }
} on SocketException {
  showSnackBar('No internet connection');
} on TimeoutException {
  showSnackBar('Server not responding');
} catch (e) {
  showSnackBar('Unexpected error: $e');
}
```

### 3. User Feedback
Show sync status in UI:
```dart
bool _isSyncing = false;

Future<void> _sync() async {
  setState(() => _isSyncing = true);
  try {
    final result = await syncService.syncAll();
    if (result.success) {
      showSnackBar('✅ Synced ${result.changesApplied} changes');
    }
  } finally {
    setState(() => _isSyncing = false);
  }
}
```

### 4. Conflict Prevention
- Minimize concurrent edits on multiple devices
- Sync frequently to reduce conflict window
- Design UI to clearly show which device last modified data

## Troubleshooting

### Device can't register
- ✅ Check server is running: `curl http://localhost:8080/health`
- ✅ Check network connectivity
- ✅ Verify server URL is correct

### Sync fails with 403 Forbidden
- ✅ Device token might be invalid
- ✅ Re-register the device

### Changes not syncing
- ✅ Check `is_dirty` flag is set on modified records
- ✅ Verify network connection
- ✅ Check server logs for errors

### Conflicts keep occurring
- ✅ Check system time is correct on all devices
- ✅ Ensure all devices sync regularly
- ✅ Review conflict resolution strategy

## Security Considerations

### Production Deployment

1. **Enable SSL/TLS**
   - Use HTTPS for all API communication
   - Configure PostgreSQL SSL mode

2. **Secure Device Tokens**
   - Tokens are SHA256 hashed
   - Store tokens securely on device
   - Implement token expiration/refresh

3. **Rate Limiting**
   - Add rate limiting to API endpoints
   - Prevent abuse

4. **Data Encryption**
   - Consider encrypting sensitive data at rest
   - Use encrypted connections

5. **Authentication**
   - Add user authentication layer
   - Multi-device per user support

## Performance Tips

- Use indexed columns for sync queries
- Batch sync operations
- Implement incremental sync (already done!)
- Monitor PostgreSQL query performance
- Consider connection pooling (already configured)

## Next Steps

- [ ] Add user authentication layer
- [ ] Implement push notifications for sync
- [ ] Add conflict resolution UI components
- [ ] Create admin dashboard for monitoring
- [ ] Add data export/backup features
- [ ] Implement selective sync (choose what to sync)

## Support

For issues or questions:
1. Check server logs
2. Check client logs (debugPrint statements)
3. Review sync_log table in PostgreSQL
4. Test with `curl` commands directly to API

Happy syncing! 🚀
