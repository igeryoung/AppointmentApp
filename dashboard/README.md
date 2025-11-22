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

2. **Configure environment** (optional):

   The dashboard connects to `/api/dashboard/*` endpoints which are proxied to `http://localhost:8080` by Vite.

   To change the backend URL, edit `vite.config.ts`:
   ```typescript
   proxy: {
     '/api': {
       target: 'http://your-server:port',
       changeOrigin: true,
     },
   }
   ```

## Running the Dashboard

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
1. Ensure Dart server is running on port 8080
2. Check Vite proxy configuration in `vite.config.ts`
3. Verify CORS settings if needed

### Login fails
1. Check server logs for dashboard credentials
2. Verify `DASHBOARD_USERNAME` and `DASHBOARD_PASSWORD` env vars
3. Check browser console for error messages

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
