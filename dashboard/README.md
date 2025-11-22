# Appointment App Dashboard

A real-time monitoring dashboard for the Appointment Registration App. Built with React + TypeScript and Vite.

## Features

✅ **Overview Dashboard** - System health and key metrics at a glance
✅ **Device Management** - Monitor all registered devices and sync status
✅ **Books Monitoring** - Track all appointment books, active/archived status
✅ **Events Analytics** - View events by type, time, and status
✅ **Notes Statistics** - Monitor note coverage and recent updates
✅ **Drawings Overview** - Track schedule drawings by view mode
✅ **Backup Management** - Monitor backups, sizes, and restore history
✅ **Sync Logs** - Track sync operations, success rates, and conflicts

## Tech Stack

- **Frontend**: React 18 + TypeScript
- **Build Tool**: Vite
- **Routing**: React Router v6
- **HTTP Client**: Axios
- **Icons**: Lucide React
- **Charts**: ApexCharts (ready for future use)
- **Styling**: Custom CSS (clean, professional design)

## Prerequisites

- Node.js 18+ and npm
- Running Dart server (port 8080)
- PostgreSQL database with data

## Installation

1. **Install dependencies**:
   ```bash
   cd dashboard
   npm install
   ```

2. **Configure backend connection**:

   The dashboard connects to `/api/dashboard/*` endpoints which are proxied to the Dart server by Vite.

   **Default configuration** (in `vite.config.ts`):
   - Target: `https://localhost:8080` (HTTPS with self-signed cert)
   - Port: 8080 (matches custom server configuration)

   **To match your server configuration**:
   1. Check your `../.env` file for `SERVER_PORT` value
   2. Update `vite.config.ts` if needed:
      ```typescript
      const BACKEND_URL = 'https://localhost:YOUR_SERVER_PORT';
      ```
   3. Or set environment variable:
      ```bash
      export VITE_BACKEND_URL=https://localhost:8443
      npm run dev
      ```

   **Common server configurations**:
   - `SERVER_PORT=8080` + `ENABLE_SSL=true` → Use `https://localhost:8080`
   - `SERVER_PORT=8443` + `ENABLE_SSL=true` → Use `https://localhost:8443` (default)
   - `SERVER_PORT=8080` + `ENABLE_SSL=false` → Use `http://localhost:8080`

## Running the Dashboard

### Test Backend Connection (Optional but Recommended)

Before starting the dashboard, test the API connection:

```bash
# Make sure server is running first
cd ../server
dart run main.dart --dev

# In another terminal, test the connection
cd dashboard
./test-dashboard-api.sh
```

This will verify:
- Server is responding
- Login endpoint is working
- Authentication token is valid
- Credentials are correct

If the test fails, it will show debugging hints.

### Development Mode

```bash
npm run dev
```

The dashboard will be available at **http://localhost:3000**

### Production Build

```bash
npm run build
npm run preview
```

## Default Credentials

**Username**: `admin`
**Password**: `admin123`

To change credentials, set environment variables on the server:
- `DASHBOARD_USERNAME`
- `DASHBOARD_PASSWORD`

## Dashboard Features

### 1. Overview Page (`/`)

**Real-time statistics**:
- Total Devices (active/inactive breakdown)
- Total Books (active/archived)
- Total Events (active/removed)
- Total Notes (coverage %)
- Schedule Drawings (by view mode)
- Backups (count and total size)
- Sync Statistics (success rate, failures, conflicts)

**Controls**:
- ✅ Manual refresh button
- ✅ Auto-refresh toggle (30s, 1min, 2min, 5min intervals)
- ✅ Export to CSV
- ✅ Last updated timestamp

### 2. Books Page (`/books`)

**Features**:
- Complete book list with statistics
- Search by book name
- Filter: Show/hide archived books
- Columns: ID, Name, Device, Events, Notes, Drawings, Created, Status
- Export to CSV

### 3. Other Pages

Placeholder pages ready for future implementation:
- `/devices` - Device details and sync history
- `/events` - Event timeline and analytics
- `/notes` - Note coverage and recent updates
- `/drawings` - Drawing statistics by view mode
- `/backups` - Backup management
- `/sync` - Detailed sync operation logs

## API Endpoints (Server Side)

All endpoints require `Authorization: Bearer <token>` header after login.

### Authentication
- `POST /api/dashboard/auth/login` - Admin login

