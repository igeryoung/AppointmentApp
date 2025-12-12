-- =========================================================
-- Migration 016: Remove redundant device_id columns and book_backups
--
-- - device_id in events/notes/drawings is redundant (derived from book)
-- - book_backups table removed (not needed)
-- - notes keeps locked_by_device_id for edit locking
-- =========================================================

BEGIN;

-- Drop book_backups table
DROP TABLE IF EXISTS public.book_backups CASCADE;

-- Remove device_id from events
ALTER TABLE public.events DROP COLUMN IF EXISTS device_id;

-- Remove device_id from notes (keep locked_by_device_id)
ALTER TABLE public.notes DROP COLUMN IF EXISTS device_id;

-- Remove device_id from schedule_drawings
ALTER TABLE public.schedule_drawings DROP COLUMN IF EXISTS device_id;

-- Drop indexes that referenced device_id
DROP INDEX IF EXISTS idx_events_device_id;
DROP INDEX IF EXISTS idx_notes_device_id;
DROP INDEX IF EXISTS idx_schedule_drawings_device_id;

COMMIT;
