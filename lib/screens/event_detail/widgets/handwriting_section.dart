import 'package:flutter/material.dart';
import '../../../models/note.dart';
import '../../../widgets/handwriting_canvas.dart';
import 'handwriting_toolbar.dart';
import 'handwriting_control_panel.dart';

/// Handwriting section combining canvas, toolbar, and control panel
class HandwritingSection extends StatefulWidget {
  final GlobalKey<HandwritingCanvasState> canvasKey;
  final List<Stroke> initialStrokes;
  final VoidCallback onStrokesChanged;

  const HandwritingSection({
    super.key,
    required this.canvasKey,
    required this.initialStrokes,
    required this.onStrokesChanged,
  });

  @override
  State<HandwritingSection> createState() => _HandwritingSectionState();
}

class _HandwritingSectionState extends State<HandwritingSection> {
  bool _isControlPanelExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: StatefulBuilder(
        builder: (context, setToolbarState) {
          final canvasState = widget.canvasKey.currentState;
          final currentTool = canvasState?.currentTool ?? DrawingTool.pen;
          final currentColor = canvasState?.strokeColor ?? Colors.black;
          final currentWidth = canvasState?.strokeWidth ?? 2.0;
          final currentHighlighterColor = canvasState?.highlighterColor ?? const Color(0x66FFEB3B);
          final currentHighlighterWidth = canvasState?.highlighterWidth ?? 10.0;
          final currentEraserRadius = canvasState?.eraserRadius ?? 20.0;

          return Stack(
            children: [
              // Handwriting canvas (full space)
              Column(
                children: [
                  // Toolbar
                  HandwritingToolbar(
                    currentTool: currentTool,
                    isControlPanelExpanded: _isControlPanelExpanded,
                    onPenTap: () {
                      widget.canvasKey.currentState?.setTool(DrawingTool.pen);
                      setToolbarState(() {});
                    },
                    onHighlighterTap: () {
                      widget.canvasKey.currentState?.setTool(DrawingTool.highlighter);
                      setToolbarState(() {});
                    },
                    onEraserTap: () {
                      widget.canvasKey.currentState?.setTool(DrawingTool.eraser);
                      setToolbarState(() {});
                    },
                    onExpandCollapseTap: () {
                      setState(() {
                        _isControlPanelExpanded = !_isControlPanelExpanded;
                      });
                    },
                    onUndo: () => widget.canvasKey.currentState?.undo(),
                    onRedo: () => widget.canvasKey.currentState?.redo(),
                    onClear: () => widget.canvasKey.currentState?.clear(),
                  ),
                  // Canvas takes remaining space
                  Expanded(
                    child: HandwritingCanvas(
                      key: widget.canvasKey,
                      initialStrokes: widget.initialStrokes,
                      onStrokesChanged: widget.onStrokesChanged,
                    ),
                  ),
                ],
              ),
              // Overlaying control panel
              Positioned(
                top: 48, // Below toolbar
                left: 0,
                right: 0,
                child: HandwritingControlPanel(
                  isExpanded: _isControlPanelExpanded,
                  currentTool: currentTool,
                  currentColor: currentColor,
                  currentWidth: currentWidth,
                  currentHighlighterColor: currentHighlighterColor,
                  currentHighlighterWidth: currentHighlighterWidth,
                  currentEraserRadius: currentEraserRadius,
                  onWidthChanged: (value) {
                    widget.canvasKey.currentState?.setStrokeWidth(value);
                    setToolbarState(() {});
                  },
                  onHighlighterWidthChanged: (value) {
                    widget.canvasKey.currentState?.setHighlighterWidth(value);
                    setToolbarState(() {});
                  },
                  onEraserRadiusChanged: (value) {
                    widget.canvasKey.currentState?.setEraserRadius(value);
                    setToolbarState(() {});
                  },
                  onColorSelected: (color) {
                    widget.canvasKey.currentState?.setStrokeColor(color);
                    setToolbarState(() {});
                  },
                  onHighlighterColorSelected: (color) {
                    widget.canvasKey.currentState?.setHighlighterColor(color);
                    setToolbarState(() {});
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
