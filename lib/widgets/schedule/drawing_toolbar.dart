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
    final isErasing = canvasState?.isErasing ?? false;
    final currentColor = canvasState?.strokeColor ?? Colors.black;

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
          // Pen/Eraser toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    canvasState?.setErasing(false);
                    onCanvasStateChange();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: !isErasing ? Colors.blue.shade100 : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 18,
                      color: !isErasing ? Colors.blue.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
                Container(width: 1, height: 20, color: Colors.grey.shade300),
                InkWell(
                  onTap: () {
                    canvasState?.setErasing(true);
                    onCanvasStateChange();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isErasing ? Colors.orange.shade100 : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                    ),
                    child: Icon(
                      Icons.auto_fix_high,
                      size: 18,
                      color: isErasing ? Colors.orange.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Color picker (only show when not erasing)
          if (!isErasing) ...[
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
