import React, { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useNavigate } from 'react-router-dom';
import { Check, FileText } from 'lucide-react';
import { PositionedEvent } from './types';
import { parseEventTypes } from '../../utils/event';
import { parseServerDate } from '../../utils/date';

interface EventTileProps {
  positionedEvent: PositionedEvent;
  slotHeight: number;
}

type CanonicalEventType =
  | 'consultation'
  | 'surgery'
  | 'followUp'
  | 'emergency'
  | 'checkUp'
  | 'treatment'
  | 'other';

const EVENT_TYPE_BASE_COLORS: Record<CanonicalEventType, string> = {
  consultation: '#2196F3',
  surgery: '#F44336',
  followUp: '#4CAF50',
  emergency: '#FF9800',
  checkUp: '#9C27B0',
  treatment: '#00BCD4',
  other: '#9E9E9E',
};

const EVENT_TYPE_ALIASES: Record<string, CanonicalEventType> = {
  consultation: 'consultation',
  initialconsultation: 'consultation',
  firstvisit: 'consultation',
  門診: 'consultation',
  初診: 'consultation',
  surgery: 'surgery',
  operation: 'surgery',
  手術: 'surgery',
  followup: 'followUp',
  revisit: 'followUp',
  複診: 'followUp',
  復診: 'followUp',
  emergency: 'emergency',
  急診: 'emergency',
  checkup: 'checkUp',
  exam: 'checkUp',
  檢查: 'checkUp',
  健檢: 'checkUp',
  treatment: 'treatment',
  治療: 'treatment',
  other: 'other',
  其他: 'other',
};

const clamp01 = (value: number): number => Math.min(1, Math.max(0, value));

const hexToRgb = (hex: string): [number, number, number] => {
  const normalized = hex.replace('#', '');
  const parseChannel = (start: number) => parseInt(normalized.slice(start, start + 2), 16) / 255;
  return [parseChannel(0), parseChannel(2), parseChannel(4)];
};

const rgbToHsl = (r: number, g: number, b: number): [number, number, number] => {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const delta = max - min;

  let h = 0;
  const l = (max + min) / 2;
  const s = delta === 0 ? 0 : delta / (1 - Math.abs(2 * l - 1));

  if (delta !== 0) {
    if (max === r) {
      h = ((g - b) / delta) % 6;
    } else if (max === g) {
      h = (b - r) / delta + 2;
    } else {
      h = (r - g) / delta + 4;
    }
    h /= 6;
    if (h < 0) {
      h += 1;
    }
  }

  return [h, clamp01(s), clamp01(l)];
};

const hslToRgb = (h: number, s: number, l: number): [number, number, number] => {
  if (s === 0) {
    return [l, l, l];
  }

  const hue2rgb = (p: number, q: number, t: number) => {
    let next = t;
    if (next < 0) next += 1;
    if (next > 1) next -= 1;
    if (next < 1 / 6) return p + (q - p) * 6 * next;
    if (next < 1 / 2) return q;
    if (next < 2 / 3) return p + (q - p) * (2 / 3 - next) * 6;
    return p;
  };

  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;

  return [hue2rgb(p, q, h + 1 / 3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1 / 3)];
};

