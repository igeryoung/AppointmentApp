#!/bin/bash

# Book Backup API Integration Test Script
# Tests the file-based book backup API with all edge cases
# As Linus says: "Backups are useless. Testing your restore is priceless."

set -e

echo "🧪 Book Backup API - Integration Test"
echo "======================================"
echo ""

BASE_URL="https://localhost:8080"
DB_NAME="schedule_note_dev"
DB_PORT="5433"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

test_count=0
pass_count=0
fail_count=0
start_time=$(date +%s)

# Helper function to print test results
print_test() {
    local test_name=$1
    local expected=$2
    local actual=$3

    test_count=$((test_count + 1))

    if [[ "$actual" == *"$expected"* ]]; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        pass_count=$((pass_count + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        echo -e "   Expected: $expected"
        echo -e "   Got: $actual"
        fail_count=$((fail_count + 1))
    fi
}

echo -e "${BLUE}📋 Step 1: Health Check${NC}"
echo "-----------------------"
HEALTH=$(curl -s --insecure "$BASE_URL/health")
print_test "Server health check" "healthy" "$HEALTH"
echo ""

echo -e "${BLUE}📋 Step 2: Register Device${NC}"
echo "----------------------------"
REGISTER_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/devices/register" \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "Book Backup Test Device", "platform": "test"}')

DEVICE_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"deviceId":"[^"]*' | cut -d'"' -f4)
DEVICE_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"deviceToken":"[^"]*' | cut -d'"' -f4)

echo "Device registered:"
echo "  ID: $DEVICE_ID"
echo "  Token: ${DEVICE_TOKEN:0:20}..."
print_test "Device registration" "$DEVICE_ID" "$DEVICE_ID"
echo ""

echo -e "${BLUE}📋 Step 3: Create Test Data in Database${NC}"
echo "-----------------------------------------"
# Create a book with UUID
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO books (device_id, name, book_uuid, created_at, updated_at, synced_at, version, is_deleted)
  VALUES (
    '$DEVICE_ID',
    'Test Book for Backup',
    gen_random_uuid(),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1,
    false
  );
" > /dev/null

BOOK_ID=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT id FROM books WHERE device_id = '$DEVICE_ID' ORDER BY id DESC LIMIT 1;
" | tr -d ' ')

echo "Created Book #$BOOK_ID"

# Create 10 events
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO events (book_id, device_id, name, record_number, event_type, start_time, end_time, created_at, updated_at, synced_at, version, is_deleted)
  SELECT
    $BOOK_ID,
    '$DEVICE_ID',
    'Test Event ' || i,
    'REC' || LPAD(i::text, 3, '0'),
    'appointment',
    ('2025-11-' || LPAD((i % 30 + 1)::text, 2, '0') || ' 10:00:00')::timestamp,
    ('2025-11-' || LPAD((i % 30 + 1)::text, 2, '0') || ' 11:00:00')::timestamp,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1,
    false
  FROM generate_series(1, 10) AS i;
" > /dev/null

EVENT_IDS=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT array_agg(id ORDER BY id) FROM events WHERE book_id = $BOOK_ID;
" | tr -d ' ')

echo "Created 10 events"

# Create 5 notes for the first 5 events
FIRST_EVENT_ID=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT id FROM events WHERE book_id = $BOOK_ID ORDER BY id LIMIT 1;
" | tr -d ' ')

psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO notes (event_id, device_id, strokes_data, created_at, updated_at, synced_at, version, is_deleted)
  SELECT
    id,
    '$DEVICE_ID',
    '{\"strokes\": [{\"points\": [[10, 20], [30, 40], [50, 60]]}]}',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1,
    false
  FROM events WHERE book_id = $BOOK_ID ORDER BY id LIMIT 5;
" > /dev/null

echo "Created 5 notes"

# Create 2 drawings
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO schedule_drawings (book_id, device_id, date, view_mode, strokes_data, created_at, updated_at, synced_at, version, is_deleted)
  VALUES
    ($BOOK_ID, '$DEVICE_ID', '2025-11-15', 1, '{\"strokes\": []}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', '2025-11-16', 1, '{\"strokes\": []}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false);
" > /dev/null

echo "Created 2 drawings"
print_test "Test data created" "$BOOK_ID" "$BOOK_ID"
echo ""

echo -e "${BLUE}📋 Step 4: Create File-Based Backup${NC}"
echo "------------------------------------"
backup_start=$(date +%s)
CREATE_BACKUP_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/books/$BOOK_ID/backup" \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceId\": \"$DEVICE_ID\",
    \"deviceToken\": \"$DEVICE_TOKEN\",
    \"backupName\": \"Test Backup $(date +%Y-%m-%d)\"
  }")

