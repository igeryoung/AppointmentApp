import React from 'react';
import { Event } from '../../types';
import { EventTile } from './EventTile';
import {
  SCHEDULE_START_HOUR,
  MINUTES_PER_SLOT,
  TOTAL_SLOTS,
  PositionedEvent,
  EventWithPosition,
} from './types';

interface BookColumnProps {
  events: Event[];
  slotHeight: number;
  columnWidth: number;
}

// Calculate which slot an event starts in (0-47)
const getStartSlotIndex = (startTime: string): number => {
  const date = new Date(startTime);
  const hour = date.getHours();
  const minute = date.getMinutes();

  if (hour < SCHEDULE_START_HOUR) return 0;
  if (hour >= 21) return TOTAL_SLOTS - 1;

  const slotIndex = (hour - SCHEDULE_START_HOUR) * 4 + Math.floor(minute / MINUTES_PER_SLOT);
  return Math.max(0, Math.min(TOTAL_SLOTS - 1, slotIndex));
};

// Calculate how many slots an event spans
const getSlotsSpanned = (event: Event): number => {
  // Open-ended events (removed or no end time): display as 1 slot (15 min)
  if (event.isRemoved || !event.endTime) {
    return 1;
  }

  const start = new Date(event.startTime);
  const end = new Date(event.endTime);
  const durationMinutes = Math.floor((end.getTime() - start.getTime()) / (1000 * 60));

  // At least 1 slot, at most TOTAL_SLOTS
  const slots = Math.ceil(durationMinutes / MINUTES_PER_SLOT);
  return Math.max(1, Math.min(TOTAL_SLOTS, slots));
};

// Calculate event positions using slot occupancy algorithm
const calculateEventPositions = (
  events: Event[],
  slotHeight: number,
  columnWidth: number
): PositionedEvent[] => {
  if (events.length === 0) return [];

  // Step 1: Convert events to EventWithPosition
  const eventsWithMeta: EventWithPosition[] = events.map((event) => ({
    ...event,
    slotIndex: getStartSlotIndex(event.startTime),
    slotsSpanned: getSlotsSpanned(event),
    horizontalIndex: 0,
    maxConcurrent: 1,
  }));

  // Step 2: Sort by start time (slot index), then by end time descending
  eventsWithMeta.sort((a, b) => {
    if (a.slotIndex !== b.slotIndex) {
      return a.slotIndex - b.slotIndex;
    }
    // If same start, prioritize events with end time (closed-end) over open-end
    const aHasEnd = !a.isRemoved && a.endTime;
    const bHasEnd = !b.isRemoved && b.endTime;
    if (aHasEnd && !bHasEnd) return -1;
    if (!aHasEnd && bHasEnd) return 1;
    return b.slotsSpanned - a.slotsSpanned; // Longer events first
  });

  // Step 3: Build slot occupancy map
  // Map: slot index -> Set of horizontal positions occupied
  const slotOccupancy = new Map<number, Set<number>>();
  for (let i = 0; i < TOTAL_SLOTS; i++) {
    slotOccupancy.set(i, new Set());
  }

  // Step 4: Assign horizontal positions
  for (let i = 0; i < eventsWithMeta.length; i++) {
    const event = eventsWithMeta[i];

    // Find the first available horizontal position across ALL slots this event spans
    let horizontalIndex = 0;
    let positionAvailable = false;

    while (!positionAvailable) {
      positionAvailable = true;

      // Check if this horizontal position is free for ALL slots the event spans
      for (let slot = event.slotIndex; slot < event.slotIndex + event.slotsSpanned; slot++) {
        if (slot >= TOTAL_SLOTS) break;
        const occupied = slotOccupancy.get(slot);
        if (occupied && occupied.has(horizontalIndex)) {
          positionAvailable = false;
          break;
        }
      }

      if (!positionAvailable) {
        horizontalIndex++;
      }
    }

    // Mark this horizontal position as occupied for all slots
    for (let slot = event.slotIndex; slot < event.slotIndex + event.slotsSpanned; slot++) {
      if (slot >= TOTAL_SLOTS) break;
      slotOccupancy.get(slot)!.add(horizontalIndex);
    }

    event.horizontalIndex = horizontalIndex;
  }

  // Step 5: Calculate max concurrent for each event
  for (const event of eventsWithMeta) {
    let maxConcurrent = 1;

    // Check all slots this event spans
    for (let slot = event.slotIndex; slot < event.slotIndex + event.slotsSpanned; slot++) {
      if (slot >= TOTAL_SLOTS) break;
      const occupiedPositions = slotOccupancy.get(slot);
      if (occupiedPositions) {
        maxConcurrent = Math.max(maxConcurrent, occupiedPositions.size);
      }
    }

    event.maxConcurrent = maxConcurrent;
  }

  // Step 6: Convert to PositionedEvent with pixel positions
  return eventsWithMeta.map((event, index) => {
    // Default event width is 1/4 of column width
    const eventWidth = columnWidth / 4;

    return {
      event,
      top: event.slotIndex * slotHeight,
      left: event.horizontalIndex * eventWidth,
      width: eventWidth - 2, // 2px margin between concurrent events
      height: event.slotsSpanned * slotHeight - 1, // 1px margin bottom
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
    <div
      className="book-column"
      style={{
        width: `${columnWidth}px`,
        flexShrink: 0,
        borderRight: '1px solid #e5e7eb',
        position: 'relative',
      }}
    >
      {/* Grid background with slots */}
      <div style={{ position: 'relative', height: `${totalHeight}px` }}>
        {/* Grid lines */}
        {Array.from({ length: TOTAL_SLOTS }).map((_, index) => (
          <div
            key={index}
            style={{
              position: 'absolute',
              top: `${index * slotHeight}px`,
              left: 0,
              right: 0,
              height: `${slotHeight}px`,
              borderBottom: index % 4 === 0 ? '1px solid #d1d5db' : '0.5px solid #e5e7eb',
              backgroundColor: index % 4 === 0 ? '#f9fafb' : 'transparent',
            }}
          />
        ))}

        {/* Events */}
        {positionedEvents.length > 0 ? (
          positionedEvents.map((positionedEvent, index) => (
            <EventTile
              key={`${positionedEvent.event.id}-${index}`}
              positionedEvent={positionedEvent}
              slotHeight={slotHeight}
            />
          ))
        ) : (
          <div
            style={{
              position: 'absolute',
              top: '50%',
              left: '50%',
              transform: 'translate(-50%, -50%)',
              color: '#9ca3af',
              fontSize: '14px',
              textAlign: 'center',
              whiteSpace: 'nowrap',
            }}
          >
            No events
          </div>
        )}
      </div>
    </div>
  );
};
