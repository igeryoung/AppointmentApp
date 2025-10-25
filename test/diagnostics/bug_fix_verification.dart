import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/note.dart';
import '../lib/widgets/handwriting_canvas.dart';

/// Test to verify the specific bug fix for note loading
void main() {
  group('Bug Fix Verification', () {
    testWidgets('CRITICAL: Empty canvas loads saved strokes correctly', (WidgetTester tester) async {
      print('🔍 CRITICAL TEST: Empty canvas should load saved strokes');

      final GlobalKey<HandwritingCanvasState> canvasKey = GlobalKey<HandwritingCanvasState>();

      // Simulate saved strokes from database
      final savedStrokes = [
        Stroke(
          points: [StrokePoint(10.0, 10.0), StrokePoint(20.0, 20.0)],
          strokeWidth: 2.0,
          color: 0xFF000000,
        ),
        Stroke(
          points: [StrokePoint(30.0, 30.0), StrokePoint(40.0, 40.0)],
          strokeWidth: 3.0,
          color: 0xFF0000FF,
        ),
      ];

      // Step 1: Start with empty canvas (simulating new event screen)
      print('📝 Step 1: Creating empty canvas...');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: const [], // Empty initially
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var canvasState = canvasKey.currentState!;
      var strokes = canvasState.getStrokes();
      expect(strokes.length, equals(0), reason: 'Canvas should start empty');
      print('✅ Step 1: Canvas starts empty (${strokes.length} strokes)');

      // Step 2: Widget rebuilds with loaded strokes (simulating note load from database)
      print('📝 Step 2: Rebuilding with loaded strokes...');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: savedStrokes, // Now with saved strokes
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 3: Verify strokes are displayed
      strokes = canvasState.getStrokes();
      print('📊 Step 3: Canvas shows ${strokes.length} strokes (expected: ${savedStrokes.length})');

      expect(strokes.length, equals(savedStrokes.length),
             reason: 'BUG FIX: Canvas should display loaded strokes');

      // Verify stroke details match
      for (int i = 0; i < savedStrokes.length; i++) {
        final original = savedStrokes[i];
        final displayed = strokes[i];

        expect(displayed.points.length, equals(original.points.length),
               reason: 'Stroke $i should have correct point count');
        expect(displayed.strokeWidth, equals(original.strokeWidth),
               reason: 'Stroke $i should have correct width');
        expect(displayed.color, equals(original.color),
               reason: 'Stroke $i should have correct color');
      }

      print('✅ SUCCESS: Bug is FIXED! Saved strokes load correctly');
    });

    testWidgets('EDGE CASE: Canvas preserves user work when appropriate', (WidgetTester tester) async {
      print('🔍 EDGE CASE: Canvas should preserve user work');

      final GlobalKey<HandwritingCanvasState> canvasKey = GlobalKey<HandwritingCanvasState>();

      // Start with empty canvas
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

      // Simulate user drawing
      print('📝 User draws some strokes...');
      final testGesture = await tester.startGesture(const Offset(50, 50));
      await testGesture.moveTo(const Offset(100, 100));
      await testGesture.up();
      await tester.pumpAndSettle();

      var canvasState = canvasKey.currentState!;
      var userStrokes = canvasState.getStrokes();
      expect(userStrokes.length, equals(1), reason: 'User should have drawn 1 stroke');
      print('✅ User drew ${userStrokes.length} strokes');

      // Now simulate widget rebuild with empty strokes (could happen due to app state changes)
      print('📝 Widget rebuilds with empty strokes (should preserve user work)...');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: const [], // Empty strokes
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify user strokes are preserved
      var finalStrokes = canvasState.getStrokes();
      print('📊 Final strokes: ${finalStrokes.length} (should preserve user work)');

      expect(finalStrokes.length, equals(1),
             reason: 'User work should be preserved');

      print('✅ SUCCESS: User work preserved correctly');
    });

    testWidgets('REGRESSION: Canvas handles stroke count increases', (WidgetTester tester) async {
      print('🔍 REGRESSION: Canvas should handle stroke count increases');

      final GlobalKey<HandwritingCanvasState> canvasKey = GlobalKey<HandwritingCanvasState>();

      // Start with some strokes
      final initialStrokes = [
        Stroke(points: [StrokePoint(10, 10)], strokeWidth: 2.0, color: 0xFF000000),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: initialStrokes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var canvasState = canvasKey.currentState!;
      var strokes = canvasState.getStrokes();
      expect(strokes.length, equals(1), reason: 'Should start with 1 stroke');
      print('✅ Started with ${strokes.length} strokes');

      // Update with more strokes
      final moreStrokes = [
        ...initialStrokes,
        Stroke(points: [StrokePoint(20, 20)], strokeWidth: 3.0, color: 0xFF0000FF),
        Stroke(points: [StrokePoint(30, 30)], strokeWidth: 4.0, color: 0xFF00FF00),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: moreStrokes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      strokes = canvasState.getStrokes();
      expect(strokes.length, equals(3), reason: 'Should update to 3 strokes');
      print('✅ Updated to ${strokes.length} strokes');

      print('✅ SUCCESS: Stroke count increases handled correctly');
    });
  });
}