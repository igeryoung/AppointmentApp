import 'package:flutter/material.dart';
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
          final isErasing = canvasState?.isErasing ?? false;
          final currentColor = canvasState?.strokeColor ?? Colors.black;
          final currentWidth = canvasState?.strokeWidth ?? 2.0;
          final currentEraserRadius = canvasState?.eraserRadius ?? 20.0;

          return Stack(
            children: [
              // Handwriting canvas (full space)
              Column(
                children: [
                  // Toolbar
                  HandwritingToolbar(
                    isErasing: isErasing,
                    isControlPanelExpanded: _isControlPanelExpanded,
                    onPenTap: () {
                      widget.canvasKey.currentState?.setErasing(false);
                      setToolbarState(() {});
                    },
                    onEraserTap: () {
                      widget.canvasKey.currentState?.setErasing(true);
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
                  isErasing: isErasing,
                  currentColor: currentColor,
                  currentWidth: currentWidth,
                  currentEraserRadius: currentEraserRadius,
                  onWidthChanged: (value) {
                    widget.canvasKey.currentState?.setStrokeWidth(value);
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
