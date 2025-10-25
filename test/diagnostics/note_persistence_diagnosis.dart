import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import '../lib/models/book.dart';
import '../lib/models/event.dart';
import '../lib/models/note.dart';
import '../lib/services/web_prd_database_service.dart';

/// Comprehensive test suite to diagnose note persistence issues
void main() {
  group('Note Persistence Diagnosis', () {
    late WebPRDDatabaseService dbService;
    late Book testBook;
    late Event testEvent;

    setUp(() async {
      // Use web database service for testing (no SQLite dependency)
      WebPRDDatabaseService.resetInstance();
      dbService = WebPRDDatabaseService();
      await dbService.clearAllData();

      // Create test book and event
      testBook = await dbService.createBook('Test Book');
      testEvent = await dbService.createEvent(Event(
        bookId: testBook.id!,
        name: 'Test Event',
        recordNumber: 'TEST001',
        eventType: 'Consultation',
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    });

    test('Phase 1: Database Schema Verification', () async {
      print('🔍 PHASE 1: Database Schema Verification');

      // 1. Verify note is auto-created with event
      print('📝 Testing auto-creation of notes with events...');
      final note = await dbService.getNoteByEventId(testEvent.id!);
      expect(note, isNotNull, reason: 'Note should be auto-created with event');
      expect(note!.strokes, isEmpty, reason: 'Initial note should have empty strokes');
      print('✅ Note auto-created successfully with event');

      // 2. Test note table structure
      print('📊 Testing note table structure...');
      expect(note.id, isNotNull, reason: 'Note should have an ID');
      expect(note.eventId, equals(testEvent.id), reason: 'Note should be linked to event');
      expect(note.createdAt, isNotNull, reason: 'Note should have creation timestamp');
      expect(note.updatedAt, isNotNull, reason: 'Note should have update timestamp');
      print('✅ Note table structure verified');
    });

    test('Phase 1: Stroke Serialization/Deserialization', () async {
      print('🔍 PHASE 1: Stroke Serialization/Deserialization Testing');

      // Create test strokes with various complexities
      final testStrokes = [
        // Simple single-point stroke
        Stroke(
          points: [StrokePoint(10.5, 20.5)],
          strokeWidth: 2.0,
          color: 0xFF000000,
        ),
        // Multi-point stroke
        Stroke(
          points: [
            StrokePoint(10.5, 20.5),
            StrokePoint(15.7, 25.3),
            StrokePoint(20.1, 30.8),
          ],
          strokeWidth: 3.5,
          color: 0xFF0000FF,
        ),
        // Complex stroke with pressure
        Stroke(
          points: [
            StrokePoint(50.0, 50.0, pressure: 0.5),
            StrokePoint(55.2, 55.8, pressure: 0.8),
            StrokePoint(60.1, 60.3, pressure: 1.0),
          ],
          strokeWidth: 5.0,
          color: 0xFFFF0000,
        ),
      ];

      print('📝 Testing stroke serialization...');

      // Test individual stroke serialization
      for (int i = 0; i < testStrokes.length; i++) {
        final stroke = testStrokes[i];
        print('🎨 Testing stroke $i: ${stroke.points.length} points, width: ${stroke.strokeWidth}, color: ${stroke.color}');

        // Test stroke to/from map
        final strokeMap = stroke.toMap();
        final deserializedStroke = Stroke.fromMap(strokeMap);

        expect(deserializedStroke.points.length, equals(stroke.points.length),
               reason: 'Point count should be preserved');
        expect(deserializedStroke.strokeWidth, equals(stroke.strokeWidth),
               reason: 'Stroke width should be preserved');
        expect(deserializedStroke.color, equals(stroke.color),
               reason: 'Color should be preserved');

        // Test individual points
        for (int j = 0; j < stroke.points.length; j++) {
          final originalPoint = stroke.points[j];
          final deserializedPoint = deserializedStroke.points[j];

          expect(deserializedPoint.dx, equals(originalPoint.dx),
                 reason: 'Point X coordinate should be preserved');
          expect(deserializedPoint.dy, equals(originalPoint.dy),
                 reason: 'Point Y coordinate should be preserved');
          expect(deserializedPoint.pressure, equals(originalPoint.pressure),
                 reason: 'Point pressure should be preserved');
        }
      }
      print('✅ Individual stroke serialization verified');

      // Test full note serialization with all strokes
      print('📝 Testing full note serialization...');
      final testNote = Note(
        eventId: testEvent.id!,
        strokes: testStrokes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final noteMap = testNote.toMap();
      final deserializedNote = Note.fromMap(noteMap);

      expect(deserializedNote.strokes.length, equals(testStrokes.length),
             reason: 'All strokes should be preserved');
      expect(deserializedNote.eventId, equals(testNote.eventId),
             reason: 'Event ID should be preserved');

      print('✅ Full note serialization verified');
    });

    test('Phase 1: Database Storage and Retrieval', () async {
      print('🔍 PHASE 1: Database Storage and Retrieval Testing');

      // Create test strokes
      final testStrokes = [
        Stroke(
          points: [StrokePoint(10.0, 10.0), StrokePoint(20.0, 20.0)],
          strokeWidth: 2.0,
          color: 0xFF000000,
        ),
        Stroke(
          points: [StrokePoint(30.0, 30.0), StrokePoint(40.0, 40.0), StrokePoint(50.0, 50.0)],
          strokeWidth: 4.0,
          color: 0xFF0000FF,
        ),
      ];

      print('💾 Testing note storage...');
      final noteToSave = Note(
        eventId: testEvent.id!,
        strokes: testStrokes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save note
      final savedNote = await dbService.updateNote(noteToSave);
      expect(savedNote.strokes.length, equals(testStrokes.length),
             reason: 'Saved note should have all strokes');
      print('✅ Note saved successfully with ${savedNote.strokes.length} strokes');

      print('📖 Testing note retrieval...');
      // Retrieve note
      final retrievedNote = await dbService.getNoteByEventId(testEvent.id!);
      expect(retrievedNote, isNotNull, reason: 'Note should be retrievable');
      expect(retrievedNote!.strokes.length, equals(testStrokes.length),
             reason: 'Retrieved note should have all strokes');

      // Verify stroke details
      for (int i = 0; i < testStrokes.length; i++) {
        final originalStroke = testStrokes[i];
        final retrievedStroke = retrievedNote.strokes[i];

        expect(retrievedStroke.points.length, equals(originalStroke.points.length),
               reason: 'Stroke $i point count should match');
        expect(retrievedStroke.strokeWidth, equals(originalStroke.strokeWidth),
               reason: 'Stroke $i width should match');
        expect(retrievedStroke.color, equals(originalStroke.color),
               reason: 'Stroke $i color should match');

        for (int j = 0; j < originalStroke.points.length; j++) {
          final originalPoint = originalStroke.points[j];
          final retrievedPoint = retrievedStroke.points[j];

          expect(retrievedPoint.dx, equals(originalPoint.dx),
                 reason: 'Stroke $i point $j X should match');
          expect(retrievedPoint.dy, equals(originalPoint.dy),
                 reason: 'Stroke $i point $j Y should match');
        }
      }
      print('✅ Note retrieved successfully with all data intact');
    });

    test('Phase 1: Update Operations', () async {
      print('🔍 PHASE 1: Update Operations Testing');

      // Create initial note with strokes
      final initialStrokes = [
        Stroke(points: [StrokePoint(10.0, 10.0)], strokeWidth: 2.0, color: 0xFF000000),
      ];

      final initialNote = Note(
        eventId: testEvent.id!,
        strokes: initialStrokes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await dbService.updateNote(initialNote);
      print('📝 Initial note saved with ${initialStrokes.length} strokes');

      // Update with additional strokes
      final updatedStrokes = [
        ...initialStrokes,
        Stroke(points: [StrokePoint(20.0, 20.0)], strokeWidth: 3.0, color: 0xFF0000FF),
        Stroke(points: [StrokePoint(30.0, 30.0)], strokeWidth: 4.0, color: 0xFF00FF00),
      ];

      final updatedNote = Note(
        eventId: testEvent.id!,
        strokes: updatedStrokes,
        createdAt: initialNote.createdAt,
        updatedAt: DateTime.now(),
      );

      await dbService.updateNote(updatedNote);
      print('📝 Note updated with ${updatedStrokes.length} strokes');

      // Verify update
      final finalNote = await dbService.getNoteByEventId(testEvent.id!);
      expect(finalNote, isNotNull, reason: 'Updated note should be retrievable');
      expect(finalNote!.strokes.length, equals(updatedStrokes.length),
             reason: 'Updated note should have all strokes');
      expect(finalNote.updatedAt.isAfter(initialNote.updatedAt), isTrue,
             reason: 'Updated timestamp should be newer');

      print('✅ Update operations verified successfully');
    });

    tearDown(() async {
      await dbService.clearAllData();
      await dbService.close();
    });
  });
}