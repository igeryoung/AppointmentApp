import React, { useState, useEffect, useRef } from 'react';
import { Calendar, Loader2 } from 'lucide-react';
import { BookSelector } from '../components/TodaySchedule/BookSelector';
import { ScheduleGrid } from '../components/TodaySchedule/ScheduleGrid';
import { BookWithEvents, TOTAL_SLOTS } from '../components/TodaySchedule/types';
import { Book, Event } from '../types';
import { dashboardAPI } from '../services/api';

const SESSION_STORAGE_KEY = 'todayOverview_selectedBooks';
const COLUMN_WIDTH = 250; // pixels
const HEADER_HEIGHT = 140; // pixels (page header + margins)
const MIN_SLOT_HEIGHT = 12; // minimum pixels per slot

export const TodayOverview: React.FC = () => {
  const [books, setBooks] = useState<Book[]>([]);
  const [selectedBookUuids, setSelectedBookUuids] = useState<string[]>([]);
  const [events, setEvents] = useState<Event[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [slotHeight, setSlotHeight] = useState(MIN_SLOT_HEIGHT);

  const gridContainerRef = useRef<HTMLDivElement>(null);

  // Load selected books from session storage on mount
  useEffect(() => {
    const savedSelection = sessionStorage.getItem(SESSION_STORAGE_KEY);
    if (savedSelection) {
      try {
        const parsed = JSON.parse(savedSelection);
        if (Array.isArray(parsed)) {
          setSelectedBookUuids(parsed);
        }
      } catch (e) {
        console.error('Failed to parse saved book selection:', e);
      }
    }
  }, []);

  // Save selected books to session storage
  useEffect(() => {
    if (selectedBookUuids.length > 0) {
      sessionStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(selectedBookUuids));
    }
  }, [selectedBookUuids]);

  // Fetch books on mount
  useEffect(() => {
    const fetchBooks = async () => {
      try {
        const response = await dashboardAPI.getBooks();
        const fetchedBooks = response.books || [];
        // Filter out archived books
        const activeBooks = fetchedBooks.filter((book: Book) => !book.archivedAt);
        setBooks(activeBooks);

        // If no saved selection, select all books by default
        if (selectedBookUuids.length === 0) {
          setSelectedBookUuids(activeBooks.map((book: Book) => book.bookUuid));
        }
      } catch (err) {
        console.error('Failed to fetch books:', err);
        setError('Failed to load books');
      }
    };

    fetchBooks();
  }, []);

  // Fetch today's events when selected books change
  useEffect(() => {
    const fetchTodayEvents = async () => {
      if (selectedBookUuids.length === 0) {
        setEvents([]);
        setLoading(false);
        return;
      }

      setLoading(true);
      setError(null);

      try {
        // Get today's date range (00:00 to 23:59 in local time)
        const today = new Date();
        const startOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 0, 0, 0);
        const endOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 23, 59, 59);

        // Get selected book names for matching
        const selectedBookNames = books
          .filter((book: Book) => selectedBookUuids.includes(book.bookUuid))
          .map((book: Book) => book.name);

        // Fetch all events
        const response = await dashboardAPI.getFilteredEvents({});
        const allEvents = response.events;

        // Filter for today and selected books
        const todayEvents = allEvents.filter((event) => {
          const eventStart = new Date(event.startTime);

          // Check if event starts today
          const isToday =
            eventStart >= startOfDay &&
            eventStart <= endOfDay;

          // Check if event belongs to selected book (match by book name)
          const isSelectedBook = event.bookName && selectedBookNames.includes(event.bookName);

          return isToday && isSelectedBook;
        });

        setEvents(todayEvents);
      } catch (err) {
        console.error('Failed to fetch events:', err);
        setError('Failed to load today\'s events');
      } finally {
        setLoading(false);
      }
    };

    fetchTodayEvents();
  }, [selectedBookUuids]);

  // Calculate slot height based on available viewport height
  useEffect(() => {
    const calculateSlotHeight = () => {
      const viewportHeight = window.innerHeight;
      const availableHeight = viewportHeight - HEADER_HEIGHT - 40; // 40px for margins
      const calculatedHeight = Math.floor(availableHeight / TOTAL_SLOTS);
      setSlotHeight(Math.max(MIN_SLOT_HEIGHT, calculatedHeight));
    };

    calculateSlotHeight();
    window.addEventListener('resize', calculateSlotHeight);

    return () => {
      window.removeEventListener('resize', calculateSlotHeight);
    };
  }, []);

  // Group events by book
  const booksWithEvents: BookWithEvents[] = selectedBookUuids
    .map((bookUuid: string) => {
      const book = books.find((b: Book) => b.bookUuid === bookUuid);
      if (!book) return null;

      const bookEvents = events.filter(
        (event: Event) => event.bookName === book.name
      );

      return {
        bookUuid: book.bookUuid,
        bookName: book.name,
        events: bookEvents,
      };
    })
    .filter((item): item is BookWithEvents => item !== null);

  // Get today's date string
  const today = new Date();
  const dateString = today.toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });

  return (
    <div style={{ padding: '24px', height: '100vh', display: 'flex', flexDirection: 'column' }}>
      {/* Header */}
      <div style={{ marginBottom: '24px', flexShrink: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '8px' }}>
          <Calendar size={28} color="#3b82f6" />
          <h1 style={{ fontSize: '24px', fontWeight: 700, color: '#1e293b', margin: 0 }}>
            Today's Schedule
          </h1>
        </div>
        <p style={{ fontSize: '14px', color: '#64748b', margin: 0 }}>
          {dateString}
        </p>
      </div>

      {/* Book Selector */}
      <div style={{ marginBottom: '20px', flexShrink: 0 }}>
        <BookSelector
          books={books}
          selectedBookUuids={selectedBookUuids}
          onChange={setSelectedBookUuids}
        />
      </div>

      {/* Schedule Grid - Fixed width container with constrained overflow */}
      <div
        ref={gridContainerRef}
        style={{
          flex: 1,
          minHeight: 0,
          width: '100%',
          maxWidth: 'calc(100vw - 280px - 48px)', // viewport - sidebar - padding
          overflow: 'hidden', // Prevent container from expanding horizontally
          border: '1px solid #e5e7eb',
          borderRadius: '8px',
          backgroundColor: 'white',
          boxShadow: '0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06)',
        }}
      >
        {loading ? (
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              height: '100%',
              gap: '12px',
              color: '#64748b',
            }}
          >
            <Loader2 size={24} className="animate-spin" />
            <span>Loading schedule...</span>
          </div>
        ) : error ? (
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              height: '100%',
              color: '#ef4444',
              fontSize: '14px',
            }}
          >
            {error}
          </div>
        ) : (
          <ScheduleGrid
            booksWithEvents={booksWithEvents}
            slotHeight={slotHeight}
            columnWidth={COLUMN_WIDTH}
          />
        )}
      </div>
    </div>
  );
};
