import React from 'react';
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
        {/* Placeholder header for time column - maintains alignment */}
        <div
          style={{
            width: '60px',
            height: `${bookHeaderHeight}px`,
            borderRight: '1px solid #e5e7eb',
            borderBottom: '2px solid #e5e7eb',
            backgroundColor: '#f8fafc',
            flexShrink: 0,
          }}
        />

        {/* Book headers container */}
        <div
          style={{
            display: 'flex',
            flex: 1,
            overflowX: 'auto',
            overflowY: 'hidden',
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
      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        {/* Time column (fixed on left) */}
        <TimeColumn slotHeight={slotHeight} />

        {/* Book columns (horizontal scrollable) */}
        <div
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
