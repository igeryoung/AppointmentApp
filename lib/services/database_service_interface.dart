import '../models/book.dart';
import '../models/event.dart';
import 'database/mixins/event_operations_mixin.dart';

/// Interface for database services
///
/// Implemented by:
/// - [PRDDatabaseService] for mobile/desktop platforms
abstract class IDatabaseService {
  // ===================
  // Book Operations
  // ===================

  /// Get all books, optionally including archived ones
  Future<List<Book>> getAllBooks({bool includeArchived = false});

  /// Get a book by its UUID
  Future<Book?> getBookByUuid(String uuid);

  /// Create a new book
  Future<Book> createBook(String name);

  /// Update an existing book
  Future<Book> updateBook(Book book);

  /// Archive a book (soft delete)
  Future<void> archiveBook(String uuid);

  /// Delete a book permanently
  Future<void> deleteBook(String uuid);

  // ===================
  // Event Operations
  // ===================

  /// Get events for a single day
  Future<List<Event>> getEventsByDay(String bookUuid, DateTime date);

  /// Get events for a 3-day period starting from date
  Future<List<Event>> getEventsBy3Days(String bookUuid, DateTime startDate);

  /// Get events for a week
  Future<List<Event>> getEventsByWeek(String bookUuid, DateTime weekStart);

  /// Get all events for a book (regardless of date)
  Future<List<Event>> getAllEventsByBook(String bookUuid);

  /// Get an event by its ID
  Future<Event?> getEventById(String id);

  /// Create a new event
  Future<Event> createEvent(Event event);

  /// Update an existing event
  Future<Event> updateEvent(Event event);

  /// Delete an event permanently
  Future<void> deleteEvent(String id);

  /// Mark an event as removed (soft delete with reason)
  Future<Event> removeEvent(String id, String reason);

  /// Change the time of an event (creates a new event and links them)
  /// Returns both the new event and the old event (marked as removed)
  Future<ChangeEventTimeResult> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  );

  /// Replace local event row with authoritative server data
  Future<void> replaceEventWithServerData(Event event);

  // ===================
  // Utility Operations
  // ===================

  /// Get the count of events in a book
  Future<int> getEventCountByBook(String bookUuid);

  /// Get all unique record numbers for a book
  Future<List<String>> getAllRecordNumbers(String bookUuid);

  /// Get unique record numbers filtered by title match (case-insensitive)
  Future<List<String>> getRecordNumbersByName(String bookUuid, String name);

  /// Search events by title and record number
  Future<List<Event>> searchByNameAndRecordNumber(
    String bookUuid,
    String name,
    String recordNumber,
  );

  /// Clear all data (for testing)
  Future<void> clearAllData();

  /// Close the database connection
  Future<void> close();
}
