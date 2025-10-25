-- Add book_uuid column to books table for unique book identification across devices
-- This migration adds UUID support to books and updates book_backups to use UUIDs

-- Add book_uuid column to books table
ALTER TABLE books ADD COLUMN book_uuid UUID UNIQUE;

-- Generate UUIDs for existing books
UPDATE books SET book_uuid = uuid_generate_v4() WHERE book_uuid IS NULL;

-- Make book_uuid NOT NULL after populating existing rows
ALTER TABLE books ALTER COLUMN book_uuid SET NOT NULL;

-- Create index on book_uuid
CREATE INDEX idx_books_uuid ON books(book_uuid);

-- Add book_uuid column to book_backups table
ALTER TABLE book_backups ADD COLUMN book_uuid UUID;

-- Populate book_uuid in book_backups from books table (for existing backups)
UPDATE book_backups bb
SET book_uuid = b.book_uuid
FROM books b
WHERE bb.book_id = b.id AND bb.book_uuid IS NULL;

-- Add unique constraint on (device_id, book_uuid) to ensure one backup per book per device
CREATE UNIQUE INDEX idx_book_backups_device_uuid ON book_backups(device_id, book_uuid) WHERE is_deleted = false;

-- Comments
COMMENT ON COLUMN books.book_uuid IS 'Unique identifier for book across all devices';
COMMENT ON COLUMN book_backups.book_uuid IS 'UUID of the book (for identification across devices)';
COMMENT ON INDEX idx_book_backups_device_uuid IS 'Ensures one active backup per book per device';
