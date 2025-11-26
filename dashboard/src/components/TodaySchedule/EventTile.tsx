import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Check, FileText } from 'lucide-react';
import { PositionedEvent } from './types';

interface EventTileProps {
  positionedEvent: PositionedEvent;
  slotHeight: number;
}

// Event type color mapping (matching mobile app)
const EVENT_TYPE_COLORS: Record<string, string> = {
  '初診': '#FF6B6B',
  '複診': '#4ECDC4',
  '急診': '#FFD93D',
  '手術': '#A8E6CF',
  '檢查': '#95B8D1',
  '其他': '#B8B8D8',
};

const getEventTypeColor = (eventType: string): string => {
  return EVENT_TYPE_COLORS[eventType] || '#94A3B8';
};

export const EventTile: React.FC<EventTileProps> = ({ positionedEvent, slotHeight }) => {
  const navigate = useNavigate();
  const { event, top, left, width, height, zIndex } = positionedEvent;

  // Parse event types
  let eventTypes: string[] = [];
  try {
    eventTypes = JSON.parse(event.eventTypes || '[]');
  } catch {
    if (event.eventType) {
      eventTypes = [event.eventType];
    }
  }

  // Get colors (max 2, sorted alphabetically)
  const sortedTypes = [...eventTypes].sort();
  const colors = sortedTypes.slice(0, 2).map(getEventTypeColor);

  // Background rendering
  const renderBackground = () => {
    if (colors.length === 0) {
      return <div style={{ width: '100%', height: '100%', backgroundColor: '#94A3B8', opacity: 0.7 }} />;
    }

    if (colors.length === 1) {
      return <div style={{ width: '100%', height: '100%', backgroundColor: colors[0], opacity: 0.7 }} />;
    }

    // Two colors: split vertically
    return (
      <div style={{ display: 'flex', width: '100%', height: '100%' }}>
        <div style={{ width: '50%', backgroundColor: colors[0], opacity: 0.7 }} />
        <div style={{ width: '50%', backgroundColor: colors[1], opacity: 0.7 }} />
      </div>
    );
  };

  const handleClick = () => {
    navigate(`/events/${event.id}`);
  };

  const fontSize = Math.max(slotHeight * 0.5, 10); // Min 10px
  const smallFontSize = Math.max(slotHeight * 0.3, 8); // Min 8px
  const iconSize = Math.max(slotHeight * 0.6, 12); // Min 12px

  return (
    <div
      onClick={handleClick}
      style={{
        position: 'absolute',
        top: `${top}px`,
        left: `${left}px`,
        width: `${width}px`,
        height: `${height}px`,
        zIndex,
        cursor: 'pointer',
        margin: '0 1px 1px 1px',
      }}
    >
      <div
        style={{
          width: '100%',
          height: '100%',
          borderRadius: '2px',
          overflow: 'hidden',
          border: event.isRemoved ? '1px dashed #ef4444' : 'none',
          position: 'relative',
          transition: 'transform 0.1s ease, box-shadow 0.1s ease',
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.transform = 'scale(1.02)';
          e.currentTarget.style.boxShadow = '0 2px 8px rgba(0,0,0,0.15)';
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.transform = 'scale(1)';
          e.currentTarget.style.boxShadow = 'none';
        }}
      >
        {/* Background layer */}
        <div style={{ position: 'absolute', inset: 0 }}>
          {renderBackground()}
        </div>

        {/* Content layer */}
        <div
          style={{
            position: 'relative',
            padding: `${slotHeight * 0.15}px 4px 2px ${event.hasNote ? '0' : '4px'}`,
            height: '100%',
            overflow: 'hidden',
          }}
        >
          {/* Note indicator (left bar) */}
          {event.hasNote && (
            <div
              style={{
                position: 'absolute',
                left: 0,
                top: 0,
                bottom: 0,
                width: '4px',
                backgroundColor: '#1e293b',
                opacity: 0.6,
              }}
            />
          )}

          {/* Patient name and record number */}
          <div
            style={{
              fontSize: `${fontSize}px`,
              fontWeight: 500,
              color: '#1e293b',
              lineHeight: 1.2,
              wordBreak: 'break-word',
              marginLeft: event.hasNote ? '6px' : '0',
            }}
          >
            {event.name}
            {event.recordNumber && (
              <span style={{ fontSize: `${smallFontSize}px`, color: '#475569', marginLeft: '2px' }}>
                ({event.recordNumber})
              </span>
            )}
          </div>

          {/* Status indicators (top right) */}
          <div
            style={{
              position: 'absolute',
              top: '2px',
              right: '4px',
              display: 'flex',
              gap: '2px',
              alignItems: 'center',
            }}
          >
            {event.isChecked && (
              <div
                style={{
                  backgroundColor: '#10b981',
                  borderRadius: '50%',
                  padding: '2px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
              >
                <Check size={iconSize} color="white" strokeWidth={3} />
              </div>
            )}
            {event.hasNote && (
              <FileText size={iconSize} color="#1e293b" strokeWidth={2} opacity={0.6} />
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
