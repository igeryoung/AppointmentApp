import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/note.dart';
import 'note_repository.dart';

/// Implementation of NoteRepository using SQLite
/// Handles local caching of notes with dirty flag tracking
class NoteRepositoryImpl implements INoteRepository {
  final Future<Database> Function() _getDatabaseFn;

  NoteRepositoryImpl(this._getDatabaseFn);

  @override
  Future<Note?> getCached(int eventId) async {
    final db = await _getDatabaseFn();
    final maps = await db.query('notes', where: 'event_id = ?', whereArgs: [eventId], limit: 1);
    if (maps.isEmpty) return null;
    return Note.fromMap(maps.first);
  }

  @override
  Future<void> saveToCache(Note note, {required bool isDirty}) async {
    final db = await _getDatabaseFn();
    final now = DateTime.now();
    final updatedNote = note.copyWith(updatedAt: now, isDirty: isDirty);

    final noteMap = updatedNote.toMap();
    debugPrint('🔍 SQLite: updateNote called with ${updatedNote.strokes.length} strokes');
    debugPrint('🔍 SQLite: noteMap contents:');
    noteMap.forEach((key, value) {
      debugPrint('   $key: $value (${value.runtimeType})');
    });

    try {
      final updateMap = Map<String, dynamic>.from(noteMap);
      final originalStrokesData = updateMap['strokes_data'];

      // Force string conversion to prevent SQLite parameter binding corruption
      if (originalStrokesData is String) {
        debugPrint('🔍 SQLite: strokes_data is String, ensuring it stays as String');
        updateMap['strokes_data'] = originalStrokesData.toString();
      } else {
        debugPrint('⚠️ SQLite: strokes_data is NOT a String: ${originalStrokesData.runtimeType}');
        updateMap['strokes_data'] = originalStrokesData.toString();
      }

      debugPrint('🔍 SQLite: Final strokes_data type: ${updateMap['strokes_data'].runtimeType}');
      debugPrint('🔍 SQLite: Final strokes_data length: ${updateMap['strokes_data'].toString().length} chars');

      final strokesDataString = updateMap['strokes_data'] as String;
      final cachedAt = now.millisecondsSinceEpoch ~/ 1000;
      final isDirtyFlag = updateMap['is_dirty'] ?? 0;

      debugPrint('🔍 SQLite: Using raw SQL with explicit string parameter');
      final updatedRows = await db.rawUpdate(
        'UPDATE notes SET event_id = ?, strokes_data = ?, created_at = ?, updated_at = ?, cached_at = ?, is_dirty = ? WHERE event_id = ?',
        [
          updateMap['event_id'],
          strokesDataString,
          updateMap['created_at'],
          updateMap['updated_at'],
          cachedAt,
          isDirtyFlag,
          note.eventId,
        ],
      );

      debugPrint('✅ SQLite: Update successful, updated $updatedRows rows');

      if (updatedRows == 0) {
        debugPrint('🔍 SQLite: Inserting new note using raw SQL');
        await db.rawInsert(
          'INSERT INTO notes (event_id, strokes_data, created_at, updated_at, cached_at, cache_hit_count, is_dirty) VALUES (?, ?, ?, ?, ?, 0, ?)',
          [
            updateMap['event_id'],
            strokesDataString,
            updateMap['created_at'],
            updateMap['updated_at'],
            cachedAt,
            isDirtyFlag,
          ],
        );
        debugPrint('✅ SQLite: Insert successful');
      }
    } catch (e) {
      debugPrint('❌ SQLite: Database operation failed: $e');
      debugPrint('❌ SQLite: Failed noteMap was:');
      noteMap.forEach((key, value) {
        debugPrint('   $key: $value (${value.runtimeType})');
      });
      rethrow;
    }
  }

  @override
  Future<void> deleteCache(int eventId) async {
    final db = await _getDatabaseFn();
    await db.delete('notes', where: 'event_id = ?', whereArgs: [eventId]);
  }

