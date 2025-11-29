-- Migration: Convert event IDs from INTEGER to UUID (TEXT)
-- This prevents ID collisions when multiple devices create events locally
-- and ensures globally unique event identifiers

-- Step 1: Create new events table with UUID primary key
CREATE TABLE events_new (
    id TEXT PRIMARY KEY,
    book_uuid TEXT NOT NULL,
    device_id TEXT NOT NULL,
    name TEXT NOT NULL,
    record_number TEXT,
    event_type TEXT,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_removed BOOLEAN DEFAULT false,
    removal_reason TEXT,
    original_event_id TEXT,  -- Changed from INTEGER to TEXT
    new_event_id TEXT,       -- Changed from INTEGER to TEXT
    synced_at TIMESTAMP,
    version INTEGER DEFAULT 1,
    is_deleted BOOLEAN DEFAULT false,
    is_checked BOOLEAN DEFAULT false,
    has_note BOOLEAN DEFAULT false,
    FOREIGN KEY (book_uuid) REFERENCES books(book_uuid) ON DELETE CASCADE
);

-- Step 2: Create new notes table with TEXT event_id foreign key
CREATE TABLE notes_new (
    id SERIAL PRIMARY KEY,
    event_id TEXT NOT NULL UNIQUE,  -- Changed from INTEGER to TEXT
    device_id TEXT NOT NULL,
    pages_data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    synced_at TIMESTAMP,
    version INTEGER DEFAULT 1,
    is_deleted BOOLEAN DEFAULT false,
    FOREIGN KEY (event_id) REFERENCES events_new(id) ON DELETE CASCADE
);

-- Step 3: Drop old tables (data will be lost, but this is for development)
-- In production, you would migrate data here before dropping
DROP TABLE IF EXISTS notes CASCADE;
DROP TABLE IF EXISTS events CASCADE;

-- Step 4: Rename new tables to original names
ALTER TABLE events_new RENAME TO events;
ALTER TABLE notes_new RENAME TO notes;

-- Step 5: Recreate indexes
CREATE INDEX IF NOT EXISTS idx_events_book_uuid ON events(book_uuid);
CREATE INDEX IF NOT EXISTS idx_events_start_time ON events(start_time);
CREATE INDEX IF NOT EXISTS idx_events_book_uuid_start_time ON events(book_uuid, start_time);
CREATE INDEX IF NOT EXISTS idx_events_has_note ON events(has_note);
CREATE INDEX IF NOT EXISTS idx_events_synced_at ON events(synced_at);

CREATE INDEX IF NOT EXISTS idx_notes_event_id ON notes(event_id);
CREATE INDEX IF NOT EXISTS idx_notes_synced_at ON notes(synced_at);

-- Confirm migration completed
SELECT 'Migration 012: Event UUID migration completed successfully' AS status;
