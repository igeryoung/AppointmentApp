import React from 'react';
import {
  SCHEDULE_START_HOUR,
  SLOTS_PER_HOUR,
  TOTAL_SLOTS,
  TimeSlot,
} from './types';

interface TimeColumnProps {
  slotHeight: number;
}

export const TimeColumn: React.FC<TimeColumnProps> = ({ slotHeight }) => {
  const timeSlots: TimeSlot[] = [];

  for (let index = 0; index < TOTAL_SLOTS; index += 1) {
    const hour = SCHEDULE_START_HOUR + Math.floor(index / SLOTS_PER_HOUR);
    const minute = (index % SLOTS_PER_HOUR) * 15;
    const label = `${hour}:${minute.toString().padStart(2, '0')}`;
    timeSlots.push({ hour, minute, label, slotIndex: index });
  }

  return (
    <div className="time-column">
      {timeSlots.map((slot) => {
        const isHour = slot.minute === 0;
        const isHalfHour = slot.minute === 30;

        return (
          <div
            key={slot.slotIndex}
            className={`time-slot ${isHour ? 'is-hour' : isHalfHour ? 'is-half' : 'is-quarter'}`}
            style={{ height: `${slotHeight}px` }}
          >
            {isHour ? slot.label : isHalfHour ? `${slot.hour}:30` : ''}
          </div>
        );
      })}
    </div>
  );
};
