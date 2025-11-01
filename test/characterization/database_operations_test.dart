import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';
import 'package:schedule_note_app/services/prd_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Characterization tests that capture current database behavior
/// These tests MUST continue to pass after refactoring
/// They serve as a safety net to ensure no behavior changes
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Characterization Tests - Database Operations', () {
    late PRDDatabaseService db;

    setUp(() async {
      PRDDatabaseService.resetInstance();
      db = PRDDatabaseService();
      await db.clearAllData();
    });

    tearDown(() async {
      await db.clearAllData();
      await db.close();
      PRDDatabaseService.resetInstance();
    });

    test('Create book → retrieve book → data matches', () async {
      final book = await db.createBook('Test Book');

      expect(book.id, isNotNull);
      expect(book.name, 'Test Book');

      final retrieved = await db.getBookById(book.id!);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, book.id);
      expect(retrieved.name, book.name);
    });

    test('Create multiple books → getAllBooks → returns all', () async {
      await db.createBook('Book 1');
      await db.createBook('Book 2');
      await db.createBook('Book 3');

      final books = await db.getAllBooks();
      expect(books.length, 3);
      expect(books[0].name, 'Book 1');
      expect(books[1].name, 'Book 2');
      expect(books[2].name, 'Book 3');
    });

    test('Delete book → cascade deletes events', () async {
      final book = await db.createBook('Test Book');
      final event = await db.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC001',
        eventType: 'appointment',
        startTime: DateTime(2025, 1, 15, 10, 0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await db.deleteBook(book.id!);

      final retrievedBook = await db.getBookById(book.id!);
      expect(retrievedBook, isNull);

      final retrievedEvent = await db.getEventById(event.id!);
      expect(retrievedEvent, isNull);
    });

    test('Create event → retrieve event → data matches', () async {
      final book = await db.createBook('Test Book');
      final startTime = DateTime(2025, 1, 15, 10, 0);
      final event = await db.createEvent(Event(
        bookId: book.id!,
        name: 'Dentist Appointment',
        recordNumber: 'REC001',
        eventType: 'appointment',
        startTime: startTime,
        endTime: DateTime(2025, 1, 15, 11, 0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(event.id, isNotNull);
      expect(event.name, 'Dentist Appointment');
      expect(event.recordNumber, 'REC001');

      final retrieved = await db.getEventById(event.id!);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, event.id);
      expect(retrieved.name, event.name);
      expect(retrieved.bookId, book.id);
    });

    test('Get events by day → returns correct events', () async {
      final book = await db.createBook('Test Book');

      // Create event on specific date
      await db.createEvent(Event(
        bookId: book.id!,
        name: 'Event 1',
        recordNumber: 'REC001',
        eventType: 'appointment',
        startTime: DateTime(2025, 1, 15, 10, 0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await db.createEvent(Event(
        bookId: book.id!,
        name: 'Event 2',
        recordNumber: 'REC002',
        eventType: 'appointment',
        startTime: DateTime(2025, 1, 16, 10, 0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Query for events on January 15
      final events = await db.getEventsByDay(
        book.id!,
        DateTime(2025, 1, 15),
      );

      expect(events.length, 1);
      expect(events[0].name, 'Event 1');
    });

    test('Save note to cache → retrieve from cache → data matches', () async {
      final book = await db.createBook('Test Book');
      final event = await db.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC001',
        eventType: 'appointment',
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final note = Note(
        eventId: event.id!,
        strokes: const [
          Stroke(points: [
            StrokePoint(10.0, 20.0),
            StrokePoint(30.0, 40.0),
            StrokePoint(50.0, 60.0),
          ])
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await db.saveCachedNote(note);

      final retrieved = await db.getCachedNote(event.id!);
      expect(retrieved, isNotNull);
      expect(retrieved!.eventId, event.id);
      expect(retrieved.strokes.length, 1);
      expect(retrieved.strokes[0].points.length, 3);
    });

    test('Save drawing to cache → retrieve from cache → data matches', () async {
      final book = await db.createBook('Test Book');
      final date = DateTime(2025, 1, 15);
      const viewMode = 0; // Day view

      final drawing = ScheduleDrawing(
        bookId: book.id!,
        date: date,
        viewMode: viewMode,
        strokes: const [
          Stroke(points: [
            StrokePoint(100.0, 200.0),
            StrokePoint(150.0, 250.0),
          ])
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await db.saveCachedDrawing(drawing);

      final retrieved = await db.getCachedDrawing(book.id!, date, viewMode);
      expect(retrieved, isNotNull);
      expect(retrieved!.bookId, book.id);
      expect(retrieved.viewMode, viewMode);
      expect(retrieved.strokes.length, 1);
      expect(retrieved.strokes[0].points.length, 2);
    });

    test('Dirty notes tracking → save dirty → get dirty → returns note', () async {
      final book = await db.createBook('Test Book');
      final event = await db.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC001',
        eventType: 'appointment',
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final note = Note(
        eventId: event.id!,
        strokes: const [
          Stroke(points: [StrokePoint(10.0, 20.0)])
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDirty: true,  // Mark as dirty
      );

      // Save dirty note
      await db.saveCachedNote(note);

      final dirtyNotes = await db.getAllDirtyNotes();
      expect(dirtyNotes.length, 1);
      expect(dirtyNotes[0].eventId, event.id);
      expect(dirtyNotes[0].isDirty, true);

      // Save as clean
      final cleanNote = note.copyWith(isDirty: false);
      await db.saveCachedNote(cleanNote);

      final dirtyNotesAfter = await db.getAllDirtyNotes();
      expect(dirtyNotesAfter.length, 0);
    });

    test('Device credentials → save and retrieve', () async {
      const deviceId = 'test-device-123';
      const deviceToken = 'test-token-456';
      const deviceName = 'Test Device';

      await db.saveDeviceCredentials(
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: deviceName,
      );

      final credentials = await db.getDeviceCredentials();

      expect(credentials, isNotNull);
      expect(credentials!.deviceId, deviceId);
      expect(credentials.deviceToken, deviceToken);
    });
  });
}
