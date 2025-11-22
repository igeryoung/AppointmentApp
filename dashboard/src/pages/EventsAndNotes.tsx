import React, { useState, useEffect } from 'react';
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
      const hasFilters = filters.bookId || filters.name || filters.recordNumber;

      if (hasFilters) {
        const response = await dashboardAPI.getFilteredEvents(filters);
        setEvents(response.events || []);
      } else {
        // Fetch all events by passing empty filter object
        const response = await dashboardAPI.getFilteredEvents({});
        setEvents(response.events || []);
      }
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
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Events & Notes</h1>
        <p className="text-gray-600">
          View and manage all events with their handwritten notes
        </p>
      </div>

      {/* Controls */}
      <div className="flex justify-between items-center mb-4">
        <div className="flex items-center gap-4">
          <button
            onClick={handleRefresh}
            disabled={loading}
            className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:bg-gray-300"
          >
            {loading ? 'Loading...' : 'Refresh'}
          </button>

          <label className="flex items-center gap-2 text-sm text-gray-700">
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(e) => setAutoRefresh(e.target.checked)}
              className="rounded"
            />
            Auto-refresh (30s)
          </label>
        </div>

        <button
          onClick={handleExport}
          className="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600"
        >
          Export CSV
        </button>
      </div>

      {/* Filters */}
      <EventFilterBar filters={filters} onFiltersChange={setFilters} />

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded mb-4">
          {error}
        </div>
      )}

      {/* Events Table */}
      <EventsTable events={events} loading={loading} />
    </div>
  );
};
