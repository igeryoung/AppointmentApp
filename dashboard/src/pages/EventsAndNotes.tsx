import React, { useCallback, useEffect, useState } from 'react';
import { RefreshCw, Download } from 'lucide-react';
import { EventFilterBar, EventsTable } from '../components';
import type { Event, EventFilters } from '../types';
import { dashboardAPI } from '../services/api';

const PAGE_SIZE = 30;

/**
 * Events & Notes Dashboard Page
 * Lists all events with filtering capabilities
 * Users can click on events to view details and handwritten notes
 */
export const EventsAndNotes: React.FC = () => {
  const [events, setEvents] = useState<Event[]>([]);
  const [filters, setFilters] = useState<EventFilters>({});
  const [currentPage, setCurrentPage] = useState(0);
  const [totalEvents, setTotalEvents] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(false);

  const loadEvents = useCallback(async (page: number, activeFilters: EventFilters) => {
    try {
      setLoading(true);
      setError(null);

      const normalizedFilters = activeFilters.bookUuid || activeFilters.name || activeFilters.recordNumber
        ? activeFilters
        : {};
      const response = await dashboardAPI.getFilteredEvents(
        normalizedFilters,
        { limit: PAGE_SIZE, offset: page * PAGE_SIZE },
      );

      if (response.total > 0 && page * PAGE_SIZE >= response.total) {
        setCurrentPage(Math.max(0, Math.ceil(response.total / PAGE_SIZE) - 1));
        return;
      }

      setEvents(response.events || []);
      setTotalEvents(response.total);
    } catch (err) {
      console.error('Failed to load events:', err);
      setError('Failed to load events. Please try again.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadEvents(currentPage, filters);
  }, [currentPage, filters, loadEvents]);

  useEffect(() => {
    if (!autoRefresh) return;

    const interval = setInterval(() => {
      loadEvents(currentPage, filters);
    }, 30000); // Refresh every 30 seconds

    return () => clearInterval(interval);
  }, [autoRefresh, currentPage, filters, loadEvents]);

  const totalPages = Math.max(1, Math.ceil(totalEvents / PAGE_SIZE));
  const hasPreviousPage = currentPage > 0;
  const hasNextPage = (currentPage + 1) * PAGE_SIZE < totalEvents;
  const pageStart = totalEvents === 0 ? 0 : currentPage * PAGE_SIZE + 1;
  const pageEnd = totalEvents === 0 ? 0 : Math.min(totalEvents, (currentPage + 1) * PAGE_SIZE);

  const handleRefresh = () => {
    loadEvents(currentPage, filters);
  };

  const handleFiltersChange = (nextFilters: EventFilters) => {
    setFilters(nextFilters);
    setCurrentPage(0);
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
      <EventFilterBar filters={filters} onFiltersChange={handleFiltersChange} />

      {/* Error Message */}
      {error && (
        <div className="card" style={{ marginBottom: '1.5rem', backgroundColor: '#fef2f2', borderLeft: '4px solid #ef4444' }}>
          <div className="card-body" style={{ color: '#dc2626' }}>
            {error}
          </div>
        </div>
      )}

      {/* Events Table */}
      <EventsTable events={events} loading={loading} totalCount={totalEvents} />

      {!loading && totalEvents > 0 && (
        <div className="toolbar" style={{ marginTop: '1rem' }}>
          <div className="toolbar-section">
            <span style={{ color: '#6b7280', fontSize: '0.875rem' }}>
              Showing {pageStart}-{pageEnd} of {totalEvents}
            </span>
          </div>
          <div className="toolbar-section">
            <button
              onClick={() => setCurrentPage((page) => Math.max(0, page - 1))}
              className="btn btn-secondary btn-sm"
              disabled={!hasPreviousPage || loading}
            >
              Previous
            </button>
            <span style={{ color: '#374151', fontSize: '0.875rem' }}>
              Page {currentPage + 1} of {totalPages}
            </span>
            <button
              onClick={() => setCurrentPage((page) => page + 1)}
              className="btn btn-secondary btn-sm"
              disabled={!hasNextPage || loading}
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
