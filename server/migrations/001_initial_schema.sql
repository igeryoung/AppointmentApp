-- PostgreSQL Schema for Schedule Note App
-- Mirrors SQLite structure with sync capabilities

-- Enable UUID extension for device IDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Devices table - Track all registered devices
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_name VARCHAR(255) NOT NULL,
    device_token VARCHAR(512) UNIQUE NOT NULL,
    platform VARCHAR(50), -- 'ios', 'android', 'web', etc.
    registered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_sync_at TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_devices_token ON devices(device_token);
CREATE INDEX idx_devices_last_sync ON devices(last_sync_at);

-- Books table - Top-level containers
CREATE TABLE books (
    id SERIAL PRIMARY KEY,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    archived_at TIMESTAMP,
    synced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version INTEGER NOT NULL DEFAULT 1,
    is_deleted BOOLEAN DEFAULT false
);

CREATE INDEX idx_books_device ON books(device_id);
CREATE INDEX idx_books_synced ON books(synced_at);
CREATE INDEX idx_books_deleted ON books(is_deleted) WHERE is_deleted = false;

-- Events table - Individual appointment entries
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    record_number VARCHAR(100) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_removed BOOLEAN DEFAULT false,
    removal_reason TEXT,
    original_event_id INTEGER REFERENCES events(id),
    new_event_id INTEGER REFERENCES events(id),
    synced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version INTEGER NOT NULL DEFAULT 1,
    is_deleted BOOLEAN DEFAULT false
);

CREATE INDEX idx_events_book ON events(book_id);
CREATE INDEX idx_events_device ON events(device_id);
CREATE INDEX idx_events_start_time ON events(start_time);
CREATE INDEX idx_events_book_time ON events(book_id, start_time);
CREATE INDEX idx_events_synced ON events(synced_at);
CREATE INDEX idx_events_deleted ON events(is_deleted) WHERE is_deleted = false;

-- Notes table - Handwriting notes linked to events
CREATE TABLE notes (
    id SERIAL PRIMARY KEY,
    event_id INTEGER NOT NULL UNIQUE REFERENCES events(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    strokes_data TEXT, -- JSON array of strokes
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    synced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version INTEGER NOT NULL DEFAULT 1,
    is_deleted BOOLEAN DEFAULT false
);

CREATE INDEX idx_notes_event ON notes(event_id);
CREATE INDEX idx_notes_device ON notes(device_id);
CREATE INDEX idx_notes_synced ON notes(synced_at);
CREATE INDEX idx_notes_deleted ON notes(is_deleted) WHERE is_deleted = false;

-- Schedule Drawings table - Handwriting overlay on schedule views
CREATE TABLE schedule_drawings (
    id SERIAL PRIMARY KEY,
    book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    date TIMESTAMP NOT NULL, -- Normalized to midnight
    view_mode INTEGER NOT NULL, -- 0: Day, 1: 3-Day, 2: Week
    strokes_data TEXT, -- JSON array of strokes
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    synced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version INTEGER NOT NULL DEFAULT 1,
    is_deleted BOOLEAN DEFAULT false,
    UNIQUE(book_id, date, view_mode)
);

CREATE INDEX idx_schedule_drawings_book_date_view ON schedule_drawings(book_id, date, view_mode);
CREATE INDEX idx_schedule_drawings_device ON schedule_drawings(device_id);
CREATE INDEX idx_schedule_drawings_synced ON schedule_drawings(synced_at);
CREATE INDEX idx_schedule_drawings_deleted ON schedule_drawings(is_deleted) WHERE is_deleted = false;

-- Sync Log table - Audit trail of all sync operations
CREATE TABLE sync_log (
    id SERIAL PRIMARY KEY,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    operation VARCHAR(50) NOT NULL, -- 'push', 'pull', 'resolve_conflict'
    table_name VARCHAR(50) NOT NULL,
    record_id INTEGER,
    status VARCHAR(50) NOT NULL, -- 'success', 'failed', 'conflict'
    error_message TEXT,
    changes_count INTEGER DEFAULT 0,
    synced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sync_log_device ON sync_log(device_id);
CREATE INDEX idx_sync_log_synced ON sync_log(synced_at);
CREATE INDEX idx_sync_log_status ON sync_log(status);

-- Trigger to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_books_updated_at BEFORE UPDATE ON books
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_events_updated_at BEFORE UPDATE ON events
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notes_updated_at BEFORE UPDATE ON notes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_schedule_drawings_updated_at BEFORE UPDATE ON schedule_drawings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Trigger to increment version on update
CREATE OR REPLACE FUNCTION increment_version()
RETURNS TRIGGER AS $$
BEGIN
    NEW.version = OLD.version + 1;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER increment_books_version BEFORE UPDATE ON books
    FOR EACH ROW EXECUTE FUNCTION increment_version();

CREATE TRIGGER increment_events_version BEFORE UPDATE ON events
    FOR EACH ROW EXECUTE FUNCTION increment_version();

CREATE TRIGGER increment_notes_version BEFORE UPDATE ON notes
    FOR EACH ROW EXECUTE FUNCTION increment_version();

CREATE TRIGGER increment_schedule_drawings_version BEFORE UPDATE ON schedule_drawings
    FOR EACH ROW EXECUTE FUNCTION increment_version();

-- Comments for documentation
COMMENT ON TABLE devices IS 'Tracks all registered devices for sync';
COMMENT ON TABLE books IS 'Top-level containers for events';
COMMENT ON TABLE events IS 'Individual appointment entries with PRD metadata';
COMMENT ON TABLE notes IS 'Handwriting-only notes linked to events';
COMMENT ON TABLE schedule_drawings IS 'Handwriting overlay on schedule views';
COMMENT ON TABLE sync_log IS 'Audit trail of all sync operations';

COMMENT ON COLUMN books.version IS 'Incremented on each update for conflict detection';
COMMENT ON COLUMN books.synced_at IS 'Last time this record was synced to server';
COMMENT ON COLUMN books.is_deleted IS 'Soft delete flag for sync purposes';
