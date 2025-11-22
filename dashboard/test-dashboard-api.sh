#!/bin/bash
# Test script for dashboard API
# Tests connectivity and authentication with the dashboard backend

set -e

# Configuration - update these to match your server
PROTOCOL="https"
HOST="localhost"
PORT="8080"
BASE_URL="${PROTOCOL}://${HOST}:${PORT}"

# Credentials - update these if you've customized them
USERNAME="admin"
PASSWORD="admin123"

echo "========================================="
echo "Dashboard API Connection Test"
echo "========================================="
echo ""
echo "Backend URL: ${BASE_URL}"
echo "Testing user: ${USERNAME}"
echo ""

# Test 1: Server health check
echo "Test 1: Server Health Check"
echo "----------------------------"
echo "GET ${BASE_URL}/health"
if curl -k -s -f "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "✅ Server is responding"
    curl -k -s "${BASE_URL}/health" | python3 -m json.tool || echo ""
else
    echo "❌ Server is not responding"
    echo "   Make sure the server is running: cd server && dart run main.dart --dev"
    exit 1
fi
echo ""

# Test 2: Dashboard login endpoint
echo "Test 2: Dashboard Login"
echo "-----------------------"
echo "POST ${BASE_URL}/api/dashboard/auth/login"
echo "Payload: {\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}"
echo ""

RESPONSE=$(curl -k -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" \
    "${BASE_URL}/api/dashboard/auth/login")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | head -n -1)

echo "HTTP Status: ${HTTP_CODE}"
echo "Response Body:"
echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Login successful!"

    # Extract token
    TOKEN=$(echo "$BODY" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

    if [ -n "$TOKEN" ]; then
        echo "   Token: ${TOKEN:0:50}..."
        echo ""

        # Test 3: Test authenticated endpoint
        echo "Test 3: Authenticated Request (Stats)"
        echo "-------------------------------------"
        echo "GET ${BASE_URL}/api/dashboard/stats"
        echo "Authorization: Bearer ${TOKEN:0:20}..."
        echo ""

        STATS_RESPONSE=$(curl -k -s -w "\n%{http_code}" \
            -H "Authorization: Bearer ${TOKEN}" \
            "${BASE_URL}/api/dashboard/stats")

        STATS_HTTP_CODE=$(echo "$STATS_RESPONSE" | tail -n 1)
        STATS_BODY=$(echo "$STATS_RESPONSE" | head -n -1)

        echo "HTTP Status: ${STATS_HTTP_CODE}"
        if [ "$STATS_HTTP_CODE" = "200" ]; then
            echo "✅ Authenticated request successful!"
            echo ""
            echo "Sample stats:"
            echo "$STATS_BODY" | python3 -m json.tool 2>/dev/null | head -n 30 || echo "$STATS_BODY" | head -n 30
        else
            echo "❌ Authenticated request failed"
            echo "Response: $STATS_BODY"
        fi
    fi
else
    echo "❌ Login failed with HTTP ${HTTP_CODE}"

    if [ "$HTTP_CODE" = "500" ]; then
        echo ""
        echo "500 Internal Server Error detected!"
        echo ""
        echo "Debugging steps:"
        echo "1. Check server console logs for detailed error messages"
        echo "2. Look for this log output:"
        echo "   🔐 Dashboard login attempt..."
        echo "      Request body: ..."
        echo "      Username: ..."
        echo "3. Verify database connection is working"
        echo "4. Check that .env file is loaded (look for 📄 Loaded environment variables)"
        echo ""
    elif [ "$HTTP_CODE" = "403" ]; then
        echo ""
        echo "Wrong credentials!"
        echo "Check server startup logs for actual credentials:"
        echo "   Dashboard credentials: admin / admin123"
    fi
fi

echo ""
echo "========================================="
echo "Test complete"
echo "========================================="
