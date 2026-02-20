import React, { useEffect, useRef } from 'react';
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
  const headerScrollRef = useRef<HTMLDivElement>(null);
  const bodyBookScrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const headerScroll = headerScrollRef.current;
    const bodyBookScroll = bodyBookScrollRef.current;

    if (!headerScroll || !bodyBookScroll) {
      return;
    }

    const syncHeaderHorizontal = () => {
      if (bodyBookScroll.scrollLeft !== headerScroll.scrollLeft) {
        bodyBookScroll.scrollLeft = headerScroll.scrollLeft;
      }
    };

    const syncBodyHorizontal = () => {
      if (headerScroll.scrollLeft !== bodyBookScroll.scrollLeft) {
        headerScroll.scrollLeft = bodyBookScroll.scrollLeft;
      }
    };

    headerScroll.addEventListener('scroll', syncHeaderHorizontal);
    bodyBookScroll.addEventListener('scroll', syncBodyHorizontal);

    return () => {
      headerScroll.removeEventListener('scroll', syncHeaderHorizontal);
      bodyBookScroll.removeEventListener('scroll', syncBodyHorizontal);
    };
  }, []);

  return (
    <div className="schedule-grid">
      <div className="schedule-grid__header-row">
        <div className="schedule-grid__time-header">Time</div>

        <div ref={headerScrollRef} className="schedule-grid__book-headers">
          {booksWithEvents.length === 0 ? (
            <div className="schedule-grid__headers-empty">No books</div>
          ) : (
            booksWithEvents.map((bookData) => (
              <div
                key={`header-${bookData.bookUuid}`}
                className="schedule-grid__book-header"
                style={{ width: `${columnWidth}px` }}
                title={bookData.bookName}
              >
                {bookData.bookName}
              </div>
            ))
          )}
        </div>
      </div>

      <div className="schedule-grid__body-viewport">
        <div className="schedule-grid__body-row">
          <div className="schedule-grid__time-column-wrap">
            <TimeColumn slotHeight={slotHeight} />
          </div>

          <div ref={bodyBookScrollRef} className="schedule-grid__book-columns">
            {booksWithEvents.length === 0 ? (
              <div className="schedule-grid__empty-state">
                <h3>No books selected</h3>
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
    </div>
  );
};
