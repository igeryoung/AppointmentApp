import React, { useEffect, useRef, useState } from 'react';
import { Loader2, Minus, Plus } from 'lucide-react';
import { BookSelector } from '../components/TodaySchedule/BookSelector';
import { ScheduleGrid } from '../components/TodaySchedule/ScheduleGrid';
import { BookWithEvents, TOTAL_SLOTS } from '../components/TodaySchedule/types';
import { Book, Event } from '../types';
import { dashboardAPI } from '../services/api';
import '../styles/today-overview.css';

const SESSION_STORAGE_KEY = 'todayOverview_selectedBooks';
const BASE_COLUMN_WIDTH = 250;
const MIN_SLOT_HEIGHT = 8;
const MIN_ZOOM = 0.6;
const MAX_ZOOM = 2.2;
const ZOOM_STEP = 0.2;

const hasPersistedBookSelection = (): boolean => {
  if (typeof window === 'undefined') {
    return false;
  }

  return sessionStorage.getItem(SESSION_STORAGE_KEY) !== null;
};

const readPersistedBookSelection = (): string[] => {
  if (typeof window === 'undefined') {
    return [];
  }

  const savedSelection = sessionStorage.getItem(SESSION_STORAGE_KEY);
  if (!savedSelection) {
    return [];
  }

  try {
    const parsed = JSON.parse(savedSelection);
    if (Array.isArray(parsed)) {
      return parsed.filter((value): value is string => typeof value === 'string');
    }
  } catch (error) {
    console.error('Failed to parse saved book selection:', error);
  }

  return [];
};

export const TodayOverview: React.FC = () => {
  const [books, setBooks] = useState<Book[]>([]);
  const [selectedBookUuids, setSelectedBookUuids] = useState<string[]>(() => readPersistedBookSelection());
  const [events, setEvents] = useState<Event[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [slotHeight, setSlotHeight] = useState(MIN_SLOT_HEIGHT);
  const [zoomLevel, setZoomLevel] = useState(1);
  const [hadPersistedSelectionOnLoad] = useState<boolean>(() => hasPersistedBookSelection());

  const gridContainerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    sessionStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(selectedBookUuids));
  }, [selectedBookUuids]);

  useEffect(() => {
    const fetchBooks = async () => {
      try {
        const response = await dashboardAPI.getBooks();
        const fetchedBooks = response.books || [];
        const activeBooks = fetchedBooks.filter((book: Book) => !book.archivedAt);
        const availableBookUuids = new Set(activeBooks.map((book: Book) => book.bookUuid));

        setBooks(activeBooks);
        setSelectedBookUuids((previousSelection) => {
          if (hadPersistedSelectionOnLoad) {
            return previousSelection.filter((bookUuid) => availableBookUuids.has(bookUuid));
          }

          if (previousSelection.length === 0) {
            return activeBooks.map((book: Book) => book.bookUuid);
          }

          return previousSelection;
        });
      } catch (fetchError) {
        console.error('Failed to fetch books:', fetchError);
        setError('Failed to load books');
      }
    };

    fetchBooks();
  }, [hadPersistedSelectionOnLoad]);

  useEffect(() => {
    let isCancelled = false;

    const fetchTodayEvents = async () => {
      if (selectedBookUuids.length === 0) {
        setEvents([]);
        setLoading(false);
        return;
      }

      setLoading(true);
      setError(null);

      try {
        const now = new Date();
        const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
        const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0);

        const eventResponses = await Promise.all(
          selectedBookUuids.map((bookUuid) =>
            dashboardAPI.getFilteredEvents({
              bookUuid,
              startDate: startOfDay.toISOString(),
              endDate: endOfDay.toISOString(),
            })
          )
        );

        if (!isCancelled) {
          setEvents(eventResponses.flatMap((response) => response.events || []));
        }
      } catch (fetchError) {
        console.error('Failed to fetch events:', fetchError);
        if (!isCancelled) {
          setError('Failed to load today\'s events');
        }
      } finally {
        if (!isCancelled) {
          setLoading(false);
        }
      }
    };

    fetchTodayEvents();

    return () => {
      isCancelled = true;
    };
  }, [selectedBookUuids]);

  useEffect(() => {
    const calculateSlotHeight = () => {
      if (!gridContainerRef.current) {
        return;
      }

      const containerRect = gridContainerRef.current.getBoundingClientRect();
      const availableHeight = window.innerHeight - containerRect.top - 24;
      const fitSlotHeight = Math.floor(availableHeight / TOTAL_SLOTS);
      const zoomedSlotHeight = Math.floor(fitSlotHeight * zoomLevel);

      setSlotHeight(Math.max(MIN_SLOT_HEIGHT, zoomedSlotHeight));
    };

    const rafId = window.requestAnimationFrame(calculateSlotHeight);
    window.addEventListener('resize', calculateSlotHeight);

    return () => {
      window.cancelAnimationFrame(rafId);
      window.removeEventListener('resize', calculateSlotHeight);
    };
  }, [zoomLevel, books.length, events.length, loading, error]);

  const booksWithEvents: BookWithEvents[] = selectedBookUuids
    .map((bookUuid: string) => {
      const book = books.find((candidate: Book) => candidate.bookUuid === bookUuid);
      if (!book) {
        return null;
      }

      return {
        bookUuid: book.bookUuid,
        bookName: book.name,
        events: events.filter((event: Event) => event.bookUuid === book.bookUuid),
      };
    })
    .filter((item): item is BookWithEvents => item !== null);
  const columnWidth = Math.max(160, Math.round(BASE_COLUMN_WIDTH * zoomLevel));

  const handleZoomOut = () => {
    setZoomLevel((current) => Math.max(MIN_ZOOM, Number((current - ZOOM_STEP).toFixed(1))));
  };

  const handleZoomIn = () => {
    setZoomLevel((current) => Math.min(MAX_ZOOM, Number((current + ZOOM_STEP).toFixed(1))));
  };

  return (
    <div className="today-page today-page--schedule-only">
      <div className="today-page__background" aria-hidden="true" />

      <section ref={gridContainerRef} className="today-schedule-card today-schedule-card--full" aria-busy={loading}>
        <div className="today-schedule-topbar">
          <div className="today-schedule-selector-wrap">
            <BookSelector
              books={books}
              selectedBookUuids={selectedBookUuids}
              onChange={setSelectedBookUuids}
            />
          </div>

          <div className="today-schedule-controls" role="group" aria-label="Schedule zoom controls">
            <button
              type="button"
              className="today-schedule-control-button"
              onClick={handleZoomOut}
              disabled={zoomLevel <= MIN_ZOOM}
              title="Zoom out"
              aria-label="Zoom out"
            >
              <Minus size={16} />
            </button>
            <span className="today-schedule-control-value">{Math.round(zoomLevel * 100)}%</span>
            <button
              type="button"
              className="today-schedule-control-button"
              onClick={handleZoomIn}
              disabled={zoomLevel >= MAX_ZOOM}
              title="Zoom in"
              aria-label="Zoom in"
            >
              <Plus size={16} />
            </button>
          </div>
        </div>

        {loading ? (
          <div className="today-state today-state--loading">
            <Loader2 size={18} className="today-spin" />
            <span>Loading schedule...</span>
          </div>
        ) : error ? (
          <div className="today-state today-state--error">{error}</div>
        ) : (
          <ScheduleGrid
            booksWithEvents={booksWithEvents}
            slotHeight={slotHeight}
            columnWidth={columnWidth}
          />
        )}
      </section>
    </div>
  );
};