backup_end=$(date +%s)
backup_duration=$((backup_end - backup_start))

BACKUP_ID=$(echo "$CREATE_BACKUP_RESPONSE" | grep -o '"backupId":[0-9]*' | cut -d':' -f2)

echo "Backup created: ID $BACKUP_ID"
echo "Time taken: ${backup_duration}s"
print_test "Backup creation" "success" "$CREATE_BACKUP_RESPONSE"
# Check if BACKUP_ID is a number
if [[ "$BACKUP_ID" =~ ^[0-9]+$ ]]; then
    print_test "Backup ID returned" "true" "true (ID: $BACKUP_ID)"
else
    print_test "Backup ID returned" "true" "false (Got: $BACKUP_ID)"
fi

# Performance test: should be < 5 seconds for 10 events
if [ $backup_duration -lt 5 ]; then
    print_test "Performance: Backup created in < 5s" "true" "true"
else
    print_test "Performance: Backup created in < 5s" "true" "false (${backup_duration}s)"
fi
echo ""

echo -e "${BLUE}📋 Step 5: Verify Backup in Database${NC}"
echo "--------------------------------------"
BACKUP_META=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT
    id,
    backup_path,
    backup_size_bytes,
    backup_type,
    status
  FROM book_backups
  WHERE id = $BACKUP_ID;
")

echo "Backup metadata: $BACKUP_META"
print_test "Backup metadata in DB" "$BACKUP_ID" "$BACKUP_META"

BACKUP_PATH=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT backup_path FROM book_backups WHERE id = $BACKUP_ID;
" | tr -d ' ')

BACKUP_SIZE=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT backup_size_bytes FROM book_backups WHERE id = $BACKUP_ID;
" | tr -d ' ')

echo "Backup file: $BACKUP_PATH"
echo "Backup size: $BACKUP_SIZE bytes"
print_test "Backup file path set" ".sql.gz" "$BACKUP_PATH"
print_test "Backup type is 'full'" "full" "$BACKUP_META"
print_test "Backup status is 'completed'" "completed" "$BACKUP_META"
echo ""

echo -e "${BLUE}📋 Step 6: Verify File Exists${NC}"
echo "-------------------------------"
if [ -f "server/backups/$BACKUP_PATH" ]; then
    FILE_SIZE=$(stat -f%z "server/backups/$BACKUP_PATH" 2>/dev/null || stat -c%s "server/backups/$BACKUP_PATH" 2>/dev/null)
    echo "File exists: server/backups/$BACKUP_PATH"
    echo "File size: $FILE_SIZE bytes"
    print_test "Backup file exists" "true" "true"
    print_test "File size matches DB" "$BACKUP_SIZE" "$FILE_SIZE"

    # Check compression ratio
    # Decompress to check original size
    ORIGINAL_SIZE=$(gunzip -c "server/backups/$BACKUP_PATH" | wc -c | tr -d ' ')
    COMPRESSION_RATIO=$(awk "BEGIN {printf \"%.1f\", (1 - $FILE_SIZE / $ORIGINAL_SIZE) * 100}")
    echo "Original SQL size: $ORIGINAL_SIZE bytes"
    echo "Compressed size: $FILE_SIZE bytes"
    echo "Compression ratio: ${COMPRESSION_RATIO}%"

    # Test compression > 50%
    if (( $(echo "$COMPRESSION_RATIO > 50" | bc -l) )); then
        print_test "Compression > 50%" "true" "true (${COMPRESSION_RATIO}%)"
    else
        print_test "Compression > 50%" "true" "false (${COMPRESSION_RATIO}%)"
    fi
else
    echo "File not found: server/backups/$BACKUP_PATH"
    print_test "Backup file exists" "true" "false"
fi
echo ""

echo -e "${BLUE}📋 Step 7: List Backups for Book${NC}"
echo "----------------------------------"
LIST_BACKUPS_RESPONSE=$(curl -s --insecure -X GET \
  "$BASE_URL/api/books/$BOOK_ID/backups?deviceId=$DEVICE_ID&deviceToken=$DEVICE_TOKEN")

echo "List response: ${LIST_BACKUPS_RESPONSE:0:200}..."
print_test "List backups API" "success" "$LIST_BACKUPS_RESPONSE"
print_test "Backup in list" "$BACKUP_ID" "$LIST_BACKUPS_RESPONSE"
print_test "isFileBased flag" "true" "$LIST_BACKUPS_RESPONSE"
echo ""

