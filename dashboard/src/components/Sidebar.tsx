import { Link, useLocation } from 'react-router-dom';
import {
  LayoutDashboard,
  BookOpen,
  Calendar,
  FileText,
  Palette,
  Database,
  RefreshCw,
  Users,
  LogOut,
} from 'lucide-react';
import { dashboardAPI } from '../services/api';

const navItems = [
  { path: '/', label: 'Overview', icon: LayoutDashboard },
  { path: '/devices', label: 'Devices', icon: Users },
  { path: '/books', label: 'Books', icon: BookOpen },
  { path: '/events', label: 'Events', icon: Calendar },
  { path: '/notes', label: 'Notes', icon: FileText },
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
          const isActive = location.pathname === item.path;

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
