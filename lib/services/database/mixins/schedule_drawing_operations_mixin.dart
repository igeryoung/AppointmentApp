import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../models/schedule_drawing.dart';

/// Schedule drawing database operations
mixin ScheduleDrawingOperationsMixin {
  Future<Database> get database;

  Future<ScheduleDrawing?> getDrawing(String bookUuid, DateTime date, int viewMode) async {
    final db = await database;
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final maps = await db.query(
      'schedule_drawings',
      where: 'book_uuid = ? AND date = ? AND view_mode = ?',
      whereArgs: [bookUuid, normalizedDate.millisecondsSinceEpoch ~/ 1000, viewMode],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ScheduleDrawing.fromMap(maps.first);
  }

  Future<ScheduleDrawing> saveDrawing(ScheduleDrawing drawing) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final normalizedDate = DateTime(drawing.date.year, drawing.date.month, drawing.date.day);
    final updated = drawing.copyWith(updatedAt: now, version: drawing.version + 1);

    final data = {
      'book_uuid': drawing.bookUuid,
      'date': normalizedDate.millisecondsSinceEpoch ~/ 1000,
      'view_mode': drawing.viewMode,
      'strokes_data': jsonEncode(drawing.strokes.map((s) => s.toMap()).toList()),
      'created_at': updated.createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updated.updatedAt.millisecondsSinceEpoch ~/ 1000,
      'version': updated.version,
      'is_dirty': 1,
    };

    await db.insert('schedule_drawings', data, conflictAlgorithm: ConflictAlgorithm.replace);
    return updated;
  }

  Future<void> deleteDrawing(String bookUuid, DateTime date, int viewMode) async {
    final db = await database;
    final normalizedDate = DateTime(date.year, date.month, date.day);
    await db.delete(
      'schedule_drawings',
      where: 'book_uuid = ? AND date = ? AND view_mode = ?',
      whereArgs: [bookUuid, normalizedDate.millisecondsSinceEpoch ~/ 1000, viewMode],
    );
  }

  Future<List<ScheduleDrawing>> getDirtyDrawings() async {
    final db = await database;
    final maps = await db.query('schedule_drawings', where: 'is_dirty = 1');
    return maps.map((m) => ScheduleDrawing.fromMap(m)).toList();
  }

  Future<void> markDrawingsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.execute('UPDATE schedule_drawings SET is_dirty = 0 WHERE id IN ($placeholders)', ids);
  }
}
