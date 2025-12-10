import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/note.dart';
import 'note_repository.dart';

/// Implementation of NoteRepository using SQLite
/// Handles local caching of notes for display
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
  Future<void> saveToCache(Note note) async {
    final db = await _getDatabaseFn();
    final now = DateTime.now().toUtc();
    // Increment version when saving
    final newVersion = note.version + 1;
    final updatedNote = note.copyWith(updatedAt: now, version: newVersion);

    final noteMap = updatedNote.toMap();

    try {
      final updateMap = Map<String, dynamic>.from(noteMap);
      final originalPagesData = updateMap['pages_data'];

      // Force string conversion to prevent SQLite parameter binding corruption
      if (originalPagesData is String) {
        updateMap['pages_data'] = originalPagesData.toString();
      } else {
        updateMap['pages_data'] = originalPagesData.toString();
      }

      final pagesDataString = updateMap['pages_data'] as String;
      final cachedAt = now.millisecondsSinceEpoch ~/ 1000;

      final updatedRows = await db.rawUpdate(
        'UPDATE notes SET event_id = ?, pages_data = ?, created_at = ?, updated_at = ?, cached_at = ?, version = ? WHERE event_id = ?',
        [
          updateMap['event_id'],
          pagesDataString,
          updateMap['created_at'],
          updateMap['updated_at'],
          cachedAt,
          updateMap['version'],
          note.eventId,
        ],
      );

      if (updatedRows == 0) {
        await db.rawInsert(
          'INSERT INTO notes (event_id, pages_data, created_at, updated_at, cached_at, cache_hit_count, version) VALUES (?, ?, ?, ?, ?, 0, ?)',
          [
            updateMap['event_id'],
            pagesDataString,
            updateMap['created_at'],
            updateMap['updated_at'],
            cachedAt,
            updateMap['version'],
          ],
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> deleteCache(String eventId) async {
    final db = await _getDatabaseFn();
    await db.delete('notes', where: 'event_id = ?', whereArgs: [eventId]);
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
        INSERT INTO notes (event_id, pages_data, created_at, updated_at, cached_at, cache_hit_count, version)
        VALUES (?, ?, ?, ?, ?, 0, ?)
        ON CONFLICT(event_id) DO UPDATE SET
          pages_data = excluded.pages_data,
          updated_at = excluded.updated_at,
          cached_at = excluded.cached_at,
          version = excluded.version
      ''', [
        eventId,
        noteMap['pages_data'],
        noteMap['created_at'],
        noteMap['updated_at'],
        cachedAt,
        noteMap['version'] ?? 1,
      ]);
    }

    await batch.commit(noResult: true);
  }

  /// Clear all notes cache
  Future<void> clearAll() async {
    final db = await _getDatabaseFn();
    await db.delete('notes');
  }

  @override
  Future<void> applyServerChange(Map<String, dynamic> changeData) async {
    final db = await _getDatabaseFn();
    final eventId = changeData['event_id'] as String;

    // Check if note exists locally
    final existing = await getCached(eventId);

    final syncChangeData = Map<String, dynamic>.from(changeData);

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
