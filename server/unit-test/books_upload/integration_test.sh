#!/bin/bash

# Books Upload API Integration Test Script
# Tests the JSON-based book backup upload API with all edge cases
# Tests: POST /api/books/upload

set -e

echo "🧪 Books Upload API - Integration Test"
echo "======================================="
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
  -d '{"deviceName": "Books Upload Test Device", "platform": "test", "password": "password"}')

DEVICE_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"deviceId":"[^"]*' | cut -d'"' -f4)
DEVICE_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"deviceToken":"[^"]*' | cut -d'"' -f4)

echo "Device registered:"
echo "  ID: $DEVICE_ID"
echo "  Token: ${DEVICE_TOKEN:0:20}..."
print_test "Device registration" "$DEVICE_ID" "$DEVICE_ID"
echo ""

echo -e "${BLUE}📋 Step 3: Create Test Book in Database${NC}"
echo "-------------------------------------------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO books (device_id, name, book_uuid, created_at, updated_at, synced_at, version, is_deleted)
  VALUES (
    '$DEVICE_ID',
    'Test Book for Upload',
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

BOOK_UUID=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT book_uuid FROM books WHERE id = $BOOK_ID;
" | tr -d ' ')

echo "Created Book #$BOOK_ID (UUID: $BOOK_UUID)"
echo ""

echo -e "${BLUE}📋 Step 4: Create Test Events${NC}"
echo "-------------------------------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO events (book_id, device_id, name, record_number, event_type, start_time, end_time, created_at, updated_at, synced_at, version, is_deleted)
  SELECT
    $BOOK_ID,
    '$DEVICE_ID',
    'Test Event ' || i,
    'REC' || LPAD(i::text, 3, '0'),
    'appointment',
    CURRENT_TIMESTAMP + (i || ' hours')::interval,
    CURRENT_TIMESTAMP + (i || ' hours')::interval + '1 hour'::interval,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1,
    false
  FROM generate_series(1, 5) AS i;
" > /dev/null

EVENT_COUNT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM events WHERE book_id = $BOOK_ID;
" | tr -d ' ')

echo "Created $EVENT_COUNT events"
echo ""

echo -e "${BLUE}📋 Step 5: Create Test Notes${NC}"
echo "-----------------------------"
EVENT_ID=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT id FROM events WHERE book_id = $BOOK_ID LIMIT 1;
" | tr -d ' ')

psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO notes (event_id, strokes_data, created_at, updated_at, version, is_deleted)
  VALUES (
    $EVENT_ID,
    '[{\"points\":[{\"x\":100,\"y\":200},{\"x\":150,\"y\":250}]}]',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1,
    false
  );
" > /dev/null

NOTE_COUNT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM notes WHERE event_id IN (SELECT id FROM events WHERE book_id = $BOOK_ID);
" | tr -d ' ')

echo "Created $NOTE_COUNT notes"
echo ""

echo -e "${BLUE}📋 Step 6: Prepare Backup Data${NC}"
echo "--------------------------------"
# Fetch book data
BOOK_DATA=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT json_build_object(
    'id', id,
    'device_id', device_id,
    'name', name,
    'book_uuid', book_uuid::text,
    'created_at', created_at::text,
    'updated_at', updated_at::text,
    'synced_at', synced_at::text,
    'version', version,
    'is_deleted', is_deleted
  )
  FROM books WHERE id = $BOOK_ID;
")

# Fetch events data
EVENTS_DATA=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT json_agg(
    json_build_object(
      'id', id,
      'book_id', book_id,
      'device_id', device_id,
      'name', name,
      'record_number', record_number,
      'event_type', event_type,
      'start_time', start_time::text,
      'end_time', end_time::text,
      'created_at', created_at::text,
      'updated_at', updated_at::text,
      'synced_at', synced_at::text,
      'version', version,
      'is_deleted', is_deleted
    )
  )
  FROM events WHERE book_id = $BOOK_ID;
")

# Fetch notes data
NOTES_DATA=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT json_agg(
    json_build_object(
      'id', n.id,
      'event_id', n.event_id,
      'strokes_data', n.strokes_data,
      'created_at', n.created_at::text,
      'updated_at', n.updated_at::text,
      'version', n.version,
      'is_deleted', n.is_deleted
    )
  )
  FROM notes n
  JOIN events e ON n.event_id = e.id
  WHERE e.book_id = $BOOK_ID;
")

# Set empty array if null
if [ "$NOTES_DATA" == " " ] || [ -z "$NOTES_DATA" ]; then
  NOTES_DATA="[]"
fi

echo "Backup data prepared"
echo ""

echo -e "${BLUE}📋 Step 7: Test Upload Backup (Success)${NC}"
echo "--------------------------------------------"
BACKUP_NAME="Integration Test Backup $(date +%Y-%m-%d_%H:%M:%S)"

UPLOAD_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/books/upload" \
  -H "Content-Type: application/json" \
  -H "x-device-id: $DEVICE_ID" \
  -H "x-device-token: $DEVICE_TOKEN" \
  -d "{
    \"bookId\": $BOOK_ID,
    \"backupName\": \"$BACKUP_NAME\",
    \"backupData\": {
      \"book\": $BOOK_DATA,
      \"events\": $EVENTS_DATA,
      \"notes\": $NOTES_DATA,
      \"drawings\": []
    }
  }")

