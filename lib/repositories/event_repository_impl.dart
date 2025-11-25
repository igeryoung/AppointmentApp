import 'package:sqflite/sqflite.dart';
import '../models/event.dart';
import '../models/note.dart';
import 'event_repository.dart';
import 'base_repository.dart';

/// Implementation of EventRepository using SQLite
class EventRepositoryImpl extends BaseRepository<Event, int> implements IEventRepository {
  final Future<Note?> Function(int eventId) _getCachedNoteFn;

  EventRepositoryImpl(Future<Database> Function() getDatabaseFn, this._getCachedNoteFn)
      : super(getDatabaseFn);

  @override
  String get tableName => 'events';

  @override
  Event fromMap(Map<String, dynamic> map) => Event.fromMap(map);

  @override
  Map<String, dynamic> toMap(Event entity) => entity.toMap();

  @override
  Future<List<Event>> getAll() => queryAll(orderBy: 'start_time ASC');

  @override
  Future<Event?> getById(int id) => super.getById(id);

  @override
  Future<List<Event>> getByBookId(String bookUuid) {
    return query(
      where: 'book_uuid = ?',
      whereArgs: [bookUuid],
      orderBy: 'start_time ASC',
    );
  }

  @override
  Future<List<Event>> getByDateRange(
    String bookUuid,
    DateTime startDate,
    DateTime endDate,
  ) {
    return query(
      where: 'book_uuid = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        bookUuid,
        startDate.millisecondsSinceEpoch ~/ 1000,
        endDate.millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'start_time ASC',
    );
  }

  /// Get events for Day view
  Future<List<Event>> getEventsByDay(String bookUuid, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return getByDateRange(bookUuid, startOfDay, endOfDay);
  }

  /// Get events for 3-Day view
  Future<List<Event>> getEventsBy3Days(String bookUuid, DateTime startDate) async {
    final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endOfPeriod = startOfDay.add(const Duration(days: 3));
    return getByDateRange(bookUuid, startOfDay, endOfPeriod);
  }

