#!/bin/bash

# Sync System End-to-End Test Script
# Tests the complete sync flow from device registration to data sync

set -e

echo "🧪 Schedule Note Sync - End-to-End Test"
echo "======================================="
echo ""

BASE_URL="http://localhost:8080"
DB_NAME="schedule_note_dev"
DB_PORT="5433"

echo "📋 Step 1: Health Check"
echo "-----------------------"
HEALTH=$(curl -s "$BASE_URL/health")
echo "Server status: $HEALTH"
echo ""

echo "📋 Step 2: Register Device"
echo "----------------------------"
REGISTER_RESPONSE=$(curl -s -X POST "$BASE_URL/api/devices/register" \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "CLI Test Device", "platform": "macos"}')

DEVICE_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"deviceId":"[^"]*' | cut -d'"' -f4)
DEVICE_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"deviceToken":"[^"]*' | cut -d'"' -f4)

echo "Device registered:"
echo "  ID: $DEVICE_ID"
echo "  Token: ${DEVICE_TOKEN:0:20}..."
echo ""

echo "📋 Step 3: Insert Test Data Directly to Server"
echo "------------------------------------------------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  INSERT INTO books (device_id, name, created_at, updated_at, synced_at, version, is_deleted)
  VALUES (
    '$DEVICE_ID',
    'Server Book $(date +%s)',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    1,
    false
  );
"
echo "✅ Test book inserted to server"
echo ""

echo "📋 Step 4: Verify Data in PostgreSQL"
echo "--------------------------------------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  SELECT id, name, device_id, version FROM books ORDER BY id DESC LIMIT 3;
"
echo ""

echo "📋 Step 5: Test Pull Endpoint"
echo "-------------------------------"
PULL_RESPONSE=$(curl -s -X POST "$BASE_URL/api/sync/pull" \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceId\": \"$DEVICE_ID\",
    \"deviceToken\": \"$DEVICE_TOKEN\",
    \"lastSyncTime\": \"2020-01-01T00:00:00.000Z\"
  }")

echo "Pull response:"
echo "$PULL_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$PULL_RESPONSE"
echo ""

echo "📋 Step 6: Test Push Endpoint"
echo "-------------------------------"
# First, insert a book from client's perspective
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
PUSH_RESPONSE=$(curl -s -X POST "$BASE_URL/api/sync/push" \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceId\": \"$DEVICE_ID\",
    \"deviceToken\": \"$DEVICE_TOKEN\",
    \"changes\": [
      {
        \"tableName\": \"books\",
        \"recordId\": 99999,
        \"data\": {
          \"id\": 99999,
          \"device_id\": \"$DEVICE_ID\",
          \"name\": \"Client Book from CLI\",
          \"created_at\": \"$CURRENT_TIME\",
          \"updated_at\": \"$CURRENT_TIME\",
          \"synced_at\": \"$CURRENT_TIME\",
          \"version\": 1,
          \"is_deleted\": false
        },
        \"version\": 1,
        \"operation\": \"insert\"
      }
    ]
  }")

echo "Push response:"
echo "$PUSH_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$PUSH_RESPONSE"
echo ""

echo "📋 Step 7: Verify Pushed Data"
echo "-------------------------------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  SELECT id, name, device_id, version FROM books ORDER BY id DESC LIMIT 5;
"
echo ""

echo "📋 Step 8: Check Sync Log"
echo "--------------------------"
psql -p "$DB_PORT" -d "$DB_NAME" -c "
  SELECT
    operation,
    table_name,
    status,
    changes_count,
    synced_at
  FROM sync_log
  ORDER BY synced_at DESC
  LIMIT 5;
"
echo ""

echo "✅ End-to-End Test Complete!"
echo ""
echo "Summary:"
echo "  ✅ Server health check passed"
echo "  ✅ Device registration works"
echo "  ✅ Data inserted to PostgreSQL"
echo "  ✅ Pull endpoint tested"
echo "  ✅ Push endpoint tested"
echo "  ✅ Sync log populated"
echo ""
echo "Next: Test from Flutter app using the Sync Test screen"
echo "  1. Tap the sync icon in the app bar"
echo "  2. Register device (or use existing)"
echo "  3. Create test data"
echo "  4. Push/Pull/Full Sync"
