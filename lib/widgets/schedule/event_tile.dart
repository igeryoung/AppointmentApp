import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
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
  /// Record number is displayed at 0.7x the name font size
  static Widget buildFormattedNameText({
    required Event event,
    required double fontSize,
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
            TextSpan(text: event.name),
            TextSpan(
              text: '($lastTwoDigits)',
              style: TextStyle(
                fontSize: fontSize * 0.7,
              ),
            ),
          ],
        ),
      );
    }

    return Text(
      event.name,
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
  static List<Color> _getEventColors(BuildContext context, Event event, Color Function(BuildContext, EventType) getEventTypeColor) {
    final sorted = EventType.sortAlphabetically(event.eventTypes);
    final topTwo = sorted.take(2).toList();
    return topTwo.map((type) => getEventTypeColor(context, type)).toList();
  }

  /// Build split-color background widget for multi-type events
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
      // Vertical split for 2 colors
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
        children: [
          // Icon section - 10% width, left-aligned
          Expanded(
            flex: 10,
            child: Container(
              color: Colors.black.withOpacity(0.3),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Icon(
                    Icons.edit,
                    color: Colors.white70,
                    size: 10,
                  ),
                ),
              ),
            ),
          ),
          // Color section - 90% width
          Expanded(
            flex: 90,
            child: colorWidget,
          ),
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
    required bool isMenuOpen,
    bool hasHandwriting = false,
    Widget Function(Color)? dottedBorderPainter,
  }) {
    // Calculate how many 15-minute slots this event spans
    final durationInMinutes = getDisplayDurationInMinutes(event);
    final slotsSpanned = ((durationInMinutes / 15).ceil()).clamp(1, 16);
    final tileHeight = (slotsSpanned * slotHeight) - 1;

    // Get colors for this event (up to 2, alphabetically sorted)
    final colors = _getEventColors(context, event, getEventTypeColor);
    final primaryColor = colors.first; // Use first color for borders and accents

    Widget eventWidget = GestureDetector(
      onTap: isMenuOpen ? null : onTap,
      onLongPressStart: (details) {
        if (!isMenuOpen) {
          onLongPress(details.globalPosition);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
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
                  left: hasHandwriting ? 0 : 2, // No left padding when icon present
                  right: 2,
                  top: 2,
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
                    // OK indicator for checked events (top-right corner, full tile height)
                    if (event.isChecked)
                      Positioned(
                        top: -2,
                        right: -1,
                        child: Image.asset(
                          'assets/images/icons8-ok-96.png',
                          width: tileHeight / 2,
                          height: tileHeight / 2,
                          fit: BoxFit.contain,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Make event draggable only when menu is open
    if (isMenuOpen) {
      eventWidget = Draggable<Event>(
        data: event,
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(2),
          child: Opacity(
            opacity: 0.7,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                width: 100,
                height: tileHeight,
                child: Stack(
                  children: [
                    // Background color layer (single or split)
                    Positioned.fill(
                      child: _buildColorBackground(colors, 1.0, hasHandwriting: hasHandwriting),
                    ),
                    // Content layer
                    Padding(
                      padding: EdgeInsets.only(
                        left: hasHandwriting ? 0 : 2,
                        right: 2,
                        top: 2,
                        bottom: 0,
                      ),
                      child: buildEventTileContent(
                        event: event,
                        tileHeight: tileHeight,
                        slotHeight: slotHeight,
                        events: events,
                        hasHandwriting: hasHandwriting,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: eventWidget,
        ),
        onDragEnd: (details) {
          // Drag ended, no action needed
        },
        child: eventWidget,
      );
    }

    return eventWidget;
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
    if (isClosedEnd) {
      // Closed-end events: Always show just the name
      final fontSize = getEventNameFontSize(slotHeight, 9.0) * 0.9;
      content = Align(
        alignment: Alignment.topLeft,
        child: buildFormattedNameText(
            event: event,
            fontSize: fontSize,
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
      final baseFontSize = (tileHeight * 0.4).clamp(8.0, 10.0);
      final fontSize = getEventNameFontSize(slotHeight, baseFontSize) * 0.9;
      content = _buildNameOnly(event, fontSize);
    } else {
      // Open-end events: Small and larger - Show name with appropriate font
      final baseFontSize = (tileHeight * 0.35).clamp(8.0, 10.0);
      final fontSize = getEventNameFontSize(slotHeight, baseFontSize) * 0.9;
      content = _buildNameOnly(event, fontSize);
    }

    // Add left padding when handwriting icon is present (icon takes 10% width)
    if (hasHandwriting) {
      return Padding(
        padding: const EdgeInsets.only(left: 12), // Shift text right to avoid icon
        child: content,
      );
    }

    return content;
  }

  static Widget _buildNameOnly(Event event, double fontSize) {
    return Align(
      alignment: Alignment.topLeft,
      child: buildFormattedNameText(
        event: event,
        fontSize: fontSize,
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
