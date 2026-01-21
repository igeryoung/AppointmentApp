import React, { useEffect, useState } from 'react';
import axios from 'axios';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import { EventsTable, HandwritingCanvas, PageNavigation } from '../components';
import type { Event, Note, NotePages, RecordSummary } from '../types';
import { dashboardAPI } from '../services/api';
import { parseServerDate } from '../utils/date';
import { formatShortId } from '../utils/id';
import { parseNotePagesData } from '../utils/handwriting';

export const RecordDetail: React.FC = () => {
  const { recordUuid } = useParams<{ recordUuid: string }>();
  const navigate = useNavigate();

  const [record, setRecord] = useState<RecordSummary | null>(null);
  const [events, setEvents] = useState<Event[]>([]);
  const [note, setNote] = useState<Note | null>(null);
  const [notePages, setNotePages] = useState<NotePages>([]);
  const [noteCanvasSize, setNoteCanvasSize] = useState<{ width: number; height: number } | null>(null);
  const [currentPageIndex, setCurrentPageIndex] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (recordUuid) {
      loadRecordData(recordUuid);
    }
  }, [recordUuid]);

  const loadRecordData = async (id: string) => {
    try {
      setLoading(true);
      setError(null);

      const data = await dashboardAPI.getRecordDetail(id);
      setRecord(data.record);
      setEvents(data.events);

      if (data.note) {
        setNote(data.note);
        const parsedNote = parseNotePagesData(data.note);
        setNotePages(parsedNote.pages);
        setNoteCanvasSize(parsedNote.canvasSize);
        setCurrentPageIndex(0);
      } else {
        setNote(null);
        setNotePages([]);
        setNoteCanvasSize(null);
      }
    } catch (err) {
      console.error('Failed to load record:', err);
      if (axios.isAxiosError(err)) {
        const serverData = err.response?.data as { message?: string; error?: string } | undefined;
        const serverMessage = serverData?.message || serverData?.error;
        setError(serverMessage ?? 'Failed to load record details. Please try again.');
      } else {
        setError('Failed to load record details. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  };

  const formatDateTime = (value?: string | null) => {
    const date = parseServerDate(value);
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

  const getRecordInitials = (fullName?: string | null) => {
    const cleaned = (fullName ?? '').trim();
    if (!cleaned) return 'NA';
    const parts = cleaned.split(/\s+/).filter(Boolean);
    const initials = parts.slice(0, 2).map((part) => part[0]?.toUpperCase() ?? '').join('');
    return initials || 'NA';
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
          <p style={{ color: '#6b7280', fontSize: '1.125rem' }}>Loading record details...</p>
        </div>
      </div>
    );
  }

  if (error || !record) {
    return (
      <div>
        <div className="card" style={{ marginBottom: '1.5rem', backgroundColor: '#fef2f2', borderLeft: '4px solid #ef4444' }}>
          <div className="card-body" style={{ color: '#dc2626' }}>
            {error || 'Record not found'}
          </div>
        </div>
        <button onClick={() => navigate('/records')} className="btn btn-secondary">
          <ArrowLeft size={16} />
          Back to Records
        </button>
      </div>
    );
  }

  const recordInitials = getRecordInitials(record.name);
  const recordName = record.name?.trim() ? record.name : 'Unknown Patient';

  return (
    <div className="record-detail">
      <div className="page-header record-header">
        <div className="record-header-main">
          <button
            onClick={() => navigate('/records')}
            className="btn btn-secondary btn-sm"
          >
            <ArrowLeft size={16} />
            Back to Records
          </button>
          <div className="record-header-title">
            <h1 className="page-title">Record Details</h1>
            <p className="page-subtitle">
              Record ID: <span className="record-id">{formatShortId(record.recordUuid)}</span>
            </p>
          </div>
        </div>
        <div className="record-header-actions">
          <span className="badge badge-info">{record.eventCount} Events</span>
          <span className={`badge ${record.hasNote ? 'badge-success' : 'badge-warning'}`}>
            {record.hasNote ? 'Notes Available' : 'No Notes'}
          </span>
        </div>
      </div>

      <div className="card">
        <div className="card-body record-summary-body">
          <div className="record-summary-main">
            <div className="record-avatar">{recordInitials}</div>
            <div>
              <p className="record-eyebrow">Patient</p>
              <h2 className="record-name">{recordName}</h2>
              <dl className="record-identity-grid">
                <div>
                  <dt>Record Number</dt>
                  <dd className="record-meta-mono">{record.recordNumber || '-'}</dd>
                </div>
                <div>
                  <dt>Phone</dt>
                  <dd className="record-meta-mono">{record.phone || '-'}</dd>
                </div>
              </dl>
            </div>
          </div>

          <div className="record-summary-aside">
            <div className="record-stat-grid">
              <div className="record-stat">
                <span className="record-stat-value">{record.eventCount}</span>
                <span className="record-stat-label">Events</span>
              </div>
              <div className="record-stat">
                <span
                  className={`record-note-indicator ${record.hasNote ? 'is-available' : 'is-missing'}`}
                >
                  {record.hasNote ? 'Available' : 'None'}
                </span>
                <span className="record-stat-label">Notes</span>
              </div>
            </div>
            <dl className="record-meta-list">
              <div>
                <dt>Created</dt>
                <dd>{formatDateTime(record.createdAt)}</dd>
              </div>
              <div>
                <dt>Updated</dt>
                <dd>{formatDateTime(record.updatedAt)}</dd>
              </div>
            </dl>
          </div>
        </div>
      </div>

      <EventsTable
        events={events}
        title="Record Events"
        emptyMessage="No events found for this record"
      />

      <div className="card">
        <div className="card-header">
          <h2 className="card-title">Handwriting Notes</h2>
          {record.hasNote && notePages.length > 0 && (
            <span className="badge badge-info">{notePages.length} Pages</span>
          )}
        </div>
        <div className="card-body">
          {!record.hasNote || notePages.length === 0 ? (
            <div className="record-note-empty">
              <p>No handwritten notes available</p>
            </div>
          ) : (
            <div>
              <div className="record-note-preview">
                <HandwritingCanvas
                  page={notePages[currentPageIndex]}
                  width={600}
                  height={800}
                  className="record-note-canvas"
                  sourceWidth={noteCanvasSize?.width}
                  sourceHeight={noteCanvasSize?.height}
                />
              </div>

              {notePages.length > 1 && (
                <PageNavigation
                  currentPage={currentPageIndex}
                  totalPages={notePages.length}
                  onPrevious={handlePreviousPage}
                  onNext={handleNextPage}
                />
              )}

              {note && (
                <dl className="record-note-meta">
                  <div>
                    <dt>Note ID</dt>
                    <dd>{note.id}</dd>
                  </div>
                  <div>
                    <dt>Last Updated</dt>
                    <dd>{formatDateTime(note.updatedAt)}</dd>
                  </div>
                  <div>
                    <dt>Version</dt>
                    <dd>{note.version}</dd>
                  </div>
                  <div>
                    <dt>Total Pages</dt>
                    <dd>{notePages.length}</dd>
                  </div>
                </dl>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
