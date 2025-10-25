# Book Backup/Restore Feature Guide

## Overview
The book backup feature allows you to upload complete books (including all events, notes, and drawings) to the server and restore them later. This is independent of the sync system.

## Prerequisites
1. Device must be registered (use Sync Test screen to register)
2. Server must be running at `http://169.254.230.40:8080`
3. PostgreSQL migration `002_book_backups.sql` must be applied

## How to Use

### Upload a Book to Server
1. Open the Book List screen
2. Find the book you want to upload
3. Tap the three-dot menu on the book card
4. Select "Upload to Server"
5. The book (with all its events, notes, and drawings) will be uploaded
6. A success message will show the Backup ID

### Restore a Book from Server
1. Open the Book List screen
2. Tap the cloud download icon in the app bar (top right)
3. A dialog will show all available backups
4. Each backup shows:
   - Book ID
   - Backup name
   - Creation date/time
   - Size in KB
   - Restoration status (if previously restored)
5. Tap on a backup to select it
6. The book will be restored on the server
7. Use "Pull Changes" in Sync Test screen to download it to the device

## Technical Details

### Upload Process
- Collects all data from local SQLite database:
  - Book metadata
  - All events for the book
  - All notes for those events
  - All schedule drawings for the book
- Sends complete dataset to server as JSONB
- Server stores in `book_backups` table

### Restore Process
- Server-side restoration only (doesn't automatically sync to device)
- Replaces existing book if same ID exists (CASCADE delete)
- Creates fresh book with all related data
- Marks backup as "restored" with timestamp

### API Endpoints
- `POST /api/books/upload` - Upload a book
- `GET /api/books/list` - List all backups for device
- `POST /api/books/restore/{backupId}` - Restore a book
- `DELETE /api/books/{backupId}` - Delete a backup

### Database Schema
```sql
CREATE TABLE book_backups (
    id SERIAL PRIMARY KEY,
    book_id INTEGER,
    backup_name VARCHAR(255) NOT NULL,
    device_id UUID NOT NULL REFERENCES devices(id),
    backup_data JSONB NOT NULL,
    backup_size INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    restored_at TIMESTAMP,
    is_deleted BOOLEAN DEFAULT false
);
```

## Testing Checklist

### Test 1: Upload a Book
- [ ] Create a test book with events and notes
- [ ] Upload book to server
- [ ] Verify success message with backup ID
- [ ] Check PostgreSQL: `SELECT * FROM book_backups;`
- [ ] Verify backup_data contains book, events, notes, drawings

### Test 2: List Backups
- [ ] Tap cloud download icon in app bar
- [ ] Verify backup list shows all uploaded books
- [ ] Verify backup metadata (name, size, date) is correct
- [ ] Verify UI displays properly

### Test 3: Restore a Book
- [ ] Delete the original book from device
- [ ] Tap cloud download icon
- [ ] Select backup to restore
- [ ] Verify "restored on server" message
- [ ] Go to Sync Test screen
- [ ] Tap "Pull Changes"
- [ ] Verify book reappears in book list
- [ ] Open book and verify all events, notes, drawings are restored

### Test 4: Replace Existing Book
- [ ] Upload a book (Backup A)
- [ ] Modify the book (add/remove events)
- [ ] Upload the same book again (Backup B)
- [ ] Restore Backup A (older version)
- [ ] Pull changes
- [ ] Verify book reverted to older state

### Test 5: Multiple Backups
- [ ] Create and upload 3 different books
- [ ] Verify all 3 appear in backup list
- [ ] Restore each one individually
- [ ] Verify each restoration is independent

## Known Limitations
1. Restore is server-side only - requires sync pull to download
2. No automatic conflict resolution - restore replaces existing book
3. Web platform not supported (mobile/desktop only)
4. Server URL is hardcoded in `book_list_screen.dart:35`

## Troubleshooting

### "Device not registered" error
- Go to Sync Test screen
- Register device with server first

### "Failed to upload book" error
- Check server is running: `http://169.254.230.40:8080/health`
- Check device network connectivity
- Check server logs for detailed error

### "No backups available"
- Verify device ID matches (may be different device)
- Check `book_backups` table in PostgreSQL
- Verify `is_deleted = false` in database

### Backup not appearing after restore
- Restore only updates server, not local device
- Must use "Pull Changes" to download
- Check sync system is working
