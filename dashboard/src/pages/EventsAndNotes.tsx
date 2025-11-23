import React, { useState, useEffect } from 'react';
import { RefreshCw, Download } from 'lucide-react';
import { EventFilterBar, EventsTable } from '../components';
import type { Event, EventFilters } from '../types';
import { dashboardAPI } from '../services/api';

/**
 * Events & Notes Dashboard Page
 * Lists all events with filtering capabilities
 * Users can click on events to view details and handwritten notes
 */
export const EventsAndNotes: React.FC = () => {
  const [events, setEvents] = useState<Event[]>([]);
  const [filters, setFilters] = useState<EventFilters>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(false);

  useEffect(() => {
    loadEvents();
  }, [filters]);

  useEffect(() => {
    if (!autoRefresh) return;

    const interval = setInterval(() => {
      loadEvents();
    }, 30000); // Refresh every 30 seconds

    return () => clearInterval(interval);
  }, [autoRefresh, filters]);

  const loadEvents = async () => {
    try {
      setLoading(true);
      setError(null);

      // If no filters, fetch all events
      const response = await dashboardAPI.getFilteredEvents(filters.bookUuid || filters.name || filters.recordNumber ? filters : {});
      setEvents(response.events || []);
    } catch (err) {
      console.error('Failed to load events:', err);
      setError('Failed to load events. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const handleRefresh = () => {
    loadEvents();
  };

  const handleExport = async () => {
    try {
      await dashboardAPI.exportData('events', 'csv', filters);
    } catch (err) {
      console.error('Failed to export events:', err);
      alert('Failed to export events');
    }
  };

  return (
    <div>
      {/* Header */}
      <div className="page-header">
        <h1 className="page-title">Events & Notes</h1>
        <p className="page-subtitle">View and manage all events with their handwritten notes</p>
      </div>

      {/* Controls */}
      <div className="toolbar">
        <div className="toolbar-section">
          <button onClick={handleRefresh} className="btn btn-primary btn-sm" disabled={loading}>
            <RefreshCw size={16} />
            {loading ? 'Loading...' : 'Refresh'}
          </button>

          <button onClick={handleExport} className="btn btn-secondary btn-sm">
            <Download size={16} />
            Export
          </button>

          <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.875rem' }}>
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(e) => setAutoRefresh(e.target.checked)}
            />
            Auto-refresh (30s)
          </label>
        </div>
      </div>

      {/* Filters */}
      <EventFilterBar filters={filters} onFiltersChange={setFilters} />

      {/* Error Message */}
      {error && (
        <div className="card" style={{ marginBottom: '1.5rem', backgroundColor: '#fef2f2', borderLeft: '4px solid #ef4444' }}>
          <div className="card-body" style={{ color: '#dc2626' }}>
            {error}
          </div>
        </div>
      )}

      {/* Events Table */}
      <EventsTable events={events} loading={loading} />
    </div>
  );
};
