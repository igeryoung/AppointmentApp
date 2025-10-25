-- Book Backups Feature
-- Allow users to upload complete books to server and restore them

-- Book backups table - Store complete book snapshots
CREATE TABLE book_backups (
    id SERIAL PRIMARY KEY,
    book_id INTEGER, -- Original book ID (may not exist if deleted)
    backup_name VARCHAR(255) NOT NULL,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    backup_data JSONB NOT NULL, -- Complete book data: {book, events, notes, drawings}
    backup_size INTEGER, -- Size in bytes for display
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    restored_at TIMESTAMP, -- Track if/when backup was restored
    is_deleted BOOLEAN DEFAULT false
);

CREATE INDEX idx_book_backups_device ON book_backups(device_id);
CREATE INDEX idx_book_backups_book ON book_backups(book_id);
CREATE INDEX idx_book_backups_created ON book_backups(created_at);
CREATE INDEX idx_book_backups_deleted ON book_backups(is_deleted) WHERE is_deleted = false;

COMMENT ON TABLE book_backups IS 'Complete book backups including all related data';
COMMENT ON COLUMN book_backups.backup_data IS 'JSONB containing book, events, notes, and schedule_drawings arrays';
COMMENT ON COLUMN book_backups.backup_size IS 'Total size of backup data in bytes';