print_test "Upload backup success" '"success":true' "$UPLOAD_RESPONSE"
BACKUP_ID=$(echo "$UPLOAD_RESPONSE" | grep -o '"backupId":[0-9]*' | cut -d':' -f2)
echo "Backup ID: $BACKUP_ID"
echo ""

echo -e "${BLUE}📋 Step 8: Verify Backup in Database${NC}"
echo "--------------------------------------"
BACKUP_EXISTS=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM book_backups WHERE id = $BACKUP_ID;
" | tr -d ' ')

print_test "Backup exists in database" "1" "$BACKUP_EXISTS"

BACKUP_INFO=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT backup_name, book_id, device_id FROM book_backups WHERE id = $BACKUP_ID;
")

echo "Backup info: $BACKUP_INFO"
echo ""

echo -e "${BLUE}📋 Step 9: Test Authentication Errors${NC}"
echo "---------------------------------------"

# Test missing device ID
MISSING_ID_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/books/upload" \
  -H "Content-Type: application/json" \
  -H "x-device-token: $DEVICE_TOKEN" \
  -d "{
    \"bookId\": $BOOK_ID,
    \"backupName\": \"Test\",
    \"backupData\": {\"book\":{},\"events\":[],\"notes\":[],\"drawings\":[]}
  }")

print_test "Missing device ID returns error" '"success":false' "$MISSING_ID_RESPONSE"

# Test missing device token
MISSING_TOKEN_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/books/upload" \
  -H "Content-Type: application/json" \
  -H "x-device-id: $DEVICE_ID" \
  -d "{
    \"bookId\": $BOOK_ID,
    \"backupName\": \"Test\",
    \"backupData\": {\"book\":{},\"events\":[],\"notes\":[],\"drawings\":[]}
  }")

print_test "Missing device token returns error" '"success":false' "$MISSING_TOKEN_RESPONSE"

# Test invalid credentials
INVALID_CREDS_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/books/upload" \
  -H "Content-Type: application/json" \
  -H "x-device-id: invalid-device-id" \
  -H "x-device-token: invalid-token" \
  -d "{
    \"bookId\": $BOOK_ID,
    \"backupName\": \"Test\",
    \"backupData\": {\"book\":{},\"events\":[],\"notes\":[],\"drawings\":[]}
  }")

print_test "Invalid credentials returns error" '"success":false' "$INVALID_CREDS_RESPONSE"
echo ""

echo -e "${BLUE}📋 Step 10: Test Malformed Requests${NC}"
echo "-------------------------------------"

# Test malformed JSON
MALFORMED_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/books/upload" \
  -H "Content-Type: application/json" \
  -H "x-device-id: $DEVICE_ID" \
  -H "x-device-token: $DEVICE_TOKEN" \
  -d "{invalid-json}")

print_test "Malformed JSON returns error" '"success":false' "$MALFORMED_RESPONSE"

# Test missing required fields
MISSING_FIELDS_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/books/upload" \
  -H "Content-Type: application/json" \
  -H "x-device-id: $DEVICE_ID" \
  -H "x-device-token: $DEVICE_TOKEN" \
  -d '{"bookId": 1}')

print_test "Missing required fields returns error" '"success":false' "$MISSING_FIELDS_RESPONSE"
echo ""

echo -e "${BLUE}📋 Step 11: Test Empty Backup Data${NC}"
echo "-----------------------------------"
EMPTY_BACKUP_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/books/upload" \
  -H "Content-Type: application/json" \
  -H "x-device-id: $DEVICE_ID" \
  -H "x-device-token: $DEVICE_TOKEN" \
  -d "{
    \"bookId\": $BOOK_ID,
    \"backupName\": \"Empty Backup\",
    \"backupData\": {
      \"book\": $BOOK_DATA,
      \"events\": [],
      \"notes\": [],
      \"drawings\": []
    }
  }")

print_test "Empty backup data accepted" '"success":true' "$EMPTY_BACKUP_RESPONSE"
echo ""

echo -e "${BLUE}📋 Step 12: Cleanup Test Data${NC}"
echo "-------------------------------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  DELETE FROM book_backups WHERE device_id = '$DEVICE_ID';
  DELETE FROM notes WHERE event_id IN (SELECT id FROM events WHERE book_id = $BOOK_ID);
  DELETE FROM events WHERE book_id = $BOOK_ID;
  DELETE FROM books WHERE id = $BOOK_ID;
  DELETE FROM devices WHERE id = '$DEVICE_ID';
" > /dev/null

echo "Test data cleaned up"
echo ""

# Print summary
end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
echo "========================================="
echo -e "${BLUE}Test Summary${NC}"
echo "========================================="
echo -e "Total tests: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo "Duration: ${duration}s"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed.${NC}"
    exit 1
fi
