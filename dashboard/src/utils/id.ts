/**
 * Format an identifier into a short, human-friendly string.
 * Removes hyphens so UUIDs become compact and then truncates to the desired length.
 */
export const formatShortId = (id?: string | null, length = 5): string => {
  if (!id) {
    return '-';
  }

  const normalized = id.replace(/-/g, '');
  if (!normalized) {
    return '-';
  }

  return normalized.slice(0, length);
};
