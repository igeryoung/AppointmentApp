import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';
import 'package:schedule_note_app/services/prd_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('PRDDatabaseService Cache Refactoring Tests', () {
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

    group('Note Cache Operations', () {
      test('getCachedNote returns null for non-existent note', () async {
        final result = await db.getCachedNote(999);
        expect(result, isNull);
      });

      test('saveCachedNote → getCachedNote → verify data', () async {
        // Create a book and event first
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

        // Create and save a note
        final note = Note(
          eventId: event.id!,
          strokes: const [
            Stroke(points: [
              StrokePoint(10.0, 20.0),
              StrokePoint(30.0, 40.0),
            ])
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final savedNote = await db.saveCachedNote(note);
        expect(savedNote.eventId, event.id);
        expect(savedNote.strokes.length, 1);

        // Retrieve and verify
        final retrievedNote = await db.getCachedNote(event.id!);
        expect(retrievedNote, isNotNull);
        expect(retrievedNote!.eventId, event.id);
        expect(retrievedNote.strokes.length, 1);
        expect(retrievedNote.strokes[0].points.length, 2);
      });

      test('saveCachedNote updates existing note (upsert behavior)', () async {
        // Create a book and event
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

        // Save initial note
        final note1 = Note(
          eventId: event.id!,
          strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await db.saveCachedNote(note1);

        // Update with new strokes
        final note2 = Note(
          eventId: event.id!,
          strokes: const [
            Stroke(points: [StrokePoint(100.0, 200.0)]),
            Stroke(points: [StrokePoint(300.0, 400.0)]),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await db.saveCachedNote(note2);

        // Verify updated content
        final retrievedNote = await db.getCachedNote(event.id!);
        expect(retrievedNote, isNotNull);
        expect(retrievedNote!.strokes.length, 2);
      });

      test('deleteCachedNote removes note from cache', () async {
        // Create a book and event
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

        // Save a note
        final note = Note(
          eventId: event.id!,
          strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await db.saveCachedNote(note);

        // Verify it exists
        var retrievedNote = await db.getCachedNote(event.id!);
        expect(retrievedNote, isNotNull);

        // Delete it
        await db.deleteCachedNote(event.id!);

        // Verify it's gone
        retrievedNote = await db.getCachedNote(event.id!);
        expect(retrievedNote, isNull);
      });

      test('incrementNoteCacheHit increases cache_hit_count', () async {
        // Create a book and event
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

        // Save a note
        final note = Note(
          eventId: event.id!,
          strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await db.saveCachedNote(note);

        // Increment hit count multiple times
        await db.incrementNoteCacheHit(event.id!);
        await db.incrementNoteCacheHit(event.id!);
        await db.incrementNoteCacheHit(event.id!);

        // Verify hit count
        final hitCount = await db.getNotesHitCount();
        expect(hitCount, 3);
      });

      test('batchGetCachedNotes returns only existing notes', () async {
        // Create a book and multiple events
        final book = await db.createBook('Test Book');
        final event1 = await db.createEvent(Event(
          bookId: book.id!,
          name: 'Event 1',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        final event2 = await db.createEvent(Event(
          bookId: book.id!,
          name: 'Event 2',
          recordNumber: 'REC002',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        final event3 = await db.createEvent(Event(
          bookId: book.id!,
          name: 'Event 3',
          recordNumber: 'REC003',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));

        // Save notes for event1 and event2 only
        await db.saveCachedNote(Note(
          eventId: event1.id!,
          strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        await db.saveCachedNote(Note(
          eventId: event2.id!,
          strokes: const [Stroke(points: [StrokePoint(30.0, 40.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));

        // Batch get all three (event3 has no note)
        final results = await db.batchGetCachedNotes([event1.id!, event2.id!, event3.id!]);

        expect(results.length, 2);
        expect(results.containsKey(event1.id!), true);
        expect(results.containsKey(event2.id!), true);
        expect(results.containsKey(event3.id!), false);
      });

      test('batchSaveCachedNotes saves multiple notes', () async {
        // Create a book and multiple events
        final book = await db.createBook('Test Book');
        final event1 = await db.createEvent(Event(
          bookId: book.id!,
          name: 'Event 1',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        final event2 = await db.createEvent(Event(
          bookId: book.id!,
          name: 'Event 2',
          recordNumber: 'REC002',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));

        // Batch save notes
        final notesMap = {
          event1.id!: Note(
            eventId: event1.id!,
            strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          event2.id!: Note(
            eventId: event2.id!,
            strokes: const [Stroke(points: [StrokePoint(30.0, 40.0)])],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        };

        await db.batchSaveCachedNotes(notesMap);

        // Verify both notes were saved
        final note1 = await db.getCachedNote(event1.id!);
        final note2 = await db.getCachedNote(event2.id!);
        expect(note1, isNotNull);
        expect(note2, isNotNull);
        expect(note1!.strokes.length, 1);
        expect(note2!.strokes.length, 1);
      });
    });

    group('Drawing Cache Operations', () {
      test('getCachedDrawing returns null for non-existent drawing', () async {
        final book = await db.createBook('Test Book');
        final result = await db.getCachedDrawing(book.id!, DateTime.now(), 0);
        expect(result, isNull);
      });

      test('saveCachedDrawing → getCachedDrawing → verify data', () async {
        final book = await db.createBook('Test Book');
        final date = DateTime.now();

        final drawing = ScheduleDrawing(
          bookId: book.id!,
          date: date,
          viewMode: 1,
          strokes: const [
            Stroke(points: [
              StrokePoint(50.0, 60.0),
              StrokePoint(70.0, 80.0),
            ])
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await db.saveCachedDrawing(drawing);

        // Retrieve and verify
        final retrieved = await db.getCachedDrawing(book.id!, date, 1);
        expect(retrieved, isNotNull);
        expect(retrieved!.bookId, book.id);
        expect(retrieved.viewMode, 1);
        expect(retrieved.strokes.length, 1);
        expect(retrieved.strokes[0].points.length, 2);
      });

      test('deleteCachedDrawing removes drawing from cache', () async {
        final book = await db.createBook('Test Book');
        final date = DateTime.now();

        final drawing = ScheduleDrawing(
          bookId: book.id!,
          date: date,
          viewMode: 1,
          strokes: const [Stroke(points: [StrokePoint(50.0, 60.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await db.saveCachedDrawing(drawing);

        // Verify it exists
        var retrieved = await db.getCachedDrawing(book.id!, date, 1);
        expect(retrieved, isNotNull);

        // Delete it
        await db.deleteCachedDrawing(book.id!, date, 1);

        // Verify it's gone
        retrieved = await db.getCachedDrawing(book.id!, date, 1);
        expect(retrieved, isNull);
      });

      test('batchGetCachedDrawings retrieves drawings in date range', () async {
        final book = await db.createBook('Test Book');
        final date1 = DateTime(2025, 10, 24);
        final date2 = DateTime(2025, 10, 25);
        final date3 = DateTime(2025, 10, 26);

        // Save drawings for different dates
        await db.saveCachedDrawing(ScheduleDrawing(
          bookId: book.id!,
          date: date1,
          viewMode: 1,
          strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        await db.saveCachedDrawing(ScheduleDrawing(
          bookId: book.id!,
          date: date2,
          viewMode: 1,
          strokes: const [Stroke(points: [StrokePoint(30.0, 40.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        await db.saveCachedDrawing(ScheduleDrawing(
          bookId: book.id!,
          date: date3,
          viewMode: 1,
          strokes: const [Stroke(points: [StrokePoint(50.0, 60.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));

        // Batch get for date range
        final results = await db.batchGetCachedDrawings(
          bookId: book.id!,
          startDate: date1,
          endDate: date2,
          viewMode: 1,
        );

        expect(results.length, 2);
        expect(results.any((d) => d.date.day == date1.day), true);
        expect(results.any((d) => d.date.day == date2.day), true);
        expect(results.any((d) => d.date.day == date3.day), false);
      });

      test('batchSaveCachedDrawings saves multiple drawings', () async {
        final book = await db.createBook('Test Book');
        final date1 = DateTime(2025, 10, 24);
        final date2 = DateTime(2025, 10, 25);

        final drawings = [
          ScheduleDrawing(
            bookId: book.id!,
            date: date1,
            viewMode: 1,
            strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          ScheduleDrawing(
            bookId: book.id!,
            date: date2,
            viewMode: 1,
            strokes: const [Stroke(points: [StrokePoint(30.0, 40.0)])],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        await db.batchSaveCachedDrawings(drawings);

        // Verify both drawings were saved
        final drawing1 = await db.getCachedDrawing(book.id!, date1, 1);
        final drawing2 = await db.getCachedDrawing(book.id!, date2, 1);
        expect(drawing1, isNotNull);
        expect(drawing2, isNotNull);
      });
    });

    group('Cache Clearing', () {
      test('clearNotesCache removes all notes but preserves events', () async {
        // Create a book and event
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

        // Save a note
        await db.saveCachedNote(Note(
          eventId: event.id!,
          strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));

        // Verify note exists
        var note = await db.getCachedNote(event.id!);
        expect(note, isNotNull);

        // Clear notes cache
        await db.clearNotesCache();

        // Verify note is gone
        note = await db.getCachedNote(event.id!);
        expect(note, isNull);

        // Verify event still exists
        final eventStillExists = await db.getEventById(event.id!);
        expect(eventStillExists, isNotNull);
      });

      test('clearDrawingsCache removes all drawings but preserves books', () async {
        // Create a book and drawing
        final book = await db.createBook('Test Book');
        final drawing = ScheduleDrawing(
          bookId: book.id!,
          date: DateTime.now(),
          viewMode: 1,
          strokes: const [Stroke(points: [StrokePoint(50.0, 60.0)])],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await db.saveCachedDrawing(drawing);

        // Verify drawing exists
        var retrievedDrawing = await db.getCachedDrawing(book.id!, drawing.date, 1);
        expect(retrievedDrawing, isNotNull);

        // Clear drawings cache
        await db.clearDrawingsCache();

        // Verify drawing is gone
        retrievedDrawing = await db.getCachedDrawing(book.id!, drawing.date, 1);
        expect(retrievedDrawing, isNull);

        // Verify book still exists
        final bookStillExists = await db.getBookById(book.id!);
        expect(bookStillExists, isNotNull);
      });
    });

    group('Regression Tests', () {
      test('Books operations are unaffected by cache refactoring', () async {
        final book1 = await db.createBook('Book 1');
        final book2 = await db.createBook('Book 2');

        final allBooks = await db.getAllBooks();
        expect(allBooks.length, 2);

        final retrieved = await db.getBookById(book1.id!);
        expect(retrieved, isNotNull);
        expect(retrieved!.name, 'Book 1');
      });

      test('Events operations are unaffected by cache refactoring', () async {
        final book = await db.createBook('Test Book');
        final event1 = await db.createEvent(Event(
          bookId: book.id!,
          name: 'Event 1',
          recordNumber: 'REC001',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        final event2 = await db.createEvent(Event(
          bookId: book.id!,
          name: 'Event 2',
          recordNumber: 'REC002',
          eventType: 'appointment',
          startTime: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));

        final allEvents = await db.getAllEventsByBook(book.id!);
        expect(allEvents.length, 2);

        final retrieved = await db.getEventById(event1.id!);
        expect(retrieved, isNotNull);
        expect(retrieved!.name, 'Event 1');
      });
    });
  });
}
