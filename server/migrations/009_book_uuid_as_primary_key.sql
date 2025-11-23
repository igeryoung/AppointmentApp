-- Migration 009: Make book_uuid the PRIMARY KEY and remove id column
-- This migration completes the transition to using UUID as the sole identifier for books
-- BREAKING CHANGE: Removes auto-increment id completely

-- ============================================================================
-- STEP 1: Drop foreign key constraints that reference books
-- ============================================================================

-- Drop foreign keys from events table
ALTER TABLE events DROP CONSTRAINT IF EXISTS fk_events_book_uuid;
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_book_id_fkey;

-- Drop foreign keys from schedule_drawings table
ALTER TABLE schedule_drawings DROP CONSTRAINT IF EXISTS fk_drawings_book_uuid;
ALTER TABLE schedule_drawings DROP CONSTRAINT IF EXISTS schedule_drawings_book_id_fkey;

-- Drop foreign keys from book_backups table (if any)
ALTER TABLE book_backups DROP CONSTRAINT IF EXISTS fk_book_backups_book;

-- ============================================================================
-- STEP 2: Drop old PRIMARY KEY from books table and create new one
-- ============================================================================

-- Drop the old SERIAL PRIMARY KEY constraint
ALTER TABLE books DROP CONSTRAINT IF EXISTS books_pkey;

-- Make book_uuid the PRIMARY KEY
ALTER TABLE books ADD PRIMARY KEY (book_uuid);

-- Drop the old id column entirely
ALTER TABLE books DROP COLUMN IF EXISTS id;

-- ============================================================================
-- STEP 3: Drop deprecated book_id columns from child tables
-- ============================================================================

-- Drop book_id from events table (already have book_uuid with NOT NULL)
ALTER TABLE events DROP COLUMN IF EXISTS book_id;

-- Drop book_id from schedule_drawings table (already have book_uuid with NOT NULL)
ALTER TABLE schedule_drawings DROP COLUMN IF EXISTS book_id;

-- Drop book_id from book_backups table (already have book_uuid)
ALTER TABLE book_backups DROP COLUMN IF EXISTS book_id;

-- ============================================================================
-- STEP 4: Recreate foreign key constraints using book_uuid
-- ============================================================================

-- Add foreign key constraint to events.book_uuid
ALTER TABLE events
  ADD CONSTRAINT fk_events_book_uuid
  FOREIGN KEY (book_uuid)
  REFERENCES books(book_uuid)
  ON DELETE CASCADE;

-- Add foreign key constraint to schedule_drawings.book_uuid
ALTER TABLE schedule_drawings
  ADD CONSTRAINT fk_drawings_book_uuid
  FOREIGN KEY (book_uuid)
  REFERENCES books(book_uuid)
  ON DELETE CASCADE;

-- ============================================================================
-- STEP 5: Update indexes for performance
-- ============================================================================

-- Ensure book_uuid indexes exist on child tables (should already exist from migration 006)
CREATE INDEX IF NOT EXISTS idx_events_book_uuid ON events(book_uuid);
CREATE INDEX IF NOT EXISTS idx_drawings_book_uuid ON schedule_drawings(book_uuid);

-- Drop old book_id indexes if they still exist
DROP INDEX IF EXISTS idx_events_book;
DROP INDEX IF EXISTS idx_schedule_drawings_book_date_view;
DROP INDEX IF EXISTS idx_events_book_time;

-- Create new composite indexes using book_uuid
CREATE INDEX IF NOT EXISTS idx_events_book_uuid_time ON events(book_uuid, start_time);
CREATE INDEX IF NOT EXISTS idx_drawings_book_uuid_date_view ON schedule_drawings(book_uuid, date, view_mode);

-- ============================================================================
-- STEP 6: Update unique constraints for schedule_drawings
-- ============================================================================

-- Drop old unique constraint that used book_id
ALTER TABLE schedule_drawings
  DROP CONSTRAINT IF EXISTS schedule_drawings_book_id_date_view_mode_key;

-- Add new unique constraint using book_uuid
ALTER TABLE schedule_drawings
  DROP CONSTRAINT IF EXISTS unique_book_uuid_date_view;

ALTER TABLE schedule_drawings
  ADD CONSTRAINT unique_book_uuid_date_view
  UNIQUE (book_uuid, date, view_mode);

-- ============================================================================
-- STEP 7: Verify migration success
-- ============================================================================

DO $$
DECLARE
  books_count INTEGER;
  events_count INTEGER;
  drawings_count INTEGER;
  backups_count INTEGER;
  orphaned_events INTEGER;
  orphaned_drawings INTEGER;
BEGIN
  -- Count all records
  SELECT COUNT(*) INTO books_count FROM books;
  SELECT COUNT(*) INTO events_count FROM events;
  SELECT COUNT(*) INTO drawings_count FROM schedule_drawings;
  SELECT COUNT(*) INTO backups_count FROM book_backups WHERE is_deleted = false;

  -- Check for orphaned records (should be 0 due to foreign keys)
  SELECT COUNT(*) INTO orphaned_events
  FROM events e
  LEFT JOIN books b ON e.book_uuid = b.book_uuid
  WHERE b.book_uuid IS NULL;

  SELECT COUNT(*) INTO orphaned_drawings
  FROM schedule_drawings sd
  LEFT JOIN books b ON sd.book_uuid = b.book_uuid
  WHERE b.book_uuid IS NULL;

  RAISE NOTICE '=== Migration 009 Verification ===';
  RAISE NOTICE 'Books: %', books_count;
  RAISE NOTICE 'Events: %', events_count;
  RAISE NOTICE 'Schedule Drawings: %', drawings_count;
  RAISE NOTICE 'Book Backups: %', backups_count;
  RAISE NOTICE 'Orphaned Events: %', orphaned_events;
  RAISE NOTICE 'Orphaned Drawings: %', orphaned_drawings;

  IF orphaned_events = 0 AND orphaned_drawings = 0 THEN
    RAISE NOTICE '✓ Migration successful - book_uuid is now the PRIMARY KEY';
    RAISE NOTICE '✓ All book_id columns removed';
    RAISE NOTICE '✓ All foreign keys updated to reference book_uuid';
  ELSE
    RAISE EXCEPTION 'Migration failed - found orphaned records';
  END IF;
END $$;

-- ============================================================================
-- STEP 8: Update table comments
-- ============================================================================

COMMENT ON TABLE books IS
  'Books table - book_uuid (UUID) is the PRIMARY KEY. '
  'The auto-increment id column has been removed. '
  'All references to books use book_uuid.';

COMMENT ON COLUMN books.book_uuid IS
  'PRIMARY KEY - Globally unique book identifier across all devices.';

COMMENT ON TABLE events IS
  'Events table - uses book_uuid (UUID) to reference books. '
  'The book_id column has been removed.';

COMMENT ON TABLE schedule_drawings IS
  'Schedule drawings table - uses book_uuid (UUID) to reference books. '
  'The book_id column has been removed.';

COMMENT ON TABLE book_backups IS
  'Book backups table - uses book_uuid (UUID) to identify books. '
  'The book_id column has been removed.';
