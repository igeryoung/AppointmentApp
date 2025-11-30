import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import '../models/event.dart';
import '../models/note.dart';
import '../models/schedule_drawing.dart';
import 'database_service_interface.dart';

/// Simple in-memory database for web platform testing
class WebPRDDatabaseService implements IDatabaseService {
  static WebPRDDatabaseService? _instance;

  // In-memory storage
  final List<Book> _books = [];
  final List<Event> _events = [];
  final List<Note> _notes = [];
  final List<ScheduleDrawing> _scheduleDrawings = [];
  int _nextEventId = 1;
  int _nextNoteId = 1;
  int _nextScheduleDrawingId = 1;

  WebPRDDatabaseService._internal();

  factory WebPRDDatabaseService() {
    _instance ??= WebPRDDatabaseService._internal();
    return _instance!;
  }

  static void resetInstance() {
    _instance = null;
  }

  // ===================
  // Book Operations
  // ===================

  Future<List<Book>> getAllBooks({bool includeArchived = false}) async {
    await Future.delayed(const Duration(milliseconds: 10));
    return _books.where((book) => includeArchived || !book.isArchived).toList();
  }

  Future<Book?> getBookByUuid(String uuid) async {
    await Future.delayed(const Duration(milliseconds: 5));
    try {
      return _books.firstWhere((book) => book.uuid == uuid);
    } catch (e) {
      return null;
    }
  }

  Future<Book> createBook(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    await Future.delayed(const Duration(milliseconds: 10));

    final book = Book(
      uuid: const Uuid().v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
    );

    _books.add(book);
    return book;
  }

  Future<Book> updateBook(Book book) async {
    if (book.name.trim().isEmpty) throw ArgumentError('Book name cannot be empty');

    await Future.delayed(const Duration(milliseconds: 10));

    final index = _books.indexWhere((b) => b.uuid == book.uuid);
    if (index == -1) throw Exception('Book not found');

    final updatedBook = book.copyWith(name: book.name.trim());
    _books[index] = updatedBook;
    return updatedBook;
  }

  Future<void> archiveBook(String uuid) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final index = _books.indexWhere((b) => b.uuid == uuid && !b.isArchived);
    if (index == -1) throw Exception('Book not found or already archived');

