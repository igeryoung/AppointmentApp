import '../models/book.dart';
import '../models/event.dart';
import '../models/note.dart';
import '../models/schedule_drawing.dart';

/// Interface for database services
///
/// Implemented by:
/// - [PRDDatabaseService] for mobile/desktop platforms
/// - [WebPRDDatabaseService] for web platform
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
  Future<Event> removeEvent(int id, String reason);

  /// Change the time of an event (creates a new event and links them)
  Future<Event> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  );

  // ===================
  // Note Cache Operations
  // ===================

  /// Get cached note by event ID
  Future<Note?> getCachedNote(String eventId);

  /// Save note to cache (insert or update)
  Future<Note> saveCachedNote(Note note);

  /// Delete cached note by event ID
  Future<void> deleteCachedNote(String eventId);

  /// Batch get cached notes
  Future<Map<String, Note>> batchGetCachedNotes(List<String> eventIds);

  /// Batch save cached notes
  Future<void> batchSaveCachedNotes(Map<int, Note> notes);

  // ===================
  // Schedule Drawing Cache Operations
  // ===================

  /// Get cached drawing for a specific view
  Future<ScheduleDrawing?> getCachedDrawing(
    String bookUuid,
    DateTime date,
    int viewMode,
  );

  /// Save drawing to cache (insert or update)
  Future<ScheduleDrawing> saveCachedDrawing(ScheduleDrawing drawing);

  /// Delete cached drawing
  Future<void> deleteCachedDrawing(String bookUuid, DateTime date, int viewMode);

  /// Batch get cached drawings for a date range
  Future<List<ScheduleDrawing>> batchGetCachedDrawings({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
    int? viewMode,
  });

  /// Batch save cached drawings
  Future<void> batchSaveCachedDrawings(List<ScheduleDrawing> drawings);

  // ===================
  // Utility Operations
  // ===================

  /// Get the count of events in a book
  Future<int> getEventCountByBook(String bookUuid);

  /// Get all unique record numbers for a book
  Future<List<String>> getAllRecordNumbers(String bookUuid);

  /// Get unique record numbers filtered by exact name match (case-insensitive)
  Future<List<String>> getRecordNumbersByName(String bookUuid, String name);

  /// Search events by name and record number
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