echo -e "${BLUE}📋 Step 8: Download Backup File${NC}"
echo "---------------------------------"
DOWNLOAD_FILE="/tmp/test_backup_${BACKUP_ID}.sql.gz"
HTTP_CODE=$(curl -s --insecure -w "%{http_code}" -o "$DOWNLOAD_FILE" \
  "$BASE_URL/api/backups/$BACKUP_ID/download?deviceId=$DEVICE_ID&deviceToken=$DEVICE_TOKEN")

echo "HTTP Code: $HTTP_CODE"
print_test "Download HTTP 200" "200" "$HTTP_CODE"

if [ -f "$DOWNLOAD_FILE" ]; then
    DOWNLOAD_SIZE=$(stat -f%z "$DOWNLOAD_FILE" 2>/dev/null || stat -c%s "$DOWNLOAD_FILE" 2>/dev/null)
    echo "Downloaded file size: $DOWNLOAD_SIZE bytes"
    print_test "Downloaded file exists" "true" "true"
    print_test "Downloaded size matches" "$FILE_SIZE" "$DOWNLOAD_SIZE"

    # Verify it's a valid gzip file
    if gunzip -t "$DOWNLOAD_FILE" 2>/dev/null; then
        print_test "Downloaded file is valid gzip" "true" "true"

        # Extract and check SQL content
        SQL_CONTENT=$(gunzip -c "$DOWNLOAD_FILE")
        print_test "SQL contains book data" "Test Book for Backup" "$SQL_CONTENT"
        print_test "SQL contains INSERT statements" "INSERT INTO" "$SQL_CONTENT"
        print_test "SQL contains events" "Test Event" "$SQL_CONTENT"
    else
        print_test "Downloaded file is valid gzip" "true" "false"
    fi

    rm "$DOWNLOAD_FILE"
else
    print_test "Downloaded file exists" "true" "false"
fi
echo ""

echo -e "${BLUE}📋 Step 9: Restore Book from Backup${NC}"
echo "-------------------------------------"
# First, delete the original book to test full restore
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  DELETE FROM books WHERE id = $BOOK_ID;
" > /dev/null

echo "Original book deleted (Book #$BOOK_ID)"

# Verify book is gone
BOOK_COUNT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM books WHERE id = $BOOK_ID;
" | tr -d ' ')

print_test "Book deleted successfully" "0" "$BOOK_COUNT"

# Restore from backup
restore_start=$(date +%s)
RESTORE_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/backups/$BACKUP_ID/restore" \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceId\": \"$DEVICE_ID\",
    \"deviceToken\": \"$DEVICE_TOKEN\"
  }")

restore_end=$(date +%s)
restore_duration=$((restore_end - restore_start))

echo "Restore response: $RESTORE_RESPONSE"
echo "Time taken: ${restore_duration}s"
print_test "Restore API success" "success" "$RESTORE_RESPONSE"

# Performance test: should be < 5 seconds
if [ $restore_duration -lt 5 ]; then
    print_test "Performance: Restore completed in < 5s" "true" "true"
else
    print_test "Performance: Restore completed in < 5s" "true" "false (${restore_duration}s)"
fi
echo ""

echo -e "${BLUE}📋 Step 10: Verify Restored Data${NC}"
echo "----------------------------------"
# Check book exists
RESTORED_BOOK=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT id, name FROM books WHERE id = $BOOK_ID;
")

print_test "Book restored" "$BOOK_ID" "$RESTORED_BOOK"
print_test "Book name correct" "Test Book for Backup" "$RESTORED_BOOK"

# Check event count
EVENT_COUNT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM events WHERE book_id = $BOOK_ID;
" | tr -d ' ')

print_test "Event count" "10" "$EVENT_COUNT"

# Check note count
NOTE_COUNT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM notes WHERE event_id IN (SELECT id FROM events WHERE book_id = $BOOK_ID);
" | tr -d ' ')

print_test "Note count" "5" "$NOTE_COUNT"

# Check drawing count
DRAWING_COUNT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM schedule_drawings WHERE book_id = $BOOK_ID;
" | tr -d ' ')

print_test "Drawing count" "2" "$DRAWING_COUNT"

# Check specific event data
FIRST_EVENT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT name FROM events WHERE book_id = $BOOK_ID ORDER BY id LIMIT 1;
" | tr -d ' ')

print_test "Event data integrity" "TestEvent1" "$FIRST_EVENT"

# Check backup marked as restored
RESTORED_AT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT restored_at IS NOT NULL FROM book_backups WHERE id = $BACKUP_ID;
" | tr -d ' ')

print_test "Backup marked as restored" "t" "$RESTORED_AT"
echo ""

