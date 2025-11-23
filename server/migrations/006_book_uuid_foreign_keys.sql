-- Migration 006: Add book_uuid foreign keys to events and schedule_drawings
-- This migration eliminates book_id conflicts by using book_uuid (UUID) as the
-- authoritative foreign key instead of book_id (auto-increment integer).

-- ============================================================================
-- STEP 1: Add book_uuid column to events table
-- ============================================================================

ALTER TABLE events ADD COLUMN IF NOT EXISTS book_uuid UUID;

-- Populate book_uuid from books table using existing book_id
UPDATE events e
SET book_uuid = b.book_uuid
FROM books b
WHERE e.book_id = b.id AND e.book_uuid IS NULL;

-- Make book_uuid NOT NULL after population (with safety check)
DO $$
DECLARE
  null_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO null_count FROM events WHERE book_uuid IS NULL;

  IF null_count > 0 THEN
    RAISE WARNING 'Found % events without book_uuid - these may be orphaned', null_count;
    RAISE EXCEPTION 'Cannot set book_uuid NOT NULL - some events have no matching book';
  END IF;

  ALTER TABLE events ALTER COLUMN book_uuid SET NOT NULL;
  RAISE NOTICE 'Successfully set events.book_uuid to NOT NULL';
END $$;

-- Add foreign key constraint to book_uuid
ALTER TABLE events
  DROP CONSTRAINT IF EXISTS fk_events_book_uuid;

ALTER TABLE events
  ADD CONSTRAINT fk_events_book_uuid
  FOREIGN KEY (book_uuid)
  REFERENCES books(book_uuid)
  ON DELETE CASCADE;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_events_book_uuid ON events(book_uuid);

-- Deprecate old book_id foreign key (keep column for backward compatibility)
COMMENT ON COLUMN events.book_id IS
  'DEPRECATED: Use book_uuid instead. Kept for backward compatibility. '
  'Foreign key constraint removed in favor of book_uuid.';

-- ============================================================================
-- STEP 2: Add book_uuid column to schedule_drawings table
-- ============================================================================

ALTER TABLE schedule_drawings ADD COLUMN IF NOT EXISTS book_uuid UUID;

-- Populate book_uuid from books table using existing book_id
UPDATE schedule_drawings sd
SET book_uuid = b.book_uuid
FROM books b
WHERE sd.book_id = b.id AND sd.book_uuid IS NULL;

-- Make book_uuid NOT NULL after population (with safety check)
DO $$
DECLARE
  null_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO null_count FROM schedule_drawings WHERE book_uuid IS NULL;

  IF null_count > 0 THEN
    RAISE WARNING 'Found % schedule_drawings without book_uuid - these may be orphaned', null_count;
    RAISE EXCEPTION 'Cannot set book_uuid NOT NULL - some drawings have no matching book';
  END IF;

  ALTER TABLE schedule_drawings ALTER COLUMN book_uuid SET NOT NULL;
  RAISE NOTICE 'Successfully set schedule_drawings.book_uuid to NOT NULL';
END $$;

-- Add foreign key constraint to book_uuid
ALTER TABLE schedule_drawings
  DROP CONSTRAINT IF EXISTS fk_drawings_book_uuid;

ALTER TABLE schedule_drawings
  ADD CONSTRAINT fk_drawings_book_uuid
  FOREIGN KEY (book_uuid)
  REFERENCES books(book_uuid)
  ON DELETE CASCADE;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_drawings_book_uuid ON schedule_drawings(book_uuid);

-- Update composite unique constraint to use book_uuid
ALTER TABLE schedule_drawings
  DROP CONSTRAINT IF EXISTS schedule_drawings_book_id_date_view_mode_key;

-- Note: Keeping the old unique constraint for now to avoid breaking existing queries
-- New applications should use (book_uuid, date, view_mode) combination

-- Deprecate old book_id foreign key (keep column for backward compatibility)
COMMENT ON COLUMN schedule_drawings.book_id IS
  'DEPRECATED: Use book_uuid instead. Kept for backward compatibility. '
  'Foreign key constraint removed in favor of book_uuid.';

-- ============================================================================
-- STEP 3: Verify data integrity
-- ============================================================================

DO $$
DECLARE
  events_count INTEGER;
  drawings_count INTEGER;
  events_uuid_count INTEGER;
  drawings_uuid_count INTEGER;
BEGIN
  -- Count total records
  SELECT COUNT(*) INTO events_count FROM events;
  SELECT COUNT(*) INTO drawings_count FROM schedule_drawings;

  -- Count records with book_uuid
  SELECT COUNT(*) INTO events_uuid_count FROM events WHERE book_uuid IS NOT NULL;
  SELECT COUNT(*) INTO drawings_uuid_count FROM schedule_drawings WHERE book_uuid IS NOT NULL;

  RAISE NOTICE '=== Migration 006 Verification ===';
  RAISE NOTICE 'Events: % total, % with book_uuid', events_count, events_uuid_count;
  RAISE NOTICE 'Schedule Drawings: % total, % with book_uuid', drawings_count, drawings_uuid_count;

  IF events_count = events_uuid_count AND drawings_count = drawings_uuid_count THEN
    RAISE NOTICE '✓ All records successfully migrated to book_uuid foreign keys';
  ELSE
    RAISE WARNING '⚠ Some records missing book_uuid - data integrity issue detected';
  END IF;
END $$;

-- ============================================================================
-- STEP 4: Migration complete
-- ============================================================================

COMMENT ON TABLE events IS
  'Events table now uses book_uuid as the authoritative foreign key to books. '
  'book_id column is deprecated but kept for backward compatibility.';

COMMENT ON TABLE schedule_drawings IS
  'Schedule drawings table now uses book_uuid as the authoritative foreign key to books. '
  'book_id column is deprecated but kept for backward compatibility.';
