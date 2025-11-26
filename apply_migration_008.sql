-- Apply Migration 008: Multi-page handwriting notes
-- This adds the missing pages_data column to the notes table

-- Add new pages_data column
ALTER TABLE notes ADD COLUMN IF NOT EXISTS pages_data TEXT;

-- Migrate existing strokes_data to pages_data format (wrap in array)
-- Only migrate non-null, non-deleted notes
UPDATE notes
SET pages_data = CASE
    WHEN strokes_data IS NOT NULL AND strokes_data != '' THEN '[' || strokes_data || ']'
    ELSE '[[]]'
END
WHERE pages_data IS NULL AND is_deleted = false;

-- Set pages_data to [[]] for any notes that didn't have strokes_data
UPDATE notes
SET pages_data = '[[]]'
WHERE pages_data IS NULL;

-- Create index on pages_data for performance (optional)
CREATE INDEX IF NOT EXISTS idx_notes_pages_data ON notes USING GIN (to_tsvector('english', pages_data));

-- Verify the migration
DO $$
DECLARE
    has_column BOOLEAN;
    notes_count INTEGER;
    notes_with_data INTEGER;
BEGIN
    -- Check if pages_data column exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'notes' AND column_name = 'pages_data'
    ) INTO has_column;

    IF NOT has_column THEN
        RAISE EXCEPTION 'Migration failed: pages_data column not created';
    END IF;

    -- Count notes with pages_data
    SELECT COUNT(*) INTO notes_count FROM notes;
    SELECT COUNT(*) INTO notes_with_data FROM notes WHERE pages_data IS NOT NULL;

    RAISE NOTICE '✅ Migration 008 completed successfully';
    RAISE NOTICE '   - pages_data column added to notes table';
    RAISE NOTICE '   - Total notes: %', notes_count;
    RAISE NOTICE '   - Notes with pages_data: %', notes_with_data;
END $$;
