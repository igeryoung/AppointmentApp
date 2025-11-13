-- Migration: Add multi-type event support
-- Adds event_types column to store JSON array of event types

-- Add new event_types column to store JSON array
ALTER TABLE events ADD COLUMN event_types TEXT;

-- Migrate existing data: wrap single event_type in JSON array
-- For example: "consultation" becomes ["consultation"]
UPDATE events
SET event_types = '["' || event_type || '"]'
WHERE event_types IS NULL;

-- Make event_types NOT NULL after migration
ALTER TABLE events ALTER COLUMN event_types SET NOT NULL;

-- Optional: Keep event_type column for backward compatibility
-- or remove it if you want to fully migrate:
-- ALTER TABLE events DROP COLUMN event_type;

COMMENT ON COLUMN events.event_types IS 'JSON array of event types, sorted alphabetically';
