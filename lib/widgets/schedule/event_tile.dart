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

  /// Get formatted name with last 2 digits of record number
  static String getFormattedName(Event event) {
    if (event.recordNumber != null && event.recordNumber!.isNotEmpty) {
      // Get last 2 digits of record number
      String lastTwoDigits = event.recordNumber!.length >= 2
          ? event.recordNumber!.substring(event.recordNumber!.length - 2)
          : event.recordNumber!;
      return '${event.name}($lastTwoDigits)';
    }
    return event.name;
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
    Widget Function(Color)? dottedBorderPainter,
  }) {
    // Calculate how many 15-minute slots this event spans
    final durationInMinutes = getDisplayDurationInMinutes(event);
    final slotsSpanned = ((durationInMinutes / 15).ceil()).clamp(1, 16);
    final tileHeight = (slotsSpanned * slotHeight) - 1;

    Widget eventWidget = GestureDetector(
      onTap: isMenuOpen ? null : onTap,
      onLongPressStart: (details) {
        if (!isMenuOpen) {
          onLongPress(details.globalPosition);
        }
      },
      child: Container(
        height: tileHeight,
        margin: const EdgeInsets.only(left: 1, right: 1, top: 1),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        decoration: BoxDecoration(
          color: event.isRemoved
              ? getEventTypeColor(context, event.eventType).withOpacity(0.3)
              : getEventTypeColor(context, event.eventType).withOpacity(0.75),
          borderRadius: BorderRadius.circular(2),
          border: isMenuOpen
              ? Border.all(color: Colors.white, width: 2)
              : event.isRemoved
                  ? Border.all(
                      color: getEventTypeColor(context, event.eventType).withOpacity(0.6),
                      width: 1,
                      style: BorderStyle.solid,
                    )
                  : null,
        ),
        child: Stack(
          children: [
            // Dotted line overlay for removed events
            if (event.isRemoved && dottedBorderPainter != null)
              Positioned.fill(
                child: dottedBorderPainter(getEventTypeColor(context, event.eventType).withOpacity(0.8)),
              ),
            // Content with height-adaptive rendering
            buildEventTileContent(
              event: event,
              tileHeight: tileHeight,
              slotHeight: slotHeight,
              events: events,
            ),
          ],
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
            child: Container(
              width: 100,
              height: tileHeight,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: BoxDecoration(
                color: getEventTypeColor(context, event.eventType),
                borderRadius: BorderRadius.circular(2),
              ),
              child: buildEventTileContent(
                event: event,
                tileHeight: tileHeight,
                slotHeight: slotHeight,
                events: events,
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
  }) {
    // For closed-end events, always show simplified content
    final isClosedEnd = !shouldDisplayAsOpenEnd(event);

    if (isClosedEnd) {
      // Closed-end events: Always show just the name
      final fontSize = getEventNameFontSize(slotHeight, 9.0);
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            getFormattedName(event),
            style: TextStyle(
              fontSize: fontSize,
              color: event.isRemoved ? Colors.white70 : Colors.white,
              height: 1.2,
              decoration: event.isRemoved ? TextDecoration.lineThrough : null,
              decorationColor: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );
    }

    // Open-end events: Height-adaptive rendering
    if (tileHeight < 20) {
      // Very small: Only show name with tiny font
      final baseFontSize = (tileHeight * 0.4).clamp(8.0, 10.0);
      final fontSize = getEventNameFontSize(slotHeight, baseFontSize);
      return _buildNameOnly(event, fontSize);
    } else {
      // Small and larger: Show name with appropriate font
      final baseFontSize = (tileHeight * 0.35).clamp(8.0, 10.0);
      final fontSize = getEventNameFontSize(slotHeight, baseFontSize);
      return _buildNameOnly(event, fontSize);
    }
  }

  static Widget _buildNameOnly(Event event, double fontSize) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          getFormattedName(event),
          style: TextStyle(
            fontSize: fontSize,
            color: event.isRemoved ? Colors.white70 : Colors.white,
            height: 1.2,
            decoration: event.isRemoved ? TextDecoration.lineThrough : null,
            decorationColor: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
