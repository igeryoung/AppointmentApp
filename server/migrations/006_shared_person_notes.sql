-- Add shared person notes with lock mechanism
-- This migration adds support for sharing handwritten notes across events
-- with the same (name + record_number) composite key, plus a lock mechanism
-- to prevent concurrent editing conflicts

-- Add normalized fields for person info sharing
ALTER TABLE notes ADD COLUMN person_name_normalized TEXT;
ALTER TABLE notes ADD COLUMN record_number_normalized TEXT;

-- Add lock mechanism columns
ALTER TABLE notes ADD COLUMN locked_by_device_id TEXT;
ALTER TABLE notes ADD COLUMN locked_at TIMESTAMP;

-- Create indexes for person lookup and lock management
CREATE INDEX idx_notes_person_key
  ON notes(person_name_normalized, record_number_normalized);

CREATE INDEX idx_notes_locked_by
  ON notes(locked_by_device_id);

-- Comments
COMMENT ON COLUMN notes.person_name_normalized IS 'Normalized (trimmed, lowercase) person name for shared notes';
COMMENT ON COLUMN notes.record_number_normalized IS 'Normalized (trimmed, lowercase) record number for shared notes';
COMMENT ON COLUMN notes.locked_by_device_id IS 'Device ID that currently holds the edit lock (NULL = unlocked)';
COMMENT ON COLUMN notes.locked_at IS 'Timestamp when lock was acquired (NULL = unlocked)';

-- Populate normalized fields for existing notes with record numbers
UPDATE notes
SET
  person_name_normalized = LOWER(TRIM(events.name)),
  record_number_normalized = LOWER(TRIM(events.record_number))
FROM events
WHERE notes.event_id = events.id
  AND events.record_number IS NOT NULL
  AND events.record_number != '';

-- Sync strokes from most recent note to all notes in same person group
-- This handles existing duplicates by applying last-modified-wins strategy
WITH latest_notes AS (
  SELECT DISTINCT ON (person_name_normalized, record_number_normalized)
    person_name_normalized,
    record_number_normalized,
    strokes_data,
    updated_at
  FROM notes
  WHERE person_name_normalized IS NOT NULL
    AND record_number_normalized IS NOT NULL
  ORDER BY person_name_normalized, record_number_normalized, updated_at DESC
)
UPDATE notes
SET
  strokes_data = latest_notes.strokes_data,
  updated_at = latest_notes.updated_at
FROM latest_notes
WHERE notes.person_name_normalized = latest_notes.person_name_normalized
  AND notes.record_number_normalized = latest_notes.record_number_normalized
  AND notes.updated_at < latest_notes.updated_at;
