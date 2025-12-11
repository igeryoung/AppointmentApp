-- =========================================================
-- Migration 015: Record-Number-Based Schema
--
-- This migration transforms the database from event-centric
-- to record-centric architecture where:
-- - Records are first-class entities with global identity
-- - All events with same record_number share the same record_uuid
-- - Notes are tied to record_uuid (shared across all events for same record)
-- - Events without record_number get their own unique record (independent)
-- =========================================================

-- =========================================================
-- 0. Drop existing schema (no data preserved)
-- =========================================================

BEGIN;

-- Drop in dependency-safe order (CASCADE handles the rest)
DROP TABLE IF EXISTS public.book_backups       CASCADE;
DROP TABLE IF EXISTS public.book_device_access CASCADE;
DROP TABLE IF EXISTS public.schedule_drawings  CASCADE;
DROP TABLE IF EXISTS public.sync_log           CASCADE;
DROP TABLE IF EXISTS public.notes              CASCADE;
DROP TABLE IF EXISTS public.events             CASCADE;
DROP TABLE IF EXISTS public.books              CASCADE;
DROP TABLE IF EXISTS public.devices            CASCADE;
DROP TABLE IF EXISTS public.records            CASCADE;

COMMIT;

-- =========================================================
-- 1. Prerequisite extension
-- =========================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================================================
-- 2. Helper functions
-- =========================================================

BEGIN;

-- Function to auto-increment version on update
CREATE OR REPLACE FUNCTION public.increment_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.version = OLD.version + 1;
    RETURN NEW;
END;
$$;

-- Function to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

COMMIT;

-- =========================================================
-- 3. Core tables (devices, records, books, events, notes)
-- =========================================================

BEGIN;

