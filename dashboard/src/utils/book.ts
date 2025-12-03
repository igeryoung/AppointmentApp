/**
 * Returns a human-readable label for a book using the available metadata.
 * Prefers the explicit name, falls back to numeric ID, then to a
 * shortened UUID segment so dashboards always have a stable identifier.
 */
export const getBookDisplayName = (
  bookName?: string | null,
  bookUuid?: string | null
): string => {
  if (bookName && bookName.trim().length > 0) {
    return bookName.trim();
  }

  if (bookUuid && bookUuid.trim().length > 0) {
    const sanitized = bookUuid.replace(/-/g, '');
    const shortId = sanitized.slice(0, 6).toUpperCase();
    return `Book ${shortId}`;
  }

  return 'Unknown Book';
};
