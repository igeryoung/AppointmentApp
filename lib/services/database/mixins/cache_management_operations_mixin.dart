import 'package:sqflite/sqflite.dart';

/// Mixin providing Cache Management operations for PRDDatabaseService
mixin CacheManagementOperationsMixin {
  /// Subclasses must provide database access
  Future<Database> get database;

  // ===================
  // Cache Management Operations
  // ===================

  /// Increment cache hit count for a note (called on every read)
  Future<void> incrementNoteCacheHit(int eventId) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE notes
      SET cache_hit_count = cache_hit_count + 1
      WHERE event_id = ?
    ''', [eventId]);
  }

  /// Increment cache hit count for a drawing (called on every read)
  Future<void> incrementDrawingCacheHit(int bookId, DateTime date, int viewMode) async {
    final db = await database;
    final normalizedDate = DateTime(date.year, date.month, date.day);
    await db.rawUpdate('''
      UPDATE schedule_drawings
      SET cache_hit_count = cache_hit_count + 1
      WHERE book_id = ? AND date = ? AND view_mode = ?
    ''', [
      bookId,
      normalizedDate.millisecondsSinceEpoch ~/ 1000,
      viewMode,
    ]);
  }

  /// Get cache size in bytes for notes
  Future<int> getNotesCacheSize() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(LENGTH(pages_data)) as total_size
      FROM notes
      WHERE pages_data IS NOT NULL
    ''');
    return (result.first['total_size'] as int?) ?? 0;
  }

  /// Get cache size in bytes for drawings
  Future<int> getDrawingsCacheSize() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(LENGTH(strokes_data)) as total_size
      FROM schedule_drawings
      WHERE strokes_data IS NOT NULL
    ''');
    return (result.first['total_size'] as int?) ?? 0;
  }

  /// Get count of notes in cache
  Future<int> getNotesCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM notes');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get count of drawings in cache
  Future<int> getDrawingsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM schedule_drawings');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total cache hit count for notes
  Future<int> getNotesHitCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(cache_hit_count) as total_hits
      FROM notes
    ''');
    return (result.first['total_hits'] as int?) ?? 0;
  }

  /// Get total cache hit count for drawings
  Future<int> getDrawingsHitCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(cache_hit_count) as total_hits
      FROM schedule_drawings
    ''');
    return (result.first['total_hits'] as int?) ?? 0;
  }

  /// Count expired notes based on cache duration
  Future<int> countExpiredNotes(int durationDays) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: durationDays))
        .millisecondsSinceEpoch ~/
        1000;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM notes
      WHERE cached_at < ?
    ''', [cutoffTime]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Count expired drawings based on cache duration
  Future<int> countExpiredDrawings(int durationDays) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: durationDays))
        .millisecondsSinceEpoch ~/
        1000;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM schedule_drawings
      WHERE cached_at < ?
    ''', [cutoffTime]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete expired notes from cache
  Future<int> deleteExpiredNotes(int durationDays) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: durationDays))
        .millisecondsSinceEpoch ~/
        1000;
    return await db.delete(
      'notes',
      where: 'cached_at < ?',
      whereArgs: [cutoffTime],
    );
  }

  /// Delete expired drawings from cache
  Future<int> deleteExpiredDrawings(int durationDays) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: durationDays))
        .millisecondsSinceEpoch ~/
        1000;
    return await db.delete(
      'schedule_drawings',
      where: 'cached_at < ?',
      whereArgs: [cutoffTime],
    );
  }

  /// Delete least recently used notes (by hit count) to meet size target
  /// Returns number of entries deleted
  Future<int> deleteLRUNotes(int targetCount) async {
    if (targetCount <= 0) return 0;

    final db = await database;
    // Get IDs of least-used notes
    final result = await db.rawQuery('''
      SELECT id FROM notes
      ORDER BY cache_hit_count ASC, cached_at ASC
      LIMIT ?
    ''', [targetCount]);

    if (result.isEmpty) return 0;

    final idsToDelete = result.map((row) => row['id'] as int).toList();

    // Delete them
    return await db.delete(
      'notes',
      where: 'id IN (${idsToDelete.join(',')})',
    );
  }

  /// Delete least recently used drawings (by hit count) to meet size target
  /// Returns number of entries deleted
  Future<int> deleteLRUDrawings(int targetCount) async {
    if (targetCount <= 0) return 0;

    final db = await database;
    // Get IDs of least-used drawings
    final result = await db.rawQuery('''
      SELECT id FROM schedule_drawings
      ORDER BY cache_hit_count ASC, cached_at ASC
      LIMIT ?
    ''', [targetCount]);

    if (result.isEmpty) return 0;

    final idsToDelete = result.map((row) => row['id'] as int).toList();

    // Delete them
    return await db.delete(
      'schedule_drawings',
      where: 'id IN (${idsToDelete.join(',')})',
    );
  }

  /// Clear all notes from cache
  Future<void> clearNotesCache() async {
    final db = await database;
    await db.delete('notes');
  }

  /// Clear all drawings from cache
  Future<void> clearDrawingsCache() async {
    final db = await database;
    await db.delete('schedule_drawings');
  }
}
