-- Migration: Fix Timestamp Timezone Inconsistency
-- Convert all TIMESTAMP columns to TIMESTAMP WITH TIME ZONE (TIMESTAMPTZ)
-- This ensures all timestamps are stored with explicit timezone information (UTC)

-- Devices table
ALTER TABLE devices
    ALTER COLUMN registered_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN last_sync_at TYPE TIMESTAMP WITH TIME ZONE;

-- Books table
ALTER TABLE books
    ALTER COLUMN created_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN updated_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN archived_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN synced_at TYPE TIMESTAMP WITH TIME ZONE;

-- Events table
ALTER TABLE events
    ALTER COLUMN start_time TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN end_time TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN created_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN updated_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN synced_at TYPE TIMESTAMP WITH TIME ZONE;

-- Notes table
ALTER TABLE notes
    ALTER COLUMN created_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN updated_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN synced_at TYPE TIMESTAMP WITH TIME ZONE;

-- Schedule Drawings table
ALTER TABLE schedule_drawings
    ALTER COLUMN date TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN created_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN updated_at TYPE TIMESTAMP WITH TIME ZONE,
    ALTER COLUMN synced_at TYPE TIMESTAMP WITH TIME ZONE;

-- Sync Log table
ALTER TABLE sync_log
    ALTER COLUMN synced_at TYPE TIMESTAMP WITH TIME ZONE;

-- Update the trigger function to use timezone-aware CURRENT_TIMESTAMP
-- Note: CURRENT_TIMESTAMP in PostgreSQL is already timezone-aware and returns TIMESTAMPTZ
-- This update ensures consistency with the new column types
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add comment for documentation
COMMENT ON FUNCTION update_updated_at_column() IS 'Auto-update updated_at column with timezone-aware timestamp';
