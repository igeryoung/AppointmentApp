import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/note.dart';
import '../lib/widgets/handwriting_canvas.dart';

/// Test suite to diagnose canvas state management issues
void main() {
  group('Canvas State Management Diagnosis', () {
    testWidgets('Phase 2: Canvas State Initialization', (WidgetTester tester) async {
      print('🔍 PHASE 2: Canvas State Initialization Testing');

      // Test empty canvas initialization
      print('📝 Testing empty canvas initialization...');
      final GlobalKey<HandwritingCanvasState> canvasKey = GlobalKey<HandwritingCanvasState>();

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

      // Verify initial state
      final canvasState = canvasKey.currentState;
      expect(canvasState, isNotNull, reason: 'Canvas state should be available');

      final initialStrokes = canvasState!.getStrokes();
      expect(initialStrokes, isEmpty, reason: 'Initial canvas should have no strokes');

      print('✅ Empty canvas initialization verified');
    });

    testWidgets('Phase 2: Canvas Stroke Capture Simulation', (WidgetTester tester) async {
      print('🔍 PHASE 2: Canvas Stroke Capture Simulation');

      final GlobalKey<HandwritingCanvasState> canvasKey = GlobalKey<HandwritingCanvasState>();
      bool strokesChangedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: const [],
              onStrokesChanged: () {
                strokesChangedCalled = true;
                print('📱 Canvas onStrokesChanged callback fired');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      print('📝 Testing stroke capture via gesture simulation...');
      final canvasState = canvasKey.currentState!;

      // Simulate drawing a stroke by calling internal methods directly
      final testGesture = await tester.startGesture(const Offset(50, 50));
      await testGesture.moveTo(const Offset(100, 100));
      await testGesture.moveTo(const Offset(150, 150));
      await testGesture.up();

      await tester.pumpAndSettle();

      // Verify stroke was captured
      final strokes = canvasState.getStrokes();
      print('📊 Canvas captured ${strokes.length} strokes');

      expect(strokes.length, greaterThan(0), reason: 'Canvas should capture stroke from gesture');
      expect(strokesChangedCalled, isTrue, reason: 'onStrokesChanged should be called');

      if (strokes.isNotEmpty) {
        final firstStroke = strokes.first;
        print('🎨 First stroke: ${firstStroke.points.length} points, color: ${firstStroke.color}');
        expect(firstStroke.points.length, greaterThan(0), reason: 'Stroke should have points');
      }

      print('✅ Stroke capture simulation verified');
    });

    testWidgets('Phase 2: Canvas Initial Strokes Loading', (WidgetTester tester) async {
      print('🔍 PHASE 2: Canvas Initial Strokes Loading');

      // Create test strokes to load
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

      print('📝 Testing canvas with ${testStrokes.length} initial strokes...');
      final GlobalKey<HandwritingCanvasState> canvasKey = GlobalKey<HandwritingCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: testStrokes,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify strokes were loaded
      final canvasState = canvasKey.currentState!;
      final loadedStrokes = canvasState.getStrokes();

      print('📊 Canvas loaded ${loadedStrokes.length} strokes');
      expect(loadedStrokes.length, equals(testStrokes.length),
             reason: 'Canvas should load all initial strokes');

      // Verify stroke details
      for (int i = 0; i < testStrokes.length; i++) {
        final original = testStrokes[i];
        final loaded = loadedStrokes[i];

        expect(loaded.points.length, equals(original.points.length),
               reason: 'Loaded stroke $i should have same point count');
        expect(loaded.strokeWidth, equals(original.strokeWidth),
               reason: 'Loaded stroke $i should have same width');
        expect(loaded.color, equals(original.color),
               reason: 'Loaded stroke $i should have same color');

        print('🎨 Stroke $i verified: ${loaded.points.length} points, width: ${loaded.strokeWidth}');
      }

      print('✅ Initial strokes loading verified');
    });

    testWidgets('Phase 2: Canvas Widget Update Behavior', (WidgetTester tester) async {
      print('🔍 PHASE 2: Canvas Widget Update Behavior');

      final GlobalKey<HandwritingCanvasState> canvasKey = GlobalKey<HandwritingCanvasState>();

      // Start with empty strokes
      print('📝 Testing widget rebuild with changing initial strokes...');
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

      // Add a user stroke
      print('📝 Simulating user drawing...');
      final testGesture = await tester.startGesture(const Offset(50, 50));
      await testGesture.moveTo(const Offset(100, 100));
      await testGesture.up();
      await tester.pumpAndSettle();

      final canvasState = canvasKey.currentState!;
      final userStrokes = canvasState.getStrokes();
      print('📊 User drew ${userStrokes.length} strokes');

      // Now simulate a widget update with new initial strokes (like loading from database)
      final newInitialStrokes = [
        Stroke(
          points: [StrokePoint(200.0, 200.0), StrokePoint(250.0, 250.0)],
          strokeWidth: 3.0,
          color: 0xFF00FF00,
        ),
      ];

      print('📝 Rebuilding widget with new initial strokes...');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HandwritingCanvas(
              key: canvasKey,
              initialStrokes: newInitialStrokes,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check what happens to strokes after widget update
      final finalStrokes = canvasState.getStrokes();
      print('📊 After widget update: ${finalStrokes.length} strokes');

      // This is a critical test - what should happen?
      // According to the current logic, it should preserve user strokes if they exist
      // and only update if we're getting MORE strokes or the canvas is empty

      if (finalStrokes.length > userStrokes.length) {
        print('✅ Widget update added new strokes (loaded state)');
      } else if (finalStrokes.length == userStrokes.length) {
        print('⚠️ Widget update preserved user strokes (may be expected behavior)');
      } else {
        print('❌ Widget update lost strokes - this could be the bug!');
      }

      print('✅ Widget update behavior analyzed');
    });

    testWidgets('Phase 2: Canvas State Persistence Methods', (WidgetTester tester) async {
      print('🔍 PHASE 2: Canvas State Persistence Methods');

      final GlobalKey<HandwritingCanvasState> canvasKey = GlobalKey<HandwritingCanvasState>();

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

      final canvasState = canvasKey.currentState!;

      // Test loadStrokes method
      print('📝 Testing loadStrokes method...');
      final testStrokes = [
        Stroke(
          points: [StrokePoint(10.0, 10.0)],
          strokeWidth: 2.0,
          color: 0xFF000000,
        ),
      ];

      canvasState.loadStrokes(testStrokes);
      await tester.pumpAndSettle();

      final loadedStrokes = canvasState.getStrokes();
      expect(loadedStrokes.length, equals(1), reason: 'loadStrokes should work');
      print('✅ loadStrokes method verified');

      // Test forceRefreshState method
      print('📝 Testing forceRefreshState method...');
      final moreStrokes = [
        ...testStrokes,
        Stroke(
          points: [StrokePoint(20.0, 20.0)],
          strokeWidth: 3.0,
          color: 0xFF0000FF,
        ),
      ];

      canvasState.forceRefreshState(moreStrokes);
      await tester.pumpAndSettle();

      final refreshedStrokes = canvasState.getStrokes();
      expect(refreshedStrokes.length, equals(2), reason: 'forceRefreshState should work');
      print('✅ forceRefreshState method verified');

      // Test state validation
      print('📝 Testing state validation...');
      canvasState.validateState();
      final stateInfo = canvasState.getStateInfo();
      print('📊 Canvas state info: $stateInfo');
      expect(stateInfo['strokeCount'], equals(2), reason: 'State info should be accurate');
      print('✅ State validation verified');
    });
  });
}