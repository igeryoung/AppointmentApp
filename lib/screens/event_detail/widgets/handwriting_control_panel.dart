import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/handwriting_canvas.dart';

/// Control panel for pen width, highlighter width, eraser size, and color selection
class HandwritingControlPanel extends StatelessWidget {
  final bool isExpanded;
  final DrawingTool currentTool;
  final Color currentColor;
  final double currentWidth;
  final Color currentHighlighterColor;
  final double currentHighlighterWidth;
  final double currentEraserRadius;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onHighlighterWidthChanged;
  final ValueChanged<double> onEraserRadiusChanged;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<Color> onHighlighterColorSelected;

  const HandwritingControlPanel({
    super.key,
    required this.isExpanded,
    required this.currentTool,
    required this.currentColor,
    required this.currentWidth,
    required this.currentHighlighterColor,
    required this.currentHighlighterWidth,
    required this.currentEraserRadius,
    required this.onWidthChanged,
    required this.onHighlighterWidthChanged,
    required this.onEraserRadiusChanged,
    required this.onColorSelected,
    required this.onHighlighterColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      height: isExpanded ? null : 0,
      child: isExpanded
          ? Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Size Control
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          currentTool == DrawingTool.eraser
                              ? Icons.radio_button_unchecked
                              : currentTool == DrawingTool.highlighter
                                  ? Icons.highlight
                                  : Icons.edit,
                          size: 18,
                          color: currentTool == DrawingTool.eraser
                              ? Colors.orange.shade700
                              : currentTool == DrawingTool.highlighter
                                  ? Colors.amber.shade700
                                  : Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          currentTool == DrawingTool.eraser
                              ? l10n.eraserSize
                              : currentTool == DrawingTool.highlighter
                                  ? 'Highlighter Width'
                                  : l10n.penWidth,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            value: currentTool == DrawingTool.eraser
                                ? currentEraserRadius
                                : currentTool == DrawingTool.highlighter
                                    ? currentHighlighterWidth
                                    : currentWidth,
                            min: currentTool == DrawingTool.eraser
                                ? 5.0
                                : currentTool == DrawingTool.highlighter
                                    ? 5.0
                                    : 1.0,
                            max: currentTool == DrawingTool.eraser
                                ? 50.0
                                : currentTool == DrawingTool.highlighter
                                    ? 20.0
                                    : 10.0,
                            divisions: currentTool == DrawingTool.eraser
                                ? 45
                                : currentTool == DrawingTool.highlighter
                                    ? 15
                                    : 9,
                            activeColor: currentTool == DrawingTool.eraser
                                ? Colors.orange.shade700
                                : currentTool == DrawingTool.highlighter
                                    ? Colors.amber.shade700
                                    : Colors.blue.shade700,
                            onChanged: (value) {
                              if (currentTool == DrawingTool.eraser) {
                                onEraserRadiusChanged(value);
                              } else if (currentTool == DrawingTool.highlighter) {
                                onHighlighterWidthChanged(value);
                              } else {
                                onWidthChanged(value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: currentTool == DrawingTool.eraser
                                ? Colors.orange.shade50
                                : currentTool == DrawingTool.highlighter
                                    ? Colors.yellow.shade50
                                    : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: currentTool == DrawingTool.eraser
                                  ? Colors.orange.shade200
                                  : currentTool == DrawingTool.highlighter
                                      ? Colors.amber.shade200
                                      : Colors.blue.shade200,
                            ),
                          ),
                          child: Text(
                            '${(currentTool == DrawingTool.eraser ? currentEraserRadius : currentTool == DrawingTool.highlighter ? currentHighlighterWidth : currentWidth).toInt()} px',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: currentTool == DrawingTool.eraser
                                  ? Colors.orange.shade700
                                  : currentTool == DrawingTool.highlighter
                                      ? Colors.amber.shade700
                                      : Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Color Palette (show for pen and highlighter modes)
                  if (currentTool != DrawingTool.eraser)
                    Container(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.color,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: currentTool == DrawingTool.highlighter
                                  ? _buildHighlighterColorPalette(currentHighlighterColor, onHighlighterColorSelected)
                                  : _buildColorPalette(currentColor, onColorSelected),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  List<Widget> _buildColorPalette(Color currentColor, Function(Color) onColorSelected) {
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
      final isSelected = currentColor == color;
      return GestureDetector(
        onTap: () => onColorSelected(color),
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.black : Colors.grey.shade300,
              width: isSelected ? 3 : 2,
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
                  size: 20,
                  color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                )
              : null,
        ),
      );
    }).toList();
  }

  List<Widget> _buildHighlighterColorPalette(Color currentColor, Function(Color) onColorSelected) {
    // Highlighter colors with transparency (40% opacity)
    final colors = [
      const Color(0x66FFEB3B), // Yellow
      const Color(0x664CAF50), // Green
      const Color(0x66FF9800), // Orange
      const Color(0x6600BCD4), // Cyan
      const Color(0x66E91E63), // Pink
      const Color(0x669C27B0), // Purple
      const Color(0x662196F3), // Blue
    ];

    return colors.map((color) {
      final isSelected = currentColor.value == color.value;
      return GestureDetector(
        onTap: () => onColorSelected(color),
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.amber.shade700 : Colors.grey.shade300,
              width: isSelected ? 3 : 2,
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
          child: Stack(
            children: [
              // Show the transparent highlighter color on white background
              Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Check icon if selected
              if (isSelected)
                Center(
                  child: Icon(
                    Icons.check,
                    size: 20,
                    color: Colors.black,
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }
}
