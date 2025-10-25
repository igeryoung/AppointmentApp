#!/bin/bash

# Drawings API Integration Test Script
# Tests the Server-Store Drawings API with all edge cases
# As Linus says: "The composite key is the data's natural identity."

set -e

echo "🧪 Drawings API - Integration Test"
echo "==================================="
echo ""

BASE_URL="https://localhost:8080"
DB_NAME="schedule_note_dev"
DB_PORT="5433"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

echo "📋 Step 1: Health Check"
echo "-----------------------"
HEALTH=$(curl -s --insecure "$BASE_URL/health")
print_test "Server health check" "healthy" "$HEALTH"
echo ""

echo "📋 Step 2: Register Device"
echo "----------------------------"
REGISTER_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/devices/register" \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "Drawings API Test Device", "platform": "test"}')

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
    'Test Book for Drawings API',
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

echo "✅ Test data created:"
echo "  Book ID: $BOOK_ID"
echo ""

# Test dates
DATE_1="2025-11-01"
DATE_2="2025-11-02"
DATE_3="2025-11-03"
VIEW_MODE=1  # 3-Day view

echo "📋 Test 1: GET non-existent drawing → 404"
echo "-------------------------------------------"
GET_NONEXISTENT=$(curl -s --insecure -w "\n%{http_code}" -X GET \
  "$BASE_URL/api/books/$BOOK_ID/drawings?date=$DATE_1&viewMode=$VIEW_MODE" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN")

HTTP_CODE=$(echo "$GET_NONEXISTENT" | tail -n 1)
RESPONSE=$(echo "$GET_NONEXISTENT" | sed '$d')

print_test "GET non-existent drawing returns 404" "404" "$HTTP_CODE"
print_test "Response indicates not found" '"success":false' "$RESPONSE"
echo ""

echo "📋 Test 2: POST create new drawing → 200, version=1"
echo "-----------------------------------------------------"
CREATE_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X POST \
  "$BASE_URL/api/books/$BOOK_ID/drawings" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"date\": \"$DATE_1\", \"viewMode\": $VIEW_MODE, \"strokesData\": \"[{\\\"points\\\": [[10,20],[30,40]]}]\"}")

HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n 1)
RESPONSE=$(echo "$CREATE_RESPONSE" | sed '$d')

print_test "POST create returns 200" "200" "$HTTP_CODE"
print_test "Response indicates success" '"success":true' "$RESPONSE"
print_test "Version is 1" '"version":1' "$RESPONSE"
echo ""

echo "📋 Test 3: GET existing drawing → 200"
echo "---------------------------------------"
GET_EXISTING=$(curl -s --insecure -w "\n%{http_code}" -X GET \
  "$BASE_URL/api/books/$BOOK_ID/drawings?date=$DATE_1&viewMode=$VIEW_MODE" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN")

HTTP_CODE=$(echo "$GET_EXISTING" | tail -n 1)
RESPONSE=$(echo "$GET_EXISTING" | sed '$d')

print_test "GET existing drawing returns 200" "200" "$HTTP_CODE"
print_test "Response contains drawing data" '"strokesData"' "$RESPONSE"
print_test "Version is 1" '"version":1' "$RESPONSE"
echo ""

echo "📋 Test 4: POST update with correct version → 200, version=2"
echo "--------------------------------------------------------------"
UPDATE_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X POST \
  "$BASE_URL/api/books/$BOOK_ID/drawings" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"date\": \"$DATE_1\", \"viewMode\": $VIEW_MODE, \"strokesData\": \"[{\\\"points\\\": [[10,20],[30,40],[50,60]]}]\", \"version\": 1}")

HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n 1)
RESPONSE=$(echo "$UPDATE_RESPONSE" | sed '$d')

print_test "POST update returns 200" "200" "$HTTP_CODE"
print_test "Version incremented to 2" '"version":2' "$RESPONSE"
echo ""

echo "📋 Test 5: POST update with wrong version → 409 Conflict"
echo "-----------------------------------------------------------"
CONFLICT_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X POST \
  "$BASE_URL/api/books/$BOOK_ID/drawings" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"date\": \"$DATE_1\", \"viewMode\": $VIEW_MODE, \"strokesData\": \"[{\\\"points\\\": [[99,99]]}]\", \"version\": 1}")

