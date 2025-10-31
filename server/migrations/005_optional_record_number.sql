-- Make record_number optional in events table
-- This migration removes the NOT NULL constraint from the record_number column
-- Existing data is preserved as-is

-- Remove NOT NULL constraint from record_number
ALTER TABLE events ALTER COLUMN record_number DROP NOT NULL;

-- Comment
COMMENT ON COLUMN events.record_number IS 'Case/record number (optional)';
