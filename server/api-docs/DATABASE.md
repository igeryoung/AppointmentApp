# Database Schema Documentation

Complete database schema reference based on the client application structure.

**Framework:** SQLite
**Current Version:** 20
**Foreign Keys:** Enabled

---

## Table of Contents

1. [Core Tables](#core-tables)
2. [Content Tables](#content-tables)
3. [Person-based Shared Data](#person-based-shared-data)
4. [System Tables](#system-tables)
5. [Sync & Caching Architecture](#sync--caching-architecture)
6. [Data Flow Diagrams](#data-flow-diagrams)
7. [Key Concepts](#key-concepts)

---

## Core Tables

### books
Top-level containers for appointment schedules.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| book_uuid | TEXT | UNIQUE | UUID for cross-device sync |
| name | TEXT | NOT NULL | Display name of the book |
| created_at | INTEGER | NOT NULL | Unix timestamp (seconds) |
| archived_at | INTEGER | NULL | Timestamp when archived (soft delete) |
| version | INTEGER | DEFAULT 1 | Version for optimistic locking |
| is_dirty | INTEGER | DEFAULT 0 | Flag: 1 = needs sync, 0 = synced |

**Indexes:** book_uuid (unique)

---

### events
Individual appointment entries within a book.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| book_id | INTEGER | NOT NULL, FK → books(id) CASCADE | Parent book reference |
| name | TEXT | NOT NULL | Patient or event name |
| record_number | TEXT | NULL | Patient medical record number |
| phone | TEXT | NULL | Patient phone number (optional) |
| event_type | TEXT | NULL | Legacy single type field (deprecated) |
| event_types | TEXT | NOT NULL | JSON array of event types |
| has_charge_items | INTEGER | DEFAULT 0 | Flag: 1 = has charge items |
| start_time | INTEGER | NOT NULL | Unix timestamp for start |
| end_time | INTEGER | NULL | Unix timestamp for end (NULL = open) |
| created_at | INTEGER | NOT NULL | Creation timestamp |
| updated_at | INTEGER | NOT NULL | Last update timestamp |
| is_removed | INTEGER | DEFAULT 0 | Soft delete flag |
| removal_reason | TEXT | NULL | Reason for removal if deleted |
| original_event_id | INTEGER | NULL | Reference to original (time change) |
| new_event_id | INTEGER | NULL | Reference to new event (time change) |
| is_checked | INTEGER | DEFAULT 0 | Completion checkbox flag |
| has_note | INTEGER | DEFAULT 0 | Flag: 1 = has handwriting note |
| version | INTEGER | DEFAULT 1 | Version for optimistic locking |
| is_dirty | INTEGER | DEFAULT 0 | Flag: 1 = needs sync |

**Indexes:**
- (book_id, start_time)
- (book_id, date)

**Event Types Enum:**
- consultation
- surgery
- followUp
- emergency
- checkUp
- treatment
- other

---

## Content Tables

### notes
Multi-page handwriting notes (one per event).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| event_id | INTEGER | NOT NULL, UNIQUE, FK → events(id) CASCADE | One-to-one with event |
| strokes_data | TEXT | NULL | Legacy single-page strokes (JSON) |
| pages_data | TEXT | NULL | Multi-page strokes (JSON array) |
| created_at | INTEGER | NOT NULL | Creation timestamp |
| updated_at | INTEGER | NOT NULL | Last update timestamp |
| cached_at | INTEGER | NULL | Cache timestamp for LRU |
| cache_hit_count | INTEGER | DEFAULT 0 | LRU cache hit counter |
| person_name_normalized | TEXT | NULL | Normalized name for shared notes |
| record_number_normalized | TEXT | NULL | Normalized record for sharing |
| locked_by_device_id | TEXT | NULL | Device holding edit lock |
| locked_at | INTEGER | NULL | Lock acquisition timestamp |
| version | INTEGER | DEFAULT 1 | Version for optimistic locking |
| is_dirty | INTEGER | DEFAULT 0 | Flag: 1 = needs sync |

**Indexes:**
- event_id (unique)
- (person_name_normalized, record_number_normalized)
- locked_by_device_id
- cached_at DESC (for LRU)
- cache_hit_count ASC (for LRU eviction)

**Note Structure:**
Each page contains strokes. Each stroke contains:
- points: array of {dx, dy, pressure}
- strokeWidth: line thickness
- color: stroke color
- strokeType: pen (0) or highlighter (1)

---

### schedule_drawings
Handwriting overlays on schedule views (day/week views).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| book_id | INTEGER | NOT NULL, FK → books(id) CASCADE | Parent book reference |
| date | INTEGER | NOT NULL | Reference date (Unix timestamp) |
| view_mode | INTEGER | NOT NULL | 1 = 3-day view, 2 = 2-day view |
| strokes_data | TEXT | NULL | Drawing strokes (JSON array) |
| created_at | INTEGER | NOT NULL | Creation timestamp |
| updated_at | INTEGER | NOT NULL | Last update timestamp |
| cached_at | INTEGER | NULL | Cache timestamp for LRU |
| cache_hit_count | INTEGER | DEFAULT 0 | LRU cache hit counter |
| version | INTEGER | DEFAULT 1 | Version for optimistic locking |
| is_dirty | INTEGER | DEFAULT 0 | Flag: 1 = needs sync |

**Indexes:**
- (book_id, date, view_mode) - composite unique key
- cached_at DESC (for LRU)

---

## Person-based Shared Data

These tables enable data sharing across multiple events for the same person.

### person_charge_items
Charge items associated with a person (not individual events).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| person_name_normalized | TEXT | NOT NULL | Normalized person name |
| record_number_normalized | TEXT | NOT NULL | Normalized record number |
| item_name | TEXT | NOT NULL | Name of charge item |
| cost | INTEGER | NOT NULL | Cost as integer (no decimals) |
| is_paid | INTEGER | DEFAULT 0 | Payment status: 1 = paid |
| created_at | INTEGER | NOT NULL | Creation timestamp |
| updated_at | INTEGER | NOT NULL | Last update timestamp |
| version | INTEGER | DEFAULT 1 | Version for optimistic locking |
| is_dirty | INTEGER | DEFAULT 0 | Flag: 1 = needs sync |

**Unique Constraint:** (person_name_normalized, record_number_normalized, item_name)

**Indexes:**
- (person_name_normalized, record_number_normalized)
- is_dirty

---

### person_info
Person-level metadata (phone numbers).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| person_name_normalized | TEXT | NOT NULL | Normalized person name |
| record_number_normalized | TEXT | NOT NULL | Normalized record number |
| phone | TEXT | NULL | Phone number (synced across events) |
| created_at | INTEGER | NOT NULL | Creation timestamp |
| updated_at | INTEGER | NOT NULL | Last update timestamp |

**Unique Constraint:** (person_name_normalized, record_number_normalized)

**Indexes:** (person_name_normalized, record_number_normalized)

---

## System Tables

### device_info
Local device registration data (single row table).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY, CHECK (id = 1) | Always 1 (single row) |
| device_id | TEXT | UNIQUE, NOT NULL | Device UUID |
| device_token | TEXT | NOT NULL | Authentication token |
| device_name | TEXT | NOT NULL | Display name |
| platform | TEXT | NULL | iOS, Android, etc. |
| registered_at | INTEGER | NOT NULL | Registration timestamp |
| server_url | TEXT | NULL | Configured server URL |

**Constraint:** Single row (id must equal 1)

---

### sync_metadata
Sync state tracking per table.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| table_name | TEXT | UNIQUE, NOT NULL | Name of tracked table |
| last_sync_at | INTEGER | NOT NULL | Last successful sync timestamp |
| synced_record_count | INTEGER | DEFAULT 0 | Number of records synced |

**Unique Constraint:** table_name

---

### cache_policy
Cache configuration (single row table).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY, CHECK (id = 1) | Always 1 (single row) |
| max_cache_size_mb | INTEGER | DEFAULT 50 | Maximum cache size in MB |
| cache_duration_days | INTEGER | DEFAULT 7 | Cache retention period |
| auto_cleanup | INTEGER | DEFAULT 1 | Auto cleanup: 1 = enabled |
| last_cleanup_at | INTEGER | NULL | Last cleanup timestamp |

**Constraint:** Single row (id must equal 1)

**Default Values:**
- max_cache_size_mb: 50
- cache_duration_days: 7
- auto_cleanup: 1 (enabled)

---

## Sync & Caching Architecture

### Optimistic Locking Strategy

**Version Field:**
- All syncable tables include a `version` field
- Incremented on every update
- Client sends expected version when updating
- Server rejects if version doesn't match (conflict detected)

**Conflict Resolution Flow:**
```
Client Update Request (version = 5)
    ↓
Server checks current version
    ↓
If server version = 5 → Accept update, increment to 6
If server version ≠ 5 → Reject (409 Conflict)
    ↓
Client receives conflict
    ↓
Fetch latest version from server
    ↓
User resolves conflict (merge or choose)
    ↓
Retry with new version number
```

### Dirty Flag Sync Strategy

**is_dirty Field:**
- 0 = Record is synced with server
- 1 = Record has local changes needing sync

**Sync Process:**
```
1. Find all records where is_dirty = 1
2. Send batch to server
3. On success: Set is_dirty = 0
4. On failure: Keep is_dirty = 1, retry later
```

### LRU Cache System

**Purpose:**
Limit storage used by notes and drawings while keeping frequently used items.

**Cache Fields:**
- cached_at: Timestamp when item was cached
- cache_hit_count: Number of times accessed

**Eviction Strategy:**
```
When cache exceeds limit:
1. Sort by cache_hit_count ASC (least used first)
2. Remove items with oldest cached_at
3. Stop when under cache limit
```

**Cache Policy:**
- Max size: 50 MB (configurable)
- Duration: 7 days (configurable)
- Auto cleanup: Enabled by default

### Person-based Note Sharing

**Normalization:**
- Names and record numbers are normalized (case-insensitive)
- Multiple events for same person share notes and charge items

**Process:**
```
Event: John Doe, Record #12345
    ↓
Normalize: john doe, 12345
    ↓
Look up in notes table by normalized keys
    ↓
If found → Link to existing note
If not found → Create new note
```

**Benefits:**
- Single note shared across all appointments for a person
- Charge items accumulated per person, not per event
- Phone number synced across all events

---

## Data Flow Diagrams

### Event Creation Flow

```
User creates event
    ↓
Insert into events table
    ↓
Set is_dirty = 1, version = 1
    ↓
Normalize person name + record number
    ↓
Check person_info table
    ↓
If found → Copy phone to event
If not → Create person_info entry
    ↓
Event ready for sync
```

### Note Creation and Sharing Flow

```
User opens note for Event A (John Doe #12345)
    ↓
Normalize: john doe, 12345
    ↓
Query notes table by normalized keys
    ↓
If exists → Load existing note (shared)
If not → Create new note
    ↓
User edits note
    ↓
Save to notes table
    ↓
Set is_dirty = 1, increment version
    ↓
Note ready for sync
    ↓
Other events for same person see updated note
```

### Sync Flow (Client → Server)

```
Periodic sync trigger
    ↓
Find all records where is_dirty = 1
    ↓
Group by table:
  - books
  - events
  - notes
  - schedule_drawings
  - person_charge_items
  - person_info
    ↓
For each table:
    ↓
    Send batch to server with version numbers
        ↓
    Server validates versions
        ↓
    If version matches → Accept, increment version
    If version conflict → Return 409 with server data
        ↓
    On success: Set is_dirty = 0
    On conflict: Show conflict UI to user
        ↓
Update sync_metadata.last_sync_at
```

### Cache Management Flow

```
User accesses note/drawing
    ↓
Increment cache_hit_count
    ↓
Update cached_at = current time
    ↓
Background task checks cache size
    ↓
If size > max_cache_size_mb:
    ↓
    Query cached items ordered by:
      1. cache_hit_count ASC (least used)
      2. cached_at ASC (oldest)
    ↓
    Delete items until under limit
    ↓
    Log cleanup in cache_policy.last_cleanup_at
```

### Cascade Delete Flow

```
User deletes book (or soft delete via archived_at)
    ↓
CASCADE DELETE triggers:
    ↓
    Delete all events (book_id FK)
        ↓
        CASCADE DELETE on notes (event_id FK)
        ↓
        Orphaned person data remains:
          - person_charge_items (not FK linked)
          - person_info (not FK linked)
    ↓
    Delete all schedule_drawings (book_id FK)
```

**Note:** Person data persists after event deletion to maintain history.

---

## Key Concepts

### Timestamps
- All timestamps stored as INTEGER (Unix seconds)
- NULL timestamps allowed for optional fields
- created_at and updated_at track record lifecycle

### Soft Deletes
- **Books:** archived_at timestamp (NULL = active)
- **Events:** is_removed flag + removal_reason text
- Soft deleted records not shown in UI but retained in DB

### Foreign Key Cascades
```
books
  ├── events (CASCADE)
  │     └── notes (CASCADE)
  └── schedule_drawings (CASCADE)
```

### Composite Keys
Person-based data uses composite keys:
- (person_name_normalized, record_number_normalized)
- Enables case-insensitive person matching
- Links events to shared notes and charge items

### Single Row Tables
- device_info: Stores this device's registration
- cache_policy: Stores cache configuration
- Enforced via CHECK constraint (id = 1)

### Version Numbers
- Start at 1 on creation
- Increment on every update
- Used for optimistic locking
- Client must send expected version

### Dirty Flags
- Track local changes needing server sync
- Set to 1 on create/update
- Set to 0 after successful sync
- Enables efficient incremental sync

### Event Type Evolution
- Old: event_type (single TEXT)
- New: event_types (JSON array)
- Supports multiple types per event
- Migration handled in app logic

### Time Change Tracking
- original_event_id: Points to original event
- new_event_id: Points to rescheduled event
- Maintains appointment history chain

### Phone Number Syncing
- Phone stored in person_info (master)
- Copied to events.phone (cached)
- Updates to person_info propagate to all events

### Charge Items Evolution
- Old: events.charge_items (JSON in event)
- New: person_charge_items table (shared)
- has_charge_items flag on event for quick check
- Migration completed in version 20

---

## Schema Version History

**Version 16:** Baseline (requires app reinstall for older versions)
**Version 17:** Added phone and charge_items to events
**Version 18:** Created person_charge_items table, migrated data
**Version 19:** Created person_info table, migrated phone numbers
**Version 20:** Added has_charge_items flag, removed legacy charge_items column (current)

---

## Notes for Server Implementation

When implementing server-side schema:

1. **Add server-specific fields:**
   - device_id references for ownership tracking
   - server-side timestamps (received_at, processed_at)
   - is_deleted for soft deletes on server

2. **Adjust data types:**
   - INTEGER timestamps → TIMESTAMPTZ in PostgreSQL
   - TEXT → VARCHAR or TEXT
   - INTEGER booleans → BOOLEAN

3. **Add indexes for:**
   - Foreign key lookups
   - Composite person keys
   - Sync queries (is_dirty, version, device_id)
   - Time-based queries (created_at, updated_at)

4. **Multi-device considerations:**
   - Track which device owns each record
   - Handle conflicts across devices
   - Broadcast changes to other devices

5. **Person data normalization:**
   - Ensure consistent normalization logic
   - Handle edge cases (empty names, special characters)
   - Consider full-text search for person lookup

6. **Cache is client-side only:**
   - Server doesn't need cache_hit_count or cached_at
   - Server stores all data permanently
   - Client manages its own cache

---

*This schema documentation reflects the client application database structure (version 20) and should be used as the authoritative reference for server-side implementation.*
