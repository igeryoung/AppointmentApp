import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';
import 'package:schedule_note_app/services/prd_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Characterization tests for cache behavior
/// These ensure offline-first functionality remains intact after refactoring
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Characterization Tests - Cache Behavior', () {
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

    test('Cache upsert behavior → save same note twice → only one entry', () async {
      final book = await db.createBook('Test Book');
      final event = await db.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC001',
        eventType: EventType.consultation,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Save first version
      final note1 = Note(
        eventId: event.id!,
        strokes: const [
          Stroke(points: [StrokePoint(10.0, 20.0)])
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.saveCachedNote(note1);

      // Save updated version
      final note2 = Note(
        eventId: event.id!,
        strokes: const [
          Stroke(points: [
            StrokePoint(100.0, 200.0),
            StrokePoint(150.0, 250.0),
          ])
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.saveCachedNote(note2);

      // Should only have one note with updated data
      final retrieved = await db.getCachedNote(event.id!);
      expect(retrieved, isNotNull);
      expect(retrieved!.strokes.length, 1);
      expect(retrieved.strokes[0].points.length, 2);
    });

    test('Delete cached note → note removed from cache', () async {
      final book = await db.createBook('Test Book');
      final event = await db.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC001',
        eventType: EventType.consultation,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final note = Note(
        eventId: event.id!,
        strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.saveCachedNote(note);

      await db.deleteCachedNote(event.id!);

      final retrieved = await db.getCachedNote(event.id!);
      expect(retrieved, isNull);
    });

    test('Clear cache → cached data removed', () async {
      final book = await db.createBook('Test Book');
      final event = await db.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC001',
        eventType: EventType.consultation,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      final date = DateTime(2025, 1, 15);
      const viewMode = 0;

      // Add note and drawing to cache
      await db.saveCachedNote(Note(
        eventId: event.id!,
        strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await db.saveCachedDrawing(ScheduleDrawing(
        bookId: book.id!,
        date: date,
        viewMode: viewMode,
        strokes: const [Stroke(points: [StrokePoint(100.0, 200.0)])],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Clear notes and drawings cache
      await db.clearNotesCache();
      await db.clearDrawingsCache();

      // Verify cache is empty
      final note = await db.getCachedNote(event.id!);
      final drawing = await db.getCachedDrawing(book.id!, date, viewMode);

      expect(note, isNull);
      expect(drawing, isNull);
    });

    test('Get dirty notes for book → returns only dirty notes from that book', () async {
      final book1 = await db.createBook('Book 1');
      final book2 = await db.createBook('Book 2');

      final event1 = await db.createEvent(Event(
        bookId: book1.id!,
        name: 'Event 1',
        recordNumber: 'REC001',
        eventType: EventType.consultation,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final event2 = await db.createEvent(Event(
        bookId: book2.id!,
        name: 'Event 2',
        recordNumber: 'REC002',
        eventType: EventType.consultation,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Save notes
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

      final dirtyNotesForBook1 = await db.getDirtyNotesByBookId(book1.id!);
      expect(dirtyNotesForBook1.length, 1);
      expect(dirtyNotesForBook1[0].eventId, event1.id);
    });

    test('Offline data persists → save → close → reopen → data still there', () async {
      // Create data
      final book = await db.createBook('Test Book');
      final event = await db.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC001',
        eventType: EventType.consultation,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await db.saveCachedNote(Note(
        eventId: event.id!,
        strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Close and reopen
      await db.close();
      PRDDatabaseService.resetInstance();
      db = PRDDatabaseService();

      // Verify data persists
      final retrievedBook = await db.getBookById(book.id!);
      final retrievedEvent = await db.getEventById(event.id!);
      final retrievedNote = await db.getCachedNote(event.id!);

      expect(retrievedBook, isNotNull);
      expect(retrievedEvent, isNotNull);
      expect(retrievedNote, isNotNull);
      expect(retrievedNote!.strokes.length, 1);
    });

    test('Foreign key constraints → delete book cascades to events and cache', () async {
      final book = await db.createBook('Test Book');
      final event = await db.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC001',
        eventType: EventType.consultation,
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Add cached note for the event
      await db.saveCachedNote(Note(
        eventId: event.id!,
        strokes: const [Stroke(points: [StrokePoint(10.0, 20.0)])],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Delete book should cascade
      await db.deleteBook(book.id!);

      // Verify cascade
      final retrievedEvent = await db.getEventById(event.id!);
      final retrievedNote = await db.getCachedNote(event.id!);

      expect(retrievedEvent, isNull);
      // Note should also be deleted via cascade
      expect(retrievedNote, isNull);
    });
  });
}
