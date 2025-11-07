import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/handwriting_canvas.dart';

/// Helper class for building schedule drawing toolbar
class ScheduleDrawingToolbarHelper {
  /// Build drawing toolbar widget
  static Widget buildDrawingToolbar({
    required BuildContext context,
    required GlobalKey<HandwritingCanvasState>? Function() getCanvasKey,
    required VoidCallback onCanvasStateChange,
    required Future<void> Function() saveDrawing,
  }) {
    final canvasState = getCanvasKey()?.currentState;
    final currentTool = canvasState?.currentTool ?? DrawingTool.pen;
    final currentColor = canvasState?.strokeColor ?? Colors.black;
    final currentHighlighterColor = canvasState?.highlighterColor ?? const Color(0x66FFEB3B);

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade50.withOpacity(0.95),
        border: Border(
          bottom: BorderSide(color: Colors.orange.shade300, width: 2),
        ),
      ),
      child: Row(
        children: [
          // Pen/Highlighter/Eraser toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pen button
                InkWell(
                  onTap: () {
                    canvasState?.setTool(DrawingTool.pen);
                    onCanvasStateChange();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: currentTool == DrawingTool.pen ? Colors.blue.shade100 : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 18,
                      color: currentTool == DrawingTool.pen ? Colors.blue.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
                Container(width: 1, height: 20, color: Colors.grey.shade300),
                // Highlighter button
                InkWell(
                  onTap: () {
                    canvasState?.setTool(DrawingTool.highlighter);
                    onCanvasStateChange();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: currentTool == DrawingTool.highlighter ? Colors.yellow.shade100 : Colors.transparent,
                    ),
                    child: Icon(
                      Icons.highlight,
                      size: 18,
                      color: currentTool == DrawingTool.highlighter ? Colors.amber.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
                Container(width: 1, height: 20, color: Colors.grey.shade300),
                // Eraser button
                InkWell(
                  onTap: () {
                    canvasState?.setTool(DrawingTool.eraser);
                    onCanvasStateChange();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: currentTool == DrawingTool.eraser ? Colors.orange.shade100 : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                    ),
                    child: Icon(
                      Icons.auto_fix_high,
                      size: 18,
                      color: currentTool == DrawingTool.eraser ? Colors.orange.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Color picker (show for pen and highlighter)
          if (currentTool != DrawingTool.eraser) ...[
            // Show pen colors or highlighter colors based on current tool
            if (currentTool == DrawingTool.pen) ...[
              ...[
                Colors.black,
                Colors.red,
                Colors.blue,
                Colors.green,
                Colors.orange,
                Colors.purple,
              ].map((color) {
                final isSelected = currentColor == color;
                return GestureDetector(
                  onTap: () {
                    canvasState?.setStrokeColor(color);
                    onCanvasStateChange();
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.grey.shade400,
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 14,
                            color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                          )
                        : null,
                  ),
                );
              }),
            ] else ...[
              // Highlighter colors with transparency
              ...[
                const Color(0x66FFEB3B), // Yellow
                const Color(0x664CAF50), // Green
                const Color(0x66FF9800), // Orange
                const Color(0x6600BCD4), // Cyan
                const Color(0x66E91E63), // Pink
              ].map((color) {
                final isSelected = currentHighlighterColor.value == color.value;
                return GestureDetector(
                  onTap: () {
                    canvasState?.setHighlighterColor(color);
                    onCanvasStateChange();
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.amber.shade700 : Colors.grey.shade400,
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Center(
                            child: Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.black,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
          const Spacer(),
          // Action buttons
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed: canvasState?.canUndo ?? false
                        ? () {
                            canvasState?.undo();
                            onCanvasStateChange();
                          }
                        : null,
                    tooltip: l10n.undo,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo, size: 20),
                    onPressed: canvasState?.canRedo ?? false
                        ? () {
                            canvasState?.redo();
                            onCanvasStateChange();
                          }
                        : null,
                    tooltip: l10n.redo,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () {
                      canvasState?.clear();
                      onCanvasStateChange();
                      saveDrawing();
                    },
                    tooltip: l10n.clear,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
