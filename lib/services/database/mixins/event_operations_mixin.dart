import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../models/event.dart';

class ChangeEventTimeResult {
  final Event newEvent;
  final Event oldEvent;
  ChangeEventTimeResult({required this.newEvent, required this.oldEvent});
}

/// Event database operations
mixin EventOperationsMixin {
  Future<Database> get database;
  static const _uuid = Uuid();

  Future<List<Event>> getEventsByDay(String bookUuid, DateTime date) async {
    final db = await database;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final maps = await db.query(
      'events',
      where: 'book_uuid = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [bookUuid, start.millisecondsSinceEpoch ~/ 1000, end.millisecondsSinceEpoch ~/ 1000],
      orderBy: 'start_time ASC',
    );
    return maps.map((m) => Event.fromMap(m)).toList();
  }

  Future<List<Event>> getEventsBy3Days(String bookUuid, DateTime startDate) async {
    final db = await database;
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = start.add(const Duration(days: 3));
    final maps = await db.query(
      'events',
      where: 'book_uuid = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [bookUuid, start.millisecondsSinceEpoch ~/ 1000, end.millisecondsSinceEpoch ~/ 1000],
      orderBy: 'start_time ASC',
    );
    return maps.map((m) => Event.fromMap(m)).toList();
  }

  Future<List<Event>> getEventsByWeek(String bookUuid, DateTime weekStart) async {
    final db = await database;
    final end = weekStart.add(const Duration(days: 7));
    final maps = await db.query(
      'events',
      where: 'book_uuid = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [bookUuid, weekStart.millisecondsSinceEpoch ~/ 1000, end.millisecondsSinceEpoch ~/ 1000],
      orderBy: 'start_time ASC',
    );
    return maps.map((m) => Event.fromMap(m)).toList();
  }

  Future<List<Event>> getAllEventsByBook(String bookUuid) async {
    final db = await database;
    final maps = await db.query('events', where: 'book_uuid = ?', whereArgs: [bookUuid], orderBy: 'start_time ASC');
    return maps.map((m) => Event.fromMap(m)).toList();
  }

  Future<List<Event>> getEventsByRecordUuid(String recordUuid) async {
    final db = await database;
    final maps = await db.query(
      'events',
      where: 'record_uuid = ? AND is_removed = 0',
      whereArgs: [recordUuid],
      orderBy: 'start_time ASC',
    );
    return maps.map((m) => Event.fromMap(m)).toList();
  }

  Future<Event?> getEventById(String id) async {
    final db = await database;
    final maps = await db.query('events', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Event.fromMap(maps.first);
  }

  Future<Event> createEvent(Event event) async {
    if (event.recordUuid.isEmpty) {
      throw ArgumentError('Event must have a record_uuid');
    }
    final db = await database;
    final now = DateTime.now();
    final id = event.id ?? _uuid.v4();
    final created = event.copyWith(id: id, createdAt: now, updatedAt: now);
    await db.insert('events', {...created.toMap(), 'is_dirty': 1});
    return created;
  }

  Future<Event> updateEvent(Event event) async {
    if (event.id == null) throw ArgumentError('Event ID cannot be null');
    final db = await database;
    final now = DateTime.now();
    final updated = event.copyWith(updatedAt: now);
    final data = updated.toMap();
    data.remove('id');
    data['is_dirty'] = 1;
    final rows = await db.update('events', data, where: 'id = ?', whereArgs: [event.id]);
    if (rows == 0) throw Exception('Event not found');
    return updated;
  }

  Future<void> deleteEvent(String id) async {
    final db = await database;
    final rows = await db.delete('events', where: 'id = ?', whereArgs: [id]);
    if (rows == 0) throw Exception('Event not found');
  }

  Future<Event> removeEvent(String eventId, String reason) async {
    if (reason.trim().isEmpty) throw ArgumentError('Removal reason cannot be empty');
    final db = await database;
    final maps = await db.query('events', where: 'id = ?', whereArgs: [eventId], limit: 1);
    if (maps.isEmpty) throw Exception('Event not found');
    final event = Event.fromMap(maps.first);
    if (event.isRemoved) throw Exception('Event is already removed');

    final updated = event.copyWith(isRemoved: true, removalReason: reason.trim(), updatedAt: DateTime.now());
    final data = updated.toMap();
    data['is_dirty'] = 1;
    await db.update('events', data, where: 'id = ?', whereArgs: [eventId]);
    return updated;
  }

  Future<ChangeEventTimeResult> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  ) async {
    if (reason.trim().isEmpty) throw ArgumentError('Time change reason cannot be empty');
    if (originalEvent.id == null) throw ArgumentError('Original event must have an ID');

    final db = await database;
    final now = DateTime.now();
    final removedOld = await removeEvent(originalEvent.id!, reason.trim());
    final newEventId = _uuid.v4();

    final newEvent = originalEvent.copyWith(
      id: newEventId,
      startTime: newStartTime,
      endTime: newEndTime,
      originalEventId: originalEvent.id,
      isRemoved: false,
      removalReason: null,
      updatedAt: now,
    );

    await db.insert('events', {...newEvent.toMap(), 'is_dirty': 1});
    await db.update('events', {'new_event_id': newEventId, 'is_dirty': 1}, where: 'id = ?', whereArgs: [originalEvent.id]);

    final oldMaps = await db.query('events', where: 'id = ?', whereArgs: [originalEvent.id], limit: 1);
    final finalOld = oldMaps.isNotEmpty ? Event.fromMap(oldMaps.first) : removedOld;

    return ChangeEventTimeResult(newEvent: newEvent, oldEvent: finalOld);
  }

  Future<List<Event>> getDirtyEvents() async {
    final db = await database;
    final maps = await db.query('events', where: 'is_dirty = 1');
    return maps.map((m) => Event.fromMap(m)).toList();
  }

  Future<void> markEventsSynced(List<String> eventIds) async {
    if (eventIds.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(eventIds.length, '?').join(',');
    await db.execute('UPDATE events SET is_dirty = 0 WHERE id IN ($placeholders)', eventIds);
  }

  Future<void> updateHasNoteFlag(String recordUuid, bool hasNote) async {
    final db = await database;
    await db.update('events', {'has_note': hasNote ? 1 : 0}, where: 'record_uuid = ?', whereArgs: [recordUuid]);
  }
}