  /// Get events for Week view
  Future<List<Event>> getEventsByWeek(String bookUuid, DateTime weekStart) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return getByDateRange(bookUuid, weekStart, weekEnd);
  }

  @override
  Future<Event> create(Event event) async {
    final db = await getDatabaseFn();
    final now = DateTime.now();

    // Mark as dirty and set version to 1 for new events
    final eventToCreate = event.copyWith(
      createdAt: now,
      updatedAt: now,
      version: 1,
      isDirty: true,
    );
    final id = await insert(eventToCreate.toMap());

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

    final now = DateTime.now();
    // Increment version and mark as dirty for updates
    final updatedEvent = event.copyWith(
      updatedAt: now,
      version: event.version + 1,
      isDirty: true,
    );
    final updateData = toMap(updatedEvent);
    updateData.remove('id');

    final updatedRows = await updateById(event.id!, updateData);
    if (updatedRows == 0) throw Exception('Event not found');

    return updatedEvent;
  }

  @override
  Future<void> delete(int id) async {
    // Perform soft delete: mark as deleted and dirty for sync
    final db = await getDatabaseFn();
    final event = await getById(id);
    if (event == null) throw Exception('Event not found');

    await db.update(
      'events',
      {
        'is_deleted': 1,
        'is_dirty': 1,
        'version': event.version + 1,
        'updated_at': (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft remove an event with a reason
  @override
  Future<Event> removeEvent(int eventId, String reason) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Removal reason cannot be empty');
    }

    final db = await getDatabaseFn();

    // Get the current event
    final event = await getById(eventId);
    if (event == null) throw Exception('Event not found');
    if (event.isRemoved) throw Exception('Event is already removed');

    // Update the event with removal information
    final updatedEvent = event.copyWith(
      isRemoved: true,
      removalReason: reason.trim(),
      updatedAt: DateTime.now(),
    );

    final updateData = toMap(updatedEvent);
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
  @override
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

    final db = await getDatabaseFn();
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
    final newEventMap = toMap(newEvent);
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
  Future<int> getEventCountByBook(String bookUuid) async {
    final db = await getDatabaseFn();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM events WHERE book_uuid = ?',
      [bookUuid],
    );
    return result.first['count'] as int;
  }

  @override
  Future<List<String>> getAllNames(String bookUuid) async {
    final db = await getDatabaseFn();
    final result = await db.query(
      'events',
      columns: ['DISTINCT name'],
      where: 'book_uuid = ? AND name IS NOT NULL AND name != ""',
      whereArgs: [bookUuid],
      orderBy: 'name ASC',
    );
    return result
        .map((row) => row['name'] as String)
        .toList();
  }

  @override
  Future<List<String>> getAllRecordNumbers(String bookUuid) async {
    final db = await getDatabaseFn();
    final result = await db.query(
      'events',
      columns: ['DISTINCT record_number'],
      where: 'book_uuid = ? AND record_number IS NOT NULL AND record_number != ""',
      whereArgs: [bookUuid],
      orderBy: 'record_number ASC',
    );
    return result
        .map((row) => row['record_number'] as String)
        .toList();
  }

  @override
  Future<List<NameRecordPair>> getAllNameRecordPairs(String bookUuid) async {
    final db = await getDatabaseFn();
    final result = await db.query(
      'events',
      distinct: true,
      columns: ['name', 'record_number'],
      where: 'book_uuid = ? AND name IS NOT NULL AND name != "" AND record_number IS NOT NULL AND record_number != ""',
      whereArgs: [bookUuid],
      orderBy: 'name ASC, record_number ASC',
    );
    return result
        .map((row) => NameRecordPair(
              name: row['name'] as String,
              recordNumber: row['record_number'] as String,
            ))
        .toList();
  }

  @override
  Future<List<String>> getRecordNumbersByName(String bookUuid, String name) async {
    final db = await getDatabaseFn();
    final result = await db.query(
      'events',
      columns: ['DISTINCT record_number'],
      where: 'book_uuid = ? AND LOWER(name) = LOWER(?) AND record_number IS NOT NULL AND record_number != ""',
      whereArgs: [bookUuid, name],
      orderBy: 'record_number ASC',
    );
    return result
        .map((row) => row['record_number'] as String)
        .toList();
  }

  @override
  Future<List<Event>> searchByNameAndRecordNumber(
    String bookUuid,
    String name,
    String recordNumber,
  ) async {
    return query(
      where: 'book_uuid = ? AND name = ? AND record_number = ?',
      whereArgs: [bookUuid, name, recordNumber],
      orderBy: 'start_time DESC',
    );
  }

  // Sync-related methods

  @override
  Future<List<Event>> getDirtyEvents() async {
    return query(
      where: 'is_dirty = ?',
      whereArgs: [1],
      orderBy: 'updated_at ASC',
    );
  }

  @override
  Future<void> markEventSynced(int id, DateTime syncedAt) async {
    final db = await getDatabaseFn();
    await db.update(
      'events',
      {
        'is_dirty': 0,
        'synced_at': syncedAt.millisecondsSinceEpoch ~/ 1000,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> applyServerChange(Map<String, dynamic> changeData) async {
    final db = await getDatabaseFn();
    final id = changeData['id'] as int;

    // Check if event exists locally
    final existing = await getById(id);

    if (existing == null) {
      // Insert new event from server
      await db.insert('events', changeData);
    } else {
      // Update existing event with server data
      final updateData = Map<String, dynamic>.from(changeData);
      updateData.remove('id');
      updateData['is_dirty'] = 0; // Server data is not dirty
      await db.update(
        'events',
        updateData,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  @override
  Future<Event?> getByServerId(int serverId) async {
    return getById(serverId);
  }
}
