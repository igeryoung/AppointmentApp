import 'package:sqflite/sqflite.dart';
import '../../../models/event.dart';
import '../../../models/note.dart';

/// Mixin providing person info utilities for PRDDatabaseService
mixin PersonInfoUtilitiesMixin {
  /// Subclasses must provide database access
  Future<Database> get database;

  // ===================
  // Person Info Utilities
  // ===================

  /// Normalize a string for person key matching (case-insensitive, trimmed)
  /// Used for both person names and record numbers
  static String normalizePersonKey(String input) {
    return input.trim().toLowerCase();
  }

  /// Get normalized person key tuple from event
  /// Returns null if recordNumber is null or empty
  static (String, String)? getPersonKeyFromEvent(Event event) {
    if (event.recordNumber == null || event.recordNumber!.trim().isEmpty) {
      return null;
    }
    return (
      normalizePersonKey(event.name),
      normalizePersonKey(event.recordNumber!),
    );
  }

  /// Check if a person note exists in DB (for showing dialog before overwriting)
  /// Returns the existing note if found, null if no existing note
  Future<Note?> findExistingPersonNote(String name, String recordNumber) async {
    if (name.trim().isEmpty || recordNumber.trim().isEmpty) {
      return null;
    }

    final db = await database;
    final nameNorm = normalizePersonKey(name);
    final recordNorm = normalizePersonKey(recordNumber);

    final groupNotes = await db.query(
      'notes',
      where: 'person_name_normalized = ? AND record_number_normalized = ?',
      whereArgs: [nameNorm, recordNorm],
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    if (groupNotes.isEmpty) {
      return null;
    }

    final note = Note.fromMap(groupNotes.first);
    // Only return if it has actual handwriting
    return note.isNotEmpty ? note : null;
  }

  /// Get all distinct record numbers for a given person name
  /// Queries both events and notes tables, excludes empty record numbers
  Future<List<String>> getRecordNumbersByName(int bookId, String name) async {
    if (name.trim().isEmpty) {
      return [];
    }

    final db = await database;
    final nameNorm = normalizePersonKey(name);

    // Query events table (using LOWER(name) since events table doesn't have person_name_normalized)
    final eventsResult = await db.rawQuery('''
      SELECT DISTINCT record_number
      FROM events
      WHERE book_id = ?
        AND LOWER(TRIM(name)) = ?
        AND record_number IS NOT NULL
        AND TRIM(record_number) != ''
        AND is_removed = 0
      ORDER BY record_number
    ''', [bookId, nameNorm]);

    // Query notes table (joined with events to filter by book_id)
    final notesResult = await db.rawQuery('''
      SELECT DISTINCT n.record_number_normalized
      FROM notes n
      INNER JOIN events e ON n.event_id = e.id
      WHERE e.book_id = ?
        AND n.person_name_normalized = ?
        AND n.record_number_normalized IS NOT NULL
        AND TRIM(n.record_number_normalized) != ''
      ORDER BY n.record_number_normalized
    ''', [bookId, nameNorm]);

    // Combine and deduplicate
    final recordNumbers = <String>{};

    for (final row in eventsResult) {
      final recordNumber = row['record_number'] as String?;
      if (recordNumber != null && recordNumber.trim().isNotEmpty) {
        recordNumbers.add(recordNumber.trim());
      }
    }

    for (final row in notesResult) {
      final recordNumber = row['record_number_normalized'] as String?;
      if (recordNumber != null && recordNumber.trim().isNotEmpty) {
        // Notes store normalized values, we need to preserve original case
        // For now, we'll use the normalized value as-is
        recordNumbers.add(recordNumber.trim());
      }
    }

    return recordNumbers.toList()..sort();
  }
}
