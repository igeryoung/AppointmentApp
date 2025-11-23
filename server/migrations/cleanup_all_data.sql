-- Cleanup script: Remove all data from server database for testing
-- WARNING: This will DELETE ALL DATA! Only use in development/testing environments.

-- ============================================================================
-- Option 1: TRUNCATE CASCADE (Recommended for testing - fastest)
-- ============================================================================
-- This will remove all rows and reset auto-increment sequences

TRUNCATE TABLE
  notes,
  events,
  schedule_drawings,
  books,
  book_backups,
  device_info
CASCADE;

-- Reset sequences to start from 1
ALTER SEQUENCE IF EXISTS books_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS events_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS notes_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS schedule_drawings_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS book_backups_id_seq RESTART WITH 1;

-- ============================================================================
-- Verify cleanup
-- ============================================================================

DO $$
DECLARE
  books_count INTEGER;
  events_count INTEGER;
  notes_count INTEGER;
  drawings_count INTEGER;
  backups_count INTEGER;
  devices_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO books_count FROM books;
  SELECT COUNT(*) INTO events_count FROM events;
  SELECT COUNT(*) INTO notes_count FROM notes;
  SELECT COUNT(*) INTO drawings_count FROM schedule_drawings;
  SELECT COUNT(*) INTO backups_count FROM book_backups;
  SELECT COUNT(*) INTO devices_count FROM device_info;

  RAISE NOTICE '=== Database Cleanup Complete ===';
  RAISE NOTICE 'Books: %', books_count;
  RAISE NOTICE 'Events: %', events_count;
  RAISE NOTICE 'Notes: %', notes_count;
  RAISE NOTICE 'Schedule Drawings: %', drawings_count;
  RAISE NOTICE 'Book Backups: %', backups_count;
  RAISE NOTICE 'Device Info: %', devices_count;

  IF books_count = 0 AND events_count = 0 AND notes_count = 0
     AND drawings_count = 0 AND backups_count = 0 AND devices_count = 0 THEN
    RAISE NOTICE '✓ All data successfully cleaned';
  ELSE
    RAISE WARNING '⚠ Some data remains in tables';
  END IF;
END $$;
