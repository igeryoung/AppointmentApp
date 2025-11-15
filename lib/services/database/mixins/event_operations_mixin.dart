import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../models/event.dart';
import '../../../models/note.dart';

/// Mixin providing Event CRUD operations for PRDDatabaseService
mixin EventOperationsMixin {
  /// Subclasses must provide database access
  Future<Database> get database;

  /// Required for changeEventTime - must be provided by main class or another mixin
  Future<Note?> getCachedNote(int eventId);

  // ===================
  // Event Operations
  // ===================

  /// Get events for Day view
  ///
  /// [date] should be normalized to midnight (start of day)
  Future<List<Event>> getEventsByDay(int bookId, DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'events',
      where: 'book_id = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        bookId,
        startOfDay.millisecondsSinceEpoch ~/ 1000,
        endOfDay.millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => Event.fromMap(map)).toList();
  }

  /// Get events for 3-Day view
  ///
  /// [startDate] MUST be the 3-day window start date (calculated by _get3DayWindowStart)
  /// to ensure events are loaded for the correct window being displayed
  Future<List<Event>> getEventsBy3Days(int bookId, DateTime startDate) async {
    final db = await database;
    final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endOfPeriod = startOfDay.add(const Duration(days: 3));

    final maps = await db.query(
      'events',
      where: 'book_id = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        bookId,
        startOfDay.millisecondsSinceEpoch ~/ 1000,
        endOfPeriod.millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => Event.fromMap(map)).toList();
  }

  /// Get events for Week view
  ///
  /// [weekStart] MUST be the week start date (Monday, calculated by _getWeekStart)
  /// to ensure events are loaded for the correct week being displayed
  Future<List<Event>> getEventsByWeek(int bookId, DateTime weekStart) async {
    final db = await database;
    final weekEnd = weekStart.add(const Duration(days: 7));

    final maps = await db.query(
      'events',
      where: 'book_id = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        bookId,
        weekStart.millisecondsSinceEpoch ~/ 1000,
        weekEnd.millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => Event.fromMap(map)).toList();
  }

  /// Get all events for a book (regardless of date)
  Future<List<Event>> getAllEventsByBook(int bookId) async {
    final db = await database;

    final maps = await db.query(
      'events',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => Event.fromMap(map)).toList();
  }

  Future<Event?> getEventById(int id) async {
    final db = await database;
    final maps = await db.query('events', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Event.fromMap(maps.first);
  }

  Future<Event> createEvent(Event event) async {
    final db = await database;
    final now = DateTime.now();

    final eventToCreate = event.copyWith(createdAt: now, updatedAt: now);
    final id = await db.insert('events', eventToCreate.toMap());

    // Create associated empty note with one empty page
    await db.insert('notes', {
      'event_id': id,
      'pages_data': '[[]]', // Start with one empty page
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
      'updated_at': now.millisecondsSinceEpoch ~/ 1000,
    });

    return eventToCreate.copyWith(id: id);
  }

  Future<Event> updateEvent(Event event) async {
    if (event.id == null) throw ArgumentError('Event ID cannot be null');

    final db = await database;
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

  Future<void> deleteEvent(int id) async {
    final db = await database;
    final deletedRows = await db.delete('events', where: 'id = ?', whereArgs: [id]);
    if (deletedRows == 0) throw Exception('Event not found');
  }

  /// Soft remove an event with a reason
  Future<Event> removeEvent(int eventId, String reason) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Removal reason cannot be empty');
    }

    final db = await database;

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

    final updatedRows = await db.update(
      'events',
      updatedEvent.toMap(),
      where: 'id = ?',
      whereArgs: [eventId],
    );

    if (updatedRows == 0) throw Exception('Failed to remove event');
    return updatedEvent;
  }

  /// Change event time while preserving metadata and notes
  Future<Event> changeEventTime(Event originalEvent, DateTime newStartTime, DateTime? newEndTime, String reason) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Time change reason cannot be empty');
    }
    if (originalEvent.id == null) {
      throw ArgumentError('Original event must have an ID');
    }

    final db = await database;
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
    final originalNote = await getCachedNote(originalEvent.id!);
    if (originalNote != null) {
      // Directly insert a new note for the new event (don't use updateNote)
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
        'pages_data': '[[]]',
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'updated_at': now.millisecondsSinceEpoch ~/ 1000,
        'is_dirty': 1, // Mark as dirty to trigger server sync
      });
    }

    return createdEvent;
  }

  Future<List<Event>> searchByNameAndRecordNumber(
    int bookId,
    String name,
    String recordNumber,
  ) async {
    final db = await database;
    final maps = await db.query(
      'events',
      where: 'book_id = ? AND name = ? AND record_number = ?',
      whereArgs: [bookId, name, recordNumber],
      orderBy: 'start_time ASC',
    );
    return maps.map((map) => Event.fromMap(map)).toList();
  }
}
