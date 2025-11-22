import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
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
          // Note might not exist even though hasNote is true
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
      // Try pages_data first (multi-page format)
      if (noteData.pagesData) {
        return JSON.parse(noteData.pagesData);
      }

      // Fallback to strokes_data (legacy single-page format)
      if (noteData.strokesData) {
        const strokes = JSON.parse(noteData.strokesData);
        return [strokes]; // Wrap in array to make it a single-page note
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
      <div className="flex justify-center items-center h-screen">
        <div className="text-gray-500 text-xl">Loading event details...</div>
      </div>
    );
  }

  if (error || !event) {
    return (
      <div className="p-6 max-w-7xl mx-auto">
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
          {error || 'Event not found'}
        </div>
        <button
          onClick={() => navigate('/events')}
          className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
        >
          ← Back to Events List
        </button>
      </div>
    );
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="mb-6">
        <button
          onClick={() => navigate('/events')}
          className="mb-4 text-blue-600 hover:text-blue-800 font-medium"
        >
          ← Back to Events List
        </button>
        <h1 className="text-3xl font-bold text-gray-900">Event Details</h1>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Event Information */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h2 className="text-xl font-semibold text-gray-800 mb-4">Event Information</h2>

          <div className="space-y-3">
            <div>
              <label className="text-sm font-medium text-gray-500">ID</label>
              <p className="text-gray-900">{event.id}</p>
            </div>

            <div>
              <label className="text-sm font-medium text-gray-500">Book</label>
              <p className="text-gray-900">{event.bookName || `Book ${event.bookId}`}</p>
            </div>

            <div>
              <label className="text-sm font-medium text-gray-500">Patient Name</label>
              <p className="text-gray-900 font-medium">{event.name}</p>
            </div>

            <div>
              <label className="text-sm font-medium text-gray-500">Record Number</label>
              <p className="text-gray-900">{event.recordNumber || '-'}</p>
            </div>

            <div>
              <label className="text-sm font-medium text-gray-500">Event Types</label>
              <div className="flex flex-wrap gap-2 mt-1">
                {parseEventTypes(event.eventTypes).map((type, index) => (
                  <span
                    key={index}
                    className="px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 rounded"
                  >
                    {type}
                  </span>
                ))}
              </div>
            </div>

            <div>
              <label className="text-sm font-medium text-gray-500">Start Time</label>
              <p className="text-gray-900">{formatDateTime(event.startTime)}</p>
            </div>

            <div>
              <label className="text-sm font-medium text-gray-500">End Time</label>
              <p className="text-gray-900">
                {event.endTime ? formatDateTime(event.endTime) : 'Open-ended'}
              </p>
            </div>

            <div>
              <label className="text-sm font-medium text-gray-500">Status</label>
              <div className="flex gap-2 mt-1">
                {event.isRemoved && (
                  <span className="px-2 py-1 text-xs font-medium bg-red-100 text-red-800 rounded">
                    Removed
                  </span>
                )}
                {event.isChecked && (
                  <span className="px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 rounded">
                    Checked
                  </span>
                )}
                {!event.isRemoved && !event.isChecked && (
                  <span className="px-2 py-1 text-xs font-medium bg-green-100 text-green-800 rounded">
                    Active
                  </span>
                )}
              </div>
            </div>

            {event.removalReason && (
              <div>
                <label className="text-sm font-medium text-gray-500">Removal Reason</label>
                <p className="text-gray-900">{event.removalReason}</p>
              </div>
            )}

            <div className="border-t pt-3 mt-3">
              <label className="text-sm font-medium text-gray-500">Created At</label>
              <p className="text-gray-900 text-sm">{formatDateTime(event.createdAt)}</p>
            </div>

            <div>
              <label className="text-sm font-medium text-gray-500">Updated At</label>
              <p className="text-gray-900 text-sm">{formatDateTime(event.updatedAt)}</p>
            </div>
          </div>
        </div>

        {/* Handwriting Notes */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h2 className="text-xl font-semibold text-gray-800 mb-4">Handwriting Notes</h2>

          {!event.hasNote || notePages.length === 0 ? (
            <div className="flex items-center justify-center h-64 bg-gray-50 rounded border border-gray-200">
              <p className="text-gray-500">No handwritten notes available</p>
            </div>
          ) : (
            <div className="space-y-4">
              {/* Canvas */}
              <div className="flex justify-center">
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
                <div className="border-t pt-3 mt-3 text-sm text-gray-500">
                  <p>Note ID: {note.id}</p>
                  <p>Last Updated: {formatDateTime(note.updatedAt)}</p>
                  <p>Version: {note.version}</p>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
