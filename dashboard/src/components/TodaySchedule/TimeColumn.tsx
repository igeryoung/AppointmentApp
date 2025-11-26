import React from 'react';
import {
  SCHEDULE_START_HOUR,
  SLOTS_PER_HOUR,
  TOTAL_SLOTS,
  TimeSlot
} from './types';

interface TimeColumnProps {
  slotHeight: number;
}

export const TimeColumn: React.FC<TimeColumnProps> = ({ slotHeight }) => {
  // Generate time slots
  const timeSlots: TimeSlot[] = [];
  for (let i = 0; i < TOTAL_SLOTS; i++) {
    const hour = SCHEDULE_START_HOUR + Math.floor(i / SLOTS_PER_HOUR);
    const minute = (i % SLOTS_PER_HOUR) * 15;
    const label = `${hour}:${minute.toString().padStart(2, '0')}`;
    timeSlots.push({ hour, minute, label, slotIndex: i });
  }

  return (
    <div
      className="time-column"
      style={{
        width: '60px',
        flexShrink: 0,
        borderRight: '1px solid #e5e7eb',
      }}
    >
      {timeSlots.map((slot) => (
        <div
          key={slot.slotIndex}
          className="time-slot"
          style={{
            height: `${slotHeight}px`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: '12px',
            color: '#6b7280',
            borderBottom: '0.5px solid #e5e7eb',
            backgroundColor: slot.minute === 0 ? '#f9fafb' : 'transparent',
            fontWeight: slot.minute === 0 ? 600 : 400,
          }}
        >
          {slot.label}
        </div>
      ))}
    </div>
  );
};