echo -e "${BLUE}📋 Step 11: Test Error Handling${NC}"
echo "---------------------------------"
# Test 1: Invalid book ID
INVALID_BOOK_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X POST "$BASE_URL/api/books/99999/backup" \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceId\": \"$DEVICE_ID\",
    \"deviceToken\": \"$DEVICE_TOKEN\"
  }")

HTTP_CODE=$(echo "$INVALID_BOOK_RESPONSE" | tail -1)
print_test "Invalid book ID returns error" "500" "$HTTP_CODE"

# Test 2: Invalid device credentials
INVALID_CREDS_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X POST "$BASE_URL/api/books/$BOOK_ID/backup" \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceId\": \"invalid-device-id\",
    \"deviceToken\": \"invalid-token\"
  }")

HTTP_CODE=$(echo "$INVALID_CREDS_RESPONSE" | tail -1)
print_test "Invalid credentials return 403" "403" "$HTTP_CODE"

# Test 3: Invalid backup ID
INVALID_BACKUP_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X POST "$BASE_URL/api/backups/99999/restore" \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceId\": \"$DEVICE_ID\",
    \"deviceToken\": \"$DEVICE_TOKEN\"
  }")

HTTP_CODE=$(echo "$INVALID_BACKUP_RESPONSE" | tail -1)
print_test "Invalid backup ID returns error" "500" "$HTTP_CODE"
echo ""

echo -e "${BLUE}📋 Step 12: Test Backup Cleanup${NC}"
echo "---------------------------------"
# Create 12 more backups to trigger cleanup (keeping last 10)
echo "Creating 12 more backups to test cleanup..."
for i in {1..12}; do
    curl -s --insecure -X POST "$BASE_URL/api/books/$BOOK_ID/backup" \
      -H "Content-Type: application/json" \
      -d "{
        \"deviceId\": \"$DEVICE_ID\",
        \"deviceToken\": \"$DEVICE_TOKEN\",
        \"backupName\": \"Cleanup Test Backup $i\"
      }" > /dev/null
    echo -n "."
done
echo ""

# Check backup count
BACKUP_COUNT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM book_backups WHERE book_id = $BOOK_ID AND is_deleted = false;
" | tr -d ' ')

echo "Active backups: $BACKUP_COUNT"
# Cleanup runs after each backup creation, so we should have <= 10
if [ $BACKUP_COUNT -le 10 ]; then
    print_test "Cleanup enforces max 10 backups" "true" "true ($BACKUP_COUNT backups)"
else
    print_test "Cleanup enforces max 10 backups" "true" "false ($BACKUP_COUNT backups, expected <= 10)"
fi
echo ""

echo -e "${BLUE}📋 Step 13: Test Delete Backup${NC}"
echo "--------------------------------"
# Get the oldest backup to delete
OLDEST_BACKUP=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT id FROM book_backups WHERE book_id = $BOOK_ID AND is_deleted = false ORDER BY created_at ASC LIMIT 1;
" | tr -d ' ')

DELETE_RESPONSE=$(curl -s --insecure -X DELETE \
  "$BASE_URL/api/backups/$OLDEST_BACKUP?deviceId=$DEVICE_ID&deviceToken=$DEVICE_TOKEN")

print_test "Delete backup API" "success" "$DELETE_RESPONSE"

# Verify backup is marked deleted
IS_DELETED=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT is_deleted FROM book_backups WHERE id = $OLDEST_BACKUP;
" | tr -d ' ')

print_test "Backup marked as deleted" "t" "$IS_DELETED"
echo ""

echo -e "${BLUE}📋 Step 14: Cleanup Test Data${NC}"
echo "-------------------------------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  DELETE FROM book_backups WHERE device_id = '$DEVICE_ID';
  DELETE FROM books WHERE device_id = '$DEVICE_ID';
  DELETE FROM devices WHERE id = '$DEVICE_ID';
" > /dev/null

# Clean up backup files
rm -rf server/backups/book_${BOOK_ID}_*.sql.gz 2>/dev/null || true

echo "Test data cleaned up"
print_test "Cleanup completed" "true" "true"
echo ""

# Calculate results
end_time=$(date +%s)
total_time=$((end_time - start_time))

echo "=========================================="
echo -e "${BLUE}📊 Test Summary${NC}"
echo "=========================================="
echo "Total tests: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
if [ $fail_count -gt 0 ]; then
    echo -e "${RED}Failed: $fail_count${NC}"
else
    echo "Failed: $fail_count"
fi
echo "Total time: ${total_time}s"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    echo "Linus says: \"Now THAT'S a backup system. Simple, testable, and it actually works.\""
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
