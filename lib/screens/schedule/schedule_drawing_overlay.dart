import 'package:flutter/material.dart';

import '../../models/schedule_drawing.dart';
import '../../widgets/handwriting_canvas.dart';

/// Drawing overlay for schedule screen
///
/// Wraps HandwritingCanvas with appropriate ignore/absorb pointer behavior
class ScheduleDrawingOverlay extends StatelessWidget {
  final GlobalKey<HandwritingCanvasState> canvasKey;
  final ScheduleDrawing? currentDrawing;
  final bool isDrawingMode;
  final bool showDrawing;
  final VoidCallback onStrokesChanged;

  const ScheduleDrawingOverlay({
    super.key,
    required this.canvasKey,
    required this.currentDrawing,
    required this.isDrawingMode,
    required this.showDrawing,
    required this.onStrokesChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Hide drawing completely if showDrawing is false
    if (!showDrawing) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: !isDrawingMode, // Only allow drawing when in drawing mode
      child: HandwritingCanvas(
        key: canvasKey,
        initialStrokes: currentDrawing?.strokes ?? [],
        onStrokesChanged: onStrokesChanged,
      ),
    );
  }
}
