import 'package:sqflite/sqflite.dart';
import '../../../models/note.dart';

/// Note database operations (notes are per-record)
mixin NoteOperationsMixin {
  Future<Database> get database;

  Future<Note?> getNoteByRecordUuid(String recordUuid) async {
    final db = await database;
    final maps = await db.query('notes', where: 'record_uuid = ?', whereArgs: [recordUuid], limit: 1);
    if (maps.isEmpty) return null;
    return Note.fromMap(maps.first);
  }

  /// Get or create note for a record
  Future<Note> getOrCreateNote(String recordUuid) async {
    final existing = await getNoteByRecordUuid(recordUuid);
    if (existing != null) return existing;

    final db = await database;
    final now = DateTime.now().toUtc();
    final note = Note(
      recordUuid: recordUuid,
      pages: [[]],
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('notes', {...note.toMap(), 'is_dirty': 1});
    final created = await getNoteByRecordUuid(recordUuid);
    return created ?? note;
  }

  Future<Note> saveNote(Note note) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final updated = note.copyWith(updatedAt: now, version: note.version + 1, clearLock: true);
    final data = updated.toMap();

    final existing = await getNoteByRecordUuid(note.recordUuid);
    if (existing != null) {
      data.remove('id');
      data['is_dirty'] = 1;
      await db.update('notes', data, where: 'record_uuid = ?', whereArgs: [note.recordUuid]);
    } else {
      data['is_dirty'] = 1;
      await db.insert('notes', data);
    }

    // Update has_note flag on all events for this record
    final hasStrokes = updated.isNotEmpty;
    await db.update('events', {'has_note': hasStrokes ? 1 : 0}, where: 'record_uuid = ?', whereArgs: [note.recordUuid]);

    return updated;
  }

  Future<void> deleteNote(String recordUuid) async {
    final db = await database;
    await db.delete('notes', where: 'record_uuid = ?', whereArgs: [recordUuid]);
    await db.update('events', {'has_note': 0}, where: 'record_uuid = ?', whereArgs: [recordUuid]);
  }

  Future<Note?> acquireNoteLock(String recordUuid, String deviceId) async {
    final db = await database;
    final now = DateTime.now().toUtc();

    // First ensure note exists
    await getOrCreateNote(recordUuid);

    // Check if already locked by another device
    final existing = await getNoteByRecordUuid(recordUuid);
    if (existing != null && existing.isLocked && existing.lockedByDeviceId != deviceId) {
      // Check if lock is stale (older than 5 minutes)
      final lockAge = now.difference(existing.lockedAt!);
      if (lockAge.inMinutes < 5) {
        return null; // Cannot acquire lock
      }
    }

    // Acquire lock
    await db.update(
      'notes',
      {
        'locked_by_device_id': deviceId,
        'locked_at': now.millisecondsSinceEpoch ~/ 1000,
      },
      where: 'record_uuid = ?',
      whereArgs: [recordUuid],
    );

    return await getNoteByRecordUuid(recordUuid);
  }

  Future<void> releaseNoteLock(String recordUuid, String deviceId) async {
    final db = await database;
    await db.update(
      'notes',
      {'locked_by_device_id': null, 'locked_at': null},
      where: 'record_uuid = ? AND locked_by_device_id = ?',
      whereArgs: [recordUuid, deviceId],
    );
  }

  Future<List<Note>> getDirtyNotes() async {
    final db = await database;
    final maps = await db.query('notes', where: 'is_dirty = 1');
    return maps.map((m) => Note.fromMap(m)).toList();
  }

  Future<void> markNotesSynced(List<String> recordUuids) async {
    if (recordUuids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(recordUuids.length, '?').join(',');
    await db.execute('UPDATE notes SET is_dirty = 0 WHERE record_uuid IN ($placeholders)', recordUuids);
  }
}
