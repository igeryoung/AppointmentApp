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
  Future<Note?> getCached(String eventId) async {
    final db = await _getDatabaseFn();
    final maps = await db.query('notes', where: 'event_id = ?', whereArgs: [eventId], limit: 1);
    if (maps.isEmpty) return null;
    return Note.fromMap(maps.first);
  }

  @override
  Future<void> saveToCache(Note note, {required bool isDirty}) async {
    final db = await _getDatabaseFn();
    final now = DateTime.now();
    // Increment version when saving dirty note
    final newVersion = isDirty ? note.version + 1 : note.version;
    final updatedNote = note.copyWith(updatedAt: now, version: newVersion, isDirty: isDirty);

    final noteMap = updatedNote.toMap();
    debugPrint('🔍 SQLite: updateNote called with ${updatedNote.strokes.length} strokes');
    debugPrint('🔍 SQLite: noteMap contents:');
    noteMap.forEach((key, value) {
      debugPrint('   $key: $value (${value.runtimeType})');
    });

    try {
      final updateMap = Map<String, dynamic>.from(noteMap);
      final originalPagesData = updateMap['pages_data'];

      // Force string conversion to prevent SQLite parameter binding corruption
      if (originalPagesData is String) {
        debugPrint('🔍 SQLite: pages_data is String, ensuring it stays as String');
        updateMap['pages_data'] = originalPagesData.toString();
      } else {
        debugPrint('⚠️ SQLite: pages_data is NOT a String: ${originalPagesData.runtimeType}');
        updateMap['pages_data'] = originalPagesData.toString();
      }

      debugPrint('🔍 SQLite: Final pages_data type: ${updateMap['pages_data'].runtimeType}');
      debugPrint('🔍 SQLite: Final pages_data length: ${updateMap['pages_data'].toString().length} chars');

      final pagesDataString = updateMap['pages_data'] as String;
      final cachedAt = now.millisecondsSinceEpoch ~/ 1000;
      final isDirtyFlag = updateMap['is_dirty'] ?? 0;

      debugPrint('🔍 SQLite: Using raw SQL with explicit string parameter');
      final updatedRows = await db.rawUpdate(
        'UPDATE notes SET event_id = ?, pages_data = ?, created_at = ?, updated_at = ?, cached_at = ?, version = ?, is_dirty = ? WHERE event_id = ?',
        [
          updateMap['event_id'],
          pagesDataString,
          updateMap['created_at'],
          updateMap['updated_at'],
          cachedAt,
          updateMap['version'],
          isDirtyFlag,
          note.eventId,
        ],
      );

      debugPrint('✅ SQLite: Update successful, updated $updatedRows rows');

      if (updatedRows == 0) {
        debugPrint('🔍 SQLite: Inserting new note using raw SQL');
        await db.rawInsert(
          'INSERT INTO notes (event_id, pages_data, created_at, updated_at, cached_at, cache_hit_count, version, is_dirty) VALUES (?, ?, ?, ?, ?, 0, ?, ?)',
          [
            updateMap['event_id'],
            pagesDataString,
            updateMap['created_at'],
            updateMap['updated_at'],
            cachedAt,
            updateMap['version'],
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
  Future<void> deleteCache(String eventId) async {
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
  Future<List<Note>> getDirtyNotesByBookId(String bookUuid) async {
    final db = await _getDatabaseFn();
    final maps = await db.rawQuery('''
      SELECT notes.* FROM notes
      INNER JOIN events ON notes.event_id = events.id
      WHERE notes.is_dirty = ? AND events.book_uuid = ?
    ''', [1, bookUuid]);

    final dirtyNotes = maps.map((map) => Note.fromMap(map)).toList();
    debugPrint('✅ getDirtyNotesByBookId: Found ${dirtyNotes.length} dirty notes for book $bookUuid');
    return dirtyNotes;
  }

  @override
  Future<void> markClean(String eventId) async {
    final db = await _getDatabaseFn();
    await db.update(
      'notes',
      {'is_dirty': 0},
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  @override
  Future<List<Note>> getAllCachedForBook(String bookUuid) async {
    final db = await _getDatabaseFn();
    final maps = await db.rawQuery('''
      SELECT notes.* FROM notes
      INNER JOIN events ON notes.event_id = events.id
      WHERE events.book_uuid = ?
    ''', [bookUuid]);

    return maps.map((map) => Note.fromMap(map)).toList();
  }

  @override
  Future<List<Note>> getAllCached() async {
    final db = await _getDatabaseFn();
    final maps = await db.query('notes');
    return maps.map((map) => Note.fromMap(map)).toList();
  }

  /// Batch get cached notes
  Future<Map<String, Note>> batchGetCachedNotes(List<String> eventIds) async {
    if (eventIds.isEmpty) return {};

    final db = await _getDatabaseFn();
    final placeholders = eventIds.map((_) => '?').join(',');
    final maps = await db.query(
      'notes',
      where: 'event_id IN ($placeholders)',
      whereArgs: eventIds,
    );

    final result = <String, Note>{};
    for (final map in maps) {
      final note = Note.fromMap(map);
      result[note.eventId] = note;
    }

    debugPrint('✅ batchGetCachedNotes: Found ${result.length}/${eventIds.length} notes');
    return result;
  }

  /// Batch save cached notes
  Future<void> batchSaveCachedNotes(Map<String, Note> notes) async {
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
        INSERT INTO notes (event_id, pages_data, created_at, updated_at, cached_at, cache_hit_count, version, is_dirty)
        VALUES (?, ?, ?, ?, ?, 0, ?, ?)
        ON CONFLICT(event_id) DO UPDATE SET
          pages_data = excluded.pages_data,
          updated_at = excluded.updated_at,
          cached_at = excluded.cached_at,
          version = excluded.version,
          is_dirty = excluded.is_dirty
      ''', [
        eventId,
        noteMap['pages_data'],
        noteMap['created_at'],
        noteMap['updated_at'],
        cachedAt,
        noteMap['version'] ?? 1,
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

  @override
  Future<void> markNoteSynced(String eventId, DateTime syncedAt) async {
    final db = await _getDatabaseFn();
    await db.update(
      'notes',
      {
        'is_dirty': 0,
        'synced_at': syncedAt.millisecondsSinceEpoch ~/ 1000,
      },
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  @override
  Future<void> applyServerChange(Map<String, dynamic> changeData) async {
    final db = await _getDatabaseFn();
    final eventId = changeData['event_id'] as String;

    // Check if note exists locally
    final existing = await getCached(eventId);

    final syncChangeData = Map<String, dynamic>.from(changeData);
    syncChangeData['is_dirty'] = 0; // Server data is not dirty

    if (existing == null) {
      // Insert new note from server
      await db.insert('notes', syncChangeData);
    } else {
      // Update existing note with server data
      final updateData = Map<String, dynamic>.from(syncChangeData);
      updateData.remove('id');
      await db.update(
        'notes',
        updateData,
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
    }
  }
}