-- -------------------------
-- 3.1 Devices
-- -------------------------
CREATE TABLE public.devices (
    id              uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_name     text        NOT NULL,
    device_token    text        NOT NULL UNIQUE,
    platform        text,                   -- ios, android, web, etc.
    registered_at   timestamptz NOT NULL DEFAULT NOW(),
    last_sync_at    timestamptz,
    is_active       boolean     NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE public.devices IS 'All registered client devices.';

CREATE INDEX idx_devices_token ON public.devices(device_token);
CREATE INDEX idx_devices_last_sync ON public.devices(last_sync_at);


-- -------------------------
-- 3.2 Records (global record-number–based identity)
-- -------------------------
CREATE TABLE public.records (
    record_uuid   uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
    record_number text        NOT NULL DEFAULT '',  -- empty string for no record number
    name          text,                             -- shared display name
    phone         text,                             -- shared phone
    created_at    timestamptz NOT NULL DEFAULT NOW(),
    updated_at    timestamptz NOT NULL DEFAULT NOW(),
    synced_at     timestamptz,
    version       integer     NOT NULL DEFAULT 1,
    is_deleted    boolean     NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE public.records
    IS 'Global logical record/person/case, shared across all books and events.';

COMMENT ON COLUMN public.records.record_number
    IS 'Global record number. Unique when non-empty; empty strings are allowed to duplicate for standalone records.';

-- Unique constraint only for non-empty record_number
CREATE UNIQUE INDEX idx_records_record_number_unique
    ON public.records(record_number)
    WHERE record_number <> '';

CREATE INDEX idx_records_synced_at ON public.records(synced_at);

-- Triggers for records
CREATE TRIGGER increment_records_version
    BEFORE UPDATE ON public.records
    FOR EACH ROW EXECUTE FUNCTION public.increment_version();

CREATE TRIGGER update_records_updated_at
    BEFORE UPDATE ON public.records
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


-- -------------------------
-- 3.3 Books (per-device / per-context)
-- -------------------------
CREATE TABLE public.books (
    book_uuid   uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id   uuid        NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    name        text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT NOW(),
    updated_at  timestamptz NOT NULL DEFAULT NOW(),
    archived_at timestamptz,
    synced_at   timestamptz NOT NULL DEFAULT NOW(),
    version     integer     NOT NULL DEFAULT 1,
    is_deleted  boolean     NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE public.books
    IS 'Top-level schedule/record book, keyed by UUID.';

CREATE INDEX idx_books_device_id ON public.books(device_id);

-- Triggers for books
CREATE TRIGGER increment_books_version
    BEFORE UPDATE ON public.books
    FOR EACH ROW EXECUTE FUNCTION public.increment_version();

CREATE TRIGGER update_books_updated_at
    BEFORE UPDATE ON public.books
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


-- -------------------------
-- 3.4 Events (per-book, linked to global record)
-- -------------------------
CREATE TABLE public.events (
    id              uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
    book_uuid       uuid        NOT NULL REFERENCES public.books(book_uuid)   ON DELETE CASCADE,
    record_uuid     uuid        NOT NULL REFERENCES public.records(record_uuid) ON DELETE RESTRICT,
    device_id       uuid        NOT NULL REFERENCES public.devices(id)        ON DELETE CASCADE,

    title           text        NOT NULL,   -- event title (defaults to record.name)
    event_types     text        NOT NULL DEFAULT '["other"]',  -- JSON array as text

    start_time      timestamptz NOT NULL,
    end_time        timestamptz,

    created_at      timestamptz NOT NULL DEFAULT NOW(),
    updated_at      timestamptz NOT NULL DEFAULT NOW(),
    synced_at       timestamptz,
    version         integer     NOT NULL DEFAULT 1,

    is_deleted      boolean     NOT NULL DEFAULT FALSE,
    is_removed      boolean     NOT NULL DEFAULT FALSE,
    removal_reason  text,
    is_checked      boolean     NOT NULL DEFAULT FALSE,
    has_charge_items boolean    NOT NULL DEFAULT FALSE,

    original_event_id uuid,   -- for split/merge history if needed
    new_event_id      uuid
);

COMMENT ON TABLE public.events
    IS 'Events (appointments, visits, etc.) for books, each tied to a global record.';

COMMENT ON COLUMN public.events.record_uuid
    IS 'Global record/person/case identifier. Same record_uuid across books shares meta & note.';

COMMENT ON COLUMN public.events.title
    IS 'Event display title, typically defaults to record.name but can be customized.';

COMMENT ON COLUMN public.events.event_types
    IS 'JSON array of event types, e.g. ["consultation","treatment"].';

CREATE INDEX idx_events_book_uuid   ON public.events(book_uuid);
CREATE INDEX idx_events_record_uuid ON public.events(record_uuid);
CREATE INDEX idx_events_device_id   ON public.events(device_id);
CREATE INDEX idx_events_start_time  ON public.events(start_time);
CREATE INDEX idx_events_book_uuid_time ON public.events(book_uuid, start_time);

-- Triggers for events
CREATE TRIGGER increment_events_version
    BEFORE UPDATE ON public.events
    FOR EACH ROW EXECUTE FUNCTION public.increment_version();

CREATE TRIGGER update_events_updated_at
    BEFORE UPDATE ON public.events
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


-- -------------------------
-- 3.5 Notes (one shared multi-page note per record)
-- -------------------------
CREATE TABLE public.notes (
    id          uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
    record_uuid uuid        NOT NULL REFERENCES public.records(record_uuid) ON DELETE CASCADE,
    device_id   uuid        NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    pages_data  text        NOT NULL DEFAULT '[[]]',  -- serialized multi-page content (JSON array of arrays)
    created_at  timestamptz NOT NULL DEFAULT NOW(),
    updated_at  timestamptz NOT NULL DEFAULT NOW(),
    synced_at   timestamptz,
    version     integer     NOT NULL DEFAULT 1,
    is_deleted  boolean     NOT NULL DEFAULT FALSE,
    locked_by_device_id text,
    locked_at   timestamptz
);

COMMENT ON TABLE public.notes
    IS 'Multi-page note shared by all events for the same global record.';

COMMENT ON COLUMN public.notes.record_uuid
    IS 'One-to-one with records; all events for that record share this note.';

-- Enforce exactly one note per record
CREATE UNIQUE INDEX idx_notes_record_uuid
    ON public.notes(record_uuid);

CREATE INDEX idx_notes_device_id ON public.notes(device_id);
CREATE INDEX idx_notes_locked_by ON public.notes(locked_by_device_id);
CREATE INDEX idx_notes_updated ON public.notes(updated_at DESC);

-- Triggers for notes
CREATE TRIGGER increment_notes_version
    BEFORE UPDATE ON public.notes
    FOR EACH ROW EXECUTE FUNCTION public.increment_version();

CREATE TRIGGER update_notes_updated_at
    BEFORE UPDATE ON public.notes
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMIT;

-- =========================================================
-- 4. Ancillary tables
-- =========================================================

BEGIN;

-- -------------------------
-- 4.1 Book–device access (multi-device sharing)
-- -------------------------
CREATE TABLE public.book_device_access (
    book_uuid   uuid        NOT NULL REFERENCES public.books(book_uuid) ON DELETE CASCADE,
    device_id   uuid        NOT NULL REFERENCES public.devices(id)      ON DELETE CASCADE,
    access_type text        NOT NULL DEFAULT 'owner',   -- owner, editor, viewer
    created_at  timestamptz NOT NULL DEFAULT NOW(),
    PRIMARY KEY (book_uuid, device_id)
);

COMMENT ON TABLE public.book_device_access
    IS 'Controls which devices can access which books and their permission level.';

CREATE INDEX idx_book_device_access_device_id
    ON public.book_device_access(device_id);


-- -------------------------
-- 4.2 Book backups
-- -------------------------
CREATE TABLE public.book_backups (
    id                 bigserial   PRIMARY KEY,
    backup_name        text        NOT NULL,
    device_id          uuid        NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    book_uuid          uuid        NOT NULL REFERENCES public.books(book_uuid) ON DELETE CASCADE,

    backup_path        text        NOT NULL,   -- relative path from backup root
    backup_size_bytes  bigint,
    backup_type        text        NOT NULL DEFAULT 'full',      -- full, incremental, etc.
    status             text        NOT NULL DEFAULT 'completed', -- in_progress, completed, failed
    error_message      text,

    created_at         timestamptz NOT NULL DEFAULT NOW(),
    restored_at        timestamptz,
    restored_by_device_id uuid     REFERENCES public.devices(id),
    is_deleted         boolean     NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE public.book_backups
    IS 'File-based backups of books keyed by book_uuid.';

CREATE INDEX idx_book_backups_book_uuid  ON public.book_backups(book_uuid);
CREATE INDEX idx_book_backups_device_id  ON public.book_backups(device_id);
CREATE INDEX idx_book_backups_created    ON public.book_backups(created_at);
CREATE INDEX idx_book_backups_status     ON public.book_backups(status) WHERE status <> 'completed';


-- -------------------------
-- 4.3 Schedule drawings
-- -------------------------
CREATE TABLE public.schedule_drawings (
    id          bigserial   PRIMARY KEY,
    book_uuid   uuid        NOT NULL REFERENCES public.books(book_uuid) ON DELETE CASCADE,
    device_id   uuid        NOT NULL REFERENCES public.devices(id)      ON DELETE CASCADE,
    date        timestamptz NOT NULL,
    view_mode   integer     NOT NULL,   -- 0=day, 1=3-day, 2=week
    strokes_data text,
    created_at  timestamptz NOT NULL DEFAULT NOW(),
    updated_at  timestamptz NOT NULL DEFAULT NOW(),
    synced_at   timestamptz NOT NULL DEFAULT NOW(),
    version     integer     NOT NULL DEFAULT 1,
    is_deleted  boolean     NOT NULL DEFAULT FALSE,

    CONSTRAINT schedule_drawings_book_date_view_unique
        UNIQUE (book_uuid, date, view_mode)
);

COMMENT ON TABLE public.schedule_drawings
    IS 'Handwriting overlay on schedule views, per book/date/view_mode.';

CREATE INDEX idx_schedule_drawings_device_id ON public.schedule_drawings(device_id);
CREATE INDEX idx_schedule_drawings_book_uuid ON public.schedule_drawings(book_uuid);

-- Triggers for schedule_drawings
CREATE TRIGGER increment_schedule_drawings_version
    BEFORE UPDATE ON public.schedule_drawings
    FOR EACH ROW EXECUTE FUNCTION public.increment_version();

CREATE TRIGGER update_schedule_drawings_updated_at
    BEFORE UPDATE ON public.schedule_drawings
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


-- -------------------------
-- 4.4 Sync log
-- -------------------------
CREATE TABLE public.sync_log (
    id            bigserial   PRIMARY KEY,
    device_id     uuid        NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    operation     text        NOT NULL,  -- insert, update, delete, sync_pull, sync_push, etc.
    table_name    text        NOT NULL,
    record_id     uuid,                  -- ID of record in that table when applicable
    status        text        NOT NULL,  -- success, failed
    error_message text,
    changes_count integer     NOT NULL DEFAULT 0,
    synced_at     timestamptz NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.sync_log
    IS 'Audit trail of all sync operations.';

CREATE INDEX idx_sync_log_device_id  ON public.sync_log(device_id);
CREATE INDEX idx_sync_log_table_name ON public.sync_log(table_name);
CREATE INDEX idx_sync_log_synced_at  ON public.sync_log(synced_at);

COMMIT;

-- =========================================================
-- Summary of key behaviors:
-- =========================================================
--
-- 1. Global record_number identity:
--    - records.record_number is unique when non-empty
--    - Empty string ('') is allowed to duplicate for standalone records
--    - All events sharing the same record_number point to the same record_uuid
--    - They share records meta (name, phone) and the same notes row
--
-- 2. No record_number events:
--    - Use records rows with record_number = '' (empty string)
--    - Each such record_uuid is independent (one event per record)
--
-- 3. Notes are per-record:
--    - One note per record_uuid (enforced by unique index)
--    - All events for same record share the same note
--
-- =========================================================
