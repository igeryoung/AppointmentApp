import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/schedule_drawing.dart';
import 'drawing_repository.dart';

/// Implementation of DrawingRepository using SQLite
/// Handles local caching of schedule drawings with dirty flag tracking
class DrawingRepositoryImpl implements IDrawingRepository {
  final Future<Database> Function() _getDatabaseFn;

  DrawingRepositoryImpl(this._getDatabaseFn);

  @override
  Future<ScheduleDrawing?> getCached(int bookId, DateTime date) async {
    // Default to 3-day view (only supported mode)
    return getCachedWithViewMode(bookId, date, ScheduleDrawing.VIEW_MODE_3DAY);
  }

  /// Get cached drawing with specific view mode
  Future<ScheduleDrawing?> getCachedWithViewMode(int bookId, DateTime date, int viewMode) async {
    final db = await _getDatabaseFn();
    final normalizedDate = DateTime(date.year, date.month, date.day);

    final maps = await db.query(
      'schedule_drawings',
      where: 'book_id = ? AND date = ? AND view_mode = ?',
      whereArgs: [
        bookId,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        viewMode,
      ],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ScheduleDrawing.fromMap(maps.first);
  }

  @override
  Future<void> saveToCache(ScheduleDrawing drawing, {required bool isDirty}) async {
    final db = await _getDatabaseFn();
    final now = DateTime.now();
    final normalizedDate = DateTime(drawing.date.year, drawing.date.month, drawing.date.day);
    final updatedDrawing = drawing.copyWith(
      date: normalizedDate,
      updatedAt: now,
    );

    final drawingMap = updatedDrawing.toMap();
    drawingMap['cached_at'] = now.millisecondsSinceEpoch ~/ 1000;
    drawingMap['is_dirty'] = isDirty ? 1 : 0;

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
        where: 'book_id = ? AND date = ? AND view_mode = ?',
        whereArgs: [
          drawing.bookId,
          normalizedDate.millisecondsSinceEpoch ~/ 1000,
          drawing.viewMode,
        ],
      );

      // If no rows updated, insert new drawing
      if (updatedRows == 0) {
        debugPrint('🎨 SQLite: Inserting new schedule drawing');
        drawingMap['cache_hit_count'] = 0;
        await db.insert('schedule_drawings', drawingMap);
      }

      debugPrint('✅ SQLite: Schedule drawing saved successfully');
    } catch (e) {
      debugPrint('❌ SQLite: Failed to save schedule drawing: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteCache(int bookId, DateTime date) async {
    // Default to 3-day view (only supported mode)
    return deleteCacheWithViewMode(bookId, date, ScheduleDrawing.VIEW_MODE_3DAY);
  }

  /// Delete cached drawing with specific view mode
  Future<void> deleteCacheWithViewMode(int bookId, DateTime date, int viewMode) async {
    final db = await _getDatabaseFn();
    final normalizedDate = DateTime(date.year, date.month, date.day);

    await db.delete(
      'schedule_drawings',
      where: 'book_id = ? AND date = ? AND view_mode = ?',
      whereArgs: [
        bookId,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        viewMode,
      ],
    );
  }

  @override
  Future<List<ScheduleDrawing>> getDirtyDrawings() async {
    final db = await _getDatabaseFn();
    final maps = await db.query(
      'schedule_drawings',
      where: 'is_dirty = ?',
      whereArgs: [1],
    );

    final dirtyDrawings = maps.map((map) => ScheduleDrawing.fromMap(map)).toList();
    debugPrint('✅ getAllDirtyDrawings: Found ${dirtyDrawings.length} dirty drawings');
    return dirtyDrawings;
  }

  @override
  Future<void> markClean(int bookId, DateTime date) async {
    // Default to 3-day view (only supported mode)
    return markCleanWithViewMode(bookId, date, ScheduleDrawing.VIEW_MODE_3DAY);
  }

  /// Mark drawing as clean with specific view mode
  Future<void> markCleanWithViewMode(int bookId, DateTime date, int viewMode) async {
    final db = await _getDatabaseFn();
    final normalizedDate = DateTime(date.year, date.month, date.day);

    await db.update(
      'schedule_drawings',
      {'is_dirty': 0},
      where: 'book_id = ? AND date = ? AND view_mode = ?',
      whereArgs: [
        bookId,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        viewMode,
      ],
    );
  }

  @override
  Future<List<ScheduleDrawing>> getAllCachedForBook(int bookId) async {
    final db = await _getDatabaseFn();
    final maps = await db.query(
      'schedule_drawings',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'date ASC',
    );

    return maps.map((map) => ScheduleDrawing.fromMap(map)).toList();
  }

  @override
  Future<List<ScheduleDrawing>> getAllCached() async {
    final db = await _getDatabaseFn();
    final maps = await db.query('schedule_drawings', orderBy: 'date ASC');
    return maps.map((map) => ScheduleDrawing.fromMap(map)).toList();
  }

  /// Batch get cached drawings for a date range
  Future<List<ScheduleDrawing>> batchGetCachedDrawings({
    required int bookId,
    required DateTime startDate,
    required DateTime endDate,
    int? viewMode,
  }) async {
    final db = await _getDatabaseFn();
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);

    String whereClause = 'book_id = ? AND date >= ? AND date <= ?';
    List<dynamic> whereArgs = [
      bookId,
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
  Future<void> batchSaveCachedDrawings(List<ScheduleDrawing> drawings) async {
    if (drawings.isEmpty) return;

    final db = await _getDatabaseFn();
    final batch = db.batch();
    final now = DateTime.now();
    final cachedAt = now.millisecondsSinceEpoch ~/ 1000;

    for (final drawing in drawings) {
      final normalizedDate = DateTime(drawing.date.year, drawing.date.month, drawing.date.day);
      final drawingMap = drawing.toMap();

      batch.rawUpdate('''
        UPDATE schedule_drawings
        SET strokes_data = ?, updated_at = ?, cached_at = ?, is_dirty = ?
        WHERE book_id = ? AND date = ? AND view_mode = ?
      ''', [
        drawingMap['strokes_data'],
        drawingMap['updated_at'],
        cachedAt,
        drawingMap['is_dirty'] ?? 0,
        drawing.bookId,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        drawing.viewMode,
      ]);

      // Also attempt insert in case drawing doesn't exist
      batch.rawInsert('''
        INSERT OR IGNORE INTO schedule_drawings
        (book_id, date, view_mode, strokes_data, created_at, updated_at, cached_at, cache_hit_count, is_dirty)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
      ''', [
        drawing.bookId,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        drawing.viewMode,
        drawingMap['strokes_data'],
        drawingMap['created_at'],
        drawingMap['updated_at'],
        cachedAt,
        drawingMap['is_dirty'] ?? 0,
      ]);
    }

    await batch.commit(noResult: true);
    debugPrint('✅ batchSaveCachedDrawings: Saved ${drawings.length} drawings');
  }

  /// Clear all drawings cache
  Future<void> clearAll() async {
    final db = await _getDatabaseFn();
    await db.delete('schedule_drawings');
  }
}
