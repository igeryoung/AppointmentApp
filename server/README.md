# Schedule Note Server

PostgreSQL-based API server built with Dart Shelf.

## Quick Start

```bash
# 1. Install PostgreSQL (if not installed)
brew install postgresql@15  # macOS
brew services start postgresql@15

# 2. Create database
psql postgres -c "CREATE DATABASE schedule_note_dev;"

# 3. Configure environment (copy from .env.example to ../.env)
cp ../.env.example ../.env
# Edit ../.env and set DB_PASSWORD=postgres (or your password)

# 4. Install dependencies
dart pub get

# 5. Run migrations and start server
dart run main.dart --dev --migrate
```

Server starts on `http://localhost:8080`

Check health: `curl http://localhost:8080/health`

## Standard Commands

```bash
# Run server (development)
dart run main.dart --dev

# Run server (production)
dart run main.dart

# Run with migrations
dart run main.dart --dev --migrate

# Run integration tests
./test_notes_api.sh
```

## API Documentation

**Interactive docs:** `http://localhost:8080/docs` (Swagger UI)

**Available APIs:**

1. **Book API** (`/api/books/*`)
   - `POST /api/books` - Create book
   - `GET /api/books` - List books
   - `GET /api/books/{bookUuid}` - Get book metadata
   - `PATCH /api/books/{bookUuid}` - Rename/update book
   - `POST /api/books/{bookUuid}/archive` - Archive book
   - `DELETE /api/books/{bookUuid}` - Soft-delete book
   - `GET /api/books/{bookUuid}/bundle` - Fetch full book payload

2. **Event API** (`/api/books/{bookUuid}/events/*`)
   - `GET /api/books/{bookUuid}/events` - List events by date range
   - `POST /api/books/{bookUuid}/events` - Create event
   - `PATCH /api/books/{bookUuid}/events/{eventId}` - Update event
   - `POST /api/books/{bookUuid}/events/{eventId}/remove` - Soft remove event
   - `POST /api/books/{bookUuid}/events/{eventId}/reschedule` - Reschedule event
   - `DELETE /api/books/{bookUuid}/events/{eventId}` - Soft delete event

3. **Server-Store Notes/Drawings**
   - `GET/POST/DELETE /api/books/{bookUuid}/events/{eventId}/note`
   - `GET/POST/DELETE /api/books/{bookUuid}/drawings`
   - `POST /api/notes/batch`
   - `POST /api/drawings/batch`

4. **Device Management** (`/api/devices/*`)
   - `POST /api/devices/register` - Register device
   - `GET /api/devices/{id}` - Get device info

See `doc/Server-Store/` for Server-Store API implementation details.

## Configuration

**Environment variables** (see `../.env.example`):
- `DB_PASSWORD` - **Required** - Database password
- `DB_HOST` - Database host (default: localhost)
- `DB_PORT` - Database port (default: 5433 dev, 5432 prod)
- `DB_NAME` - Database name (default: schedule_note_dev)
- `DB_USER` - Database user (default: postgres)
- `SERVER_PORT` - Server port (default: 8080)
- `ENABLE_SSL` - Enable HTTPS (default: true)

**Never commit `.env` to git!**

## Database Schema

**Tables:**
- `devices` - Registered devices (auth)
- `books` - Top-level containers
- `events` - Appointment entries
- `notes` - Handwriting notes (1:1 with events)
- `schedule_drawings` - Schedule overlay drawings
- `sync_log` - Audit trail

**Key patterns:**
- `version` - Incremented on each update (optimistic locking)
- `synced_at` - Last sync timestamp
- `is_deleted` - Soft delete flag (never hard delete)
- `device_id` - Device that created/last modified record

See `migrations/*.sql` for complete schema.

## Troubleshooting

**Port already in use (Address already in use, errno = 48)**
```bash
# Find and kill process on port 8080
lsof -ti:8080 | xargs kill -9

# Or see what's using the port
lsof -i:8080
```

**Server won't start - "Postgres.app rejected trust authentication"**
- Open Postgres.app → Preferences → Network
- Allow connections without password (development only)
- Or configure password auth in `pg_hba.conf`

**Connection refused**
```bash
# Check PostgreSQL is running
brew services list  # macOS
psql -l             # Test connection
```

**Migration fails**
```bash
# Verify database exists
psql -l | grep schedule_note

# Check permissions
psql schedule_note_dev -c "SELECT 1;"
```

**API returns 403 Forbidden**
- Check device is registered: `POST /api/devices/register`
- Verify `X-Device-ID` and `X-Device-Token` headers are set
- Check device owns the book being accessed

## Development

```bash
# Analyze code
dart analyze

# Format code
dart format lib/

# Run notes API tests
./test_notes_api.sh
```

## Architecture

**Server-first architecture:**

1. **Domain writes via explicit REST endpoints**
   - Books/events/notes/drawings are written directly.
   - No generic sync transport endpoints.

2. **Server-store reads**
   - Fetch resources by book/date/record/event scope.
   - Optimistic locking supported by `version` fields on mutable entities.

See `doc/Server-Store/` for migration roadmap.

---

**Linus says:** *"Good code needs no comments. Good servers need no babysitting."*

Run it, test it, ship it. ✅
