-- Migration: Server-Store Architecture Optimization
-- Date: 2025-10-23
-- Phase: 1-01 (Server Schema Changes)
-- Description: Adds file-based backup support and optimizes indexes for Server-Store pattern

-- ============================================
-- Part 1: Enhance book_backups for File-Based Storage
-- ============================================

-- Add file-based backup columns (keeping existing JSONB for backward compatibility)
ALTER TABLE book_backups ADD COLUMN IF NOT EXISTS backup_path TEXT;
ALTER TABLE book_backups ADD COLUMN IF NOT EXISTS backup_size_bytes BIGINT;
ALTER TABLE book_backups ADD COLUMN IF NOT EXISTS backup_type VARCHAR(50) DEFAULT 'full';
ALTER TABLE book_backups ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'completed';
ALTER TABLE book_backups ADD COLUMN IF NOT EXISTS error_message TEXT;
ALTER TABLE book_backups ADD COLUMN IF NOT EXISTS restored_by_device_id UUID;

-- Make backup_data nullable to support file-based backups
ALTER TABLE book_backups ALTER COLUMN backup_data DROP NOT NULL;

-- Add indexes for backup management
CREATE INDEX IF NOT EXISTS idx_book_backups_status ON book_backups(status) WHERE status != 'completed';

-- Update comments
COMMENT ON COLUMN book_backups.backup_path IS 'Relative path from backup root directory (for file-based backups)';
COMMENT ON COLUMN book_backups.backup_type IS 'full: complete backup, incremental: changes only (future)';
COMMENT ON COLUMN book_backups.status IS 'in_progress, completed, failed - tracks async backup operations';
COMMENT ON COLUMN book_backups.backup_data IS 'JSONB backup (legacy) - new backups should use backup_path';

-- ============================================
-- Part 2: Add Server-Store Optimized Indexes
-- ============================================

-- Notes: Optimize for event_id lookup (already exists, but ensure it's there)
CREATE INDEX IF NOT EXISTS idx_notes_event ON notes(event_id);

-- Notes: Optimize for "recently modified" queries
CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes(updated_at DESC);

-- Schedule Drawings: Optimize for book+date+viewMode lookup
CREATE INDEX IF NOT EXISTS idx_drawings_lookup
ON schedule_drawings(book_id, date, view_mode);

-- Events: Optimize for book+time range queries with smart preloading
CREATE INDEX IF NOT EXISTS idx_events_book_time_range
ON events(book_id, start_time)
WHERE is_removed = false;

-- ============================================
-- Part 3: Remove Sync-Specific Indexes
-- ============================================

-- These indexes were designed for the old sync architecture
-- Server-Store doesn't need synced_at tracking
DROP INDEX IF EXISTS idx_notes_synced;
DROP INDEX IF EXISTS idx_notes_deleted;
DROP INDEX IF EXISTS idx_events_synced;
DROP INDEX IF EXISTS idx_events_deleted;
DROP INDEX IF EXISTS idx_books_synced;
DROP INDEX IF EXISTS idx_books_deleted;
DROP INDEX IF EXISTS idx_schedule_drawings_synced;
DROP INDEX IF EXISTS idx_schedule_drawings_deleted;

-- ============================================
-- Part 4: Verification
-- ============================================

DO $$
DECLARE
    v_count INTEGER;
BEGIN
    -- Verify new columns exist
    SELECT COUNT(*) INTO v_count
    FROM information_schema.columns
    WHERE table_name = 'book_backups'
    AND column_name = 'backup_path';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'backup_path column not created';
    END IF;

    -- Verify Server-Store indexes exist
    SELECT COUNT(*) INTO v_count
    FROM pg_indexes
    WHERE indexname IN ('idx_notes_updated', 'idx_drawings_lookup', 'idx_events_book_time_range');

    IF v_count < 3 THEN
        RAISE WARNING 'Not all Server-Store indexes were created (found %, expected 3)', v_count;
    END IF;

    -- Verify sync indexes are removed
    SELECT COUNT(*) INTO v_count
    FROM pg_indexes
    WHERE indexname IN ('idx_notes_synced', 'idx_events_synced', 'idx_books_synced');

    IF v_count > 0 THEN
        RAISE WARNING 'Some sync indexes still exist (found %)', v_count;
    END IF;

    RAISE NOTICE '✅ Migration 004_server_store_optimization.sql completed successfully';
    RAISE NOTICE '   - File-based backup columns added to book_backups';
    RAISE NOTICE '   - Server-Store indexes created';
    RAISE NOTICE '   - Sync-specific indexes removed';
END $$;