### Data Endpoints
- `GET /api/dashboard/stats` - Overall dashboard statistics
- `GET /api/dashboard/devices` - Device statistics
- `GET /api/dashboard/books` - Book statistics
- `GET /api/dashboard/events` - Event statistics
- `GET /api/dashboard/notes` - Note statistics
- `GET /api/dashboard/drawings` - Drawing statistics
- `GET /api/dashboard/backups` - Backup statistics
- `GET /api/dashboard/sync-logs` - Sync operation logs

## Project Structure

```
dashboard/
├── src/
│   ├── components/        # Reusable components
│   │   └── Sidebar.tsx    # Navigation sidebar
│   ├── pages/             # Page components
│   │   ├── Login.tsx      # Login page
│   │   ├── Overview.tsx   # Dashboard overview
│   │   └── Books.tsx      # Books management
│   ├── services/          # API services
│   │   └── api.ts         # Dashboard API client
│   ├── types/             # TypeScript types
│   │   └── index.ts       # Type definitions
│   ├── styles/            # CSS files
│   │   └── index.css      # Global styles
│   ├── App.tsx            # Main app component
│   └── main.tsx           # Entry point
├── public/                # Static assets
├── index.html             # HTML template
├── package.json           # Dependencies
├── tsconfig.json          # TypeScript config
├── vite.config.ts         # Vite config
└── README.md              # This file
```

## Customization

### Change Refresh Intervals

Edit `src/pages/Overview.tsx`:
```typescript
<select value={refreshInterval}>
  <option value={30}>30 sec</option>
  <option value={60}>1 min</option>
  <option value={120}>2 min</option>
  <option value={300}>5 min</option>
  // Add your custom intervals
</select>
```

### Add New Pages

1. Create component in `src/pages/YourPage.tsx`
2. Add route in `src/App.tsx`
3. Add navigation item in `src/components/Sidebar.tsx`

### Customize Styling

Edit `src/styles/index.css` - all colors are defined as CSS variables:
```css
:root {
  --primary-color: #4f46e5;
  --secondary-color: #10b981;
  /* ... */
}
```

## Read-Only Design

This dashboard is designed for **monitoring only**:
- ❌ No create/edit/delete operations
- ✅ All endpoints are GET requests (except login)
- ✅ Safe for production use
- ✅ No risk of accidental data modification

## Security Notes

- Authentication uses simple Bearer token (suitable for internal use)
- For production, consider:
  - JWT tokens with expiration
  - HTTPS only
  - Rate limiting
  - IP whitelisting
  - Stronger password policy

## Troubleshooting

### Cannot connect to API

**Check server is running:**
```bash
# From server directory
cd server
dart run main.dart --dev
```

Look for the startup message showing the port:
```
✅ Server listening on https://0.0.0.0:8080
```

**Match the Vite proxy to your server:**
1. Note the protocol (http/https) and port from server startup
2. Update `dashboard/vite.config.ts` to match:
   ```typescript
   const BACKEND_URL = 'https://localhost:8080'; // Match your server
   ```
3. Restart the dashboard dev server

**Common issues:**
- **Connection refused**: Server not running or wrong port
- **SSL errors**: Using `https://` in proxy but server has `ENABLE_SSL=false`
- **Self-signed cert errors**: Already handled with `secure: false` in proxy config

### Login fails (500 Internal Server Error)

**Check server logs for detailed error:**
1. Stop the server (Ctrl+C)
2. Restart with:
   ```bash
   cd server
   dart run main.dart --dev
   ```
3. Try logging in from the dashboard
4. Look for these log messages:
   ```
   🔐 Dashboard login attempt...
      Request body: {"username":"admin","password":"..."}
      Username: admin
      Expected: admin
   ```

**Common causes:**
- **Wrong credentials**: Default is `admin` / `admin123` (check server startup logs)
- **Environment variables**: Set `DASHBOARD_USERNAME` and `DASHBOARD_PASSWORD` in `../.env`
- **Database connection**: Server must connect to PostgreSQL successfully
- **JSON parsing error**: Check browser Network tab for request payload

**Override default credentials** (in `../.env`):
```bash
DASHBOARD_USERNAME=myadmin
DASHBOARD_PASSWORD=mypassword123
```

### Data not loading
1. Verify database connection on server
2. Check browser Network tab for failed requests
3. Ensure database has data to display

## Future Enhancements

- [ ] Real-time updates via WebSocket
- [ ] Charts and visualizations (ApexCharts)
- [ ] Advanced filtering and search
- [ ] Date range pickers
- [ ] Alert notifications
- [ ] Custom dashboard layouts
- [ ] User preferences
- [ ] Mobile responsive improvements
- [ ] Dark mode theme

## License

Same as parent project.

## Support

For issues or questions, please refer to the main project documentation.
