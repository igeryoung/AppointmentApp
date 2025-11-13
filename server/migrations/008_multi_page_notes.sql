-- Migration: Multi-page handwriting notes
-- Date: 2025-11-12
-- Description: Add pages_data column and migrate existing single-page notes to multi-page format

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

-- Note: We're keeping strokes_data column for backward compatibility
-- It can be dropped in a future migration once all clients have upgraded
