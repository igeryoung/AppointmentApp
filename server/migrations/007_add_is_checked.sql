-- Add is_checked column for event completion status
-- This migration adds support for marking events as completed/checked

-- Add is_checked column to events table
ALTER TABLE events ADD COLUMN is_checked BOOLEAN DEFAULT false;

-- Comment
COMMENT ON COLUMN events.is_checked IS 'Marks event as completed/checked (default: false)';
