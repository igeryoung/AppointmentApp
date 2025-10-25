import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/book.dart';
import '../lib/models/event.dart';
import '../lib/models/note.dart';
import '../lib/services/web_prd_database_service.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/widgets/handwriting_canvas.dart';

/// Test to reproduce the exact save/load bug scenario
void main() {
  group('Event Flow Diagnosis', () {
    testWidgets('Phase 3: Reproduce Save/Load Bug', (WidgetTester tester) async {
      print('🔍 PHASE 3: Reproducing the Save/Load Bug');

      // Setup database
      WebPRDDatabaseService.resetInstance();
      final dbService = WebPRDDatabaseService();
      await dbService.clearAllData();

      // Create test data
      final book = await dbService.createBook('Test Book');
      final event = await dbService.createEvent(Event(
        bookId: book.id!,
        name: 'Test Event',
        recordNumber: 'TEST001',
        eventType: 'Consultation',
        startTime: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      print('📝 Test Setup: Created event with ID ${event.id}');

      // Step 1: Simulate saving an event with handwritten notes
      print('📝 Step 1: Opening event for editing and adding strokes...');

      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            event: event,
            isNew: false,
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Find the canvas and simulate drawing
      final canvasFinder = find.byType(CustomPaint);
      expect(canvasFinder, findsOneWidget);

      // Simulate drawing a stroke
      print('🎨 Drawing test stroke...');
      await tester.drag(canvasFinder, const Offset(100, 100));
      await tester.pumpAndSettle();

      // Save the event
      print('💾 Saving event...');
      final saveButtonFinder = find.byIcon(Icons.save);
      expect(saveButtonFinder, findsOneWidget);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Step 2: Verify note was saved to database
      print('📖 Step 2: Verifying note was saved to database...');
      final savedNote = await dbService.getNoteByEventId(event.id!);
      expect(savedNote, isNotNull, reason: 'Note should be saved');
      expect(savedNote!.strokes.length, greaterThan(0), reason: 'Note should have strokes');
      print('✅ Database contains ${savedNote.strokes.length} strokes');

      // Step 3: Simulate reopening the same event
      print('📖 Step 3: Reopening the same event (this should load the saved strokes)...');

      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            event: event,
            isNew: false,
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Step 4: Check if strokes are displayed in canvas
      print('🔍 Step 4: Checking if saved strokes are displayed...');

      // We need to find a way to check if the canvas is displaying the strokes
      // Since we can't directly access the canvas state in widget tests easily,
      // let's create a more focused test on the canvas behavior

      print('📊 Test completed - manual verification needed in real app');
    });

    testWidgets('Phase 3: Canvas Widget Update Reproduction', (WidgetTester tester) async {
      print('🔍 PHASE 3: Canvas Widget Update Bug Reproduction');

      final GlobalKey<State> canvasKey = GlobalKey<State>();

      // Create saved strokes (simulating what comes from database)
      final savedStrokes = [
        Stroke(
          points: [StrokePoint(10.0, 10.0), StrokePoint(20.0, 20.0)],
          strokeWidth: 2.0,
          color: 0xFF000000,
        ),
      ];

      // Step 1: Build canvas with empty strokes (initial state)
      print('📝 Step 1: Building canvas with empty initial strokes...');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final initialStrokes = <Stroke>[]; // Empty initially
                return HandwritingCanvas(
                  key: canvasKey,
                  initialStrokes: initialStrokes,
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Step 2: Rebuild with loaded strokes (simulating note load)
      print('📝 Step 2: Rebuilding with loaded strokes (simulating database load)...');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final initialStrokes = savedStrokes; // Now with saved strokes
                return HandwritingCanvas(
                  key: canvasKey,
                  initialStrokes: initialStrokes,
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Step 3: Check if canvas shows the strokes
      print('📝 Step 3: Checking if canvas displays loaded strokes...');

      final canvasState = canvasKey.currentState as HandwritingCanvasState?;
      if (canvasState != null) {
        final displayedStrokes = canvasState.getStrokes();
        print('📊 Canvas shows ${displayedStrokes.length} strokes (expected: ${savedStrokes.length})');

        if (displayedStrokes.length == savedStrokes.length) {
          print('✅ SUCCESS: Canvas displays loaded strokes correctly');
        } else {
          print('❌ BUG CONFIRMED: Canvas does not display loaded strokes');
          print('   Expected: ${savedStrokes.length} strokes');
          print('   Actual: ${displayedStrokes.length} strokes');
        }
      } else {
        print('❌ Could not access canvas state');
      }
    });

    testWidgets('Phase 3: Widget Update Edge Cases', (WidgetTester tester) async {
      print('🔍 PHASE 3: Testing Widget Update Edge Cases');

      final GlobalKey<HandwritingCanvasState> canvasKey = GlobalKey<HandwritingCanvasState>();

      // Test Case 1: Empty → Non-empty (should work)
      print('📝 Test Case 1: Empty → Non-empty strokes...');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: [
                Stroke(points: [StrokePoint(10, 10)], strokeWidth: 2.0, color: 0xFF000000),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var strokes = canvasKey.currentState!.getStrokes();
      print('📊 Case 1 result: ${strokes.length} strokes (expected: 1)');

      // Test Case 2: Same strokes → Same strokes (the problematic case)
      print('📝 Test Case 2: Same strokes → Same strokes (should preserve)...');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: [
                Stroke(points: [StrokePoint(10, 10)], strokeWidth: 2.0, color: 0xFF000000),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      strokes = canvasKey.currentState!.getStrokes();
      print('📊 Case 2 result: ${strokes.length} strokes (expected: 1)');

      // Test Case 3: Non-empty → Different non-empty (should update)
      print('📝 Test Case 3: Different non-empty strokes (should update)...');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: [
                Stroke(points: [StrokePoint(20, 20)], strokeWidth: 3.0, color: 0xFF0000FF),
                Stroke(points: [StrokePoint(30, 30)], strokeWidth: 4.0, color: 0xFF00FF00),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      strokes = canvasKey.currentState!.getStrokes();
      print('📊 Case 3 result: ${strokes.length} strokes (expected: 2)');

      print('✅ Edge case testing completed');
    });
  });
}