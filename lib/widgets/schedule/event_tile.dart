import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../utils/schedule/schedule_layout_utils.dart';

/// Helper class for rendering schedule event tiles
///
/// Provides adaptive event tile rendering based on height and state
class ScheduleEventTileHelper {
  /// Check if event should be displayed as open-ended
  static bool shouldDisplayAsOpenEnd(Event event) {
    // Removed events or old events with new time should be displayed as open-end (single slot)
    // NEW events (isTimeChanged) should display normally with full duration
    return event.isRemoved || event.hasNewTime || event.isOpenEnded;
  }

  /// Get display duration in minutes for an event
  static int getDisplayDurationInMinutes(Event event) {
    if (shouldDisplayAsOpenEnd(event)) {
      return 15; // Always 15 minutes (1 slot) for open-end display
    }
    return event.durationInMinutes ?? 15;
  }

  /// Get event name font size based on slot height
  static double getEventNameFontSize(double slotHeight, double baseFontSize) {
    if (slotHeight >= ScheduleLayoutUtils.largeScreenSlotHeightThreshold) {
      return baseFontSize * 1.8;
    }
    return baseFontSize;
  }

  /// Build formatted name text with last 2 digits of record number
  /// Record number is displayed at 0.4 × slotHeight
  static Widget buildFormattedNameText({
    required Event event,
    required double fontSize,
    required double slotHeight,
    required Color color,
    required double height,
    TextDecoration? decoration,
    Color? decorationColor,
    FontWeight? fontWeight,
    TextOverflow? overflow,
    int? maxLines,
  }) {
    if (event.recordNumber != null && event.recordNumber!.isNotEmpty) {
      // Get last 2 digits of record number
      String lastTwoDigits = event.recordNumber!.length >= 2
          ? event.recordNumber!.substring(event.recordNumber!.length - 2)
          : event.recordNumber!;

      return RichText(
        overflow: overflow ?? TextOverflow.clip,
        maxLines: maxLines,
        text: TextSpan(
          style: TextStyle(
            fontSize: fontSize,
            color: color,
            height: height,
            decoration: decoration,
            decorationColor: decorationColor,
            fontWeight: fontWeight,
          ),
          children: [
            TextSpan(text: event.title),
            TextSpan(
              text: '($lastTwoDigits)',
              style: TextStyle(fontSize: slotHeight * 0.3),
            ),
          ],
        ),
      );
    }

    return Text(
      event.title,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        height: height,
        decoration: decoration,
        decorationColor: decorationColor,
        fontWeight: fontWeight,
      ),
      overflow: overflow,
      maxLines: maxLines,
    );
  }

  /// Get new event for time-changed events
  static Event? getNewEventForTimeChange(Event event, List<Event> events) {
    if (event.newEventId == null) return null;
    try {
      return events.firstWhere((e) => e.id == event.newEventId);
    } catch (e) {
      return null;
    }
  }

  /// Get new time display for time-changed events
  static String getNewTimeDisplay(Event? newEvent, BuildContext context) {
    if (newEvent == null) return '';
    return '→ ${DateFormat('MMM d, HH:mm', Localizations.localeOf(context).toString()).format(newEvent.startTime)}';
  }

  /// Get colors for event types (up to 2, alphabetically sorted)
  static List<Color> _getEventColors(
    BuildContext context,
    Event event,
    Color Function(BuildContext, EventType) getEventTypeColor,
  ) {
    final uniqueSorted = EventType.sortAlphabetically(
      event.eventTypes.toSet().toList(),
    );
    final topTwo = uniqueSorted.take(2).toList();
    if (topTwo.isEmpty) {
      return [getEventTypeColor(context, EventType.other)];
    }
    return topTwo.map((type) => getEventTypeColor(context, type)).toList();
  }

  /// Build color background widget for event types
  /// - single type: single color
  /// - multi type: 2-color split
  /// Optionally prepends a handwriting icon (10% width) when hasHandwriting is true
  static Widget _buildColorBackground(
    List<Color> colors,
    double opacity, {
    bool hasHandwriting = false,
  }) {
    Widget colorWidget;

    if (colors.length == 1) {
      colorWidget = Container(color: colors[0].withOpacity(opacity));
    } else {
      // Render two selected colors as a simple 50/50 split.
      colorWidget = Row(
        children: [
          Expanded(child: Container(color: colors[0].withOpacity(opacity))),
          Expanded(child: Container(color: colors[1].withOpacity(opacity))),
        ],
      );
    }

    // Prepend icon if event has handwriting
    if (hasHandwriting) {
      return Row(
        crossAxisAlignment:
            CrossAxisAlignment.stretch, // Force children to fill 100% height
        children: [
          // Icon section - 10% width, 100% height
          Expanded(
            flex: 10,
            child: Container(
              color: Colors.black.withOpacity(0.3),
              child: Image.asset(
                'assets/images/handwirtenote.png',
                fit: BoxFit.fill, // Stretch to fill 100% width and 100% height
              ),
            ),
          ),
          // Color section - 90% width
          Expanded(flex: 90, child: colorWidget),
        ],
      );
    }

    return colorWidget;
  }

  /// Build event tile widget
  static Widget buildEventTile({
    required BuildContext context,
    required Event event,
    required double slotHeight,
    required List<Event> events,
    required Color Function(BuildContext, EventType) getEventTypeColor,
    required VoidCallback onTap,
    required Function(Offset) onLongPress,
    required Function(Offset, Rect) onLongPressDragStart,
    required Function(Offset) onLongPressDragUpdate,
    required Function(Offset) onLongPressDragEnd,
    required VoidCallback onLongPressDragCancel,
    required bool isMenuOpen,
    bool canDrag = true,
    bool isBeingDragged = false,
    bool hasHandwriting = false,
    Widget Function(Color)? dottedBorderPainter,
  }) {
    // Calculate how many 15-minute slots this event spans
    final durationInMinutes = getDisplayDurationInMinutes(event);
    final slotsSpanned = ((durationInMinutes / 15).ceil()).clamp(1, 16);
    final tileHeight = (slotsSpanned * slotHeight) - 1;

    // Get colors for this event (up to 2, alphabetically sorted)
    final colors = _getEventColors(context, event, getEventTypeColor);
    final primaryColor =
        colors.first; // Use first color for borders and accents

    final tileContent = Opacity(
      opacity: isBeingDragged ? 0.3 : 1.0,
      child: Container(
        height: tileHeight,
        margin: const EdgeInsets.only(left: 1, right: 1, top: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: isMenuOpen
              ? Border.all(color: Colors.white, width: 2)
              : event.isRemoved
              ? Border.all(
                  color: primaryColor.withOpacity(0.6),
                  width: 1,
                  style: BorderStyle.solid,
                )
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Background color layer (single or split)
            Positioned.fill(
              child: _buildColorBackground(
                colors,
                event.isRemoved ? 0.3 : 0.75,
                hasHandwriting: hasHandwriting,
              ),
            ),
            // Content layer with padding
            Padding(
              padding: EdgeInsets.only(
                left: hasHandwriting
                    ? 0
                    : 2, // No left padding when icon present
                right: 2,
                top: slotHeight * 0.15, // 10% top padding
                bottom: 0,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Dotted line overlay for removed events
                  if (event.isRemoved && dottedBorderPainter != null)
                    Positioned.fill(
                      child: dottedBorderPainter(primaryColor.withOpacity(0.8)),
                    ),
                  // Content with height-adaptive rendering
                  buildEventTileContent(
                    event: event,
                    tileHeight: tileHeight,
                    slotHeight: slotHeight,
                    events: events,
                    hasHandwriting: hasHandwriting,
                  ),
                  // Dollar indicator for events with charge items (top-right corner, left of OK icon)
                  if (event.hasChargeItems)
                    Positioned(
                      top: -8,
                      right: event.isChecked ? slotHeight * 0.7 - 1 : -1,
                      child: Image.asset(
                        'assets/images/green_dollar.png',
                        width: slotHeight * 0.48,
                        height: slotHeight * 0.48,
                        fit: BoxFit.contain,
                      ),
                    ),
                  // OK indicator for checked events (top-right corner, 0.5 × slotHeight)
                  if (event.isChecked)
                    Positioned(
                      top: -8,
                      right: -1,
                      child: Image.asset(
                        'assets/images/icons8-ok-96.png',
                        width: slotHeight * 0.6,
                        height: slotHeight * 0.6,
                        fit: BoxFit.contain,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return _LongPressBoundaryGestureTile(
      key: ValueKey<String>(
        event.id ?? '${event.startTime.millisecondsSinceEpoch}-${event.title}',
      ),
      isMenuOpen: isMenuOpen,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressDragStart: onLongPressDragStart,
      onLongPressDragUpdate: onLongPressDragUpdate,
      onLongPressDragEnd: onLongPressDragEnd,
      onLongPressDragCancel: onLongPressDragCancel,
      canDrag: canDrag,
      child: tileContent,
    );
  }

  /// Build floating drag preview that keeps event block styling unchanged.
  static Widget buildFloatingDragPreview({
    required BuildContext context,
    required Event event,
    required double slotHeight,
    required List<Event> events,
    required Color Function(BuildContext, EventType) getEventTypeColor,
    required double width,
    required double height,
    bool hasHandwriting = false,
  }) {
    final colors = _getEventColors(context, event, getEventTypeColor);
    final primaryColor = colors.first;

    return SizedBox(
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: event.isRemoved
              ? Border.all(
                  color: primaryColor.withOpacity(0.6),
                  width: 1,
                  style: BorderStyle.solid,
                )
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _buildColorBackground(
                colors,
                event.isRemoved ? 0.3 : 0.75,
                hasHandwriting: hasHandwriting,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: hasHandwriting ? 0 : 2,
                right: 2,
                top: slotHeight * 0.15,
                bottom: 0,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  buildEventTileContent(
                    event: event,
                    tileHeight: height,
                    slotHeight: slotHeight,
                    events: events,
                    hasHandwriting: hasHandwriting,
                  ),
                  if (event.hasChargeItems)
                    Positioned(
                      top: -8,
                      right: event.isChecked ? slotHeight * 0.7 - 1 : -1,
                      child: Image.asset(
                        'assets/images/green_dollar.png',
                        width: slotHeight * 0.48,
                        height: slotHeight * 0.48,
                        fit: BoxFit.contain,
                      ),
                    ),
                  if (event.isChecked)
                    Positioned(
                      top: -8,
                      right: -1,
                      child: Image.asset(
                        'assets/images/icons8-ok-96.png',
                        width: slotHeight * 0.6,
                        height: slotHeight * 0.6,
                        fit: BoxFit.contain,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build event tile content with adaptive rendering based on height
  static Widget buildEventTileContent({
    required Event event,
    required double tileHeight,
    required double slotHeight,
    required List<Event> events,
    bool hasHandwriting = false,
  }) {
    // For closed-end events, always show simplified content
    final isClosedEnd = !shouldDisplayAsOpenEnd(event);

    Widget content;
    // Name font size = 0.4 × slotHeight
    final fontSize = slotHeight * 0.5;

    if (isClosedEnd) {
      // Closed-end events: Always show just the name
      content = Align(
        alignment: Alignment.topLeft,
        child: buildFormattedNameText(
          event: event,
          fontSize: fontSize,
          slotHeight: slotHeight,
          color: event.isRemoved ? Colors.white70 : Colors.white,
          height: 1.2,
          decoration: event.isRemoved ? TextDecoration.lineThrough : null,
          decorationColor: Colors.white70,
          fontWeight: FontWeight.bold,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      );
    } else if (tileHeight < 20) {
      // Open-end events: Very small - Only show name with tiny font
      content = _buildNameOnly(event, fontSize, slotHeight);
    } else {
      // Open-end events: Small and larger - Show name with appropriate font
      content = _buildNameOnly(event, fontSize, slotHeight);
    }

    // Add left padding when handwriting icon is present (icon takes 10% width)
    if (hasHandwriting) {
      return Padding(
        padding: const EdgeInsets.only(
          left: 12,
        ), // Shift text right to avoid icon
        child: content,
      );
    }

    return content;
  }

  static Widget _buildNameOnly(
    Event event,
    double fontSize,
    double slotHeight,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: buildFormattedNameText(
        event: event,
        fontSize: fontSize,
        slotHeight: slotHeight,
        color: event.isRemoved ? Colors.white70 : Colors.white,
        height: 1.2,
        decoration: event.isRemoved ? TextDecoration.lineThrough : null,
        decorationColor: Colors.white70,
        fontWeight: FontWeight.bold,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

class _LongPressBoundaryGestureTile extends StatefulWidget {
  const _LongPressBoundaryGestureTile({
    super.key,
    required this.isMenuOpen,
    required this.onTap,
    required this.onLongPress,
    required this.onLongPressDragStart,
    required this.onLongPressDragUpdate,
    required this.onLongPressDragEnd,
    required this.onLongPressDragCancel,
    required this.canDrag,
    required this.child,
  });

  final bool isMenuOpen;
  final VoidCallback onTap;
  final Function(Offset) onLongPress;
  final Function(Offset, Rect) onLongPressDragStart;
  final Function(Offset) onLongPressDragUpdate;
  final Function(Offset) onLongPressDragEnd;
  final VoidCallback onLongPressDragCancel;
  final bool canDrag;
  final Widget child;

  @override
  State<_LongPressBoundaryGestureTile> createState() =>
      _LongPressBoundaryGestureTileState();
}

class _LongPressBoundaryGestureTileState
    extends State<_LongPressBoundaryGestureTile> {
  Rect? _longPressBounds;
  var _hasExitedBounds = false;

  void _resetLongPressTracking() {
    _hasExitedBounds = false;
    _longPressBounds = null;
  }

  void _captureBounds() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final topLeft = renderBox.localToGlobal(Offset.zero);
      _longPressBounds = topLeft & renderBox.size;
    } else {
      _longPressBounds = null;
    }
    _hasExitedBounds = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isMenuOpen ? null : widget.onTap,
      onLongPressStart: (details) {
        if (!widget.isMenuOpen) {
          widget.onLongPress(details.globalPosition);
        }
        _captureBounds();
      },
      onLongPressMoveUpdate: (details) {
        if (!widget.canDrag) return;

        if (_hasExitedBounds) {
          widget.onLongPressDragUpdate(details.globalPosition);
          return;
        }

        final bounds = _longPressBounds;
        if (bounds == null) return;

        if (!bounds.contains(details.globalPosition)) {
          _hasExitedBounds = true;
          widget.onLongPressDragStart(details.globalPosition, bounds);
          widget.onLongPressDragUpdate(details.globalPosition);
        }
      },
      onLongPressEnd: (details) {
        if (_hasExitedBounds) {
          widget.onLongPressDragEnd(details.globalPosition);
        }
        _resetLongPressTracking();
      },
      onLongPressCancel: () {
        if (_hasExitedBounds) {
          widget.onLongPressDragCancel();
        }
        _resetLongPressTracking();
      },
      child: widget.child,
    );
  }
}
