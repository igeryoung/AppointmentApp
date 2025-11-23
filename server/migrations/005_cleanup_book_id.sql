-- Migration 005: Cleanup book_id usage and ensure book_uuid consistency
-- This migration addresses the book ID conflict issue where multiple devices
-- could upload books with the same local book_id, causing data conflicts.

-- Step 1: Ensure all backups have book_uuid populated
-- Extract book_uuid from backup_data for any backups missing it
UPDATE book_backups
SET book_uuid = (backup_data->'book'->>'book_uuid')::uuid
WHERE book_uuid IS NULL
  AND backup_data IS NOT NULL
  AND backup_data->'book'->>'book_uuid' IS NOT NULL;

-- Step 2: Verify data integrity
-- Check that all non-deleted backups have book_uuid
DO $$
DECLARE
  missing_uuid_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO missing_uuid_count
  FROM book_backups
  WHERE book_uuid IS NULL AND is_deleted = false;

  IF missing_uuid_count > 0 THEN
    RAISE WARNING 'Found % backups without book_uuid', missing_uuid_count;
  ELSE
    RAISE NOTICE 'All backups have book_uuid - data integrity verified';
  END IF;
END $$;

-- Step 3: Add comment to deprecate book_id column
COMMENT ON COLUMN book_backups.book_id IS
  'DEPRECATED: Local book ID from client device. Use book_uuid instead. '
  'This field is kept for reference only and should not be used for queries. '
  'Multiple devices can have books with the same book_id, causing conflicts.';

COMMENT ON COLUMN book_backups.book_uuid IS
  'Globally unique book identifier (UUID). This is the authoritative identifier '
  'for books across all devices. Always use this for queries instead of book_id.';

-- Step 4: Verify unique constraint exists
-- The unique constraint on (device_id, book_uuid) should already exist from migration 003
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE indexname = 'idx_book_backups_device_uuid'
  ) THEN
    RAISE EXCEPTION 'Missing unique index idx_book_backups_device_uuid - run migration 003 first';
  ELSE
    RAISE NOTICE 'Unique constraint on (device_id, book_uuid) verified';
  END IF;
END $$;

-- Step 5: Create index on book_uuid for faster lookups
-- (if it doesn't already exist)
CREATE INDEX IF NOT EXISTS idx_book_backups_uuid ON book_backups(book_uuid)
WHERE is_deleted = false;

-- Step 6: Report statistics
DO $$
DECLARE
  total_backups INTEGER;
  unique_books INTEGER;
  books_with_conflicts INTEGER;
BEGIN
  -- Count total backups
  SELECT COUNT(*) INTO total_backups
  FROM book_backups
  WHERE is_deleted = false;

  -- Count unique book UUIDs
  SELECT COUNT(DISTINCT book_uuid) INTO unique_books
  FROM book_backups
  WHERE is_deleted = false;

  -- Count books where multiple devices have same book_id (the conflict case)
  SELECT COUNT(*) INTO books_with_conflicts
  FROM (
    SELECT book_id
    FROM book_backups
    WHERE is_deleted = false AND book_id IS NOT NULL
    GROUP BY book_id
    HAVING COUNT(DISTINCT device_id) > 1
  ) conflicts;

  RAISE NOTICE '=== Migration 005 Statistics ===';
  RAISE NOTICE 'Total backups: %', total_backups;
  RAISE NOTICE 'Unique books (by UUID): %', unique_books;
  RAISE NOTICE 'Books with book_id conflicts: %', books_with_conflicts;

  IF books_with_conflicts > 0 THEN
    RAISE NOTICE 'Found % books where multiple devices used the same book_id', books_with_conflicts;
    RAISE NOTICE 'These conflicts are resolved by using book_uuid instead';
  END IF;
END $$;
