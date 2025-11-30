import '../models/event.dart';

/// Represents a name-record number pair
class NameRecordPair {
  final String name;
  final String recordNumber;

  const NameRecordPair({
    required this.name,
    required this.recordNumber,
  });

  /// Display format: [name] - [record number]
  String get displayText => '$name - $recordNumber';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NameRecordPair &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          recordNumber == other.recordNumber;

  @override
  int get hashCode => name.hashCode ^ recordNumber.hashCode;
}

/// Repository interface for Event entity operations
/// Defines the contract for event data access
abstract class IEventRepository {
  /// Retrieve all events
  Future<List<Event>> getAll();

  /// Retrieve a single event by its ID
  /// Returns null if event not found
  Future<Event?> getById(int id);

  /// Retrieve all events for a specific book
  Future<List<Event>> getByBookId(String bookUuid);

  /// Retrieve events for a specific book within a date range
  /// Includes events that overlap with the date range
  Future<List<Event>> getByDateRange(
    String bookUuid,
    DateTime startDate,
    DateTime endDate,
  );

  /// Create a new event
  /// Returns the created event with generated ID
  Future<Event> create(Event event);

  /// Update an existing event
  /// Returns the updated event
  Future<Event> update(Event event);

  /// Delete an event by its ID
  /// Also deletes associated notes from cache
  Future<void> delete(int id);

  /// Remove an event (soft delete with reason)
  /// Returns the updated event with isRemoved flag set
  Future<Event> removeEvent(String eventId, String reason);

  /// Change event time - creates new event and soft deletes original
  /// Returns the newly created event with updated time
  Future<Event> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  );

  /// Get all unique names for a specific book
  Future<List<String>> getAllNames(String bookUuid);

  /// Get all unique record numbers for a specific book
  Future<List<String>> getAllRecordNumbers(String bookUuid);

  /// Get all unique name-record number pairs for a specific book
  Future<List<NameRecordPair>> getAllNameRecordPairs(String bookUuid);

  /// Get unique record numbers filtered by exact name match (case-insensitive)
  Future<List<String>> getRecordNumbersByName(String bookUuid, String name);

  /// Search events by name and record number for a specific book
  Future<List<Event>> searchByNameAndRecordNumber(
    String bookUuid,
    String name,
    String recordNumber,
  );

  // Sync-related methods

  /// Get all events marked as dirty (need sync)
  Future<List<Event>> getDirtyEvents();

  /// Mark an event as synced (clear dirty flag)
  Future<void> markEventSynced(int id, DateTime syncedAt);

  /// Apply server change to local database
  /// Used when pulling changes from server
  Future<void> applyServerChange(Map<String, dynamic> changeData);

  /// Get event by server ID (used for sync)
  Future<Event?> getByServerId(int serverId);
}
