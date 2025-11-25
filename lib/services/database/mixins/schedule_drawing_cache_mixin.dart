import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../models/schedule_drawing.dart';

/// Mixin providing Schedule Drawing cache operations for PRDDatabaseService
mixin ScheduleDrawingCacheMixin {
  /// Subclasses must provide database access
  Future<Database> get database;

  // ===================
  // Schedule Drawing Cache Operations
  // ===================

  /// Get cached drawing for specific book, date, and view mode
  /// Automatically increments cache hit count
  ///
  /// [date] MUST be the effective date for the view:
  /// - Day view: the selected date
  /// - 3-Day view: the window start date (calculated by _get3DayWindowStart)
  /// - Week view: the week start date (calculated by _getWeekStart)
  Future<ScheduleDrawing?> getCachedDrawing(String bookUuid, DateTime date, int viewMode) async {
    final db = await database;
    final normalizedDate = DateTime(date.year, date.month, date.day);

    final maps = await db.query(
      'schedule_drawings',
      where: 'book_uuid = ? AND date = ? AND view_mode = ?',
      whereArgs: [
        bookUuid,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        viewMode,
      ],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ScheduleDrawing.fromMap(maps.first);
  }

  /// Save drawing to cache (insert or update)
  /// Updates cached_at timestamp automatically
  ///
  /// The [drawing.date] MUST be the effective date for the view:
  /// - Day view: the selected date
  /// - 3-Day view: the window start date (calculated by _get3DayWindowStart)
  /// - Week view: the week start date (calculated by _getWeekStart)
  Future<ScheduleDrawing> saveCachedDrawing(ScheduleDrawing drawing) async {
    final db = await database;
    final now = DateTime.now();
    final normalizedDate = DateTime(drawing.date.year, drawing.date.month, drawing.date.day);
    // Mark as dirty for sync
    final updatedDrawing = drawing.copyWith(
      date: normalizedDate,
      updatedAt: now,
      isDirty: true,
    );

    final drawingMap = updatedDrawing.toMap();
    // Add cache metadata
    drawingMap['cached_at'] = now.millisecondsSinceEpoch ~/ 1000;
    debugPrint('🎨 SQLite: updateScheduleDrawing called with ${updatedDrawing.strokes.length} strokes');

    try {
      // Try to update existing drawing
      // Remove id and created_at from update to avoid PRIMARY KEY constraint violation
      final updateMap = Map<String, dynamic>.from(drawingMap);
      updateMap.remove('id');
      updateMap.remove('created_at');

      final updatedRows = await db.update(
        'schedule_drawings',
        updateMap,
        where: 'book_uuid = ? AND date = ? AND view_mode = ?',
        whereArgs: [
          drawing.bookUuid,
          normalizedDate.millisecondsSinceEpoch ~/ 1000,
          drawing.viewMode,
        ],
      );

      // If no rows updated, insert new drawing
      if (updatedRows == 0) {
        debugPrint('🎨 SQLite: Inserting new schedule drawing');
        // Initialize cache_hit_count for new drawings
        drawingMap['cache_hit_count'] = 0;
        final id = await db.insert('schedule_drawings', drawingMap);
        return updatedDrawing.copyWith(id: id);
      }

      debugPrint('✅ SQLite: Schedule drawing updated successfully');
      return updatedDrawing;
    } catch (e) {
      debugPrint('❌ SQLite: Failed to save schedule drawing: $e');
      rethrow;
    }
  }

  /// Delete cached drawing
  Future<void> deleteCachedDrawing(String bookUuid, DateTime date, int viewMode) async {
    final db = await database;
    final normalizedDate = DateTime(date.year, date.month, date.day);

    await db.delete(
      'schedule_drawings',
      where: 'book_uuid = ? AND date = ? AND view_mode = ?',
      whereArgs: [
        bookUuid,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        viewMode,
      ],
    );
  }

  /// Batch get cached drawings for a date range
  /// Returns list of drawings found in cache
  Future<List<ScheduleDrawing>> batchGetCachedDrawings({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
    int? viewMode,
  }) async {
    final db = await database;
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);

    String whereClause = 'book_uuid = ? AND date >= ? AND date <= ?';
    List<dynamic> whereArgs = [
      bookUuid,
      normalizedStart.millisecondsSinceEpoch ~/ 1000,
      normalizedEnd.millisecondsSinceEpoch ~/ 1000,
    ];

    if (viewMode != null) {
      whereClause += ' AND view_mode = ?';
      whereArgs.add(viewMode);
    }

    final maps = await db.query(
      'schedule_drawings',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date ASC',
    );

    final drawings = maps.map((map) => ScheduleDrawing.fromMap(map)).toList();
    debugPrint('✅ batchGetCachedDrawings: Found ${drawings.length} drawings');
    return drawings;
  }

  /// Batch save cached drawings
  /// Updates cached_at timestamp for all drawings
  Future<void> batchSaveCachedDrawings(List<ScheduleDrawing> drawings) async {
    if (drawings.isEmpty) return;

    final db = await database;
    final batch = db.batch();
    final now = DateTime.now();
    final cachedAt = now.millisecondsSinceEpoch ~/ 1000;

    for (final drawing in drawings) {
      final normalizedDate = DateTime(drawing.date.year, drawing.date.month, drawing.date.day);
      final drawingMap = drawing.toMap();

      // Try update first
      batch.rawUpdate('''
        UPDATE schedule_drawings
        SET strokes_data = ?, updated_at = ?, cached_at = ?
        WHERE book_uuid = ? AND date = ? AND view_mode = ?
      ''', [
        drawingMap['strokes_data'],
        drawingMap['updated_at'],
        cachedAt,
        drawing.bookUuid,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        drawing.viewMode,
      ]);

      // If no rows updated, insert
      batch.rawInsert('''
        INSERT OR IGNORE INTO schedule_drawings
        (book_uuid, date, view_mode, strokes_data, created_at, updated_at, cached_at, cache_hit_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0)
      ''', [
        drawing.bookUuid,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        drawing.viewMode,
        drawingMap['strokes_data'],
        drawingMap['created_at'],
        drawingMap['updated_at'],
        cachedAt,
      ]);
    }

    await batch.commit(noResult: true);
    debugPrint('✅ batchSaveCachedDrawings: Saved ${drawings.length} drawings');
  }

  // Sync-related methods

  /// Get all drawings marked as dirty (need sync)
  Future<List<ScheduleDrawing>> getDirtyDrawings() async {
    final db = await database;
    final maps = await db.query(
      'schedule_drawings',
      where: 'is_dirty = ?',
      whereArgs: [1],
      orderBy: 'updated_at ASC',
    );

    final dirtyDrawings = maps.map((map) => ScheduleDrawing.fromMap(map)).toList();
    debugPrint('✅ getDirtyDrawings: Found ${dirtyDrawings.length} dirty drawings');
    return dirtyDrawings;
  }

  /// Mark a drawing as synced (clear dirty flag)
  Future<void> markDrawingSynced(int id, DateTime syncedAt) async {
    final db = await database;
    await db.update(
      'schedule_drawings',
      {
        'is_dirty': 0,
        'synced_at': syncedAt.millisecondsSinceEpoch ~/ 1000,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Apply server change to local database
  Future<void> applyServerDrawingChange(Map<String, dynamic> changeData) async {
    final db = await database;
    final id = changeData['id'] as int;

    // Check if drawing exists locally by id
    final existing = await db.query(
      'schedule_drawings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    final syncChangeData = Map<String, dynamic>.from(changeData);
    syncChangeData['is_dirty'] = 0; // Server data is not dirty

    if (existing.isEmpty) {
      // Insert new drawing from server
      await db.insert('schedule_drawings', syncChangeData);
    } else {
      // Update existing drawing with server data
      final updateData = Map<String, dynamic>.from(syncChangeData);
      updateData.remove('id');
      await db.update(
        'schedule_drawings',
        updateData,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }
}
