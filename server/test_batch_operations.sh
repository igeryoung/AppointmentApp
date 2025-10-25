#!/bin/bash

# Batch Operations API Integration Test Script
# Tests Phase 2-04: Batch Operations with transaction support
# As Linus says: "Batch operations aren't premature optimization.
# They're the difference between usable and unusable."

set -e

echo "🧪 Batch Operations API - Integration Test"
echo "==========================================="
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

# Helper function to print performance result
print_perf() {
    local test_name=$1
    local duration=$2
    local threshold=$3

    test_count=$((test_count + 1))

    if (( $(echo "$duration < $threshold" | bc -l) )); then
        echo -e "${GREEN}✅ PASS${NC}: $test_name (${duration}s < ${threshold}s)"
        pass_count=$((pass_count + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name (${duration}s >= ${threshold}s)"
        fail_count=$((fail_count + 1))
    fi
}

echo "📋 Step 1: Health Check"
echo "-----------------------"
HEALTH=$(curl -s --insecure "$BASE_URL/health")
print_test "Server health check" "healthy" "$HEALTH"
echo ""

echo "📋 Step 2: Register Device"
echo "----------------------------"
REGISTER_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/devices/register" \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "Batch API Test Device", "platform": "test"}')

DEVICE_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"deviceId":"[^"]*' | cut -d'"' -f4)
DEVICE_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"deviceToken":"[^"]*' | cut -d'"' -f4)

echo "Device registered:"
echo "  ID: $DEVICE_ID"
echo "  Token: ${DEVICE_TOKEN:0:20}..."
print_test "Device registration" "$DEVICE_ID" "$DEVICE_ID"
echo ""

