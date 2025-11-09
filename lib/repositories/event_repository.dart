import '../models/event.dart';

/// Repository interface for Event entity operations
/// Defines the contract for event data access
abstract class IEventRepository {
  /// Retrieve all events
  Future<List<Event>> getAll();

  /// Retrieve a single event by its ID
  /// Returns null if event not found
  Future<Event?> getById(int id);

  /// Retrieve all events for a specific book
  Future<List<Event>> getByBookId(int bookId);

  /// Retrieve events for a specific book within a date range
  /// Includes events that overlap with the date range
  Future<List<Event>> getByDateRange(
    int bookId,
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
  Future<Event> removeEvent(int eventId, String reason);

  /// Change event time - creates new event and soft deletes original
  /// Returns the newly created event with updated time
  Future<Event> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  );

  /// Get all unique record numbers for a specific book
  Future<List<String>> getAllRecordNumbers(int bookId);

  /// Search events by name and record number for a specific book
  Future<List<Event>> searchByNameAndRecordNumber(
    int bookId,
    String name,
    String recordNumber,
  );
}
