import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

/// Control panel for pen width, eraser size, and color selection
class HandwritingControlPanel extends StatelessWidget {
  final bool isExpanded;
  final bool isErasing;
  final Color currentColor;
  final double currentWidth;
  final double currentEraserRadius;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onEraserRadiusChanged;
  final ValueChanged<Color> onColorSelected;

  const HandwritingControlPanel({
    super.key,
    required this.isExpanded,
    required this.isErasing,
    required this.currentColor,
    required this.currentWidth,
    required this.currentEraserRadius,
    required this.onWidthChanged,
    required this.onEraserRadiusChanged,
    required this.onColorSelected,
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
                          isErasing ? Icons.radio_button_unchecked : Icons.edit,
                          size: 18,
                          color: isErasing ? Colors.orange.shade700 : Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isErasing ? l10n.eraserSize : l10n.penWidth,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            value: isErasing ? currentEraserRadius : currentWidth,
                            min: isErasing ? 5.0 : 1.0,
                            max: isErasing ? 50.0 : 10.0,
                            divisions: isErasing ? 45 : 9,
                            activeColor: isErasing ? Colors.orange.shade700 : Colors.blue.shade700,
                            onChanged: (value) {
                              if (isErasing) {
                                onEraserRadiusChanged(value);
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
                            color: isErasing ? Colors.orange.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isErasing ? Colors.orange.shade200 : Colors.blue.shade200,
                            ),
                          ),
                          child: Text(
                            '${(isErasing ? currentEraserRadius : currentWidth).toInt()} px',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isErasing ? Colors.orange.shade700 : Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Color Palette (only show in pen mode)
                  if (!isErasing)
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
                              children: _buildColorPalette(currentColor, onColorSelected),
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
}
