-- Migration: Add multi-device access tracking for books
-- This allows books to be accessed by multiple devices while tracking which devices have interacted with each book

-- Create book_device_access table to track which devices have access to which books
CREATE TABLE IF NOT EXISTS book_device_access (
    book_uuid UUID NOT NULL,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    access_type VARCHAR(50) NOT NULL CHECK (access_type IN ('created', 'restored', 'pulled')),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (book_uuid, device_id)
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_book_device_access_book ON book_device_access(book_uuid);
CREATE INDEX IF NOT EXISTS idx_book_device_access_device ON book_device_access(device_id);
CREATE INDEX IF NOT EXISTS idx_book_device_access_type ON book_device_access(access_type);

-- Migrate existing data: Add entries for all existing book backups
-- This ensures backward compatibility by giving existing devices access to their books
INSERT INTO book_device_access (book_uuid, device_id, access_type, created_at)
SELECT DISTINCT
    bb.book_uuid,
    bb.device_id,
    'created' as access_type,
    bb.created_at
FROM book_backups bb
WHERE bb.book_uuid IS NOT NULL
  AND bb.is_deleted = false
ON CONFLICT (book_uuid, device_id) DO NOTHING;

-- Also add entries from books table (for books that may not have backups yet)
INSERT INTO book_device_access (book_uuid, device_id, access_type, created_at)
SELECT DISTINCT
    b.book_uuid,
    b.device_id,
    'created' as access_type,
    b.created_at
FROM books b
WHERE b.book_uuid IS NOT NULL
ON CONFLICT (book_uuid, device_id) DO NOTHING;