const rgbToHex = (r: number, g: number, b: number): string => {
  const toHex = (value: number) => Math.round(clamp01(value) * 255).toString(16).padStart(2, '0');
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`.toUpperCase();
};

const withSaturation = (hexColor: string, saturation: number): string => {
  const [r, g, b] = hexToRgb(hexColor);
  const [h, , l] = rgbToHsl(r, g, b);
  const [nextR, nextG, nextB] = hslToRgb(h, clamp01(saturation), l);
  return rgbToHex(nextR, nextG, nextB);
};

const normalizeEventType = (eventType: string): CanonicalEventType => {
  const normalized = eventType.trim().replace(/^EventType\./, '');
  const key = normalized.replace(/[\s_-]/g, '').toLowerCase();
  return EVENT_TYPE_ALIASES[key] || 'other';
};

const getEventTypeColor = (eventType: string): string => {
  const canonical = normalizeEventType(eventType);
  const baseColor = EVENT_TYPE_BASE_COLORS[canonical];
  if (canonical === 'other') {
    return baseColor;
  }
  return withSaturation(baseColor, 0.6);
};

const formatTimeLabel = (value?: string | null): string => {
  const parsed = parseServerDate(value);
  if (!parsed) {
    return '--:--';
  }

  return parsed.toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  });
};

export const EventTile: React.FC<EventTileProps> = ({ positionedEvent, slotHeight }) => {
  const navigate = useNavigate();
  const { event, top, left, width, height, zIndex } = positionedEvent;
  const tileRef = useRef<HTMLButtonElement>(null);
  const [tooltipVisible, setTooltipVisible] = useState(false);
  const [tooltipPosition, setTooltipPosition] = useState<{
    left: number;
    top: number;
    placement: 'top' | 'bottom';
  } | null>(null);

  const eventTypes = parseEventTypes(event.eventTypes);
  const resolvedTypes = eventTypes.length > 0 ? eventTypes : ['other'];

  const sortedTypes = [...resolvedTypes].sort();
  const colors = sortedTypes.slice(0, 2).map(getEventTypeColor);

  const renderBackground = () => {
    if (colors.length === 0) {
      return <div className="event-tile__color-fill" style={{ backgroundColor: '#94A3B8' }} />;
    }

    if (colors.length === 1) {
      return <div className="event-tile__color-fill" style={{ backgroundColor: colors[0] }} />;
    }

    return (
      <div className="event-tile__color-split">
        <div style={{ backgroundColor: colors[0] }} />
        <div style={{ backgroundColor: colors[1] }} />
      </div>
    );
  };

  const timeRange = `${formatTimeLabel(event.startTime)} - ${formatTimeLabel(event.endTime)}`;
  const displayName = event.recordNumber ? `${event.name} (${event.recordNumber})` : event.name;

  const fontSize = Math.max(slotHeight * 0.46, 10);
  const smallFontSize = Math.max(slotHeight * 0.28, 8);
  const iconSize = Math.max(slotHeight * 0.45, 11);

  const handleClick = () => {
    navigate(`/events/${event.id}`);
  };

  const updateTooltipPosition = () => {
    const tileElement = tileRef.current;
    if (!tileElement) {
      return;
    }

    const rect = tileElement.getBoundingClientRect();
    const placement: 'top' | 'bottom' = rect.top > 56 ? 'top' : 'bottom';
    const tooltipTop = placement === 'top' ? rect.top - 8 : rect.bottom + 8;
    const tooltipLeft = rect.left + rect.width / 2;

    setTooltipPosition({
      left: tooltipLeft,
      top: tooltipTop,
      placement,
    });
  };

  useEffect(() => {
    if (!tooltipVisible) {
      return;
    }

    updateTooltipPosition();

    const handleViewportChange = () => {
      updateTooltipPosition();
    };

    window.addEventListener('resize', handleViewportChange);
    window.addEventListener('scroll', handleViewportChange, true);

    return () => {
      window.removeEventListener('resize', handleViewportChange);
      window.removeEventListener('scroll', handleViewportChange, true);
    };
  }, [tooltipVisible]);

  return (
    <>
      <button
        ref={tileRef}
        type="button"
        onClick={handleClick}
        onMouseEnter={() => {
          setTooltipVisible(true);
          updateTooltipPosition();
        }}
        onMouseLeave={() => setTooltipVisible(false)}
        onFocus={() => {
          setTooltipVisible(true);
          updateTooltipPosition();
        }}
        onBlur={() => setTooltipVisible(false)}
        className="event-tile"
        style={{
          top: `${top}px`,
          left: `${left}px`,
          width: `${width}px`,
          height: `${height}px`,
          zIndex,
        }}
        aria-label={`${displayName}, ${timeRange}`}
      >
        <div className={`event-tile__surface ${event.isRemoved ? 'is-removed' : ''}`} style={{ fontSize: `${fontSize}px` }}>
          <div className="event-tile__background-layer">{renderBackground()}</div>

          {event.hasNote && <div className="event-tile__note-accent" />}

          <div className="event-tile__meta" style={{ fontSize: `${smallFontSize}px` }} title={timeRange}>
            {timeRange}
          </div>

          <div className="event-tile__name-row">
            <span className="event-tile__name" title={displayName}>
              {displayName}
            </span>
          </div>

          <div className="event-tile__badges" style={{ fontSize: `${smallFontSize}px` }}>
            {event.isChecked && (
              <span className="event-tile__badge event-tile__badge--checked">
                <Check size={iconSize} strokeWidth={3} />
              </span>
            )}
            {event.hasNote && (
              <span className="event-tile__badge event-tile__badge--note">
                <FileText size={iconSize} strokeWidth={2.5} />
              </span>
            )}
          </div>
        </div>
      </button>

      {tooltipVisible && tooltipPosition && typeof document !== 'undefined'
        ? createPortal(
            <div
              className={`event-tooltip-portal event-tooltip-portal--${tooltipPosition.placement}`}
              role="tooltip"
              style={{ left: `${tooltipPosition.left}px`, top: `${tooltipPosition.top}px` }}
            >
              {displayName}
            </div>,
            document.body
          )
        : null}
    </>
  );
};