    final book = _books[index];
    _books[index] = book.copyWith(archivedAt: DateTime.now());
  }

  Future<void> deleteBook(String uuid) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final bookIndex = _books.indexWhere((b) => b.uuid == uuid);
    if (bookIndex == -1) throw Exception('Book not found');

    _books.removeAt(bookIndex);
    // Cascade delete events and notes
    _events.removeWhere((e) => e.bookUuid == uuid);
    _notes.removeWhere((n) => _events.every((e) => e.id != n.eventId));
  }

  // ===================
  // Event Operations
  // ===================

  /// Get events for Day view
  ///
  /// [date] should be normalized to midnight (start of day)
  Future<List<Event>> getEventsByDay(String bookUuid, DateTime date) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _events
        .where((e) =>
            e.bookUuid == bookUuid &&
            e.startTime.isAfter(startOfDay.subtract(const Duration(milliseconds: 1))) &&
            e.startTime.isBefore(endOfDay))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Get events for 3-Day view
  ///
  /// [startDate] MUST be the 3-day window start date (calculated by _get3DayWindowStart)
  /// to ensure events are loaded for the correct window being displayed
  Future<List<Event>> getEventsBy3Days(String bookUuid, DateTime startDate) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endOfPeriod = startOfDay.add(const Duration(days: 3));
    return _events
        .where((e) =>
            e.bookUuid == bookUuid &&
            e.startTime.isAfter(startOfDay.subtract(const Duration(milliseconds: 1))) &&
            e.startTime.isBefore(endOfPeriod))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Get events for Week view
  ///
  /// [weekStart] MUST be the week start date (Monday, calculated by _getWeekStart)
  /// to ensure events are loaded for the correct week being displayed
  Future<List<Event>> getEventsByWeek(String bookUuid, DateTime weekStart) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final weekEnd = weekStart.add(const Duration(days: 7));
    return _events
        .where((e) =>
            e.bookUuid == bookUuid &&
            e.startTime.isAfter(weekStart.subtract(const Duration(milliseconds: 1))) &&
            e.startTime.isBefore(weekEnd))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Get all events for a book (regardless of date)
  @override
  Future<List<Event>> getAllEventsByBook(String bookUuid) async {
    await Future.delayed(const Duration(milliseconds: 10));

    return _events
        .where((e) => e.bookUuid == bookUuid)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<Event?> getEventById(int id) async {
    await Future.delayed(const Duration(milliseconds: 5));
    try {
      return _events.firstWhere((e) => e.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<Event> createEvent(Event event) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final now = DateTime.now();
    final newEvent = event.copyWith(
      id: _nextEventId++,
      createdAt: now,
      updatedAt: now,
    );

    _events.add(newEvent);

    // Create associated empty note
    final note = Note(
      id: _nextNoteId++,
      eventId: newEvent.id!,
      pages: [[]], // Start with one empty page
      createdAt: now,
      updatedAt: now,
    );
    _notes.add(note);

    return newEvent;
  }

  Future<Event> updateEvent(Event event) async {
    if (event.id == null) throw ArgumentError('Event ID cannot be null');

    await Future.delayed(const Duration(milliseconds: 10));

    final index = _events.indexWhere((e) => e.id == event.id);
    if (index == -1) throw Exception('Event not found');

    final updatedEvent = event.copyWith(updatedAt: DateTime.now());
    _events[index] = updatedEvent;
    return updatedEvent;
  }

  Future<void> deleteEvent(int id) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final eventIndex = _events.indexWhere((e) => e.id == id);
    if (eventIndex == -1) throw Exception('Event not found');

    _events.removeAt(eventIndex);
    // Delete associated note
    _notes.removeWhere((n) => n.eventId == id);
  }

  /// Soft remove an event with a reason
  Future<Event> removeEvent(String eventId, String reason) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Removal reason cannot be empty');
    }

    await Future.delayed(const Duration(milliseconds: 10));

    final eventIndex = _events.indexWhere((e) => e.id == eventId);
    if (eventIndex == -1) throw Exception('Event not found');

    final event = _events[eventIndex];
    if (event.isRemoved) throw Exception('Event is already removed');

    // Update the event with removal information
    final updatedEvent = event.copyWith(
      isRemoved: true,
      removalReason: reason.trim(),
      updatedAt: DateTime.now(),
    );

    _events[eventIndex] = updatedEvent;
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

    await Future.delayed(const Duration(milliseconds: 10));
    final now = DateTime.now();

    // First, soft remove the original event
    await removeEvent(originalEvent.id!, reason.trim());

    // Create a new event with the new time but same metadata
    final newEvent = originalEvent.copyWith(
      id: _nextEventId++,
      startTime: newStartTime,
      endTime: newEndTime,
      originalEventId: originalEvent.id,
      isRemoved: false,
      removalReason: null,
      updatedAt: now,
    );

    _events.add(newEvent);

    // Update the original event to point to the new event
    final originalEventIndex = _events.indexWhere((e) => e.id == originalEvent.id);
    if (originalEventIndex != -1) {
      _events[originalEventIndex] = _events[originalEventIndex].copyWith(
        newEventId: newEvent.id,
      );
    }

    // Copy the note from original event to new event if it exists
    final originalNoteIndex = _notes.indexWhere((n) => n.eventId == originalEvent.id!);
    if (originalNoteIndex != -1) {
      final originalNote = _notes[originalNoteIndex];
      final newNote = originalNote.copyWith(
        id: _nextNoteId++,
        eventId: newEvent.id!,
        updatedAt: now,
      );
      _notes.add(newNote);
    } else {
      // If no original note exists, create an empty one for the new event
      final emptyNote = Note(
        id: _nextNoteId++,
        eventId: newEvent.id!,
        pages: [[]], // Start with one empty page
        createdAt: now,
        updatedAt: now,
      );
      _notes.add(emptyNote);
    }

    return newEvent;
  }

  // ===================
  // Note Operations
  // ===================

  Future<Note?> getCachedNote(String eventId) async {
    await Future.delayed(const Duration(milliseconds: 5));
    debugPrint('🗄️ WebDB: getCachedNote($eventId) - searching in ${_notes.length} notes');

    try {
      final note = _notes.firstWhere((n) => n.eventId == eventId);
      debugPrint('🗄️ WebDB: Found note for event $eventId with ${note.strokes.length} strokes');

      // Log first few strokes for debugging
      for (int i = 0; i < note.strokes.length && i < 3; i++) {
        final stroke = note.strokes[i];
        debugPrint('🗄️ WebDB: Retrieved stroke $i has ${stroke.points.length} points, color: ${stroke.color}');
      }

      return note;
    } catch (e) {
      debugPrint('🗄️ WebDB: No note found for event $eventId');
      return null;
    }
  }

  Future<Note> saveCachedNote(Note note) async {
    await Future.delayed(const Duration(milliseconds: 10));
    debugPrint('🗄️ WebDB: saveCachedNote() called for event ${note.eventId} with ${note.strokes.length} strokes');

    // Log stroke details before storing
    for (int i = 0; i < note.strokes.length && i < 3; i++) {
      final stroke = note.strokes[i];
      debugPrint('🗄️ WebDB: Storing stroke $i with ${stroke.points.length} points, color: ${stroke.color}');
    }

    final index = _notes.indexWhere((n) => n.eventId == note.eventId);
    if (index == -1) {
      // Create new note if doesn't exist
      debugPrint('🗄️ WebDB: Creating new note for event ${note.eventId}');
      final newNote = note.copyWith(
        id: _nextNoteId++,
        updatedAt: DateTime.now(),
      );
      _notes.add(newNote);
      debugPrint('🗄️ WebDB: New note created with ID ${newNote.id}, total notes: ${_notes.length}');
      return newNote;
    }

    debugPrint('🗄️ WebDB: Updating existing note at index $index');
    final updatedNote = note.copyWith(updatedAt: DateTime.now());
    _notes[index] = updatedNote;
    debugPrint('🗄️ WebDB: Note updated successfully');
    return updatedNote;
  }

  // ===================
  // Utility Operations
  // ===================

  Future<int> getEventCountByBook(String bookUuid) async {
    await Future.delayed(const Duration(milliseconds: 5));
    return _events.where((e) => e.bookUuid == bookUuid).length;
  }

  @override
  Future<List<String>> getAllRecordNumbers(String bookUuid) async {
    await Future.delayed(const Duration(milliseconds: 5));
    final recordNumbers = _events
        .where((e) => e.bookUuid == bookUuid && e.recordNumber != null && e.recordNumber!.isNotEmpty)
        .map((e) => e.recordNumber!)
        .toSet()
        .toList();
    recordNumbers.sort();
    return recordNumbers;
  }

  @override
  Future<List<String>> getRecordNumbersByName(String bookUuid, String name) async {
    await Future.delayed(const Duration(milliseconds: 5));
    final recordNumbers = _events
        .where((e) =>
          e.bookUuid == bookUuid &&
          e.name.toLowerCase() == name.toLowerCase() &&
          e.recordNumber != null &&
          e.recordNumber!.isNotEmpty)
        .map((e) => e.recordNumber!)
        .toSet()
        .toList();
    recordNumbers.sort();
    return recordNumbers;
  }

  @override
  Future<List<Event>> searchByNameAndRecordNumber(
    String bookUuid,
    String name,
    String recordNumber,
  ) async {
    await Future.delayed(const Duration(milliseconds: 5));
    return _events
        .where((e) => e.bookUuid == bookUuid && e.name == name && e.recordNumber == recordNumber)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  // ===================
  // Schedule Drawing Operations
  // ===================

  /// Get drawing for specific book, date, and view mode
  ///
  /// [date] MUST be the effective date for the view:
  /// - Day view: the selected date
  /// - 3-Day view: the window start date (calculated by _get3DayWindowStart)
  /// - Week view: the week start date (calculated by _getWeekStart)
  Future<ScheduleDrawing?> getCachedDrawing(String bookUuid, DateTime date, int viewMode) async {
    await Future.delayed(const Duration(milliseconds: 5));
    final normalizedDate = DateTime(date.year, date.month, date.day);

    try {
      return _scheduleDrawings.firstWhere(
        (d) =>
            d.bookUuid == bookUuid &&
            d.date.year == normalizedDate.year &&
            d.date.month == normalizedDate.month &&
            d.date.day == normalizedDate.day &&
            d.viewMode == viewMode,
      );
    } catch (e) {
      return null;
    }
  }

  /// Update or create schedule drawing
  ///
  /// The [drawing.date] MUST be the effective date for the view:
  /// - Day view: the selected date
  /// - 3-Day view: the window start date (calculated by _get3DayWindowStart)
  /// - Week view: the week start date (calculated by _getWeekStart)
  Future<ScheduleDrawing> saveCachedDrawing(ScheduleDrawing drawing) async {
    await Future.delayed(const Duration(milliseconds: 10));
    final normalizedDate = DateTime(drawing.date.year, drawing.date.month, drawing.date.day);
    final now = DateTime.now();

    debugPrint('🎨 Web: saveCachedDrawing called with ${drawing.strokes.length} strokes');

    // Find existing drawing
    final index = _scheduleDrawings.indexWhere(
      (d) =>
          d.bookUuid == drawing.bookUuid &&
          d.date.year == normalizedDate.year &&
          d.date.month == normalizedDate.month &&
          d.date.day == normalizedDate.day &&
          d.viewMode == drawing.viewMode,
    );

    final updatedDrawing = drawing.copyWith(
      date: normalizedDate,
      updatedAt: now,
    );

    if (index != -1) {
      // Update existing
      _scheduleDrawings[index] = updatedDrawing.copyWith(id: _scheduleDrawings[index].id);
      debugPrint('✅ Web: Schedule drawing updated');
      return _scheduleDrawings[index];
    } else {
      // Insert new
      final newDrawing = updatedDrawing.copyWith(
        id: _nextScheduleDrawingId++,
        createdAt: now,
      );
      _scheduleDrawings.add(newDrawing);
      debugPrint('✅ Web: New schedule drawing created');
      return newDrawing;
    }
  }

  Future<void> deleteCachedDrawing(String bookUuid, DateTime date, int viewMode) async {
    await Future.delayed(const Duration(milliseconds: 5));
    final normalizedDate = DateTime(date.year, date.month, date.day);

    _scheduleDrawings.removeWhere(
      (d) =>
          d.bookUuid == bookUuid &&
          d.date.year == normalizedDate.year &&
          d.date.month == normalizedDate.month &&
          d.date.day == normalizedDate.day &&
          d.viewMode == viewMode,
    );
  }

  Future<void> deleteCachedNote(String eventId) async {
    await Future.delayed(const Duration(milliseconds: 5));
    _notes.removeWhere((n) => n.eventId == eventId);
  }

  Future<Map<int, Note>> batchGetCachedNotes(List<int> eventIds) async {
    await Future.delayed(const Duration(milliseconds: 10));
    final result = <int, Note>{};
    for (final eventId in eventIds) {
      final note = await getCachedNote(eventId);
      if (note != null) {
        result[eventId] = note;
      }
    }
    return result;
  }

  Future<void> batchSaveCachedNotes(Map<int, Note> notes) async {
    await Future.delayed(const Duration(milliseconds: 10));
    for (final entry in notes.entries) {
      await saveCachedNote(entry.value);
    }
  }

  Future<List<ScheduleDrawing>> batchGetCachedDrawings({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
    int? viewMode,
  }) async {
    await Future.delayed(const Duration(milliseconds: 10));
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);

    return _scheduleDrawings.where((d) {
      if (d.bookUuid != bookUuid) return false;
      if (viewMode != null && d.viewMode != viewMode) return false;
      final normalized = DateTime(d.date.year, d.date.month, d.date.day);
      return !normalized.isBefore(normalizedStart) && !normalized.isAfter(normalizedEnd);
    }).toList();
  }

  Future<void> batchSaveCachedDrawings(List<ScheduleDrawing> drawings) async {
    await Future.delayed(const Duration(milliseconds: 10));
    for (final drawing in drawings) {
      await saveCachedDrawing(drawing);
    }
  }

  Future<void> clearAllData() async {
    await Future.delayed(const Duration(milliseconds: 5));
    _scheduleDrawings.clear();
    _notes.clear();
    _events.clear();
    _books.clear();
    _nextEventId = 1;
    _nextNoteId = 1;
    _nextScheduleDrawingId = 1;
  }

  Future<void> close() async {
    // No-op for in-memory storage
  }
}