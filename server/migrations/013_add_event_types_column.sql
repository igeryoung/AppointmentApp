-- Migration 013: Add event_types column back to events table
-- This column was missed in migration 012 when recreating the events table
-- event_types stores a JSON array of event types (e.g., '["consultation", "treatment"]')

-- Step 1: Add event_types column
ALTER TABLE events ADD COLUMN IF NOT EXISTS event_types TEXT;

-- Step 2: Migrate existing data - convert single event_type to JSON array
-- Handle both cases: event_type is present or null
UPDATE events
SET event_types = CASE
    WHEN event_type IS NOT NULL AND event_type != '' THEN '["' || event_type || '"]'
    ELSE '["other"]'
END
WHERE event_types IS NULL;

-- Step 3: Make event_types NOT NULL with default value
ALTER TABLE events ALTER COLUMN event_types SET DEFAULT '["other"]';
ALTER TABLE events ALTER COLUMN event_types SET NOT NULL;

-- Step 4: Verify migration
DO $$
DECLARE
  events_count INTEGER;
  null_event_types INTEGER;
  empty_event_types INTEGER;
BEGIN
  SELECT COUNT(*) INTO events_count FROM events;
  SELECT COUNT(*) INTO null_event_types FROM events WHERE event_types IS NULL;
  SELECT COUNT(*) INTO empty_event_types FROM events WHERE event_types = '[]';

  RAISE NOTICE '=== Migration 013 Verification ===';
  RAISE NOTICE 'Total Events: %', events_count;
  RAISE NOTICE 'NULL event_types: %', null_event_types;
  RAISE NOTICE 'Empty event_types: %', empty_event_types;

  IF null_event_types = 0 AND empty_event_types = 0 THEN
    RAISE NOTICE '✓ Migration successful - all events have event_types';
  ELSE
    RAISE EXCEPTION 'Migration failed - found % NULL or % empty event_types', null_event_types, empty_event_types;
  END IF;
END $$;

-- Add column comment
COMMENT ON COLUMN events.event_types IS 'JSON array of event types (e.g., ["consultation", "treatment"]). Must contain at least one type.';
