import 'dart:math' as math;

import 'package:flutter/material.dart';

/// App bar title layout that preserves the centered date controls while
/// showing the active book name in the unused leading title space.
class ScheduleHeaderTitle extends StatelessWidget {
  const ScheduleHeaderTitle({
    super.key,
    required this.bookName,
    required this.child,
    this.controlsLeftInset = 160,
    this.bookNameHorizontalPadding = 8,
    this.bookNameVerticalPadding = 0,
    this.textColor = Colors.black,
  });

  final String bookName;
  final Widget child;
  final double controlsLeftInset;
  final double bookNameHorizontalPadding;
  final double bookNameVerticalPadding;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final trimmedBookName = bookName.trim();
    final baseTitleStyle =
        Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleMedium;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.hasBoundedHeight;
        final maxBookNameWidth = math
            .min(
              math.max(0, controlsLeftInset - 12),
              constraints.maxWidth * 0.32,
            )
            .toDouble();

        return SizedBox(
          width: constraints.maxWidth,
          height: hasBoundedHeight ? constraints.maxHeight : null,
          child: Stack(
            fit: hasBoundedHeight ? StackFit.expand : StackFit.loose,
            children: [
              Padding(
                padding: EdgeInsets.only(left: controlsLeftInset),
                child: child,
              ),
              if (trimmedBookName.isNotEmpty && maxBookNameWidth > 0)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: controlsLeftInset,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxBookNameWidth,
                          ),
                          child: Tooltip(
                            message: trimmedBookName,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: bookNameHorizontalPadding,
                                vertical: bookNameVerticalPadding,
                              ),
                              child: Text(
                                trimmedBookName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: baseTitleStyle?.copyWith(
                                  color: textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                  height: 1,
                                  decoration: TextDecoration.underline,
                                  decorationColor: textColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
