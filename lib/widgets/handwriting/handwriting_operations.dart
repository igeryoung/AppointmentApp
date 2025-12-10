import 'package:flutter/material.dart';
import '../../models/note.dart';

/// Drawing tool type enum
enum DrawingTool {
  pen,
  highlighter,
  eraser,
}

/// Base class for canvas operations that can be undone/redone
abstract class CanvasOperation {
  void undo(List<Stroke> strokes);
  void redo(List<Stroke> strokes);
}

/// Operation for adding a stroke (drawing)
class DrawOperation extends CanvasOperation {
  final Stroke stroke;

  DrawOperation(this.stroke);

  @override
  void undo(List<Stroke> strokes) {
    strokes.removeLast();
  }

  @override
  void redo(List<Stroke> strokes) {
    strokes.add(stroke);
  }
}

/// Operation for erasing (which may remove/modify multiple strokes)
class EraseOperation extends CanvasOperation {
  final List<Stroke> strokesBefore;
  final List<Stroke> strokesAfter;

  EraseOperation({
    required this.strokesBefore,
    required this.strokesAfter,
  });

  @override
  void undo(List<Stroke> strokes) {
    strokes.clear();
    strokes.addAll(strokesBefore);
  }

  @override
  void redo(List<Stroke> strokes) {
    strokes.clear();
    strokes.addAll(strokesAfter);
  }
}

/// Operation for clearing all strokes
class ClearOperation extends CanvasOperation {
  final List<Stroke> clearedStrokes;

  ClearOperation(this.clearedStrokes);

  @override
  void undo(List<Stroke> strokes) {
    strokes.addAll(clearedStrokes);
  }

  @override
  void redo(List<Stroke> strokes) {
    strokes.clear();
  }
}
