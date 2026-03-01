# Schedule Note Server

Supabase SDK-based API server built with Dart Shelf.

## Quick Start

```bash
# 1. Configure environment (copy from .env.example to ../.env)
cp ../.env.example ../.env
# Set SUPABASE_URL and SUPABASE_KEY (service_role key)

# 2. Install dependencies
dart pub get

# 3. In Supabase SQL editor, run:
#    - server/schema.sql
#    - docs/security/supabase/rls_best_practice.sql (optional hardening)

# 4. Start server
dart run main.dart --dev
```

Server starts on `http://localhost:8080`

Check health: `curl http://localhost:8080/health`

## Standard Commands

```bash
# Run server (development)
dart run main.dart --dev

# Run server (production)
dart run main.dart

# Run integration tests
./test_notes_api.sh
```

## Deploy To Railway

This server can be deployed to Railway as a backend-only service.

Use the `server/` directory as the Railway service root and deploy with the
included [`Dockerfile`](/Users/yangping/Studio/side-project/scheduleNote/server/Dockerfile).

Required Railway variables:

- `SUPABASE_URL`
- `SUPABASE_KEY`
- `DASHBOARD_USERNAME`
- `DASHBOARD_PASSWORD`

Optional Railway variables:

- `ENABLE_SSL=false` if you want to force plain HTTP inside the container
  behind Railway's HTTPS proxy. This is already the default when Railway
  provides `PORT` and no certificate paths are configured.
- `SERVER_HOST=0.0.0.0`

Railway provides `PORT` automatically. The production server now honors that
value and binds plain HTTP inside the container while Railway terminates TLS at
the edge.

Recommended Railway settings:

- Health check path: `/health`
- Root directory: `server`
- Start command: leave empty when using Dockerfile deploy
- Public domain/custom domain: enable in Railway networking settings

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
- `SUPABASE_URL` - Project URL, e.g. `https://<project-ref>.supabase.co`
- `SUPABASE_KEY` - **Backend key (service_role / secret key)**. Never expose to frontend.
- `SERVER_PORT` - Local fallback server port when `PORT` is not provided
- `ENABLE_SSL` - Enable in-app HTTPS. Defaults to enabled off Railway and disabled on Railway-managed TLS.

**Supabase SDK example**:
```bash
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_KEY=<service-role-or-secret-key>
```

Client architecture note:
- Flutter app talks only to this API server.
- This server talks to Supabase via SDK (`SUPABASE_URL` + `SUPABASE_KEY`).
- Do not place backend keys in the frontend app.

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

Schema source: `server/schema.sql`.

## Troubleshooting

**Port already in use (Address already in use, errno = 48)**
```bash
# Find and kill process on port 8080
lsof -ti:8080 | xargs kill -9

# Or see what's using the port
lsof -i:8080
```

**Connection refused**
```bash
# Check server process and local port
lsof -i:8080
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
