import { Link, useLocation } from 'react-router-dom';
import {
  LayoutDashboard,
  CalendarDays,
  BookOpen,
  Calendar,
  Palette,
  Database,
  RefreshCw,
  Users,
  FileText,
  LogOut,
} from 'lucide-react';
import { dashboardAPI } from '../services/api';

const navItems = [
  { path: '/', label: 'Overview', icon: LayoutDashboard },
  { path: '/today', label: 'Today', icon: CalendarDays },
  { path: '/devices', label: 'Devices', icon: Users },
  { path: '/books', label: 'Books', icon: BookOpen },
  { path: '/records', label: 'Records', icon: FileText },
  { path: '/events', label: 'Events & Notes', icon: Calendar },
  { path: '/drawings', label: 'Drawings', icon: Palette },
  { path: '/backups', label: 'Backups', icon: Database },
  { path: '/sync', label: 'Sync Logs', icon: RefreshCw },
];

export function Sidebar() {
  const location = useLocation();

  const handleLogout = () => {
    dashboardAPI.logout();
    window.location.href = '/login';
  };

  return (
    <div className="sidebar">
      <div className="sidebar-header">
        <h1 className="sidebar-title">Dashboard</h1>
        <p className="sidebar-subtitle">Appointment App Monitor</p>
      </div>

      <nav className="sidebar-nav">
        {navItems.map((item) => {
          const Icon = item.icon;
          // Highlight Events & Notes for both /events and /events/:id paths
          const isActive = item.path === '/events'
            ? location.pathname === item.path || location.pathname.startsWith('/events/')
            : location.pathname === item.path;

          return (
            <Link
              key={item.path}
              to={item.path}
              className={`nav-item ${isActive ? 'active' : ''}`}
            >
              <Icon className="nav-icon" />
              <span>{item.label}</span>
            </Link>
          );
        })}

        <button
          onClick={handleLogout}
          className="nav-item"
          style={{
            width: '100%',
            background: 'none',
            border: 'none',
            textAlign: 'left',
            marginTop: '2rem',
          }}
        >
          <LogOut className="nav-icon" />
          <span>Logout</span>
        </button>
      </nav>
    </div>
  );
}
