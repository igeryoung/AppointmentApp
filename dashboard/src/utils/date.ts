/**
 * Parse server timestamps.
 * Server now returns UTC ISO strings (and sometimes numeric seconds).
 * Let the browser convert UTC → local so dashboard shows local wall time.
 */
export const parseServerDate = (value?: string | number | null): Date | null => {
  if (value === undefined || value === null) {
    return null;
  }

  // Numeric seconds
  if (typeof value === 'number') {
    const ms = value < 10_000_000_000 ? value * 1000 : value;
    const parsed = new Date(ms);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  // Allow plain numeric strings as seconds
  if (/^\d+$/.test(trimmed)) {
    const seconds = Number(trimmed);
    const parsed = new Date(seconds * 1000);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  const parsed = new Date(trimmed);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};
