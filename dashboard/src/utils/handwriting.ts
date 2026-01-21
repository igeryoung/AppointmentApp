import type { Note, NotePage, NotePages, Stroke, StrokePoint } from '../types';

type CanvasSize = { width: number; height: number };

export interface ParsedNotePages {
  pages: NotePages;
  canvasSize: CanvasSize | null;
}

const toNumber = (value: unknown, fallback: number): number => {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
};

const normalizeStrokeType = (value: unknown): Stroke['strokeType'] => {
  if (value === 'pen' || value === 'highlighter') {
    return value;
  }
  if (typeof value === 'number') {
    return value === 1 ? 'highlighter' : 'pen';
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed === 1 ? 'highlighter' : 'pen';
    }
  }
  return 'pen';
};

const normalizeStrokePoint = (point: Record<string, unknown>): StrokePoint => ({
  dx: toNumber(point.dx ?? point.x, 0),
  dy: toNumber(point.dy ?? point.y, 0),
  pressure: toNumber(point.pressure, 1),
});

const normalizeStroke = (stroke: Record<string, unknown>): Stroke => ({
  points: Array.isArray(stroke.points)
    ? stroke.points.map((point) => normalizeStrokePoint(point as Record<string, unknown>))
    : [],
  strokeWidth: toNumber(stroke.strokeWidth ?? stroke.stroke_width, 2),
  color: toNumber(stroke.color, 0xff000000),
  strokeType: normalizeStrokeType(stroke.strokeType ?? stroke.stroke_type),
});

const normalizePage = (page: unknown): NotePage => {
  if (!Array.isArray(page)) {
    return [];
  }
  return page.map((stroke) => normalizeStroke(stroke as Record<string, unknown>));
};

const extractCanvasSize = (payload: Record<string, unknown>): CanvasSize | null => {
  const width = toNumber(payload.canvasWidth ?? payload.canvas_width, Number.NaN);
  const height = toNumber(payload.canvasHeight ?? payload.canvas_height, Number.NaN);
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    return null;
  }
  return { width, height };
};

export const parseNotePagesData = (noteData: Note): ParsedNotePages => {
  try {
    if (noteData.pagesData) {
      const parsed = JSON.parse(noteData.pagesData) as unknown;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        const payload = parsed as Record<string, unknown>;
        if (Array.isArray(payload.pages)) {
          return {
            pages: payload.pages.map((page) => normalizePage(page)),
            canvasSize: extractCanvasSize(payload),
          };
        }
      }
      if (Array.isArray(parsed)) {
        return { pages: parsed.map((page) => normalizePage(page)), canvasSize: null };
      }
    }

    if (noteData.strokesData) {
      const parsed = JSON.parse(noteData.strokesData) as unknown;
      if (Array.isArray(parsed)) {
        return { pages: [parsed.map((stroke) => normalizeStroke(stroke as Record<string, unknown>))], canvasSize: null };
      }
    }

    return { pages: [], canvasSize: null };
  } catch (err) {
    console.error('Failed to parse note data:', err);
    return { pages: [], canvasSize: null };
  }
};
