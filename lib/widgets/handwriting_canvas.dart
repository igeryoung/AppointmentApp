import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/note.dart';

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
    // Remove the last stroke (most recently drawn)
    strokes.removeLast();
  }

  @override
  void redo(List<Stroke> strokes) {
    // Add the stroke back
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
    // Restore strokes to state before erase
    strokes.clear();
    strokes.addAll(strokesBefore);
  }

  @override
  void redo(List<Stroke> strokes) {
    // Apply erase result again
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
    // Restore all cleared strokes
    strokes.addAll(clearedStrokes);
  }

  @override
  void redo(List<Stroke> strokes) {
    // Clear all strokes again
    strokes.clear();
  }
}

/// Handwriting Canvas Widget for PRD-compliant handwriting-only notes
class HandwritingCanvas extends StatefulWidget {
  final List<Stroke> initialStrokes;
  final VoidCallback? onStrokesChanged;

  const HandwritingCanvas({
    super.key,
    this.initialStrokes = const [],
    this.onStrokesChanged,
  });

  @override
  State<HandwritingCanvas> createState() => HandwritingCanvasState();
}

class HandwritingCanvasState extends State<HandwritingCanvas> {
  List<Stroke> _strokes = [];
  List<CanvasOperation> _operationHistory = []; // Track all completed operations
  List<CanvasOperation> _redoStack = []; // Track operations that can be redone
  Stroke? _currentStroke;

  // Track erase operation state
  List<Stroke>? _strokesBeforeErase;

  // Drawing settings
  DrawingTool _currentTool = DrawingTool.pen;

  // Pen settings
  Color _strokeColor = Colors.black;
  double _strokeWidth = 2.0;

  // Highlighter settings
  Color _highlighterColor = const Color(0x66FFEB3B); // Yellow with 40% opacity
  double _highlighterWidth = 10.0;

  // Eraser settings
  double _eraserRadius = 20.0;

  // Canvas bounds tracking
  Size _canvasSize = Size.zero;

  // Pointer tracking for multi-touch detection
  final Set<int> _activePointers = {}; // Track all active pointer IDs

  // Pointer tracking for eraser visualization
  Offset? _currentPointerPosition;

  // Race condition prevention: Synchronization flags
  bool _isUndoRedoInProgress = false;

  // Canvas version tracking to prevent stale data overwrites
  int _canvasVersion = 0;

  @override
  void initState() {
    super.initState();
    _strokes = List<Stroke>.from(widget.initialStrokes);
    debugPrint('🎨 Canvas: initState() with ${widget.initialStrokes.length} initial strokes');
    debugPrint('🎨 Canvas: Internal _strokes now has ${_strokes.length} strokes');
  }

