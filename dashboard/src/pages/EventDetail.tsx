import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import { HandwritingCanvas, PageNavigation } from '../components';
import type { Event, Note, NotePages } from '../types';
import { dashboardAPI } from '../services/api';

/**
 * Event Detail Page
 * Displays full event information and handwritten notes
 */
export const EventDetail: React.FC = () => {
  const { eventId } = useParams<{ eventId: string }>();
  const navigate = useNavigate();

  const [event, setEvent] = useState<Event | null>(null);
  const [note, setNote] = useState<Note | null>(null);
  const [notePages, setNotePages] = useState<NotePages>([]);
  const [currentPageIndex, setCurrentPageIndex] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (eventId) {
      loadEventData(parseInt(eventId));
    }
  }, [eventId]);

  const loadEventData = async (id: number) => {
    try {
      setLoading(true);
      setError(null);

      // Load event details
      const eventData = await dashboardAPI.getEventDetail(id);
      setEvent(eventData);

      // Load note if it exists
      if (eventData.hasNote) {
        try {
          const noteData = await dashboardAPI.getEventNote(id);
          setNote(noteData);

          // Parse pages data
          const pages = parseNotePages(noteData);
          setNotePages(pages);
          setCurrentPageIndex(0);
        } catch (noteErr) {
          console.error('Failed to load note:', noteErr);
          setNote(null);
          setNotePages([]);
        }
      }
    } catch (err) {
      console.error('Failed to load event:', err);
      setError('Failed to load event details. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const parseNotePages = (noteData: Note): NotePages => {
    try {
      if (noteData.pagesData) {
        return JSON.parse(noteData.pagesData);
      }
      if (noteData.strokesData) {
        const strokes = JSON.parse(noteData.strokesData);
        return [strokes];
      }
      return [];
    } catch (err) {
      console.error('Failed to parse note data:', err);
      return [];
    }
  };

  const parseEventTypes = (eventTypesJson: string): string[] => {
    try {
      return JSON.parse(eventTypesJson);
    } catch {
      return [];
    }
  };

  const formatDateTime = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const handlePreviousPage = () => {
    if (currentPageIndex > 0) {
      setCurrentPageIndex(currentPageIndex - 1);
    }
  };

  const handleNextPage = () => {
    if (currentPageIndex < notePages.length - 1) {
      setCurrentPageIndex(currentPageIndex + 1);
    }
  };

  if (loading) {
    return (
      <div className="card">
        <div className="card-body" style={{ textAlign: 'center', padding: '3rem' }}>
          <p style={{ color: '#6b7280', fontSize: '1.125rem' }}>Loading event details...</p>
        </div>
      </div>
    );
  }

  if (error || !event) {
    return (
      <div>
        <div className="card" style={{ marginBottom: '1.5rem', backgroundColor: '#fef2f2', borderLeft: '4px solid #ef4444' }}>
          <div className="card-body" style={{ color: '#dc2626' }}>
            {error || 'Event not found'}
          </div>
        </div>
        <button onClick={() => navigate('/events')} className="btn btn-secondary">
          <ArrowLeft size={16} />
          Back to Events List
        </button>
      </div>
    );
  }

  return (
    <div>
      {/* Header */}
      <div className="page-header">
        <button
          onClick={() => navigate('/events')}
          className="btn btn-secondary btn-sm"
          style={{ marginBottom: '1rem' }}
        >
          <ArrowLeft size={16} />
          Back to Events List
        </button>
        <h1 className="page-title">Event Details</h1>
        <p className="page-subtitle">Event ID: {event.id}</p>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))', gap: '1.5rem' }}>
        {/* Event Information Card */}
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Event Information</h2>
          </div>
          <div className="card-body">
            <div style={{ display: 'grid', gap: '1rem' }}>
              <div>
                <label style={{ fontSize: '0.75rem', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                  Book
                </label>
                <p style={{ marginTop: '0.25rem' }}>{event.bookName || `Book ${event.bookId}`}</p>
              </div>

              <div>
                <label style={{ fontSize: '0.75rem', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                  Patient Name
                </label>
                <p style={{ marginTop: '0.25rem', fontWeight: '500', fontSize: '1.125rem' }}>{event.name}</p>
              </div>

              <div>
                <label style={{ fontSize: '0.75rem', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                  Record Number
                </label>
                <p style={{ marginTop: '0.25rem', fontFamily: 'monospace' }}>{event.recordNumber || '-'}</p>
              </div>

              <div>
                <label style={{ fontSize: '0.75rem', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                  Event Types
                </label>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.5rem', marginTop: '0.5rem' }}>
                  {parseEventTypes(event.eventTypes).map((type, index) => (
                    <span key={index} className="badge badge-info">
                      {type}
                    </span>
                  ))}
                </div>
              </div>

              <div>
                <label style={{ fontSize: '0.75rem', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                  Start Time
                </label>
                <p style={{ marginTop: '0.25rem' }}>{formatDateTime(event.startTime)}</p>
              </div>

              <div>
                <label style={{ fontSize: '0.75rem', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                  End Time
                </label>
                <p style={{ marginTop: '0.25rem' }}>
                  {event.endTime ? formatDateTime(event.endTime) : 'Open-ended'}
                </p>
              </div>

              <div>
                <label style={{ fontSize: '0.75rem', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                  Status
                </label>
                <div style={{ display: 'flex', gap: '0.5rem', marginTop: '0.5rem' }}>
                  {event.isRemoved && <span className="badge badge-danger">Removed</span>}
                  {event.isChecked && <span className="badge badge-info">Checked</span>}
                  {!event.isRemoved && !event.isChecked && <span className="badge badge-success">Active</span>}
                </div>
              </div>

              {event.removalReason && (
                <div>
                  <label style={{ fontSize: '0.75rem', fontWeight: '600', color: '#6b7280', textTransform: 'uppercase' }}>
                    Removal Reason
                  </label>
                  <p style={{ marginTop: '0.25rem' }}>{event.removalReason}</p>
                </div>
              )}

              <div style={{ borderTop: '1px solid #e5e7eb', paddingTop: '1rem', marginTop: '1rem' }}>
                <div style={{ display: 'grid', gap: '0.5rem', fontSize: '0.813rem', color: '#6b7280' }}>
                  <div>
                    <span style={{ fontWeight: '500' }}>Created:</span> {formatDateTime(event.createdAt)}
                  </div>
                  <div>
                    <span style={{ fontWeight: '500' }}>Updated:</span> {formatDateTime(event.updatedAt)}
                  </div>
                  <div>
                    <span style={{ fontWeight: '500' }}>Version:</span> {event.version}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Handwriting Notes Card */}
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Handwriting Notes</h2>
          </div>
          <div className="card-body">
            {!event.hasNote || notePages.length === 0 ? (
              <div style={{ textAlign: 'center', padding: '3rem', backgroundColor: '#f9fafb', borderRadius: '0.5rem', border: '1px solid #e5e7eb' }}>
                <p style={{ color: '#6b7280' }}>No handwritten notes available</p>
              </div>
            ) : (
              <div>
                {/* Canvas */}
                <div style={{ display: 'flex', justifyContent: 'center', marginBottom: '1rem' }}>
                  <HandwritingCanvas
                    page={notePages[currentPageIndex]}
                    width={600}
                    height={800}
                  />
                </div>

                {/* Page Navigation */}
                {notePages.length > 1 && (
                  <PageNavigation
                    currentPage={currentPageIndex}
                    totalPages={notePages.length}
                    onPrevious={handlePreviousPage}
                    onNext={handleNextPage}
                  />
                )}

                {/* Note Metadata */}
                {note && (
                  <div style={{ borderTop: '1px solid #e5e7eb', paddingTop: '1rem', marginTop: '1rem', fontSize: '0.813rem', color: '#6b7280' }}>
                    <div style={{ display: 'grid', gap: '0.5rem' }}>
                      <div>
                        <span style={{ fontWeight: '500' }}>Note ID:</span> {note.id}
                      </div>
                      <div>
                        <span style={{ fontWeight: '500' }}>Last Updated:</span> {formatDateTime(note.updatedAt)}
                      </div>
                      <div>
                        <span style={{ fontWeight: '500' }}>Version:</span> {note.version}
                      </div>
                      <div>
                        <span style={{ fontWeight: '500' }}>Total Pages:</span> {notePages.length}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
