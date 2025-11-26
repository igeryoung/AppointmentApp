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
  return (
    <div
      className="schedule-grid-container"
      style={{
        display: 'flex',
        border: '1px solid #e5e7eb',
        borderRadius: '8px',
        overflow: 'hidden',
        backgroundColor: 'white',
        boxShadow: '0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06)',
      }}
    >
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
                No books selected
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
              bookName={bookData.bookName}
              events={bookData.events}
              slotHeight={slotHeight}
              columnWidth={columnWidth}
            />
          ))
        )}
      </div>
    </div>
  );
};