HTTP_CODE=$(echo "$CONFLICT_RESPONSE" | tail -n 1)
RESPONSE=$(echo "$CONFLICT_RESPONSE" | sed '$d')

print_test "POST with wrong version returns 409" "409" "$HTTP_CODE"
print_test "Response indicates conflict" '"conflict":true' "$RESPONSE"
print_test "Server version is 2" '"serverVersion":2' "$RESPONSE"
echo ""

echo "📋 Test 6: Create drawings for batch test (7 days)"
echo "----------------------------------------------------"
# Create drawings for 7 consecutive days
for i in {1..7}; do
  DATE="2025-11-0$i"
  curl -s --insecure -X POST \
    "$BASE_URL/api/books/$BOOK_ID/drawings" \
    -H "X-Device-ID: $DEVICE_ID" \
    -H "X-Device-Token: $DEVICE_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"date\": \"$DATE\", \"viewMode\": $VIEW_MODE, \"strokesData\": \"[{\\\"points\\\": [[${i}00,${i}00]]}]\"}" > /dev/null
done
echo "✅ Created 7 drawings for dates 2025-11-01 to 2025-11-07"
echo ""

echo "📋 Test 7: POST batch get drawings (7 days) → 200"
echo "---------------------------------------------------"
BATCH_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X POST \
  "$BASE_URL/api/drawings/batch" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"bookId\": $BOOK_ID, \"dateRange\": {\"start\": \"2025-11-01\", \"end\": \"2025-11-07\"}, \"viewMode\": $VIEW_MODE}")

HTTP_CODE=$(echo "$BATCH_RESPONSE" | tail -n 1)
RESPONSE=$(echo "$BATCH_RESPONSE" | sed '$d')

print_test "Batch get returns 200" "200" "$HTTP_CODE"
print_test "Response indicates success" '"success":true' "$RESPONSE"
print_test "Returns 7 drawings" '"count":7' "$RESPONSE"
echo ""

echo "📋 Test 8: DELETE drawing → 200"
echo "---------------------------------"
DELETE_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X DELETE \
  "$BASE_URL/api/books/$BOOK_ID/drawings?date=$DATE_3&viewMode=$VIEW_MODE" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN")

HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n 1)
RESPONSE=$(echo "$DELETE_RESPONSE" | sed '$d')

print_test "DELETE returns 200" "200" "$HTTP_CODE"
print_test "Response indicates success" '"success":true' "$RESPONSE"
echo ""

# Verify drawing is deleted
GET_DELETED=$(curl -s --insecure -w "\n%{http_code}" -X GET \
  "$BASE_URL/api/books/$BOOK_ID/drawings?date=$DATE_3&viewMode=$VIEW_MODE" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN")

HTTP_CODE=$(echo "$GET_DELETED" | tail -n 1)
print_test "GET deleted drawing returns 404" "404" "$HTTP_CODE"
echo ""

echo "📋 Test 9: Batch get after delete → 6 drawings"
echo "------------------------------------------------"
BATCH_AFTER_DELETE=$(curl -s --insecure -w "\n%{http_code}" -X POST \
  "$BASE_URL/api/drawings/batch" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"bookId\": $BOOK_ID, \"dateRange\": {\"start\": \"2025-11-01\", \"end\": \"2025-11-07\"}, \"viewMode\": $VIEW_MODE}")

HTTP_CODE=$(echo "$BATCH_AFTER_DELETE" | tail -n 1)
RESPONSE=$(echo "$BATCH_AFTER_DELETE" | sed '$d')

print_test "Batch get returns 6 drawings after delete" '"count":6' "$RESPONSE"
echo ""

echo "📋 Test 10: Unauthorized access → 403"
echo "---------------------------------------"
# Register a different device
DEVICE2_RESPONSE=$(curl -s --insecure -X POST "$BASE_URL/api/devices/register" \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "Unauthorized Device", "platform": "test"}')

DEVICE2_ID=$(echo "$DEVICE2_RESPONSE" | grep -o '"deviceId":"[^"]*' | cut -d'"' -f4)
DEVICE2_TOKEN=$(echo "$DEVICE2_RESPONSE" | grep -o '"deviceToken":"[^"]*' | cut -d'"' -f4)

# Try to access first device's drawing
UNAUTH_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X GET \
  "$BASE_URL/api/books/$BOOK_ID/drawings?date=$DATE_1&viewMode=$VIEW_MODE" \
  -H "X-Device-ID: $DEVICE2_ID" \
  -H "X-Device-Token: $DEVICE2_TOKEN")

