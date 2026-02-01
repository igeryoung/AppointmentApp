import React, { useState, useEffect, useRef, useCallback } from 'react';
import axios from 'axios';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import { HandwritingCanvas, PageNavigation } from '../components';
import type { Event, Note, NotePages } from '../types';
import { dashboardAPI } from '../services/api';
import { parseServerDate } from '../utils/date';
import { getBookDisplayName } from '../utils/book';
import { formatShortId } from '../utils/id';
import { parseEventTypes } from '../utils/event';
import { parseNotePagesData } from '../utils/handwriting';

const CANVAS_ASPECT_RATIO = 3 / 4; // width / height
const CANVAS_MAX_WIDTH = 600;
const CANVAS_DEFAULT_HEIGHT = 800;

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
  const [noteCanvasSize, setNoteCanvasSize] = useState<{ width: number; height: number } | null>(null);
  const [currentPageIndex, setCurrentPageIndex] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Responsive canvas sizing
  const canvasContainerRef = useRef<HTMLDivElement>(null);
  const [canvasDimensions, setCanvasDimensions] = useState({ width: CANVAS_MAX_WIDTH, height: CANVAS_DEFAULT_HEIGHT });

  const calculateCanvasDimensions = useCallback(() => {
    if (!canvasContainerRef.current) return;

    const containerWidth = canvasContainerRef.current.clientWidth;
    const width = Math.min(containerWidth, CANVAS_MAX_WIDTH);
    const height = Math.round(width / CANVAS_ASPECT_RATIO);

    setCanvasDimensions({ width, height });
  }, []);

  useEffect(() => {
    calculateCanvasDimensions();

    let timeoutId: ReturnType<typeof setTimeout>;
    const handleResize = () => {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(calculateCanvasDimensions, 100);
    };

    window.addEventListener('resize', handleResize);
    return () => {
      window.removeEventListener('resize', handleResize);
      clearTimeout(timeoutId);
    };
  }, [calculateCanvasDimensions]);

  useEffect(() => {
    if (eventId) {
      loadEventData(eventId);
    }
  }, [eventId]);

  const loadEventData = async (id: string) => {
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
          const parsedNote = parseNotePagesData(noteData);
          setNotePages(parsedNote.pages);
          setNoteCanvasSize(parsedNote.canvasSize);
          setCurrentPageIndex(0);
        } catch (noteErr) {
          console.error('Failed to load note:', noteErr);
          setNote(null);
          setNotePages([]);
          setNoteCanvasSize(null);
        }
      } else {
        setNote(null);
        setNotePages([]);
        setNoteCanvasSize(null);
      }
    } catch (err) {
      console.error('Failed to load event:', err);
      if (axios.isAxiosError(err)) {
        const serverData = err.response?.data as { message?: string; error?: string } | undefined;
        const serverMessage = serverData?.message || serverData?.error;
        setError(serverMessage ?? 'Failed to load event details. Please try again.');
      } else {
        setError('Failed to load event details. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  };

  const formatDateTime = (dateString?: string | null) => {
    const date = parseServerDate(dateString);
    if (!date) {
      return '-';
    }
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
        <div className="card-body loading-state">
          <p>Loading event details...</p>
        </div>
      </div>
    );
  }

  if (error || !event) {
    return (
      <div>
        <div className="card alert-error">
          <div className="card-body">
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
        <p className="page-subtitle">Event ID: {formatShortId(event.id)}</p>
      </div>

      <div className="event-detail-grid">
        {/* Event Information Card */}
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Event Information</h2>
          </div>
          <div className="card-body">
            <div className="detail-fields-grid">
              <div className="detail-field">
                <label className="detail-field-label">Book</label>
                <p className="detail-field-value">
                  {getBookDisplayName(event.bookName, event.bookUuid)}
                </p>
              </div>

              <div className="detail-field">
                <label className="detail-field-label">Patient Name</label>
                <p className="detail-field-value detail-field-value--emphasis">{event.name}</p>
              </div>

              <div className="detail-field">
                <label className="detail-field-label">Record Number</label>
                <p className="detail-field-value detail-field-value--mono">{event.recordNumber || '-'}</p>
              </div>

              <div className="detail-field">
                <label className="detail-field-label">Phone</label>
                <p className="detail-field-value detail-field-value--mono">{event.phone || '-'}</p>
              </div>

              <div className="detail-field">
                <label className="detail-field-label">Event Types</label>
                <div className="detail-badges">
                  {parseEventTypes(event.eventTypes).map((type, index) => (
                    <span key={index} className="badge badge-info">
                      {type}
                    </span>
                  ))}
                </div>
              </div>

              <div className="detail-field">
                <label className="detail-field-label">Start Time</label>
                <p className="detail-field-value">{formatDateTime(event.startTime)}</p>
              </div>

              <div className="detail-field">
                <label className="detail-field-label">End Time</label>
                <p className="detail-field-value">
                  {event.endTime ? formatDateTime(event.endTime) : 'Open-ended'}
                </p>
              </div>

              <div className="detail-field">
                <label className="detail-field-label">Status</label>
                <div className="detail-badges">
                  {event.isRemoved && <span className="badge badge-danger">Removed</span>}
                  {event.isChecked && <span className="badge badge-info">Checked</span>}
                  {!event.isRemoved && !event.isChecked && <span className="badge badge-success">Active</span>}
                </div>
              </div>

              {event.removalReason && (
                <div className="detail-field">
                  <label className="detail-field-label">Removal Reason</label>
                  <p className="detail-field-value">{event.removalReason}</p>
                </div>
              )}

              <div className="detail-meta-section">
                <div className="detail-meta-grid">
                  <div className="detail-meta-item">
                    <span className="detail-meta-label">Created:</span> {formatDateTime(event.createdAt)}
                  </div>
                  <div className="detail-meta-item">
                    <span className="detail-meta-label">Updated:</span> {formatDateTime(event.updatedAt)}
                  </div>
                  <div className="detail-meta-item">
                    <span className="detail-meta-label">Version:</span> {event.version}
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
              <div className="note-empty-state">
                <p>No handwritten notes available</p>
              </div>
            ) : (
              <div>
                {/* Canvas */}
                <div ref={canvasContainerRef} className="canvas-container">
                  <HandwritingCanvas
                    page={notePages[currentPageIndex]}
                    width={canvasDimensions.width}
                    height={canvasDimensions.height}
                    sourceWidth={noteCanvasSize?.width}
                    sourceHeight={noteCanvasSize?.height}
                    className="canvas-responsive"
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
                  <div className="detail-meta-section">
                    <div className="detail-meta-grid">
                      <div className="detail-meta-item">
                        <span className="detail-meta-label">Note ID:</span> {note.id}
                      </div>
                      <div className="detail-meta-item">
                        <span className="detail-meta-label">Last Updated:</span> {formatDateTime(note.updatedAt)}
                      </div>
                      <div className="detail-meta-item">
                        <span className="detail-meta-label">Version:</span> {note.version}
                      </div>
                      <div className="detail-meta-item">
                        <span className="detail-meta-label">Total Pages:</span> {notePages.length}
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