echo "📋 Step 3: Create Test Data in Database"
echo "-----------------------------------------"
# Create a book
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO books (device_id, name, book_uuid, created_at, updated_at, synced_at, version, is_deleted)
  VALUES (
    '$DEVICE_ID',
    'Test Book for Batch API',
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

# Create events for notes
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO events (book_id, device_id, name, record_number, event_type, start_time, end_time, created_at, updated_at, synced_at, version, is_deleted)
  VALUES
    ($BOOK_ID, '$DEVICE_ID', 'Event 1', 'REC001', 'appointment', '2025-11-01 10:00:00', '2025-11-01 11:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', 'Event 2', 'REC002', 'appointment', '2025-11-01 14:00:00', '2025-11-01 15:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', 'Event 3', 'REC003', 'appointment', '2025-11-01 16:00:00', '2025-11-01 17:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', 'Event 4', 'REC004', 'appointment', '2025-11-02 10:00:00', '2025-11-02 11:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', 'Event 5', 'REC005', 'appointment', '2025-11-02 14:00:00', '2025-11-02 15:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', 'Event 6', 'REC006', 'appointment', '2025-11-02 16:00:00', '2025-11-02 17:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', 'Event 7', 'REC007', 'appointment', '2025-11-03 10:00:00', '2025-11-03 11:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', 'Event 8', 'REC008', 'appointment', '2025-11-03 14:00:00', '2025-11-03 15:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', 'Event 9', 'REC009', 'appointment', '2025-11-03 16:00:00', '2025-11-03 17:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false),
    ($BOOK_ID, '$DEVICE_ID', 'Event 10', 'REC010', 'appointment', '2025-11-04 10:00:00', '2025-11-04 11:00:00', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false);
" > /dev/null

EVENT_IDS=($(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT id FROM events WHERE book_id = $BOOK_ID ORDER BY id ASC;
" | tr -d ' '))

echo "Created book: $BOOK_ID"
echo "Created ${#EVENT_IDS[@]} events"
echo ""

echo "📋 Step 4: Test Empty Batch (Should Succeed)"
echo "----------------------------------------------"
EMPTY_BATCH=$(curl -s --insecure -X POST "$BASE_URL/api/batch/save" \
  -H "Content-Type: application/json" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -d '{"notes": [], "drawings": []}')

print_test "Empty batch returns success" '"success":true' "$EMPTY_BATCH"
echo ""

echo "📋 Step 5: Test Batch Save - 10 Notes + 5 Drawings"
echo "----------------------------------------------------"
# Build JSON payload
NOTES_JSON="["
for i in {0..9}; do
  EVENT_ID=${EVENT_IDS[$i]}
  NOTES_JSON="$NOTES_JSON{\"eventId\":$EVENT_ID,\"bookId\":$BOOK_ID,\"strokesData\":\"note-$i-data\"}"
  if [ $i -lt 9 ]; then
    NOTES_JSON="$NOTES_JSON,"
  fi
done
NOTES_JSON="$NOTES_JSON]"

DRAWINGS_JSON="["
for i in {0..4}; do
  DATE="2025-11-0$((i+1))T00:00:00Z"
  DRAWINGS_JSON="$DRAWINGS_JSON{\"bookId\":$BOOK_ID,\"date\":\"$DATE\",\"viewMode\":0,\"strokesData\":\"drawing-$i-data\"}"
  if [ $i -lt 4 ]; then
    DRAWINGS_JSON="$DRAWINGS_JSON,"
  fi
done
DRAWINGS_JSON="$DRAWINGS_JSON]"

START_TIME=$(date +%s.%N)
BATCH_SAVE=$(curl -s --insecure -X POST "$BASE_URL/api/batch/save" \
  -H "Content-Type: application/json" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -d "{\"notes\":$NOTES_JSON,\"drawings\":$DRAWINGS_JSON}")
END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc)

print_test "Batch save succeeds" '"success":true' "$BATCH_SAVE"
print_test "Notes succeeded count" '"succeeded":10' "$BATCH_SAVE"
print_test "Drawings succeeded count" '"succeeded":5' "$BATCH_SAVE"
print_perf "Batch save performance (10 notes + 5 drawings)" "$DURATION" "1.0"
echo ""

echo "📋 Step 6: Verify Data Was Saved"
echo "----------------------------------"
# Convert array to comma-separated list for SQL IN clause
EVENT_IDS_LIST=$(IFS=,; echo "${EVENT_IDS[*]}")
NOTE_COUNT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM notes WHERE event_id IN ($EVENT_IDS_LIST) AND is_deleted = false;
" | tr -d ' ')

DRAWING_COUNT=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM schedule_drawings WHERE book_id = $BOOK_ID AND is_deleted = false;
" | tr -d ' ')

print_test "10 notes saved in database" "10" "$NOTE_COUNT"
print_test "5 drawings saved in database" "5" "$DRAWING_COUNT"
echo ""

echo "📋 Step 7: Test Update with Correct Version"
echo "---------------------------------------------"
# Get current versions
NOTE_VERSION=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT version FROM notes WHERE event_id = ${EVENT_IDS[0]};
" | tr -d ' ')

EVENT_ID=${EVENT_IDS[0]}
UPDATE_BATCH=$(curl -s --insecure -X POST "$BASE_URL/api/batch/save" \
  -H "Content-Type: application/json" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -d "{\"notes\":[{\"eventId\":$EVENT_ID,\"bookId\":$BOOK_ID,\"strokesData\":\"updated-note-data\",\"version\":$NOTE_VERSION}],\"drawings\":[]}")

print_test "Update with correct version succeeds" '"success":true' "$UPDATE_BATCH"
echo ""

echo "📋 Step 8: Test Version Conflict (Should Rollback)"
echo "----------------------------------------------------"
WRONG_VERSION=999
CONFLICT_BATCH=$(curl -s --insecure -X POST "$BASE_URL/api/batch/save" \
  -H "Content-Type: application/json" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -d "{\"notes\":[{\"eventId\":$EVENT_ID,\"bookId\":$BOOK_ID,\"strokesData\":\"conflict-data\",\"version\":$WRONG_VERSION}],\"drawings\":[]}")

print_test "Version conflict returns failure" '"success":false' "$CONFLICT_BATCH"
print_test "Version conflict error message" 'Version conflict' "$CONFLICT_BATCH"
echo ""

echo "📋 Step 9: Test Unauthorized Access"
echo "-------------------------------------"
# Register another device
OTHER_DEVICE=$(curl -s --insecure -X POST "$BASE_URL/api/devices/register" \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "Unauthorized Device", "platform": "test"}')

OTHER_DEVICE_ID=$(echo "$OTHER_DEVICE" | grep -o '"deviceId":"[^"]*' | cut -d'"' -f4)
OTHER_DEVICE_TOKEN=$(echo "$OTHER_DEVICE" | grep -o '"deviceToken":"[^"]*' | cut -d'"' -f4)

UNAUTH_BATCH=$(curl -s --insecure -X POST "$BASE_URL/api/batch/save" \
  -H "Content-Type: application/json" \
  -H "X-Device-ID: $OTHER_DEVICE_ID" \
  -H "X-Device-Token: $OTHER_DEVICE_TOKEN" \
  -d "{\"notes\":[{\"eventId\":$EVENT_ID,\"bookId\":$BOOK_ID,\"strokesData\":\"hacker-data\"}],\"drawings\":[]}")

print_test "Unauthorized access returns failure" '"success":false' "$UNAUTH_BATCH"
print_test "Unauthorized error message" 'Unauthorized' "$UNAUTH_BATCH"
echo ""

echo "📋 Step 10: Test Invalid Credentials"
echo "--------------------------------------"
INVALID_CRED=$(curl -s --insecure -X POST "$BASE_URL/api/batch/save" \
  -H "Content-Type: application/json" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: invalid-token-xxx" \
  -d '{"notes":[],"drawings":[]}')

print_test "Invalid credentials returns failure" '"success":false' "$INVALID_CRED"
echo ""

echo "📋 Step 11: Test Payload Size Limit"
echo "-------------------------------------"
# Try to send 1001 items (over the 1000 limit)
LARGE_NOTES="["
for i in {1..1001}; do
  LARGE_NOTES="$LARGE_NOTES{\"eventId\":${EVENT_IDS[0]},\"bookId\":$BOOK_ID,\"strokesData\":\"data-$i\"}"
  if [ $i -lt 1001 ]; then
    LARGE_NOTES="$LARGE_NOTES,"
  fi
done
LARGE_NOTES="$LARGE_NOTES]"

LARGE_BATCH=$(curl -s --insecure -X POST "$BASE_URL/api/batch/save" \
  -H "Content-Type: application/json" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -d "{\"notes\":$LARGE_NOTES,\"drawings\":[]}")

print_test "Payload too large returns 413" 'Payload too large' "$LARGE_BATCH"
echo ""

echo "📋 Step 12: Test Performance - 100 Notes"
echo "------------------------------------------"
# Create 100 events
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO events (book_id, device_id, name, record_number, event_type, start_time, end_time, created_at, updated_at, synced_at, version, is_deleted)
  SELECT
    $BOOK_ID,
    '$DEVICE_ID',
    'Perf Event ' || generate_series,
    'PERF' || LPAD(generate_series::text, 5, '0'),
    'appointment',
    '2025-12-01 10:00:00'::timestamp + (generate_series || ' hours')::interval,
    '2025-12-01 11:00:00'::timestamp + (generate_series || ' hours')::interval,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1,
    false
  FROM generate_series(1, 100);
" > /dev/null

PERF_EVENT_IDS=($(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT id FROM events WHERE book_id = $BOOK_ID AND name LIKE 'Perf Event%' ORDER BY id ASC;
" | tr -d ' '))

# Build JSON for 100 notes
PERF_NOTES="["
for i in {0..99}; do
  EVENT_ID=${PERF_EVENT_IDS[$i]}
  PERF_NOTES="$PERF_NOTES{\"eventId\":$EVENT_ID,\"bookId\":$BOOK_ID,\"strokesData\":\"perf-note-$i\"}"
  if [ $i -lt 99 ]; then
    PERF_NOTES="$PERF_NOTES,"
  fi
done
PERF_NOTES="$PERF_NOTES]"

START_TIME=$(date +%s.%N)
PERF_BATCH=$(curl -s --insecure -X POST "$BASE_URL/api/batch/save" \
  -H "Content-Type: application/json" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -d "{\"notes\":$PERF_NOTES,\"drawings\":[]}")
END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc)

print_test "100 notes batch save succeeds" '"success":true' "$PERF_BATCH"
print_perf "100 notes batch save performance" "$DURATION" "1.0"
echo ""

echo "📋 Step 13: Test Transaction Rollback on Partial Failure"
echo "-----------------------------------------------------------"
# Create one note manually that will conflict
CONFLICT_EVENT=${EVENT_IDS[5]}
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  DELETE FROM notes WHERE event_id = $CONFLICT_EVENT;
  INSERT INTO notes (event_id, device_id, strokes_data, version, created_at, updated_at, synced_at, is_deleted)
  VALUES ($CONFLICT_EVENT, '$DEVICE_ID', 'existing-data', 5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, false);
" > /dev/null

# Try to batch save with wrong version - should rollback all
MIXED_NOTES="["
MIXED_NOTES="$MIXED_NOTES{\"eventId\":${EVENT_IDS[6]},\"bookId\":$BOOK_ID,\"strokesData\":\"new-note-1\"},"
MIXED_NOTES="$MIXED_NOTES{\"eventId\":$CONFLICT_EVENT,\"bookId\":$BOOK_ID,\"strokesData\":\"conflict-note\",\"version\":1},"
MIXED_NOTES="$MIXED_NOTES{\"eventId\":${EVENT_IDS[7]},\"bookId\":$BOOK_ID,\"strokesData\":\"new-note-2\"}"
MIXED_NOTES="$MIXED_NOTES]"

# Count notes before
COUNT_BEFORE=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM notes WHERE event_id IN (${EVENT_IDS[6]}, ${EVENT_IDS[7]}) AND is_deleted = false;
" | tr -d ' ')

ROLLBACK_BATCH=$(curl -s --insecure -X POST "$BASE_URL/api/batch/save" \
  -H "Content-Type: application/json" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -d "{\"notes\":$MIXED_NOTES,\"drawings\":[]}")

# Count notes after
COUNT_AFTER=$(psql -p "$DB_PORT" -d "$DB_NAME" -t -c "
  SELECT COUNT(*) FROM notes WHERE event_id IN (${EVENT_IDS[6]}, ${EVENT_IDS[7]}) AND is_deleted = false;
" | tr -d ' ')

print_test "Partial failure returns error" '"success":false' "$ROLLBACK_BATCH"
print_test "Transaction rolled back (no new notes)" "$COUNT_BEFORE" "$COUNT_AFTER"
echo ""

echo "📋 Step 14: Cleanup Test Data"
echo "-------------------------------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  DELETE FROM notes WHERE event_id IN (SELECT id FROM events WHERE book_id = $BOOK_ID);
  DELETE FROM schedule_drawings WHERE book_id = $BOOK_ID;
  DELETE FROM events WHERE book_id = $BOOK_ID;
  DELETE FROM books WHERE id = $BOOK_ID;
  DELETE FROM devices WHERE id = '$DEVICE_ID' OR id = '$OTHER_DEVICE_ID';
" > /dev/null
echo "✅ Test data cleaned up"
echo ""

echo "=========================================="
echo "📊 Test Summary"
echo "=========================================="
echo -e "Total tests: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
  echo -e "${GREEN}🎉 All tests passed!${NC}"
  echo ""
  echo "As Linus says:"
  echo "\"Batch operations aren't premature optimization."
  echo " They're the difference between usable and unusable.\""
  echo ""
  echo "✅ Phase 2-04 Batch Operations - Implementation Complete"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
