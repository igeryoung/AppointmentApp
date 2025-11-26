import React, { useRef, useEffect } from 'react';
import { TimeColumn } from './TimeColumn';
import { BookColumn } from './BookColumn';
import { BookWithEvents } from './types';

interface ScheduleGridProps {
  booksWithEvents: BookWithEvents[];
  slotHeight: number;
  columnWidth: number;
}

export const ScheduleGrid: React.FC<ScheduleGridProps> = ({
  booksWithEvents,
  slotHeight,
  columnWidth,
}) => {
  // Book header height matches BookColumn header
  const bookHeaderHeight = 44; // 12px padding top + 12px padding bottom + ~20px text height

  // Refs for scroll sync
  const headerScrollRef = useRef<HTMLDivElement>(null);
  const bodyScrollRef = useRef<HTMLDivElement>(null);

  // Sync scroll between header and body
  useEffect(() => {
    const headerScroll = headerScrollRef.current;
    const bodyScroll = bodyScrollRef.current;

    if (!headerScroll || !bodyScroll) return;

    const syncHeaderScroll = () => {
      if (bodyScroll && headerScroll.scrollLeft !== bodyScroll.scrollLeft) {
        bodyScroll.scrollLeft = headerScroll.scrollLeft;
      }
    };

    const syncBodyScroll = () => {
      if (headerScroll && bodyScroll.scrollLeft !== headerScroll.scrollLeft) {
        headerScroll.scrollLeft = bodyScroll.scrollLeft;
      }
    };

    headerScroll.addEventListener('scroll', syncHeaderScroll);
    bodyScroll.addEventListener('scroll', syncBodyScroll);

    return () => {
      headerScroll.removeEventListener('scroll', syncHeaderScroll);
      bodyScroll.removeEventListener('scroll', syncBodyScroll);
    };
  }, []);

  return (
    <div
      className="schedule-grid-container"
      style={{
        display: 'flex',
        flexDirection: 'column',
        height: '100%',
      }}
    >
      {/* Header row - aligns time column placeholder with book headers */}
      <div style={{ display: 'flex', flexShrink: 0 }}>
        {/* Placeholder header for time column - sticky */}
        <div
          style={{
            width: '60px',
            height: `${bookHeaderHeight}px`,
            borderRight: '1px solid #e5e7eb',
            borderBottom: '2px solid #e5e7eb',
            backgroundColor: '#f8fafc',
            flexShrink: 0,
            position: 'sticky',
            left: 0,
            zIndex: 20,
          }}
        />

        {/* Book headers container - scrollable */}
        <div
          ref={headerScrollRef}
          style={{
            display: 'flex',
            flex: 1,
            overflowX: 'auto',
            overflowY: 'hidden',
            scrollbarWidth: 'none', // Hide scrollbar on header
            msOverflowStyle: 'none', // Hide scrollbar on IE
          }}
        >
          {booksWithEvents.length === 0 ? (
            <div
              style={{
                flex: 1,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                padding: '12px',
                color: '#9ca3af',
                fontSize: '14px',
                borderBottom: '2px solid #e5e7eb',
                backgroundColor: '#f8fafc',
              }}
            >
              No books selected
            </div>
          ) : (
            booksWithEvents.map((bookData) => (
              <div
                key={`header-${bookData.bookUuid}`}
                style={{
                  width: `${columnWidth}px`,
                  flexShrink: 0,
                  borderRight: '1px solid #e5e7eb',
                  borderBottom: '2px solid #3b82f6',
                  padding: '12px 8px',
                  textAlign: 'center',
                  fontWeight: 600,
                  fontSize: '14px',
                  color: '#1e293b',
                  backgroundColor: '#f8fafc',
                }}
              >
                {bookData.bookName}
              </div>
            ))
          )}
        </div>
      </div>

      {/* Schedule body - time column + book columns */}
      <div style={{ display: 'flex', flex: 1, minHeight: 0, overflow: 'hidden' }}>
        {/* Time column - sticky on left */}
        <div
          style={{
            position: 'sticky',
            left: 0,
            zIndex: 10,
            backgroundColor: 'white',
            flexShrink: 0,
          }}
        >
          <TimeColumn slotHeight={slotHeight} />
        </div>

        {/* Book columns - horizontal scrollable */}
        <div
          ref={bodyScrollRef}
          className="book-columns-scroll"
          style={{
            display: 'flex',
            overflowX: 'auto',
            overflowY: 'hidden',
            flex: 1,
            scrollbarWidth: 'thin',
            scrollbarColor: '#cbd5e1 #f1f5f9',
          }}
        >
          {booksWithEvents.length === 0 ? (
            <div
              style={{
                flex: 1,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                padding: '48px',
                color: '#9ca3af',
                fontSize: '14px',
                textAlign: 'center',
              }}
            >
              <div>
                <div style={{ fontSize: '16px', fontWeight: 500, marginBottom: '8px' }}>
                  No events today
                </div>
                <div style={{ fontSize: '14px' }}>
                  Select books from the dropdown above to view their schedules
                </div>
              </div>
            </div>
          ) : (
            booksWithEvents.map((bookData) => (
              <BookColumn
                key={bookData.bookUuid}
                events={bookData.events}
                slotHeight={slotHeight}
                columnWidth={columnWidth}
              />
            ))
          )}
        </div>
      </div>
    </div>
  );
};
