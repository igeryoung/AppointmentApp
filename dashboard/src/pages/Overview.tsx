import { useState, useEffect, useCallback } from 'react';
import {
  Users,
  BookOpen,
  Calendar,
  FileText,
  Palette,
  Database,
  RefreshCw,
  Download,
} from 'lucide-react';
import { dashboardAPI } from '../services/api';
import type { DashboardStats } from '../types';

export function Overview() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(false);
  const [refreshInterval, setRefreshInterval] = useState(60); // seconds

  const fetchStats = useCallback(async () => {
    try {
      setLoading(true);
      const data = await dashboardAPI.getStats();
      setStats(data);
      setLastUpdated(new Date());
    } catch (error) {
      console.error('Failed to fetch stats:', error);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchStats();
  }, [fetchStats]);

  useEffect(() => {
    if (autoRefresh && refreshInterval > 0) {
      const interval = setInterval(fetchStats, refreshInterval * 1000);
      return () => clearInterval(interval);
    }
  }, [autoRefresh, refreshInterval, fetchStats]);

  const handleExport = async () => {
    try {
      await dashboardAPI.exportData('stats', 'csv');
    } catch (error) {
      console.error('Export failed:', error);
    }
  };

  if (loading && !stats) {
    return (
      <div className="loading">
        <div className="spinner"></div>
        <p>Loading dashboard...</p>
      </div>
    );
  }

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Dashboard Overview</h1>
        <p className="page-subtitle">
          Monitor your appointment registration system
          {lastUpdated && ` • Last updated: ${lastUpdated.toLocaleTimeString()}`}
        </p>
      </div>

      <div className="toolbar">
        <div className="toolbar-section">
          <button
            onClick={fetchStats}
            className="btn btn-primary btn-sm"
            disabled={loading}
          >
            <RefreshCw size={16} />
            Refresh
          </button>

          <button onClick={handleExport} className="btn btn-secondary btn-sm">
            <Download size={16} />
            Export
          </button>
        </div>

        <div className="toolbar-section">
          <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(e) => setAutoRefresh(e.target.checked)}
            />
            <span style={{ fontSize: '0.875rem' }}>Auto-refresh</span>
          </label>

          {autoRefresh && (
            <select
              value={refreshInterval}
              onChange={(e) => setRefreshInterval(Number(e.target.value))}
              className="input"
              style={{ maxWidth: '120px' }}
            >
              <option value={30}>30 sec</option>
              <option value={60}>1 min</option>
              <option value={120}>2 min</option>
              <option value={300}>5 min</option>
            </select>
          )}
        </div>
      </div>

      {stats && (
        <>
          <div className="stats-grid">
            <StatCard
              title="Total Devices"
              value={stats.devices.total}
              subtitle={`${stats.devices.active} active, ${stats.devices.inactive} inactive`}
              icon={Users}
              color="#4f46e5"
            />
            <StatCard
              title="Total Books"
              value={stats.books.total}
              subtitle={`${stats.books.active} active, ${stats.books.archived} archived`}
              icon={BookOpen}
              color="#10b981"
            />
            <StatCard
              title="Total Events"
              value={stats.events.total}
              subtitle={`${stats.events.active} active, ${stats.events.removed} removed`}
              icon={Calendar}
              color="#f59e0b"
            />
            <StatCard
              title="Total Notes"
              value={stats.notes.total}
              subtitle={`${stats.notes.eventsWithNotes} events with notes`}
              icon={FileText}
              color="#8b5cf6"
            />
            <StatCard
              title="Schedule Drawings"
              value={stats.drawings.total}
              subtitle={`${stats.drawings.byViewMode.day} day, ${stats.drawings.byViewMode.threeDay} 3-day, ${stats.drawings.byViewMode.week} week`}
              icon={Palette}
              color="#ec4899"
            />
            <StatCard
              title="Backups"
              value={stats.backups.total}
              subtitle={`${stats.backups.totalSizeMB} total size`}
              icon={Database}
              color="#06b6d4"
            />
          </div>

          <div className="card">
            <div className="card-header">
              <h2 className="card-title">Sync Statistics</h2>
            </div>
            <div className="card-body">
              <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))' }}>
                <div>
                  <div style={{ fontSize: '0.875rem', color: '#6b7280', marginBottom: '0.5rem' }}>
                    Total Operations
                  </div>
                  <div style={{ fontSize: '1.5rem', fontWeight: '700' }}>
                    {stats.sync.totalOperations}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: '0.875rem', color: '#6b7280', marginBottom: '0.5rem' }}>
                    Success Rate
                  </div>
                  <div style={{ fontSize: '1.5rem', fontWeight: '700', color: '#10b981' }}>
                    {stats.sync.successRate.toFixed(1)}%
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: '0.875rem', color: '#6b7280', marginBottom: '0.5rem' }}>
                    Failed Syncs
                  </div>
                  <div style={{ fontSize: '1.5rem', fontWeight: '700', color: '#ef4444' }}>
                    {stats.sync.failedSyncs}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: '0.875rem', color: '#6b7280', marginBottom: '0.5rem' }}>
                    Conflicts
                  </div>
                  <div style={{ fontSize: '1.5rem', fontWeight: '700', color: '#f59e0b' }}>
                    {stats.sync.conflictCount}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

interface StatCardProps {
  title: string;
  value: number;
  subtitle: string;
  icon: React.ElementType;
  color: string;
}

function StatCard({ title, value, subtitle, icon: Icon, color }: StatCardProps) {
  return (
    <div className="stat-card">
      <div className="stat-header">
        <div className="stat-title">{title}</div>
        <div className="stat-icon" style={{ backgroundColor: `${color}20`, color }}>
          <Icon size={24} />
        </div>
      </div>
      <div className="stat-value">{value.toLocaleString()}</div>
      <div style={{ fontSize: '0.875rem', color: '#6b7280', marginTop: '0.5rem' }}>
        {subtitle}
      </div>
    </div>
  );
}
