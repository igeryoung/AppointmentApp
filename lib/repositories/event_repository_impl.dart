import 'package:sqflite/sqflite.dart';
import '../models/event.dart';
import '../models/note.dart';
import 'event_repository.dart';

/// Implementation of EventRepository using SQLite
class EventRepositoryImpl implements IEventRepository {
  final Future<Database> Function() _getDatabaseFn;
  final Future<Note?> Function(int eventId) _getCachedNoteFn;

  EventRepositoryImpl(this._getDatabaseFn, this._getCachedNoteFn);

  @override
  Future<List<Event>> getAll() async {
    final db = await _getDatabaseFn();
    final maps = await db.query('events', orderBy: 'start_time ASC');
    return maps.map((map) => Event.fromMap(map)).toList();
  }

  @override
  Future<Event?> getById(int id) async {
    final db = await _getDatabaseFn();
    final maps = await db.query('events', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Event.fromMap(maps.first);
  }

  @override
  Future<List<Event>> getByBookId(int bookId) async {
    final db = await _getDatabaseFn();
    final maps = await db.query(
      'events',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'start_time ASC',
    );
    return maps.map((map) => Event.fromMap(map)).toList();
  }

  @override
  Future<List<Event>> getByDateRange(
    int bookId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await _getDatabaseFn();
    final maps = await db.query(
      'events',
      where: 'book_id = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        bookId,
        startDate.millisecondsSinceEpoch ~/ 1000,
        endDate.millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'start_time ASC',
    );
    return maps.map((map) => Event.fromMap(map)).toList();
  }

  /// Get events for Day view
  Future<List<Event>> getEventsByDay(int bookId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return getByDateRange(bookId, startOfDay, endOfDay);
  }

  /// Get events for 3-Day view
  Future<List<Event>> getEventsBy3Days(int bookId, DateTime startDate) async {
    final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endOfPeriod = startOfDay.add(const Duration(days: 3));
    return getByDateRange(bookId, startOfDay, endOfPeriod);
  }

  /// Get events for Week view
  Future<List<Event>> getEventsByWeek(int bookId, DateTime weekStart) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return getByDateRange(bookId, weekStart, weekEnd);
  }

  @override
  Future<Event> create(Event event) async {
    final db = await _getDatabaseFn();
    final now = DateTime.now();

    final eventToCreate = event.copyWith(createdAt: now, updatedAt: now);
    final id = await db.insert('events', eventToCreate.toMap());

    // Create associated empty note
    await db.insert('notes', {
      'event_id': id,
      'strokes_data': '[]',
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
      'updated_at': now.millisecondsSinceEpoch ~/ 1000,
    });

    return eventToCreate.copyWith(id: id);
  }

  @override
  Future<Event> update(Event event) async {
    if (event.id == null) throw ArgumentError('Event ID cannot be null');

    final db = await _getDatabaseFn();
    final now = DateTime.now();
    final updatedEvent = event.copyWith(updatedAt: now);
    final updateData = updatedEvent.toMap();
    updateData.remove('id');

    final updatedRows = await db.update(
      'events',
      updateData,
      where: 'id = ?',
      whereArgs: [event.id],
    );

    if (updatedRows == 0) throw Exception('Event not found');
    return updatedEvent;
  }

  @override
  Future<void> delete(int id) async {
    final db = await _getDatabaseFn();
    final deletedRows = await db.delete('events', where: 'id = ?', whereArgs: [id]);
    if (deletedRows == 0) throw Exception('Event not found');
  }

  /// Soft remove an event with a reason
  @override
  Future<Event> removeEvent(int eventId, String reason) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Removal reason cannot be empty');
    }

    final db = await _getDatabaseFn();

    // Get the current event
    final maps = await db.query('events', where: 'id = ?', whereArgs: [eventId], limit: 1);
    if (maps.isEmpty) throw Exception('Event not found');

    final event = Event.fromMap(maps.first);
    if (event.isRemoved) throw Exception('Event is already removed');

    // Update the event with removal information
    final updatedEvent = event.copyWith(
      isRemoved: true,
      removalReason: reason.trim(),
      updatedAt: DateTime.now(),
    );

    final updateData = updatedEvent.toMap();
    updateData.remove('id');

    await db.update(
      'events',
      updateData,
      where: 'id = ?',
      whereArgs: [eventId],
    );

    return updatedEvent;
  }

  /// Change event time - creates new event and soft deletes original
  Future<Event> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  ) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Time change reason cannot be empty');
    }
    if (originalEvent.id == null) {
      throw ArgumentError('Original event must have an ID');
    }

    final db = await _getDatabaseFn();
    final now = DateTime.now();

    // First, soft remove the original event
    await removeEvent(originalEvent.id!, reason.trim());

    // Create a new event with the new time but same metadata
    final newEvent = originalEvent.copyWith(
      id: null, // Will be auto-generated
      startTime: newStartTime,
      endTime: newEndTime,
      originalEventId: originalEvent.id,
      isRemoved: false,
      removalReason: null,
      updatedAt: now,
    );

    // Insert the new event (remove id to let DB auto-generate)
    final newEventMap = newEvent.toMap();
    newEventMap.remove('id');
    newEventMap['is_dirty'] = 1; // Mark as dirty to trigger server sync
    final newEventId = await db.insert('events', newEventMap);
    final createdEvent = newEvent.copyWith(id: newEventId);

    // Update the original event to point to the new event
    await db.update(
      'events',
      {'new_event_id': newEventId},
      where: 'id = ?',
      whereArgs: [originalEvent.id],
    );

    // Copy the note from original event to new event if it exists
    final originalNote = await _getCachedNoteFn(originalEvent.id!);
    if (originalNote != null) {
      // Directly insert a new note for the new event
      final newNoteMap = originalNote.toMap();
      newNoteMap['event_id'] = newEventId;
      newNoteMap['updated_at'] = now.millisecondsSinceEpoch ~/ 1000;
      newNoteMap['is_dirty'] = 1; // Mark as dirty to trigger server sync
      newNoteMap.remove('id'); // Let DB auto-generate the ID

      await db.insert('notes', newNoteMap);
    } else {
      // If no original note exists, create an empty one for the new event
      await db.insert('notes', {
        'event_id': newEventId,
        'strokes_data': '[]',
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'updated_at': now.millisecondsSinceEpoch ~/ 1000,
        'is_dirty': 1, // Mark as dirty to trigger server sync
      });
    }

    return createdEvent;
  }

  /// Get event count by book
  Future<int> getEventCountByBook(int bookId) async {
    final db = await _getDatabaseFn();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM events WHERE book_id = ?',
      [bookId],
    );
    return result.first['count'] as int;
  }
}
