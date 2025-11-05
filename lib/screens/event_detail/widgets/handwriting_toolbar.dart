import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

/// Toolbar for handwriting canvas with pen/eraser toggle and action buttons
class HandwritingToolbar extends StatelessWidget {
  final bool isErasing;
  final bool isControlPanelExpanded;
  final VoidCallback onPenTap;
  final VoidCallback onEraserTap;
  final VoidCallback onExpandCollapseTap;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;

  const HandwritingToolbar({
    super.key,
    required this.isErasing,
    required this.isControlPanelExpanded,
    required this.onPenTap,
    required this.onEraserTap,
    required this.onExpandCollapseTap,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            l10n.handwritingNotes,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const Spacer(),
          // Pen/Eraser toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: onPenTap,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: !isErasing ? Colors.blue.shade100 : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit,
                          size: 16,
                          color: !isErasing ? Colors.blue.shade700 : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.pen,
                          style: TextStyle(
                            fontSize: 12,
                            color: !isErasing ? Colors.blue.shade700 : Colors.grey.shade600,
                            fontWeight: !isErasing ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, height: 24, color: Colors.grey.shade300),
                InkWell(
                  onTap: onEraserTap,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isErasing ? Colors.orange.shade100 : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_fix_high,
                          size: 16,
                          color: isErasing ? Colors.orange.shade700 : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.eraser,
                          style: TextStyle(
                            fontSize: 12,
                            color: isErasing ? Colors.orange.shade700 : Colors.grey.shade600,
                            fontWeight: isErasing ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Expand/Collapse button with label
          InkWell(
            onTap: onExpandCollapseTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.controls,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isControlPanelExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            onPressed: onUndo,
            tooltip: l10n.undo,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 20),
            onPressed: onRedo,
            tooltip: l10n.redo,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.clear, size: 20),
            onPressed: onClear,
            tooltip: l10n.clearAll,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
