import 'package:sqflite/sqflite.dart';
import '../models/note.dart';
import 'note_repository.dart';

/// Implementation of NoteRepository using SQLite
/// Notes are now linked to records via record_uuid (not events)
class NoteRepositoryImpl implements INoteRepository {
  final Future<Database> Function() _getDatabaseFn;

  NoteRepositoryImpl(this._getDatabaseFn);

  @override
  Future<Note?> getCached(String eventId) async {
    // In record-based architecture, we look up via event's record_uuid
    final db = await _getDatabaseFn();
    // First get the event to find its record_uuid
    final eventMaps = await db.query('events', where: 'id = ?', whereArgs: [eventId], limit: 1);
    if (eventMaps.isEmpty) return null;

    final recordUuid = eventMaps.first['record_uuid'] as String?;
    if (recordUuid == null || recordUuid.isEmpty) return null;

    final maps = await db.query('notes', where: 'record_uuid = ?', whereArgs: [recordUuid], limit: 1);
    if (maps.isEmpty) return null;
    return Note.fromMap(maps.first);
  }

  @override
  Future<void> saveToCache(Note note) async {
    final db = await _getDatabaseFn();
    final now = DateTime.now().toUtc();
    final newVersion = note.version + 1;
    final updatedNote = note.copyWith(updatedAt: now, version: newVersion);

    final noteMap = updatedNote.toMap();

    try {
      final pagesDataString = noteMap['pages_data'] as String;

      final updatedRows = await db.rawUpdate(
        'UPDATE notes SET pages_data = ?, updated_at = ?, version = ? WHERE record_uuid = ?',
        [
          pagesDataString,
          noteMap['updated_at'],
          noteMap['version'],
          note.recordUuid,
        ],
      );

      if (updatedRows == 0) {
        await db.rawInsert(
          'INSERT INTO notes (record_uuid, pages_data, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?)',
          [
            noteMap['record_uuid'],
            pagesDataString,
            noteMap['created_at'],
            noteMap['updated_at'],
            noteMap['version'],
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
    // First get the event to find its record_uuid
    final eventMaps = await db.query('events', where: 'id = ?', whereArgs: [eventId], limit: 1);
    if (eventMaps.isEmpty) return;

    final recordUuid = eventMaps.first['record_uuid'] as String?;
    if (recordUuid == null || recordUuid.isEmpty) return;

    await db.delete('notes', where: 'record_uuid = ?', whereArgs: [recordUuid]);
  }

  @override
  Future<List<Note>> getAllCachedForBook(String bookUuid) async {
    final db = await _getDatabaseFn();
    final maps = await db.rawQuery('''
      SELECT DISTINCT notes.* FROM notes
      INNER JOIN events ON notes.record_uuid = events.record_uuid
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

  /// Batch get cached notes by record UUIDs
  Future<Map<String, Note>> batchGetCachedNotes(List<String> recordUuids) async {
    if (recordUuids.isEmpty) return {};

    final db = await _getDatabaseFn();
    final placeholders = recordUuids.map((_) => '?').join(',');
    final maps = await db.query(
      'notes',
      where: 'record_uuid IN ($placeholders)',
      whereArgs: recordUuids,
    );

    final result = <String, Note>{};
    for (final map in maps) {
      final note = Note.fromMap(map);
      result[note.recordUuid] = note;
    }

    return result;
  }

  /// Batch save cached notes
  Future<void> batchSaveCachedNotes(Map<String, Note> notes) async {
    if (notes.isEmpty) return;

    final db = await _getDatabaseFn();
    final batch = db.batch();
    final now = DateTime.now();

    for (final entry in notes.entries) {
      final recordUuid = entry.key;
      final note = entry.value;
      final noteMap = note.toMap();

      batch.rawInsert('''
        INSERT INTO notes (record_uuid, pages_data, created_at, updated_at, version)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(record_uuid) DO UPDATE SET
          pages_data = excluded.pages_data,
          updated_at = excluded.updated_at,
          version = excluded.version
      ''', [
        recordUuid,
        noteMap['pages_data'],
        noteMap['created_at'],
        noteMap['updated_at'],
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
    final recordUuid = changeData['record_uuid'] as String?;
    if (recordUuid == null) return;

    // Check if note exists locally
    final existing = await db.query('notes', where: 'record_uuid = ?', whereArgs: [recordUuid], limit: 1);

    if (existing.isEmpty) {
      // Insert new note from server
      await db.insert('notes', changeData);
    } else {
      // Update existing note with server data
      final updateData = Map<String, dynamic>.from(changeData);
      updateData.remove('id');
      await db.update(
        'notes',
        updateData,
        where: 'record_uuid = ?',
        whereArgs: [recordUuid],
      );
    }
  }
}
