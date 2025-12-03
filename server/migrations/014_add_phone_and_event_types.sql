-- Migration 014: Add phone/has_charge_items columns and normalize event_types
-- Ensures server schema matches latest mobile client fields

-- 1. Add new columns if they do not exist
ALTER TABLE events ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE events ADD COLUMN IF NOT EXISTS has_charge_items BOOLEAN DEFAULT false;

-- Ensure has_charge_items defaults to false for all rows
UPDATE events
SET has_charge_items = false
WHERE has_charge_items IS NULL;

COMMENT ON COLUMN events.phone IS 'Patient phone number (optional, cached at event-level)';
COMMENT ON COLUMN events.has_charge_items IS 'True when related person has charge items cached on the device';

-- 2. Ensure event_types column exists and is properly populated
ALTER TABLE events ADD COLUMN IF NOT EXISTS event_types TEXT;

WITH normalized_types AS (
  SELECT
    id,
    CASE
      WHEN event_type IS NOT NULL AND BTRIM(event_type) <> '' THEN BTRIM(event_type)
      ELSE 'other'
    END AS primary_type
  FROM events
)
UPDATE events e
SET event_types = json_build_array(n.primary_type)::text
FROM normalized_types n
WHERE e.id = n.id
  AND (
    e.event_types IS NULL OR
    BTRIM(e.event_types) = '' OR
    e.event_types = '["other"]'
  );

-- Fallback: ensure column is never NULL/empty even if event_type was missing
UPDATE events
SET event_types = '["other"]'
WHERE event_types IS NULL OR BTRIM(event_types) = '';

-- Mirror first entry of event_types back to legacy event_type column
WITH primary_events AS (
  SELECT
    id,
    COALESCE(
      (
        SELECT value
        FROM json_array_elements_text(event_types::json)
        LIMIT 1
      ),
      'other'
    ) AS primary_type
  FROM events
)
UPDATE events e
SET event_type = p.primary_type
FROM primary_events p
WHERE e.id = p.id;

ALTER TABLE events
  ALTER COLUMN event_types SET DEFAULT '["other"]',
  ALTER COLUMN event_types SET NOT NULL;

COMMENT ON COLUMN events.event_types IS 'JSON array of event types (e.g., ["consultation","treatment"]). Must contain at least one type.';