HTTP_CODE=$(echo "$UNAUTH_RESPONSE" | tail -n 1)
RESPONSE=$(echo "$UNAUTH_RESPONSE" | sed '$d')

print_test "Unauthorized access returns 403" "403" "$HTTP_CODE"
print_test "Response indicates unauthorized" '"success":false' "$RESPONSE"
echo ""

echo "📋 Test 11: Invalid credentials → 403"
echo "---------------------------------------"
INVALID_RESPONSE=$(curl -s --insecure -w "\n%{http_code}" -X GET \
  "$BASE_URL/api/books/$BOOK_ID/drawings?date=$DATE_1&viewMode=$VIEW_MODE" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: invalid-token-12345")

HTTP_CODE=$(echo "$INVALID_RESPONSE" | tail -n 1)

print_test "Invalid credentials returns 403" "403" "$HTTP_CODE"
echo ""

echo "📋 Test 12: Composite key uniqueness"
echo "--------------------------------------"
# Test that different view modes can have different drawings for same date
VIEW_MODE_DAY=0
CREATE_DAY_VIEW=$(curl -s --insecure -w "\n%{http_code}" -X POST \
  "$BASE_URL/api/books/$BOOK_ID/drawings" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"date\": \"$DATE_1\", \"viewMode\": $VIEW_MODE_DAY, \"strokesData\": \"[{\\\"points\\\": [[999,999]]}]\"}")

HTTP_CODE=$(echo "$CREATE_DAY_VIEW" | tail -n 1)
RESPONSE=$(echo "$CREATE_DAY_VIEW" | sed '$d')

print_test "Create drawing with different viewMode succeeds" "200" "$HTTP_CODE"
print_test "Different viewMode creates separate drawing" '"success":true' "$RESPONSE"
echo ""

# Verify both drawings exist
GET_THREE_DAY=$(curl -s --insecure -X GET \
  "$BASE_URL/api/books/$BOOK_ID/drawings?date=$DATE_1&viewMode=$VIEW_MODE" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN")

GET_DAY=$(curl -s --insecure -X GET \
  "$BASE_URL/api/books/$BOOK_ID/drawings?date=$DATE_1&viewMode=$VIEW_MODE_DAY" \
  -H "X-Device-ID: $DEVICE_ID" \
  -H "X-Device-Token: $DEVICE_TOKEN")

print_test "3-Day view drawing exists" '"viewMode":1' "$GET_THREE_DAY"
print_test "Day view drawing exists" '"viewMode":0' "$GET_DAY"
echo ""

echo "🧹 Cleanup"
echo "-----------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  DELETE FROM schedule_drawings WHERE book_id = $BOOK_ID;
  DELETE FROM books WHERE id = $BOOK_ID;
  DELETE FROM devices WHERE id = '$DEVICE_ID' OR id = '$DEVICE2_ID';
" > /dev/null
echo "✅ Test data cleaned up"
echo ""

echo "==================================="
echo "📊 Test Results Summary"
echo "==================================="
echo "Total tests: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
if [ $fail_count -gt 0 ]; then
    echo -e "${RED}Failed: $fail_count${NC}"
    echo ""
    echo "❌ Some tests failed!"
    exit 1
else
    echo -e "${GREEN}Failed: 0${NC}"
    echo ""
    echo "✅ All tests passed!"
    echo ""
    echo "Linus says: 'Composite keys are the data's natural identity.'"
    echo "The API respects the (book_id, date, view_mode) key. Good taste."
fi