  @override
  Future<List<Note>> getDirtyNotes() async {
    final db = await _getDatabaseFn();
    final maps = await db.query(
      'notes',
      where: 'is_dirty = ?',
      whereArgs: [1],
    );

    final dirtyNotes = maps.map((map) => Note.fromMap(map)).toList();
    debugPrint('✅ getAllDirtyNotes: Found ${dirtyNotes.length} dirty notes');
    return dirtyNotes;
  }

  /// Get dirty notes for a specific book
  Future<List<Note>> getDirtyNotesByBookId(int bookId) async {
    final db = await _getDatabaseFn();
    final maps = await db.rawQuery('''
      SELECT notes.* FROM notes
      INNER JOIN events ON notes.event_id = events.id
      WHERE notes.is_dirty = ? AND events.book_id = ?
    ''', [1, bookId]);

    final dirtyNotes = maps.map((map) => Note.fromMap(map)).toList();
    debugPrint('✅ getDirtyNotesByBookId: Found ${dirtyNotes.length} dirty notes for book $bookId');
    return dirtyNotes;
  }

  @override
  Future<void> markClean(int eventId) async {
    final db = await _getDatabaseFn();
    await db.update(
      'notes',
      {'is_dirty': 0},
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  @override
  Future<List<Note>> getAllCachedForBook(int bookId) async {
    final db = await _getDatabaseFn();
    final maps = await db.rawQuery('''
      SELECT notes.* FROM notes
      INNER JOIN events ON notes.event_id = events.id
      WHERE events.book_id = ?
    ''', [bookId]);

    return maps.map((map) => Note.fromMap(map)).toList();
  }

  @override
  Future<List<Note>> getAllCached() async {
    final db = await _getDatabaseFn();
    final maps = await db.query('notes');
    return maps.map((map) => Note.fromMap(map)).toList();
  }

  /// Batch get cached notes
  Future<Map<int, Note>> batchGetCachedNotes(List<int> eventIds) async {
    if (eventIds.isEmpty) return {};

    final db = await _getDatabaseFn();
    final placeholders = eventIds.map((_) => '?').join(',');
    final maps = await db.query(
      'notes',
      where: 'event_id IN ($placeholders)',
      whereArgs: eventIds,
    );

    final result = <int, Note>{};
    for (final map in maps) {
      final note = Note.fromMap(map);
      result[note.eventId] = note;
    }

    debugPrint('✅ batchGetCachedNotes: Found ${result.length}/${eventIds.length} notes');
    return result;
  }

  /// Batch save cached notes
  Future<void> batchSaveCachedNotes(Map<int, Note> notes) async {
    if (notes.isEmpty) return;

    final db = await _getDatabaseFn();
    final batch = db.batch();
    final now = DateTime.now();
    final cachedAt = now.millisecondsSinceEpoch ~/ 1000;

    for (final entry in notes.entries) {
      final eventId = entry.key;
      final note = entry.value;
      final noteMap = note.toMap();

      batch.rawInsert('''
        INSERT INTO notes (event_id, strokes_data, created_at, updated_at, cached_at, cache_hit_count, is_dirty)
        VALUES (?, ?, ?, ?, ?, 0, ?)
        ON CONFLICT(event_id) DO UPDATE SET
          strokes_data = excluded.strokes_data,
          updated_at = excluded.updated_at,
          cached_at = excluded.cached_at,
          is_dirty = excluded.is_dirty
      ''', [
        eventId,
        noteMap['strokes_data'],
        noteMap['created_at'],
        noteMap['updated_at'],
        cachedAt,
        noteMap['is_dirty'] ?? 0,
      ]);
    }

    await batch.commit(noResult: true);
    debugPrint('✅ batchSaveCachedNotes: Saved ${notes.length} notes');
  }

  /// Clear all notes cache
  Future<void> clearAll() async {
    final db = await _getDatabaseFn();
    await db.delete('notes');
  }
}