  @override
  void didUpdateWidget(HandwritingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update strokes if initialStrokes changed (e.g., when note loads)
    if (oldWidget.initialStrokes != widget.initialStrokes) {
      debugPrint('🎨 Canvas: didUpdateWidget triggered');
      debugPrint('🎨 Canvas: Old strokes: ${oldWidget.initialStrokes.length}, New strokes: ${widget.initialStrokes.length}');

      // ENHANCED LOGIC: Update canvas strokes when:
      // 1. Canvas is currently empty AND we have strokes to load (note loading)
      // 2. We're getting MORE strokes than the widget had before (external update)
      // 3. Widget initialStrokes length matches our current strokes (consistent state)
      //
      // PRESERVE user strokes when:
      // - User has drawn content and widget didn't change stroke count
      // - Widget rebuilds with same empty strokes while user has drawn content
      // - This prevents accidental clearing of user work

      final currentStrokeCount = _strokes.length;
      final newStrokeCount = widget.initialStrokes.length;
      final oldStrokeCount = oldWidget.initialStrokes.length;

      final isCanvasEmpty = currentStrokeCount == 0;
      final hasNewWidgetContent = newStrokeCount > oldStrokeCount;
      final isLoadingContent = isCanvasEmpty && newStrokeCount > 0;
      final widgetStrokeCountUnchanged = newStrokeCount == oldStrokeCount;
      final wouldLoseUserWork = currentStrokeCount > 0 && newStrokeCount < currentStrokeCount;
      final hasUserWork = currentStrokeCount > 0 && oldStrokeCount == 0;

      // Determine if we should update
      final shouldUpdate = isLoadingContent ||
                          (hasNewWidgetContent && !wouldLoseUserWork);

      debugPrint('🔍 Canvas: Update decision analysis:');
      debugPrint('   - Current canvas strokes: $currentStrokeCount');
      debugPrint('   - New widget strokes: $newStrokeCount');
      debugPrint('   - Old widget strokes: $oldStrokeCount');
      debugPrint('   - Canvas is empty: $isCanvasEmpty');
      debugPrint('   - Has new widget content: $hasNewWidgetContent');
      debugPrint('   - Is loading content: $isLoadingContent');
      debugPrint('   - Widget stroke count unchanged: $widgetStrokeCountUnchanged');
      debugPrint('   - Would lose user work: $wouldLoseUserWork');
      debugPrint('   - Has user work: $hasUserWork');
      debugPrint('   - Decision: ${shouldUpdate ? "UPDATE" : "PRESERVE"}');

      if (shouldUpdate) {
        debugPrint('🎨 Canvas: Updating strokes ($currentStrokeCount → $newStrokeCount)');

        // Validate state before update
        validateState();

        _strokes = List<Stroke>.from(widget.initialStrokes);
        // RACE CONDITION FIX: NEVER clear undo history on widget updates
        // This preserves user's ability to undo/redo across widget rebuilds
        // _operationHistory.clear();  // REMOVED - causes undo history loss
        // _redoStack.clear();          // REMOVED - causes undo history loss

        // CRITICAL: Only clear _currentStroke when actually loading saved content
        // Don't clear it on widget rebuilds (AnimatedBuilder) - user might be actively drawing!
        // Clear only when loading non-empty saved strokes (switching to different note/drawing)
        if (newStrokeCount > 0 && oldStrokeCount == 0) {
          // Loading saved content into empty canvas - clear current stroke
          _currentStroke = null;
          debugPrint('🎨 Canvas: Cleared _currentStroke (loading saved content)');
        } else {
          debugPrint('🎨 Canvas: Preserved _currentStroke (widget rebuild, user may be drawing)');
        }

        debugPrint('🎨 Canvas: Updated internal _strokes to ${_strokes.length} strokes');

        // Trigger a rebuild to show the loaded strokes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {});
            debugPrint('🔄 Canvas: Post-frame callback - Rebuilt with ${_strokes.length} strokes');
            validateState();
          }
        });
      } else {
        debugPrint('🛡️ Canvas: Preserving $currentStrokeCount user strokes (not updating)');
      }
    }
  }

  /// Get current strokes (for saving)
  List<Stroke> getStrokes() {
    debugPrint('🎨 Canvas: getStrokes() called - returning ${_strokes.length} strokes');
    final List<Stroke> strokes = List<Stroke>.from(_strokes);
    debugPrint('🎨 Canvas: getStrokes() - copied ${strokes.length} strokes for return');
    return strokes;
  }

  /// Load strokes from external source (for loading saved notes)
  void loadStrokes(List<Stroke> strokes) {
    debugPrint('🎨 Canvas: loadStrokes() called with ${strokes.length} strokes');
    setState(() {
      _strokes = List<Stroke>.from(strokes);
      // RACE CONDITION FIX: Preserve undo history even when loading
      // _operationHistory.clear();  // REMOVED
      // _redoStack.clear();          // REMOVED
      _currentStroke = null;
      _strokesBeforeErase = null;
      _canvasVersion++; // Increment version when loading new content
    });
    debugPrint('🎨 Canvas: loadStrokes() completed. Internal _strokes now has ${_strokes.length} strokes, version: $_canvasVersion');
  }

  /// Get current drawing settings
  DrawingTool get currentTool => _currentTool;
  bool get isErasing => _currentTool == DrawingTool.eraser;
  bool get isHighlighting => _currentTool == DrawingTool.highlighter;

  // Pen getters
  Color get strokeColor => _strokeColor;
  double get strokeWidth => _strokeWidth;

  // Highlighter getters
  Color get highlighterColor => _highlighterColor;
  double get highlighterWidth => _highlighterWidth;

  // Eraser getters
  double get eraserRadius => _eraserRadius;

  /// Check if undo is available
  bool get canUndo => _operationHistory.isNotEmpty;

  /// Check if redo is available
  bool get canRedo => _redoStack.isNotEmpty;

  /// Get current canvas version
  int get canvasVersion => _canvasVersion;

  /// Validate canvas internal state
  void validateState() {
    debugPrint('🔍 Canvas: State validation - _strokes: ${_strokes.length}, _operationHistory: ${_operationHistory.length}, _redoStack: ${_redoStack.length}');
    debugPrint('🔍 Canvas: Current stroke: ${_currentStroke != null ? "${_currentStroke!.points.length} points" : "null"}');

    // Validate stroke integrity
    for (int i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      if (stroke.points.isEmpty) {
        debugPrint('⚠️ Canvas: WARNING - Stroke $i has no points!');
      }
    }
  }

  /// Force refresh canvas state with explicit stroke list
  void forceRefreshState(List<Stroke> strokes) {
    debugPrint('🔄 Canvas: Force refresh with ${strokes.length} strokes');
    setState(() {
      _strokes = List<Stroke>.from(strokes);
      _operationHistory.clear();
      _redoStack.clear();
      _currentStroke = null;
    });
    debugPrint('🔄 Canvas: Force refresh completed. Internal state: ${_strokes.length} strokes');
  }

  /// Get detailed state information
  Map<String, dynamic> getStateInfo() {
    return {
      'strokeCount': _strokes.length,
      'operationHistoryCount': _operationHistory.length,
      'redoStackCount': _redoStack.length,
      'hasCurrentStroke': _currentStroke != null,
      'currentStrokePoints': _currentStroke?.points.length ?? 0,
    };
  }

  /// Clip point to canvas bounds
  Offset _clipPointToBounds(Offset point) {
    if (_canvasSize == Size.zero) return point;

    final clippedX = point.dx.clamp(0.0, _canvasSize.width);
    final clippedY = point.dy.clamp(0.0, _canvasSize.height);
    return Offset(clippedX, clippedY);
  }

  /// Start a new stroke
  void _startStroke(Offset point, int pointerId) {
    // Add pointer to active set
    _activePointers.add(pointerId);

    // ONLY start drawing if this is a SINGLE-finger touch
    if (_activePointers.length > 1) {
      debugPrint('🚫 Multi-touch detected (${_activePointers.length} fingers) - ignoring draw');
      // Cancel any in-progress stroke
      _currentStroke = null;
      _currentPointerPosition = null;
      setState(() {});
      return;
    }

    debugPrint('👆 TOUCH: raw localPosition=(${point.dx.toStringAsFixed(2)}, ${point.dy.toStringAsFixed(2)})');

    final clippedPoint = _clipPointToBounds(point);
    debugPrint('🎨 Canvas: Starting new stroke at local:(${point.dx.toStringAsFixed(2)}, ${point.dy.toStringAsFixed(2)}) clipped:(${clippedPoint.dx.toStringAsFixed(2)}, ${clippedPoint.dy.toStringAsFixed(2)}) canvasSize:(${_canvasSize.width.toStringAsFixed(2)}, ${_canvasSize.height.toStringAsFixed(2)})');

    // Update pointer position for eraser visualization
    _currentPointerPosition = point;

    if (_currentTool == DrawingTool.eraser) {
      // For eraser mode, save state before erasing
      _strokesBeforeErase = List<Stroke>.from(_strokes);
      _eraseStrokesAtPoint(clippedPoint);
      _currentStroke = null; // No stroke to create in eraser mode

      // Clear redo stack when starting new erase operation (standard undo/redo behavior)
      _redoStack.clear();
    } else {
      // For drawing mode (pen or highlighter), create a new stroke with the first point
      final strokeType = _currentTool == DrawingTool.highlighter
          ? StrokeType.highlighter
          : StrokeType.pen;
      final color = _currentTool == DrawingTool.highlighter
          ? _highlighterColor
          : _strokeColor;
      final width = _currentTool == DrawingTool.highlighter
          ? _highlighterWidth
          : _strokeWidth;

      _currentStroke = Stroke(
        points: [StrokePoint(clippedPoint.dx, clippedPoint.dy)],
        strokeWidth: width,
        color: color.value,
        strokeType: strokeType,
      );
      debugPrint('✏️ STROKE: firstPoint=(${clippedPoint.dx.toStringAsFixed(2)}, ${clippedPoint.dy.toStringAsFixed(2)}) strokeWidth=$width tool=$_currentTool');

      // Clear redo stack when starting new drawing operation (standard undo/redo behavior)
      _redoStack.clear();
      debugPrint('🎨 Canvas: Current stroke created with 1 point');
    }

    setState(() {});
  }

  /// Add point to current stroke
  void _addPointToStroke(Offset point) {
    // If multi-touch is active, stop drawing
    if (_activePointers.length > 1) {
      // Cancel current stroke if one exists
      if (_currentStroke != null) {
        debugPrint('🚫 Second finger detected - canceling current stroke');
        _currentStroke = null;
        _currentPointerPosition = null;
        setState(() {});
      }
      return;
    }

    final clippedPoint = _clipPointToBounds(point);

    // Update pointer position for eraser visualization
    _currentPointerPosition = point;

    if (_currentTool == DrawingTool.eraser) {
      // Continue erasing at this point
      _eraseStrokesAtPoint(clippedPoint);
      setState(() {});
    } else if (_currentStroke != null) {
      // Add point to current drawing stroke (pen or highlighter)
      _currentStroke = _currentStroke!.addPoint(
        StrokePoint(clippedPoint.dx, clippedPoint.dy),
      );
      setState(() {});
    }
  }

  /// End current stroke
  void _endStroke(int pointerId) {
    // Remove pointer from active set
    _activePointers.remove(pointerId);

    // Only complete stroke if this was a single-touch gesture
    if (_activePointers.isEmpty) {
      if (_currentStroke != null && _currentStroke!.points.isNotEmpty) {
        debugPrint('🎨 Canvas: Ending stroke with ${_currentStroke!.points.length} points');

        // Add stroke to canvas
        _strokes.add(_currentStroke!);

        // Create and record DrawOperation for undo/redo
        final operation = DrawOperation(_currentStroke!);
        _operationHistory.add(operation);

        // Increment canvas version to track state changes
        _canvasVersion++;

        debugPrint('🎨 Canvas: Added stroke to _strokes. Total strokes now: ${_strokes.length}, Version: $_canvasVersion');
        _currentStroke = null;
        _currentPointerPosition = null; // Clear pointer position when done

        widget.onStrokesChanged?.call();
        debugPrint('🎨 Canvas: Called onStrokesChanged callback');
        setState(() {});
      } else {
        debugPrint('🎨 Canvas: _endStroke called but no valid current stroke to add');
        _currentPointerPosition = null; // Clear pointer position
        // If we were erasing, create EraseOperation
        if (_currentTool == DrawingTool.eraser && _strokesBeforeErase != null) {
          final strokesAfter = List<Stroke>.from(_strokes);
          // Only record if something actually changed
          if (_strokesBeforeErase!.length != strokesAfter.length ||
              !_strokesEqual(_strokesBeforeErase!, strokesAfter)) {
            final operation = EraseOperation(
              strokesBefore: _strokesBeforeErase!,
              strokesAfter: strokesAfter,
            );
            _operationHistory.add(operation);
            // Increment canvas version to track state changes
            _canvasVersion++;
            debugPrint('🎨 Canvas: Recorded EraseOperation, Version: $_canvasVersion');
          }
          _strokesBeforeErase = null;
          widget.onStrokesChanged?.call();
        }
      }
    } else {
      // Other fingers still down - just clear current stroke without saving
      debugPrint('🚫 Finger lifted but ${_activePointers.length} fingers remain - discarding stroke');
      _currentStroke = null;
      _currentPointerPosition = null;
      setState(() {});
    }
  }

  /// Cancel stroke (when gesture is taken over by another widget)
  void _cancelStroke(int pointerId) {
    // Handle pointer cancel events (when gesture is taken over by another widget)
    _activePointers.remove(pointerId);

    if (_activePointers.isEmpty) {
      _currentStroke = null;
      _currentPointerPosition = null;
      _strokesBeforeErase = null;
      setState(() {});
      debugPrint('🚫 Pointer $pointerId canceled - cleared stroke');
    }
  }

  /// Helper to compare two stroke lists
  bool _strokesEqual(List<Stroke> a, List<Stroke> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Erase strokes at the given point using eraser radius (vector-based)
  /// This splits strokes and only removes the parts that intersect with the eraser
  void _eraseStrokesAtPoint(Offset point) {
    final eraserRadiusSquared = (_eraserRadius / 2) * (_eraserRadius / 2);
    final List<Stroke> newStrokes = [];

    for (final stroke in _strokes) {
      final splitStrokes = _splitStrokeByEraser(stroke, point, eraserRadiusSquared);
      newStrokes.addAll(splitStrokes);
    }

    if (newStrokes.length != _strokes.length) {
      debugPrint('🎨 Canvas: Eraser at (${point.dx}, ${point.dy}) - ${_strokes.length} strokes → ${newStrokes.length} strokes');
      _strokes = newStrokes;
    }
  }

  /// Split a stroke by removing portions that intersect with eraser circle
  /// Returns list of stroke segments that remain after erasing
  List<Stroke> _splitStrokeByEraser(Stroke stroke, Offset eraserPoint, double eraserRadiusSquared) {
    if (stroke.points.isEmpty) return [];

    final List<Stroke> resultStrokes = [];
    List<StrokePoint> currentSegment = [];
    final eraserRadius = math.sqrt(eraserRadiusSquared);

    for (int i = 0; i < stroke.points.length; i++) {
      final point = stroke.points[i];
      final dx = point.dx - eraserPoint.dx;
      final dy = point.dy - eraserPoint.dy;
      final distanceSquared = dx * dx + dy * dy;

      // Check if point is inside eraser
      bool pointInEraser = distanceSquared <= eraserRadiusSquared;

      // Also check if line segment from previous point to this point intersects eraser
      bool segmentIntersectsEraser = false;
      if (i > 0 && !pointInEraser) {
        final prevPoint = stroke.points[i - 1];
        segmentIntersectsEraser = _lineSegmentIntersectsCircle(
          Offset(prevPoint.dx, prevPoint.dy),
          Offset(point.dx, point.dy),
          eraserPoint,
          eraserRadius,
        );
      }

      if (!pointInEraser && !segmentIntersectsEraser) {
        // Point and segment are outside eraser - keep it
        currentSegment.add(point);
      } else {
        // Point or segment is inside eraser - this breaks the stroke
        if (currentSegment.isNotEmpty) {
          // Save the current segment as a new stroke
          resultStrokes.add(Stroke(
            points: currentSegment,
            strokeWidth: stroke.strokeWidth,
            color: stroke.color,
          ));
          currentSegment = [];
        }
      }
    }

    // Add any remaining segment
    if (currentSegment.isNotEmpty) {
      resultStrokes.add(Stroke(
        points: currentSegment,
        strokeWidth: stroke.strokeWidth,
        color: stroke.color,
      ));
    }

    return resultStrokes;
  }

  /// Check if a line segment intersects with a circle
  /// Uses point-to-line-segment distance calculation
  bool _lineSegmentIntersectsCircle(
    Offset lineStart,
    Offset lineEnd,
    Offset circleCenter,
    double circleRadius,
  ) {
    // Vector from line start to end
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final lengthSquared = dx * dx + dy * dy;

    // Handle degenerate case where line segment is a point
    if (lengthSquared == 0) {
      final distX = lineStart.dx - circleCenter.dx;
      final distY = lineStart.dy - circleCenter.dy;
      return (distX * distX + distY * distY) <= (circleRadius * circleRadius);
    }

    // Calculate parameter t for closest point on line segment
    // t = 0 means lineStart, t = 1 means lineEnd
    final t = (((circleCenter.dx - lineStart.dx) * dx +
                 (circleCenter.dy - lineStart.dy) * dy) /
               lengthSquared).clamp(0.0, 1.0);

    // Find closest point on line segment
    final closestX = lineStart.dx + t * dx;
    final closestY = lineStart.dy + t * dy;

    // Check distance from circle center to closest point
    final distX = closestX - circleCenter.dx;
    final distY = closestY - circleCenter.dy;
    final distanceSquared = distX * distX + distY * distY;

    return distanceSquared <= (circleRadius * circleRadius);
  }

  /// Undo last operation
  void undo() async {
    // RACE CONDITION FIX: Prevent concurrent undo operations
    if (_isUndoRedoInProgress || _operationHistory.isEmpty) {
      debugPrint('⚠️ Canvas: Undo blocked (inProgress: $_isUndoRedoInProgress, historyEmpty: ${_operationHistory.isEmpty})');
      return;
    }

    _isUndoRedoInProgress = true;
    try {
      setState(() {
        // Pop the last operation from history
        final operation = _operationHistory.removeLast();

        // Undo the operation (modifies _strokes)
        operation.undo(_strokes);

        // Add to redo stack so it can be redone
        _redoStack.add(operation);

        // Increment canvas version to track state changes
        _canvasVersion++;

        debugPrint('🎨 Canvas: Undid operation (${operation.runtimeType}). History: ${_operationHistory.length}, Redo: ${_redoStack.length}, Version: $_canvasVersion');
      });

      // Wait for setState to complete before allowing next operation
      await Future.delayed(Duration.zero);

      widget.onStrokesChanged?.call();
    } finally {
      _isUndoRedoInProgress = false;
    }
  }

  /// Redo last undone operation
  void redo() async {
    // RACE CONDITION FIX: Prevent concurrent redo operations
    if (_isUndoRedoInProgress || _redoStack.isEmpty) {
      debugPrint('⚠️ Canvas: Redo blocked (inProgress: $_isUndoRedoInProgress, redoEmpty: ${_redoStack.isEmpty})');
      return;
    }

    _isUndoRedoInProgress = true;
    try {
      setState(() {
        // Pop from redo stack
        final operation = _redoStack.removeLast();

        // Redo the operation (modifies _strokes)
        operation.redo(_strokes);

        // Add back to history
        _operationHistory.add(operation);

        // Increment canvas version to track state changes
        _canvasVersion++;

        debugPrint('🎨 Canvas: Redid operation (${operation.runtimeType}). History: ${_operationHistory.length}, Redo: ${_redoStack.length}, Version: $_canvasVersion');
      });

      // Wait for setState to complete before allowing next operation
      await Future.delayed(Duration.zero);

      widget.onStrokesChanged?.call();
    } finally {
      _isUndoRedoInProgress = false;
    }
  }

  /// Clear all strokes (can be undone)
  void clear() {
    if (_strokes.isEmpty) return; // Nothing to clear

    setState(() {
      // Save current strokes and create ClearOperation
      final clearedStrokes = List<Stroke>.from(_strokes);
      final operation = ClearOperation(clearedStrokes);
      _operationHistory.add(operation);

      // Clear redo stack (standard undo/redo behavior)
      _redoStack.clear();

      // Clear strokes
      _strokes.clear();
      _currentStroke = null;

      // Increment canvas version to track state changes
      _canvasVersion++;
      debugPrint('🎨 Canvas: Cleared all strokes, Version: $_canvasVersion');
    });
    widget.onStrokesChanged?.call();
  }

  /// Set current drawing tool
  void setTool(DrawingTool tool) {
    setState(() {
      _currentTool = tool;
    });
  }

  /// Toggle eraser mode (backward compatibility)
  void setErasing(bool isErasing) {
    setState(() {
      _currentTool = isErasing ? DrawingTool.eraser : DrawingTool.pen;
    });
  }

  /// Set pen color
  void setStrokeColor(Color color) {
    setState(() {
      _strokeColor = color;
    });
  }

  /// Set pen width
  void setStrokeWidth(double width) {
    setState(() {
      _strokeWidth = width;
    });
  }

  /// Set highlighter color
  void setHighlighterColor(Color color) {
    setState(() {
      _highlighterColor = color;
    });
  }

  /// Set highlighter width
  void setHighlighterWidth(double width) {
    setState(() {
      _highlighterWidth = width;
    });
  }

  /// Set eraser radius
  void setEraserRadius(double radius) {
    setState(() {
      _eraserRadius = radius;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Set canvas size IMMEDIATELY to ensure it's available for gesture processing
          // This prevents coordinate space issues when Transform.translate is used
          _canvasSize = constraints.biggest;

          return Listener(
            // Listener uses raw pointer events - no gesture arena delay!
            // onPointerDown fires IMMEDIATELY on touch
            onPointerDown: (event) => _startStroke(event.localPosition, event.pointer),
            // onPointerMove fires for EVERY pixel of movement - no threshold
            onPointerMove: (event) => _addPointToStroke(event.localPosition),
            // onPointerUp fires when finger lifts
            onPointerUp: (event) => _endStroke(event.pointer),
            // onPointerCancel fires when gesture is taken over by another widget
            onPointerCancel: (event) => _cancelStroke(event.pointer),
            child: ClipRect(
              child: CustomPaint(
                painter: HandwritingPainter(
                  strokes: _strokes,
                  currentStroke: _currentStroke,
                  currentTool: _currentTool,
                  eraserRadius: _eraserRadius,
                  pointerPosition: _currentPointerPosition,
                ),
                size: Size.infinite,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Custom painter for rendering handwriting strokes
class HandwritingPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? currentStroke;
  final DrawingTool currentTool;
  final double eraserRadius;
  final Offset? pointerPosition; // Position in screen space for eraser indicator

  HandwritingPainter({
    required this.strokes,
    this.currentStroke,
    this.currentTool = DrawingTool.pen,
    this.eraserRadius = 20.0,
    this.pointerPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Separate strokes by type for proper z-ordering
    final highlighterStrokes = <Stroke>[];
    final penStrokes = <Stroke>[];

    for (final stroke in strokes) {
      if (stroke.strokeType == StrokeType.highlighter) {
        highlighterStrokes.add(stroke);
      } else {
        penStrokes.add(stroke);
      }
    }

    // Draw highlighter strokes first (behind pen strokes)
    for (final stroke in highlighterStrokes) {
      _drawStroke(canvas, stroke, isCurrentStroke: false);
    }

    // Draw pen strokes on top
    for (final stroke in penStrokes) {
      _drawStroke(canvas, stroke, isCurrentStroke: false);
    }

    // Draw current stroke being drawn (on appropriate layer)
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!, isCurrentStroke: true);
    }

    // Draw eraser circle indicator when in eraser mode and actively touching
    if (currentTool == DrawingTool.eraser && pointerPosition != null) {
      final eraserPaint = Paint()
        ..color = Colors.grey.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      final eraserBorderPaint = Paint()
        ..color = Colors.grey.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Draw filled circle - use eraserRadius/2 because strokeWidth applies half on each side
      // So the actual erased area has a radius of eraserRadius/2
      final visualRadius = eraserRadius / 2;
      canvas.drawCircle(pointerPosition!, visualRadius, eraserPaint);

      // Draw border circle
      canvas.drawCircle(pointerPosition!, visualRadius, eraserBorderPaint);
    }
  }

  /// Draw a single stroke
  void _drawStroke(Canvas canvas, Stroke stroke, {bool isCurrentStroke = false}) {
    if (stroke.points.isEmpty) return;

    // Debug log for current stroke being drawn
    if (isCurrentStroke && stroke.points.isNotEmpty) {
      final firstPoint = stroke.points.first;
      debugPrint('🎨 PAINT: drawing ${stroke.points.length == 1 ? "dot" : "line"} firstPoint=(${firstPoint.dx.toStringAsFixed(2)}, ${firstPoint.dy.toStringAsFixed(2)}) totalPoints=${stroke.points.length}');
    }

    final paint = Paint()
      ..color = Color(stroke.color)
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      // Single point - draw as filled circle
      final point = stroke.points.first;
      final fillPaint = Paint()
        ..color = Color(stroke.color)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(point.dx, point.dy),
        stroke.strokeWidth / 2,
        fillPaint,
      );
    } else {
      // Multiple points - use simple line-to approach for reliability
      // This ensures ALL points are connected without gaps
      final path = Path();
      path.moveTo(stroke.points[0].dx, stroke.points[0].dy);

      // Connect all points with straight lines
      // This is more reliable than bezier curves and ensures no missing segments
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant HandwritingPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
           oldDelegate.currentStroke != currentStroke ||
           oldDelegate.pointerPosition != pointerPosition ||
           oldDelegate.currentTool != currentTool ||
           oldDelegate.eraserRadius != eraserRadius;
  }
}

/// Drawing tools panel for handwriting canvas
class DrawingToolsPanel extends StatelessWidget {
  final HandwritingCanvasState canvasState;

  const DrawingToolsPanel({
    super.key,
    required this.canvasState,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tool mode selection (Pen/Eraser)
          Row(
            children: [
              // Pen/Eraser toggle
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.edit, size: 18),
                    label: Text('Pen'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.auto_fix_high, size: 18),
                    label: Text('Eraser'),
                  ),
                ],
                selected: {canvasState.isErasing},
                onSelectionChanged: (Set<bool> selected) {
                  canvasState.setErasing(selected.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Width/Radius control - changes based on mode
          Row(
            children: [
              Text(canvasState.isErasing ? 'Eraser Radius: ' : 'Pen Width: '),
              Expanded(
                child: Slider(
                  value: canvasState.isErasing
                      ? canvasState.eraserRadius
                      : canvasState.strokeWidth,
                  min: canvasState.isErasing ? 5.0 : 1.0,
                  max: canvasState.isErasing ? 50.0 : 10.0,
                  divisions: canvasState.isErasing ? 45 : 9,
                  label: canvasState.isErasing
                      ? '${canvasState.eraserRadius.toInt()}px'
                      : '${canvasState.strokeWidth.toInt()}px',
                  onChanged: (value) {
                    if (canvasState.isErasing) {
                      canvasState.setEraserRadius(value);
                    } else {
                      canvasState.setStrokeWidth(value);
                    }
                  },
                ),
              ),
              Text(canvasState.isErasing
                  ? '${canvasState.eraserRadius.toInt()}px'
                  : '${canvasState.strokeWidth.toInt()}px'),
            ],
          ),
          const SizedBox(height: 12),
          // Color palette with scrolling
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Color: ', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _buildColorOptions(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: canvasState.canUndo ? canvasState.undo : null,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Undo'),
              ),
              ElevatedButton.icon(
                onPressed: canvasState.canRedo ? canvasState.redo : null,
                icon: const Icon(Icons.redo, size: 18),
                label: const Text('Redo'),
              ),
              ElevatedButton.icon(
                onPressed: canvasState.clear,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade100,
                  foregroundColor: Colors.red.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build color selection options
  List<Widget> _buildColorOptions() {
    final colors = [
      Colors.black,
      Colors.grey.shade700,
      Colors.blue.shade700,
      Colors.blue.shade300,
      Colors.red.shade700,
      Colors.red.shade300,
      Colors.green.shade700,
      Colors.green.shade300,
      Colors.orange.shade700,
      Colors.amber.shade600,
      Colors.purple.shade700,
      Colors.pink.shade400,
      Colors.brown.shade600,
      Colors.teal.shade600,
    ];

    return colors.map((color) {
      final isSelected = canvasState.strokeColor == color;
      return GestureDetector(
        onTap: () {
          canvasState.setStrokeColor(color);
          // Exit eraser mode when selecting a color
          if (canvasState.isErasing) {
            canvasState.setErasing(false);
          }
        },
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.black : Colors.grey.shade400,
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 18,
                  color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                )
              : null,
        ),
      );
    }).toList();
  }
}