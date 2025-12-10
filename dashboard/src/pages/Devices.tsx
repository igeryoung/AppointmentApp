import React, { useEffect, useMemo, useState } from 'react';
import { RefreshCw, Search, Users, Activity } from 'lucide-react';
import { dashboardAPI } from '../services/api';
import { parseServerDate } from '../utils/date';
import type { DeviceStats } from '../types';

const formatDateTime = (value?: string | null) => {
  const parsed = parseServerDate(value);
  return parsed ? parsed.toLocaleString() : '—';
};

const formatLastSyncStatus = (value?: string | null) => {
  if (!value) return 'Never';
  const parsed = parseServerDate(value);
  if (!parsed) return 'Never';

  const diffHours = (Date.now() - parsed.getTime()) / (1000 * 60 * 60);
  if (diffHours < 1) return 'Within 1h';
  if (diffHours < 24) return `${Math.floor(diffHours)}h ago`;
  const days = Math.floor(diffHours / 24);
  return `${days}d ago`;
};

export function Devices() {
  const [stats, setStats] = useState<DeviceStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [showOnlyActive, setShowOnlyActive] = useState(false);
  const [platformFilter, setPlatformFilter] = useState('all');

  const loadDevices = async () => {
    try {
      setLoading(true);
      const data = await dashboardAPI.getDevices();
      setStats(data);
    } catch (error) {
      console.error('Failed to load devices:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadDevices();
  }, []);

  const devices = stats?.devices ?? [];

  const platforms = useMemo(() => {
    const set = new Set<string>();
    devices.forEach((device) => {
      if (device.platform) {
        set.add(device.platform);
      }
    });
    return Array.from(set);
  }, [devices]);

  const filteredDevices = devices.filter((device) => {
    const query = searchQuery.trim().toLowerCase();
    const matchesQuery =
      !query ||
      device.deviceName.toLowerCase().includes(query) ||
      device.id.toLowerCase().includes(query);
    const matchesActive = !showOnlyActive || device.isActive;
    const matchesPlatform = platformFilter === 'all' || device.platform === platformFilter;
    return matchesQuery && matchesActive && matchesPlatform;
  });

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Devices</h1>
        <p className="page-subtitle">Monitor registered devices and their sync activity</p>
      </div>

      <div className="toolbar">
        <div className="toolbar-section">
          <button onClick={loadDevices} className="btn btn-primary btn-sm" disabled={loading}>
            <RefreshCw size={16} />
            {loading ? 'Loading...' : 'Refresh'}
          </button>
        </div>

        <div className="toolbar-section">
          <div style={{ position: 'relative' }}>
            <Search
              size={16}
              style={{
                position: 'absolute',
                left: '0.75rem',
                top: '50%',
                transform: 'translateY(-50%)',
                color: '#6b7280',
              }}
            />
            <input
              type="text"
              placeholder="Search by device name or ID..."
              className="input"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              style={{ paddingLeft: '2.5rem' }}
            />
          </div>

          <select
            value={platformFilter}
            onChange={(e) => setPlatformFilter(e.target.value)}
            className="input"
            style={{ maxWidth: '180px' }}
          >
            <option value="all">All platforms</option>
            {platforms.map((platform) => (
              <option key={platform} value={platform}>
                {platform}
              </option>
            ))}
          </select>

          <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.875rem' }}>
            <input
              type="checkbox"
              checked={showOnlyActive}
              onChange={(e) => setShowOnlyActive(e.target.checked)}
            />
            Active only
          </label>
        </div>
      </div>

      {stats && (
        <div className="stats-grid" style={{ marginTop: '1rem' }}>
          <DeviceStatCard
            title="Total Devices"
            value={stats.total}
            subtitle="Registered for sync"
            icon={Users}
            color="#4f46e5"
          />
          <DeviceStatCard
            title="Active"
            value={stats.active}
            subtitle="Currently allowed to sync"
            icon={Activity}
            color="#10b981"
          />
          <DeviceStatCard
            title="Inactive"
            value={stats.inactive}
            subtitle="Disabled or removed"
            icon={Users}
            color="#f59e0b"
          />
        </div>
      )}

      <div className="card">
        <div className="card-header">
          <h2 className="card-title">Device Registry ({filteredDevices.length})</h2>
        </div>
        <div className="card-body">
          {loading ? (
            <div className="loading">
              <div className="spinner"></div>
              <p>Loading devices...</p>
            </div>
          ) : filteredDevices.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '3rem', color: '#6b7280' }}>
              No devices found
            </div>
          ) : (
            <div className="table-container">
              <table>
                <thead>
                  <tr>
                    <th style={{ width: '18%' }}>Device</th>
                    <th>Platform</th>
                    <th style={{ width: '18%' }}>Registered</th>
                    <th style={{ width: '18%' }}>Last Sync</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredDevices.map((device) => (
                    <tr key={device.id}>
                      <td>
                        <div style={{ fontWeight: 600 }}>{device.deviceName}</div>
                        <div style={{ fontFamily: 'monospace', fontSize: '0.75rem', color: '#6b7280' }}>
                          {device.id.substring(0, 12)}...
                        </div>
                      </td>
                      <td style={{ textTransform: 'capitalize' }}>{device.platform || 'Unknown'}</td>
                      <td>{formatDateTime(device.registeredAt)}</td>
                      <td>
                        {formatDateTime(device.lastSyncAt)}
                        <div style={{ color: '#6b7280', fontSize: '0.75rem' }}>
                          {formatLastSyncStatus(device.lastSyncAt)}
                        </div>
                      </td>
                      <td>
                        {device.isActive ? (
                          <span className="badge badge-success">Active</span>
                        ) : (
                          <span className="badge badge-danger">Inactive</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

interface DeviceStatCardProps {
  title: string;
  value: number;
  subtitle: string;
  icon: React.ElementType;
  color: string;
}

function DeviceStatCard({ title, value, subtitle, icon: Icon, color }: DeviceStatCardProps) {
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
