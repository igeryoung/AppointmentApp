import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/models/book.dart';
import '../lib/models/event.dart';
import '../lib/models/note.dart';
import '../lib/services/prd_database_service.dart';

/// Verification script for the changeEventTime bug fix
void main() {
  late PRDDatabaseService dbService;

  setUpAll(() {
    // Initialize FFI for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Event Time Change Fix Verification', () {
    setUp(() async {
      PRDDatabaseService.resetInstance();
      dbService = PRDDatabaseService();
      await dbService.clearAllData();
    });

    tearDown(() async {
      await dbService.clearAllData();
      await dbService.close();
      PRDDatabaseService.resetInstance();
    });

    test('changeEventTime should copy notes correctly', () async {
      // Create a book
      final book = await dbService.createBook('Test Book');

      // Create an event
      final event = await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC001',
        eventType: 'Consultation',
        startTime: DateTime(2025, 10, 5, 10, 0),
        endTime: DateTime(2025, 10, 5, 11, 0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Add a note with strokes
      final note = Note(
        eventId: event.id!,
        strokes: [
          Stroke(
            points: [
              StrokePoint(10, 10),
              StrokePoint(20, 20),
              StrokePoint(30, 30),
            ],
            strokeWidth: 2.0,
            color: 0xFF000000,
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await dbService.updateNote(note);

      // Verify original note exists
      final originalNote = await dbService.getNoteByEventId(event.id!);
      expect(originalNote, isNotNull);
      expect(originalNote!.strokes.length, 1);

      // Change event time
      final newEvent = await dbService.changeEventTime(
        event,
        DateTime(2025, 10, 5, 14, 0),
        DateTime(2025, 10, 5, 15, 0),
        'Patient requested time change',
      );

      // Verify new event was created
      expect(newEvent.id, isNotNull);
      expect(newEvent.id, isNot(equals(event.id)));
      expect(newEvent.startTime, DateTime(2025, 10, 5, 14, 0));
      expect(newEvent.endTime, DateTime(2025, 10, 5, 15, 0));
      expect(newEvent.originalEventId, event.id);

      // Verify note was copied to new event
      final newNote = await dbService.getNoteByEventId(newEvent.id!);
      expect(newNote, isNotNull, reason: 'Note should exist for new event');
      expect(newNote!.strokes.length, 1, reason: 'Strokes should be copied');
      expect(newNote.strokes[0].points.length, 3, reason: 'Stroke points should be preserved');

      // Verify original event was soft-removed
      final originalEvent = await dbService.getEventById(event.id!);
      expect(originalEvent, isNotNull);
      expect(originalEvent!.isRemoved, true);
      expect(originalEvent.removalReason, 'Patient requested time change');

      print('✅ Time change fix verified successfully!');
      print('   - Original event soft-removed: ${originalEvent.isRemoved}');
      print('   - New event created with ID: ${newEvent.id}');
      print('   - Note copied with ${newNote.strokes.length} strokes');
    });

    test('changeEventTime should handle events without notes', () async {
      // Create a book
      final book = await dbService.createBook('Test Book');

      // Create an event
      final event = await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'REC002',
        eventType: 'Follow-up',
        startTime: DateTime(2025, 10, 6, 9, 0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Don't add any notes (event has empty note by default)

      // Change event time
      final newEvent = await dbService.changeEventTime(
        event,
        DateTime(2025, 10, 6, 10, 0),
        null,
        'Rescheduled',
      );

      // Verify new event has a note (even if empty)
      final newNote = await dbService.getNoteByEventId(newEvent.id!);
      expect(newNote, isNotNull, reason: 'Empty note should be created for new event');
      expect(newNote!.strokes.length, 0, reason: 'Note should be empty');

      print('✅ Time change without notes verified successfully!');
      print('   - New event created: ${newEvent.id}');
      print('   - Empty note created for new event');
    });
  });
}
