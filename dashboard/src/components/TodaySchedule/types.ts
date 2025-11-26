import { Event } from '../../types';

// Time grid constants (matching mobile app)
export const SCHEDULE_START_HOUR = 9;
export const SCHEDULE_END_HOUR = 21;
export const MINUTES_PER_SLOT = 15;
export const SLOTS_PER_HOUR = 60 / MINUTES_PER_SLOT;
export const TOTAL_SLOTS = (SCHEDULE_END_HOUR - SCHEDULE_START_HOUR) * SLOTS_PER_HOUR; // 48 slots

// Positioned event data after layout calculation
export interface PositionedEvent {
  event: Event;
  top: number;        // pixels from top
  left: number;       // pixels from left (within column)
  width: number;      // pixels wide
  height: number;     // pixels tall
  zIndex: number;     // stacking order
}

// Event with positioning metadata
export interface EventWithPosition extends Event {
  slotIndex: number;      // Starting slot (0-47)
  slotsSpanned: number;   // Number of 15-min slots
  horizontalIndex: number; // Position in overlapping group (0, 1, 2...)
  maxConcurrent: number;   // Max concurrent events in this event's time range
}

// Time slot info
export interface TimeSlot {
  hour: number;
  minute: number;
  label: string;        // e.g., "9:00", "9:15"
  slotIndex: number;    // 0-47
}

// Book with today's events
export interface BookWithEvents {
  bookUuid: string;
  bookName: string;
  events: Event[];
}
