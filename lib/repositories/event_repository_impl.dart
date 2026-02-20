import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/event.dart';
import '../repositories/device_repository.dart';
import '../services/api_client.dart';
import '../services/database/mixins/event_operations_mixin.dart';
import 'event_repository.dart';
import 'base_repository.dart';

/// Implementation of EventRepository using SQLite
class EventRepositoryImpl extends BaseRepository<Event, String>
    implements IEventRepository {
  final _uuid = const Uuid();
  final ApiClient? _apiClient;
  final IDeviceRepository? _deviceRepository;

  EventRepositoryImpl(
    Future<Database> Function() getDatabaseFn, {
    ApiClient? apiClient,
    IDeviceRepository? deviceRepository,
  }) : _apiClient = apiClient,
       _deviceRepository = deviceRepository,
       super(getDatabaseFn);

  @override
  String get tableName => 'events';

  @override
  Event fromMap(Map<String, dynamic> map) => Event.fromMap(map);

  @override
  Map<String, dynamic> toMap(Event entity) => entity.toMap();

  @override
  Future<List<Event>> getAll() => queryAll(orderBy: 'start_time ASC');

  @override
  Future<Event?> getById(String id) => super.getById(id);

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
  Future<List<Event>> getEventsBy3Days(
    String bookUuid,
    DateTime startDate,
  ) async {
    final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endOfPeriod = startOfDay.add(const Duration(days: 3));
    return getByDateRange(bookUuid, startOfDay, endOfPeriod);
  }

  /// Get events for Week view
  Future<List<Event>> getEventsByWeek(
    String bookUuid,
    DateTime weekStart,
  ) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return getByDateRange(bookUuid, weekStart, weekEnd);
  }

  @override
  Future<Event> create(Event event) async {
    final now = DateTime.now().toUtc();

    // Set version to 1 for new events
    final eventToCreate = event.copyWith(
      createdAt: now,
      updatedAt: now,
      version: 1,
    );
    final db = await getDatabaseFn();
    await db.insert('events', eventToCreate.toMap());

    // Note: Notes are managed separately via records, not created with events

    return eventToCreate;
  }

  @override
  Future<Event> update(Event event) async {
    if (event.id == null) throw ArgumentError('Event ID cannot be null');

    final now = DateTime.now();
    // Increment version for updates
    final updatedEvent = event.copyWith(
      updatedAt: now,
      version: event.version + 1,
    );
    final updateData = toMap(updatedEvent);
    updateData.remove('id');

    final updatedRows = await updateById(event.id!, updateData);
    if (updatedRows == 0) throw Exception('Event not found');

    return updatedEvent;
  }

  @override
  Future<void> delete(String id) async {
    final db = await getDatabaseFn();
    final deletedRows = await db.delete(
      'events',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deletedRows == 0) throw Exception('Event not found');
  }

  /// Soft remove an event with a reason
  @override
  Future<Event> removeEvent(String eventId, String reason) async {
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
  /// Returns both the new event and the old event (marked as removed)
  @override
  Future<ChangeEventTimeResult> changeEventTime(
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

    // First, soft remove the original event and get the updated version
    final removedOldEvent = await removeEvent(originalEvent.id!, reason.trim());

    // Generate UUID for new event
    final newEventId = _uuid.v4();

    // Create a new event with the new time but same metadata
    final newEvent = originalEvent.copyWith(
      id: newEventId,
      startTime: newStartTime,
      endTime: newEndTime,
      originalEventId: originalEvent.id,
      isRemoved: false,
      removalReason: null,
      updatedAt: now,
    );

    // Insert the new event
    final newEventMap = toMap(newEvent);
    await db.insert('events', newEventMap);
    final createdEvent = newEvent;

    // Update the original event to point to the new event
    await db.update(
      'events',
      {'new_event_id': newEventId},
      where: 'id = ?',
      whereArgs: [originalEvent.id],
    );

    // Get the final state of old event (with new_event_id set)
    final oldEventMaps = await db.query(
      'events',
      where: 'id = ?',
      whereArgs: [originalEvent.id],
      limit: 1,
    );
    final finalOldEvent = oldEventMaps.isNotEmpty
        ? Event.fromMap(oldEventMaps.first)
        : removedOldEvent;

    // Note: Notes are managed separately via records, not copied with events.
    // The new event shares the same record_uuid, so it accesses the same note.

    return ChangeEventTimeResult(
      newEvent: createdEvent,
      oldEvent: finalOldEvent,
    );
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
    final serverEvents = await _fetchAllEventsFromServer(bookUuid);
    if (serverEvents != null) {
      final names = serverEvents
          .map((event) => event.title.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      names.sort();
      return names;
    }

    final db = await getDatabaseFn();
    final result = await db.rawQuery(
      '''
      SELECT DISTINCT r.name
      FROM events e
      INNER JOIN records r ON e.record_uuid = r.record_uuid
      WHERE e.book_uuid = ? AND r.name IS NOT NULL AND r.name != ''
      ORDER BY r.name ASC
    ''',
      [bookUuid],
    );
    return result.map((row) => row['name'] as String).toList();
  }

  @override
  Future<List<String>> getAllRecordNumbers(String bookUuid) async {
    final db = await getDatabaseFn();
    final result = await db.query(
      'events',
      columns: ['DISTINCT record_number'],
      where:
          'book_uuid = ? AND record_number IS NOT NULL AND record_number != ""',
      whereArgs: [bookUuid],
      orderBy: 'record_number ASC',
    );
    return result.map((row) => row['record_number'] as String).toList();
  }

  @override
  Future<List<NameRecordPair>> getAllNameRecordPairs(String bookUuid) async {
    final serverEvents = await _fetchAllEventsFromServer(bookUuid);
    if (serverEvents != null) {
      final pairMap = <String, NameRecordPair>{};
      for (final event in serverEvents) {
        final name = event.title.trim();
        final recordNumber = event.recordNumber.trim();
        if (name.isEmpty || recordNumber.isEmpty) continue;
        pairMap['$name::$recordNumber'] = NameRecordPair(
          name: name,
          recordNumber: recordNumber,
        );
      }

      final pairs = pairMap.values.toList()
        ..sort((a, b) {
          final nameCompare = a.name.compareTo(b.name);
          if (nameCompare != 0) return nameCompare;
          return a.recordNumber.compareTo(b.recordNumber);
        });
      return pairs;
    }

    final db = await getDatabaseFn();
    final result = await db.rawQuery(
      '''
      SELECT DISTINCT r.name AS name, e.record_number AS record_number
      FROM events e
      INNER JOIN records r ON e.record_uuid = r.record_uuid
      WHERE e.book_uuid = ?
        AND r.name IS NOT NULL AND r.name != ''
        AND e.record_number IS NOT NULL AND e.record_number != ''
      ORDER BY r.name ASC, e.record_number ASC
    ''',
      [bookUuid],
    );
    return result
        .map(
          (row) => NameRecordPair(
            name: row['name'] as String,
            recordNumber: row['record_number'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<List<String>> getRecordNumbersByName(
    String bookUuid,
    String name,
  ) async {
    final serverEvents = await _fetchAllEventsFromServer(bookUuid);
    if (serverEvents != null) {
      final normalizedName = name.trim().toLowerCase();
      final recordNumbers = serverEvents
          .where(
            (event) =>
                event.title.trim().toLowerCase().contains(normalizedName),
          )
          .map((event) => event.recordNumber.trim())
          .where((recordNumber) => recordNumber.isNotEmpty)
          .toSet()
          .toList();
      recordNumbers.sort();
      return recordNumbers;
    }

    final db = await getDatabaseFn();
    final result = await db.rawQuery(
      '''
      SELECT DISTINCT e.record_number
      FROM events e
      INNER JOIN records r ON e.record_uuid = r.record_uuid
      WHERE e.book_uuid = ?
        AND LOWER(r.name) = LOWER(?)
        AND e.record_number IS NOT NULL AND e.record_number != ''
      ORDER BY e.record_number ASC
    ''',
      [bookUuid, name],
    );
    return result.map((row) => row['record_number'] as String).toList();
  }

  @override
  Future<List<Event>> searchByNameAndRecordNumber(
    String bookUuid,
    String name,
    String recordNumber,
  ) async {
    final serverEvents = await _fetchAllEventsFromServer(bookUuid);
    if (serverEvents != null) {
      final normalizedName = name.trim().toLowerCase();
      final normalizedRecordNumber = recordNumber.trim();
      final matched =
          serverEvents
              .where(
                (event) =>
                    event.title.trim().toLowerCase().contains(normalizedName) &&
                    event.recordNumber.trim() == normalizedRecordNumber,
              )
              .toList()
            ..sort((a, b) => b.startTime.compareTo(a.startTime));
      return matched;
    }

    final db = await getDatabaseFn();
    final result = await db.rawQuery(
      '''
      SELECT e.*
      FROM events e
      INNER JOIN records r ON e.record_uuid = r.record_uuid
      WHERE e.book_uuid = ? AND LOWER(r.name) = LOWER(?) AND e.record_number = ?
      ORDER BY e.start_time DESC
    ''',
      [bookUuid, name, recordNumber],
    );
    return result.map((row) => Event.fromMap(row)).toList();
  }

  // Sync-related methods

  @override
  Future<void> applyServerChange(Map<String, dynamic> changeData) async {
    final db = await getDatabaseFn();
    final id = changeData['id'] as String;

    // Check if event exists locally
    final existing = await getById(id);

    if (existing == null) {
      // Insert new event from server
      await db.insert('events', changeData);
    } else {
      // Update existing event with server data
      final updateData = Map<String, dynamic>.from(changeData);
      updateData.remove('id');
      await db.update('events', updateData, where: 'id = ?', whereArgs: [id]);
    }
  }

  @override
  Future<Event?> getByServerId(String serverId) async {
    return getById(serverId);
  }

  Future<List<Event>?> _fetchAllEventsFromServer(String bookUuid) async {
    final apiClient = _apiClient;
    final deviceRepository = _deviceRepository;
    if (apiClient == null || deviceRepository == null) {
      return null;
    }

    final credentials = await deviceRepository.getCredentials();
    if (credentials == null) {
      return null;
    }

    final nowUtc = DateTime.now().toUtc();
    final serverEvents = await apiClient.fetchEventsByDateRange(
      bookUuid: bookUuid,
      startDate: nowUtc.subtract(const Duration(days: 365 * 50)),
      endDate: nowUtc.add(const Duration(days: 365 * 50)),
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
    );

    return serverEvents
        .map((event) => Event.fromServerResponse(event))
        .toList();
  }
}
