/**
 * Normalize the eventTypes payload from the dashboard API.
 * The backend may return either a JSON string (legacy) or an actual array (jsonb).
 */
const cleanList = (values: unknown[]): string[] =>
  values
    .map((type) => (type ?? '').toString().trim())
    .filter((type): type is string => type.length > 0);

export const parseEventTypes = (eventTypes?: string | string[] | null): string[] => {
  if (!eventTypes) {
    return [];
  }

  if (Array.isArray(eventTypes)) {
    return cleanList(eventTypes);
  }

  const trimmed = eventTypes.trim();
  if (!trimmed) {
    return [];
  }

  try {
    const parsed = JSON.parse(trimmed) as unknown;
    if (Array.isArray(parsed)) {
      return cleanList(parsed);
    }
  } catch {
    // Fall back to treating the raw string as a single event type value
    return [trimmed];
  }

  return [];
};
