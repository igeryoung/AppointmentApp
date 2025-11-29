-- Migration: Add has_note column to events table
-- This column tracks whether an event has an associated note for faster queries

-- Add has_note column to events table
ALTER TABLE events ADD COLUMN IF NOT EXISTS has_note BOOLEAN DEFAULT false;

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_events_has_note ON events(has_note);

-- Update existing events to set has_note = true where a note exists
-- This ensures existing data is correctly populated
UPDATE events
SET has_note = true
WHERE EXISTS (
    SELECT 1 FROM notes
    WHERE notes.event_id = events.id
    AND notes.is_deleted = false
    AND notes.pages_data IS NOT NULL
    AND notes.pages_data != '[[]]'
    AND notes.pages_data != '[]'
    AND TRIM(notes.pages_data) != ''
);

-- Confirm migration completed
SELECT COUNT(*) as events_with_has_note_true
FROM events
WHERE has_note = true;
