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
  /// Returns null if recordNumber is empty
  static (String, String)? getPersonKeyFromEvent(Event event) {
    if (event.recordNumber.trim().isEmpty) {
      return null;
    }
    return (
      normalizePersonKey(event.title),
      normalizePersonKey(event.recordNumber),
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
  Future<List<String>> getRecordNumbersByName(String bookUuid, String name) async {
    if (name.trim().isEmpty) {
      return [];
    }

    final db = await database;
    final nameNorm = normalizePersonKey(name);

    // Query events table (using LOWER(title) since events table doesn't have person_name_normalized)
    final eventsResult = await db.rawQuery('''
      SELECT DISTINCT record_number
      FROM events
      WHERE book_uuid = ?
        AND LOWER(TRIM(title)) = ?
        AND record_number IS NOT NULL
        AND TRIM(record_number) != ''
        AND is_removed = 0
      ORDER BY record_number
    ''', [bookUuid, nameNorm]);

    // Query notes table (joined with events to filter by book_uuid)
    final notesResult = await db.rawQuery('''
      SELECT DISTINCT n.record_number_normalized
      FROM notes n
      INNER JOIN events e ON n.record_uuid = e.record_uuid
      WHERE e.book_uuid = ?
        AND n.person_name_normalized = ?
        AND n.record_number_normalized IS NOT NULL
        AND TRIM(n.record_number_normalized) != ''
      ORDER BY n.record_number_normalized
    ''', [bookUuid, nameNorm]);

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

  /// Get all unique names in a book
  /// Returns a sorted list of distinct names from events (excluding removed events)
  Future<List<String>> getAllNamesInBook(String bookUuid) async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT DISTINCT title
      FROM events
      WHERE book_uuid = ?
        AND title IS NOT NULL
        AND TRIM(title) != ''
        AND is_removed = 0
      ORDER BY title
    ''', [bookUuid]);

    return result
        .map((row) => row['title'] as String)
        .where((title) => title.trim().isNotEmpty)
        .toList();
  }

  /// Get all record numbers with their associated names
  /// Returns a list of maps with 'recordNumber' and 'name' keys
  /// Record number is unique, so each record number maps to exactly one name
  Future<List<Map<String, String>>> getAllRecordNumbersWithNames(
      String bookUuid) async {
    final db = await database;

    // Get record numbers with their most recent associated name (title)
    // Since record number is unique per name, we get the most recent event for each record number
    final result = await db.rawQuery('''
      SELECT record_number, title
      FROM (
        SELECT record_number, title, MAX(updated_at) as latest_update
        FROM events
        WHERE book_uuid = ?
          AND record_number IS NOT NULL
          AND TRIM(record_number) != ''
          AND title IS NOT NULL
          AND TRIM(title) != ''
          AND is_removed = 0
        GROUP BY record_number
      )
      ORDER BY record_number
    ''', [bookUuid]);

    return result
        .map((row) => {
              'recordNumber': (row['record_number'] as String).trim(),
              'name': (row['title'] as String).trim(),
            })
        .toList();
  }

  /// Get the name associated with a specific record number
  /// Returns null if record number is not found
  /// Since record number is unique, returns the single associated name
  Future<String?> getNameByRecordNumber(
      String bookUuid, String recordNumber) async {
    if (recordNumber.trim().isEmpty) {
      return null;
    }

    final db = await database;

    final result = await db.rawQuery('''
      SELECT title
      FROM events
      WHERE book_uuid = ?
        AND record_number = ?
        AND is_removed = 0
      ORDER BY updated_at DESC
      LIMIT 1
    ''', [bookUuid, recordNumber.trim()]);

    if (result.isEmpty) {
      return null;
    }

    return (result.first['title'] as String?)?.trim();
  }
}
