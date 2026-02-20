import React from 'react';
import { Event } from '../../types';
import { EventTile } from './EventTile';
import {
  SCHEDULE_START_HOUR,
  SCHEDULE_END_HOUR,
  MINUTES_PER_SLOT,
  TOTAL_SLOTS,
  PositionedEvent,
  EventWithPosition,
} from './types';
import { parseServerDate } from '../../utils/date';

interface BookColumnProps {
  events: Event[];
  slotHeight: number;
  columnWidth: number;
}

const getStartSlotIndex = (startTime: string): number => {
  const date = parseServerDate(startTime);
  if (!date) {
    return 0;
  }

  const hour = date.getHours();
  const minute = date.getMinutes();

  if (hour < SCHEDULE_START_HOUR) {
    return 0;
  }

  if (hour >= SCHEDULE_END_HOUR) {
    return TOTAL_SLOTS - 1;
  }

  const slotIndex = (hour - SCHEDULE_START_HOUR) * 4 + Math.floor(minute / MINUTES_PER_SLOT);
  return Math.max(0, Math.min(TOTAL_SLOTS - 1, slotIndex));
};

const getSlotsSpanned = (event: Event): number => {
  if (event.isRemoved || !event.endTime) {
    return 1;
  }

  const start = parseServerDate(event.startTime);
  const end = parseServerDate(event.endTime);

  if (!start || !end) {
    return 1;
  }

  const durationMinutes = Math.floor((end.getTime() - start.getTime()) / (1000 * 60));
  const slots = Math.ceil(durationMinutes / MINUTES_PER_SLOT);

  return Math.max(1, Math.min(TOTAL_SLOTS, slots));
};

const calculateEventPositions = (
  events: Event[],
  slotHeight: number,
  columnWidth: number
): PositionedEvent[] => {
  if (events.length === 0) {
    return [];
  }

  const eventsWithMeta: EventWithPosition[] = events.map((event) => ({
    ...event,
    slotIndex: getStartSlotIndex(event.startTime),
    slotsSpanned: getSlotsSpanned(event),
    horizontalIndex: 0,
    maxConcurrent: 1,
  }));

  eventsWithMeta.sort((left, right) => {
    if (left.slotIndex !== right.slotIndex) {
      return left.slotIndex - right.slotIndex;
    }

    const leftHasEnd = !left.isRemoved && left.endTime;
    const rightHasEnd = !right.isRemoved && right.endTime;

    if (leftHasEnd && !rightHasEnd) {
      return -1;
    }

    if (!leftHasEnd && rightHasEnd) {
      return 1;
    }

    return right.slotsSpanned - left.slotsSpanned;
  });

  const slotOccupancy = new Map<number, Set<number>>();
  for (let index = 0; index < TOTAL_SLOTS; index += 1) {
    slotOccupancy.set(index, new Set());
  }

  for (let eventIndex = 0; eventIndex < eventsWithMeta.length; eventIndex += 1) {
    const event = eventsWithMeta[eventIndex];

    let horizontalIndex = 0;
    let positionAvailable = false;

    while (!positionAvailable) {
      positionAvailable = true;

      for (let slot = event.slotIndex; slot < event.slotIndex + event.slotsSpanned; slot += 1) {
        if (slot >= TOTAL_SLOTS) {
          break;
        }

        const occupied = slotOccupancy.get(slot);
        if (occupied && occupied.has(horizontalIndex)) {
          positionAvailable = false;
          break;
        }
      }

      if (!positionAvailable) {
        horizontalIndex += 1;
      }
    }

    for (let slot = event.slotIndex; slot < event.slotIndex + event.slotsSpanned; slot += 1) {
      if (slot >= TOTAL_SLOTS) {
        break;
      }

      slotOccupancy.get(slot)!.add(horizontalIndex);
    }

    event.horizontalIndex = horizontalIndex;
  }

  for (const event of eventsWithMeta) {
    let maxConcurrent = 1;

    for (let slot = event.slotIndex; slot < event.slotIndex + event.slotsSpanned; slot += 1) {
      if (slot >= TOTAL_SLOTS) {
        break;
      }

      const occupiedPositions = slotOccupancy.get(slot);
      if (occupiedPositions) {
        maxConcurrent = Math.max(maxConcurrent, occupiedPositions.size);
      }
    }

    event.maxConcurrent = maxConcurrent;
  }

  return eventsWithMeta.map((event, index) => {
    const laneCount = Math.max(1, event.maxConcurrent);
    const eventWidth = columnWidth / laneCount;

    return {
      event,
      top: event.slotIndex * slotHeight,
      left: event.horizontalIndex * eventWidth,
      width: eventWidth - 3,
      height: event.slotsSpanned * slotHeight - 1,
      zIndex: 10 + index,
    };
  });
};

export const BookColumn: React.FC<BookColumnProps> = ({
  events,
  slotHeight,
  columnWidth,
}) => {
  const positionedEvents = calculateEventPositions(events, slotHeight, columnWidth);
  const totalHeight = TOTAL_SLOTS * slotHeight;

  return (
    <div className="book-column" style={{ width: `${columnWidth}px` }}>
      <div className="book-column__grid" style={{ height: `${totalHeight}px` }}>
        {Array.from({ length: TOTAL_SLOTS }).map((_, index) => (
          <div
            key={index}
            className={`book-column__slot ${index % 4 === 0 ? 'is-hour' : 'is-quarter'}`}
            style={{ top: `${index * slotHeight}px`, height: `${slotHeight}px` }}
          />
        ))}

        {positionedEvents.length > 0 ? (
          positionedEvents.map((positionedEvent, index) => (
            <EventTile
              key={`${positionedEvent.event.id}-${index}`}
              positionedEvent={positionedEvent}
              slotHeight={slotHeight}
            />
          ))
        ) : (
          <div className="book-column__empty">No events</div>
        )}
      </div>
    </div>
  );
};
