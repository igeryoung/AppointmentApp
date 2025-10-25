# Quick Start - 5 Minute Setup

The fastest way to get the sync system running.

## Option 1: Automated Setup (Recommended)

```bash
# From project root
./setup_and_test.sh
```

This script will:
- ✅ Start PostgreSQL
- ✅ Create database
- ✅ Run migrations
- ✅ Start server
- ✅ Register test device

**Server will be running at http://localhost:8080**

## Option 2: Manual Setup (3 Commands)

```bash
# 1. Start PostgreSQL and create database
brew services start postgresql@14
createdb schedule_note_dev

# 2. Run server with migrations
cd server
dart pub get
dart run main.dart --dev --migrate

# Server is now running!
```

## Test in Flutter

```dart
import 'services/sync_service.dart';
import 'services/api_client.dart';
import 'services/prd_database_service.dart';

// Initialize
final syncService = SyncService(
  dbService: PRDDatabaseService(),
  apiClient: ApiClient(baseUrl: 'http://localhost:8080'),
);

// Register device (first time only)
await syncService.registerDevice(
  deviceName: 'My Device',
  serverUrl: 'http://localhost:8080',
);

// Sync data
final result = await syncService.syncAll();
print('Synced: ${result.changesApplied} applied, ${result.changesPushed} pushed');
```

## Verify It's Working

```bash
# Check server
curl http://localhost:8080/health
# Should return: {"status": "healthy", ...}

# Check database
psql schedule_note_dev -c "SELECT count(*) FROM devices;"
# Should return: 1 (or more)

# View sync log
psql schedule_note_dev -c "SELECT * FROM sync_log ORDER BY synced_at DESC LIMIT 5;"
```

## Common Commands

### Server
```bash
# Start server (development)
cd server && dart run main.dart --dev

# Start with migrations
cd server && dart run main.dart --dev --migrate

# Stop server
# Press Ctrl+C in server terminal
```

### Database
```bash
# Connect to database
psql schedule_note_dev

# Quick queries (inside psql)
SELECT count(*) FROM books;
SELECT count(*) FROM events;
SELECT * FROM devices;
\q  # Exit
```

### Testing
```bash
# Register device via API
curl -X POST http://localhost:8080/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "Test", "platform": "macos"}'

# Check health
curl http://localhost:8080/health
```

## Troubleshooting

**PostgreSQL not starting?**
```bash
brew services restart postgresql@14
brew services list | grep postgresql
```

**Port 8080 already in use?**
```bash
lsof -i :8080
kill -9 <PID>
```

**Connection refused?**
```bash
# Check server is running
curl http://localhost:8080/health

# Check PostgreSQL is running
psql -l
```

## Next Steps

For detailed testing instructions, see **TESTING_GUIDE.md**

For production deployment, see **SYNC_GUIDE.md**

For implementation details, see **SYNC_IMPLEMENTATION_SUMMARY.md**

---

**That's it!** Your sync system should be running. 🚀
