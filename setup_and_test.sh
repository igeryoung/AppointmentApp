#!/bin/bash

# Schedule Note Sync - Quick Setup and Test Script
# This script automates the database setup and server startup

set -e  # Exit on any error

echo "🚀 Schedule Note Sync - Quick Setup"
echo "===================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Check Prerequisites
echo "📋 Step 1: Checking prerequisites..."

if ! command -v psql &> /dev/null; then
    echo -e "${RED}❌ PostgreSQL not found. Install with: brew install postgresql@14${NC}"
    exit 1
fi
echo -e "${GREEN}✅ PostgreSQL found${NC}"

if ! command -v dart &> /dev/null; then
    echo -e "${RED}❌ Dart not found. Install Flutter which includes Dart.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Dart found${NC}"

# Step 2: Start PostgreSQL
echo ""
echo "🗄️  Step 2: Starting PostgreSQL..."

if brew services list | grep -q "postgresql@14.*started"; then
    echo -e "${GREEN}✅ PostgreSQL already running${NC}"
else
    brew services start postgresql@14
    echo -e "${YELLOW}⏳ Waiting for PostgreSQL to start...${NC}"
    sleep 3
    echo -e "${GREEN}✅ PostgreSQL started${NC}"
fi

# Step 3: Create Database
echo ""
echo "💾 Step 3: Creating database..."

if psql -lqt | cut -d \| -f 1 | grep -qw schedule_note_dev; then
    echo -e "${YELLOW}⚠️  Database 'schedule_note_dev' already exists${NC}"
    read -p "Do you want to drop and recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        dropdb schedule_note_dev
        createdb schedule_note_dev
        echo -e "${GREEN}✅ Database recreated${NC}"
    else
        echo -e "${YELLOW}↪️  Using existing database${NC}"
    fi
else
    createdb schedule_note_dev
    echo -e "${GREEN}✅ Database created: schedule_note_dev${NC}"
fi

# Step 4: Install Server Dependencies
echo ""
echo "📦 Step 4: Installing server dependencies..."
cd server
dart pub get > /dev/null 2>&1
echo -e "${GREEN}✅ Dependencies installed${NC}"

# Step 5: Run Migrations
echo ""
echo "🔄 Step 5: Running database migrations..."
echo -e "${YELLOW}Starting server with migrations...${NC}"
echo ""

# Run server with migrations in background
dart run main.dart --dev --migrate &
SERVER_PID=$!

# Wait for server to start
sleep 3

# Step 6: Test Server
echo ""
echo "🧪 Step 6: Testing server endpoints..."

if curl -s http://localhost:8080/health | grep -q "healthy"; then
    echo -e "${GREEN}✅ Server is responding${NC}"
else
    echo -e "${RED}❌ Server not responding. Check server logs above.${NC}"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi

# Step 7: Register Test Device
echo ""
echo "📱 Step 7: Registering test device..."

RESPONSE=$(curl -s -X POST http://localhost:8080/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{"deviceName": "Test Device", "platform": "macos"}')

if echo "$RESPONSE" | grep -q "deviceId"; then
    DEVICE_ID=$(echo "$RESPONSE" | grep -o '"deviceId":"[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}✅ Device registered${NC}"
    echo -e "   Device ID: ${YELLOW}$DEVICE_ID${NC}"
else
    echo -e "${RED}❌ Device registration failed${NC}"
    echo "$RESPONSE"
fi

# Step 8: Verify Database
echo ""
echo "🔍 Step 8: Verifying database setup..."

DEVICE_COUNT=$(psql -t schedule_note_dev -c "SELECT count(*) FROM devices;" | xargs)
TABLE_COUNT=$(psql -t schedule_note_dev -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)

echo -e "${GREEN}✅ Database verification:${NC}"
echo "   Tables created: $TABLE_COUNT"
echo "   Devices registered: $DEVICE_COUNT"

# Final Instructions
echo ""
echo "=========================================="
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Server is running at: http://localhost:8080"
echo "Server PID: $SERVER_PID"
echo ""
echo "Next steps:"
echo "1. Keep this terminal open (server is running)"
echo "2. In your Flutter app, use SyncService with:"
echo "   baseUrl: 'http://localhost:8080'"
echo "3. Run: flutter run"
echo "4. Test sync operations"
echo ""
echo "To stop the server: kill $SERVER_PID"
echo ""
echo "For detailed testing instructions, see:"
echo "   TESTING_GUIDE.md"
echo ""
echo "To view database:"
echo "   psql schedule_note_dev"
echo ""

# Keep script running to maintain server
echo "Press Ctrl+C to stop the server and exit"
wait $SERVER_PID
