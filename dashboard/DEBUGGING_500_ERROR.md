# Debugging the Dashboard 500 Login Error

## Summary

You reported getting a 500 Internal Server Error when trying to login to the dashboard with credentials `admin`/`admin123`. I've made several improvements to help diagnose and fix this issue.

## Changes Made

### 1. Added Comprehensive Logging to Login Endpoint

The login endpoint in `server/lib/routes/dashboard_routes.dart` now includes detailed logging:
- Logs when a login attempt is made
- Logs the request body (to verify it's being sent correctly)
- Logs the username received vs expected
- Logs success or failure reasons
- Logs full stack trace if an exception occurs

### 2. Fixed Vite Proxy Configuration

**Problem**: The Vite dev server was configured to proxy to `http://localhost:8080`, but your server has `ENABLE_SSL=true`, meaning it's running on `https://localhost:8080`.

**Fix**: Updated `dashboard/vite.config.ts` to:
- Use HTTPS: `https://localhost:8080`
- Disable SSL certificate validation for self-signed certs: `secure: false`
- Made it configurable via environment variable: `VITE_BACKEND_URL`

### 3. Added Configuration Documentation

Updated `dashboard/README.md` with:
- Detailed backend connection configuration instructions
- Troubleshooting steps for connection issues
- Specific guidance for 500 errors

### 4. Created API Test Script

Created `dashboard/test-dashboard-api.sh` - a standalone test script that:
- Tests server connectivity
- Tests the login endpoint directly
- Tests authenticated requests
- Provides detailed error messages and debugging hints

## Next Steps to Debug the 500 Error

### Step 1: Restart Everything

Stop all running processes and start fresh:

```bash
# Terminal 1: Start the server
cd /home/user/AppointmentApp/server
dart run main.dart --dev
```

Look for these startup messages:
```
📄 Loaded environment variables from .env file  ← Confirms .env is loaded
✅ Database connection established              ← Confirms DB is working
✅ Server listening on https://0.0.0.0:8080     ← Note the protocol and port
Dashboard credentials: admin / admin123         ← Actual credentials being used
```

### Step 2: Test with the API Test Script

In a second terminal:

```bash
cd /home/user/AppointmentApp/dashboard
./test-dashboard-api.sh
```

This will show exactly where the problem is:
- If it succeeds → The API works fine, issue is with the dashboard frontend
- If it fails with 500 → Check the server console for error details
- If it fails with connection error → Port or protocol mismatch

### Step 3: Check Server Logs

When the test script runs (or when you try to login from the dashboard), the server should print:

**Successful login:**
```
🔐 Dashboard login attempt...
   Request body: {"username":"admin","password":"admin123"}
   Username: admin
   Expected: admin
   ✅ Login successful
```

**Failed login (wrong credentials):**
```
🔐 Dashboard login attempt...
   Request body: {"username":"admin","password":"wrong"}
   Username: admin
   Expected: admin
   ❌ Invalid credentials
```

**500 error (exception):**
```
🔐 Dashboard login attempt...
   Request body: ...
❌ Dashboard login error: <error details>
   Stack trace: <full stack trace>
```

### Step 4: Start the Dashboard (After API Test Passes)

```bash
# Terminal 3: Start the dashboard
cd /home/user/AppointmentApp/dashboard
npm run dev
```

Visit http://localhost:3000 and try logging in. Watch the server console for the login logs.

## Common Causes of 500 Errors

### 1. Database Connection Issues

If the database connection fails, any database query will throw an exception.

**Check**: Look for `✅ Database connection established` in server startup logs

**Fix**: Verify PostgreSQL is running and .env has correct DB credentials

### 2. Environment Variable Issues

If .env is not loaded or has syntax errors, credentials might not be set correctly.

**Check**: Look for `📄 Loaded environment variables from .env file` in server logs

**Fix**:
- Verify `.env` exists in `/home/user/AppointmentApp/.env` (parent of server directory)
- Check .env syntax (no quotes around values, `KEY=value` format)
- Restart the server to reload .env

### 3. JSON Parsing Errors

If the request body is malformed, `jsonDecode()` will throw an exception.

**Check**: Look at the "Request body:" in server logs - should be valid JSON

**Fix**: This should be handled by the frontend, but the logging will show the actual body received

### 4. Port/Protocol Mismatch

If the dashboard is trying to connect to the wrong port or protocol (http vs https).

**Check**:
- Server shows `Server listening on https://0.0.0.0:XXXX`
- Vite config has matching protocol and port in `BACKEND_URL`

**Fix**: Update `dashboard/vite.config.ts`:
```typescript
const BACKEND_URL = 'https://localhost:8080'; // Match your server
```

Or set environment variable:
```bash
export VITE_BACKEND_URL=https://localhost:8080
npm run dev
```

## Configuration Reference

### Server Environment Variables

In `/home/user/AppointmentApp/.env`:

```bash
# Server configuration
SERVER_PORT=8080              # Port for the API server
ENABLE_SSL=true               # Use HTTPS (recommended)
SSL_CERT_PATH=certs/cert.pem  # Self-signed cert for development
SSL_KEY_PATH=certs/key.pem    # Private key

# Dashboard credentials (optional, defaults shown)
DASHBOARD_USERNAME=admin      # Default: admin
DASHBOARD_PASSWORD=admin123   # Default: admin123

# Database connection (required)
DB_HOST=localhost
DB_PORT=5433
DB_NAME=schedule_note_dev
DB_USER=postgres
DB_PASSWORD=<your-password>
```

### Dashboard Configuration

In `dashboard/vite.config.ts`:

```typescript
// Match this to your server's SERVER_PORT and ENABLE_SSL settings
const BACKEND_URL = 'https://localhost:8080';  // https://localhost:<SERVER_PORT>
```

## Still Having Issues?

If you've followed all the steps and still get a 500 error:

1. **Share the server console output** - The detailed logs will show exactly what's happening
2. **Run the test script** - Share the output of `./test-dashboard-api.sh`
3. **Check browser dev tools** - Network tab → Login request → Headers and Payload
4. **Verify file locations**:
   - `.env` should be at `/home/user/AppointmentApp/.env`
   - Server running from `/home/user/AppointmentApp/server`
   - Dashboard running from `/home/user/AppointmentApp/dashboard`

## Summary of Tools Available

1. **Server logs**: Detailed error messages and stack traces
2. **Test script**: `./test-dashboard-api.sh` - Test API without the frontend
3. **Browser DevTools**: Network tab shows request/response details
4. **curl commands**: Manual API testing (examples in test script)

The comprehensive logging added to the login endpoint should reveal exactly what's causing the 500 error. Follow the steps above and check the server console output.
