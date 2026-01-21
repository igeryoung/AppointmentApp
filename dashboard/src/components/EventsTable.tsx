import React from 'react';
import { useNavigate } from 'react-router-dom';
import type { Event } from '../types';
import { parseServerDate } from '../utils/date';
import { getBookDisplayName } from '../utils/book';
import { formatShortId } from '../utils/id';
import { parseEventTypes } from '../utils/event';

interface EventsTableProps {
  events: Event[];
  loading?: boolean;
  title?: string;
  emptyMessage?: string;
}

/**
 * Table component for displaying events list
 * Shows event details with sortable columns and clickable rows
 */
export const EventsTable: React.FC<EventsTableProps> = ({
  events,
  loading = false,
  title = 'All Events',
  emptyMessage = 'No events found',
}) => {
  const navigate = useNavigate();

  const handleViewDetails = (eventId: string) => {
    navigate(`/events/${eventId}`);
  };

  const formatDateTime = (dateString?: string | null) => {
    const date = parseServerDate(dateString);
    if (!date) {
      return '-';
    }
    return date.toLocaleString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  if (loading) {
    return (
      <div className="card">
        <div className="card-body" style={{ textAlign: 'center', padding: '3rem' }}>
          <p style={{ color: '#6b7280' }}>Loading events...</p>
        </div>
      </div>
    );
  }

  if (events.length === 0) {
    return (
      <div className="card">
        <div className="card-body" style={{ textAlign: 'center', padding: '3rem' }}>
          <p style={{ color: '#6b7280' }}>{emptyMessage}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="card">
      <div className="card-header">
        <h2 className="card-title">{title} ({events.length})</h2>
      </div>
      <div className="card-body">
        <div className="table-container">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Book</th>
                <th>Patient Name</th>
                <th>Record #</th>
                <th>Phone</th>
                <th>Event Types</th>
                <th>Start Time</th>
                <th>End Time</th>
                <th style={{ textAlign: 'center' }}>Note</th>
                <th style={{ textAlign: 'center' }}>Status</th>
                <th style={{ textAlign: 'center' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {events.map((event) => (
                <tr
                  key={event.id}
                  onClick={() => handleViewDetails(event.id)}
                  style={{ cursor: 'pointer' }}
                >
                  <td style={{ fontFamily: 'monospace' }}>{formatShortId(event.id)}</td>
                  <td>{getBookDisplayName(event.bookName, event.bookUuid)}</td>
                  <td style={{ fontWeight: '500' }}>{event.name}</td>
                  <td style={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>
                    {event.recordNumber || '-'}
                  </td>
                  <td style={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>
                    {event.phone || '-'}
                  </td>
                  <td>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.25rem' }}>
                      {parseEventTypes(event.eventTypes).map((type, index) => (
                        <span key={index} className="badge badge-info">
                          {type}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td style={{ fontSize: '0.813rem' }}>{formatDateTime(event.startTime)}</td>
                  <td style={{ fontSize: '0.813rem' }}>
                    {event.endTime ? formatDateTime(event.endTime) : '-'}
                  </td>
                  <td style={{ textAlign: 'center' }}>
                    {event.hasNote ? (
                      <span style={{ color: '#10b981', fontWeight: 'bold' }}>✓</span>
                    ) : (
                      <span style={{ color: '#d1d5db' }}>✗</span>
                    )}
                  </td>
                  <td style={{ textAlign: 'center' }}>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.25rem', alignItems: 'center' }}>
                      {event.isRemoved && (
                        <span className="badge badge-danger">Removed</span>
                      )}
                      {event.isChecked && (
                        <span className="badge badge-info">Checked</span>
                      )}
                      {!event.isRemoved && !event.isChecked && (
                        <span className="badge badge-success">Active</span>
                      )}
                    </div>
                  </td>
                  <td style={{ textAlign: 'center' }}>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleViewDetails(event.id);
                      }}
                      className="btn btn-primary btn-sm"
                    >
                      View
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
