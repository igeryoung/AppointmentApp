import 'dart:math';

import '../../models/event.dart';
import '../../models/schedule_drawing.dart';
import '../../services/time_service.dart';

/// Data class representing a positioned event with layout information
class PositionedEventData {
  final Event event;
  final int slotIndex;
  final int slotsSpanned;
  final int horizontalPosition;
  final int maxConcurrentEvents;
  final double topPosition;
  final double width;
  final double height;

  const PositionedEventData({
    required this.event,
    required this.slotIndex,
    required this.slotsSpanned,
    required this.horizontalPosition,
    required this.maxConcurrentEvents,
    required this.topPosition,
    required this.width,
    required this.height,
  });
}

/// Utility class for schedule layout calculations
class ScheduleLayoutUtils {
  // Time range constants
  static const int startHour = 9; // 9:00 AM
  static const int endHour = 21; // 9:00 PM
  static const int totalSlots = (endHour - startHour) * 4; // 48 slots

  // Large screen detection threshold for text scaling
  static const double largeScreenSlotHeightThreshold = 15.0;

  /// Get the 2-day window start date for a given date
  /// This ensures stable 2-day windows even when the real-world date changes
  static DateTime get2DayWindowStart(DateTime date) {
    // Use fixed anchor to calculate stable 2-day windows
    final anchor = DateTime(2000, 1, 1); // Fixed epoch anchor
    final daysSinceAnchor = date.difference(anchor).inDays;
    final windowIndex = daysSinceAnchor ~/ 2;
    final windowStart = anchor.add(Duration(days: windowIndex * 2));
    return DateTime(windowStart.year, windowStart.month, windowStart.day);
  }

  /// Get the 3-day window start date for a given date
  /// This ensures stable 3-day windows even when the real-world date changes
  static DateTime get3DayWindowStart(DateTime date) {
    // Use fixed anchor to calculate stable 3-day windows
    final anchor = DateTime(2000, 1, 1); // Fixed epoch anchor
    final daysSinceAnchor = date.difference(anchor).inDays;
    final windowIndex = daysSinceAnchor ~/ 3;
    final windowStart = anchor.add(Duration(days: windowIndex * 3));
    return DateTime(windowStart.year, windowStart.month, windowStart.day);
  }

  /// Get the effective date for data operations (loading/saving events and drawings)
  static DateTime getEffectiveDate(
    DateTime selectedDate, {
    int viewMode = ScheduleDrawing.VIEW_MODE_3DAY,
  }) {
    if (viewMode == ScheduleDrawing.VIEW_MODE_2DAY) {
      return get2DayWindowStart(selectedDate);
    }
    return get3DayWindowStart(selectedDate);
  }

  /// Get unique page identifier for the current view and date
  static String getPageId(
    DateTime selectedDate, {
    int viewMode = ScheduleDrawing.VIEW_MODE_3DAY,
  }) {
    final effectiveDate = getEffectiveDate(selectedDate, viewMode: viewMode);
    return 'page_${viewMode}_${effectiveDate.year}_${effectiveDate.month}_${effectiveDate.day}';
  }

  /// Get navigation increment (always 3 days)
  static Duration getNavigationIncrement() {
    return const Duration(days: 3);
  }

  /// Check if currently viewing today's date
  static bool isViewingToday(DateTime selectedDate) {
    final now = TimeService.instance.now();
    final today = DateTime(now.year, now.month, now.day);
    final viewingDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    return viewingDate == today;
  }

  /// Determine if an event should be displayed as open-end (single slot)
  static bool shouldDisplayAsOpenEnd(Event event) {
    // Only truly open-ended events (no end time) display as single slot
    return event.isOpenEnded;
  }

  /// Get the display duration in minutes for an event
  static int getDisplayDurationInMinutes(Event event) {
    if (shouldDisplayAsOpenEnd(event)) {
      return 15; // Always 15 minutes (1 slot) for open-end display
    }
    return event.durationInMinutes ?? 15;
  }

  /// Get slot index (0-47) for a given time
  static int getSlotIndexForTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    return (hour - startHour) * 4 + (minute ~/ 15);
  }

  /// Calculate the Y position offset for an event based on its start time
  static double calculateEventTopPosition(
    DateTime startTime,
    double slotHeight,
  ) {
    final hour = startTime.hour;
    final minute = startTime.minute;
    final slotIndex = (hour - startHour) * 4 + (minute ~/ 15);
    return slotIndex * slotHeight;
  }

  /// Format the new time display for an event that has been moved
  static String getNewTimeDisplay(Event? newEvent) {
    if (newEvent == null) return '';

    final startHour = newEvent.startTime.hour.toString().padLeft(2, '0');
    final startMinute = newEvent.startTime.minute.toString().padLeft(2, '0');

    if (newEvent.endTime != null) {
      final endHour = newEvent.endTime!.hour.toString().padLeft(2, '0');
      final endMinute = newEvent.endTime!.minute.toString().padLeft(2, '0');
      return '$startHour:$startMinute-$endHour:$endMinute';
    } else {
      return '$startHour:$startMinute';
    }
  }

  /// Calculate event name font size based on slot height
  /// Returns scaled font size (1.8x) for large screens, or original size for smaller screens
  static double getEventNameFontSize(double slotHeight, double baseFontSize) {
    if (slotHeight >= largeScreenSlotHeightThreshold) {
      return baseFontSize * 1.8;
    }
    return baseFontSize;
  }

  /// Get event type color
  static int getEventTypeColor(String eventType, Map<String, String> l10nMap) {
    // l10nMap should contain: consultation, surgery, followUp, emergency, checkUp, treatment
    if (eventType == l10nMap['consultation']) {
      return 0xFF4CAF50; // Green
    } else if (eventType == l10nMap['surgery']) {
      return 0xFFF44336; // Red
    } else if (eventType == l10nMap['followUp']) {
      return 0xFF2196F3; // Blue
    } else if (eventType == l10nMap['emergency']) {
      return 0xFFFF9800; // Orange
    } else if (eventType == l10nMap['checkUp']) {
      return 0xFF9C27B0; // Purple
    } else if (eventType == l10nMap['treatment']) {
      return 0xFF00BCD4; // Cyan
    } else {
      return 0xFF757575; // Gray (default)
    }
  }

  /// Filter events for a specific date
  static List<Event> getEventsForDate(
    DateTime date,
    List<Event> allEvents,
    bool showOldEvents,
  ) {
    return allEvents.where((event) {
      // Always show all events regardless of removed/time-changed status
      return event.startTime.year == date.year &&
          event.startTime.month == date.month &&
          event.startTime.day == date.day;
    }).toList();
  }

  /// Get the new event that this event was moved to (if it has a newEventId)
  static Event? getNewEventForTimeChange(Event event, List<Event> allEvents) {
    if (event.newEventId == null) return null;

    try {
      return allEvents.firstWhere((e) => e.id == event.newEventId);
    } catch (e) {
      return null;
    }
  }

  /// Calculate event positions with slot occupancy algorithm
  /// This prevents event overlaps by tracking which horizontal positions are occupied
  ///
  /// Returns list of positioned events with layout information (position, size)
  static List<PositionedEventData> calculateEventPositions({
    required List<Event> dateEvents,
    required double availableWidth,
    required double slotHeight,
  }) {
    final List<PositionedEventData> positionedEvents = [];

    // Build slot occupancy map: slot index -> set of occupied horizontal positions
    final Map<int, Set<int>> slotOccupancy = {};

    // Group events by start time slot
    final Map<int, List<Event>> eventsBySlot = {};
    for (final event in dateEvents) {
      final slotIndex = getSlotIndexForTime(event.startTime);
      eventsBySlot.putIfAbsent(slotIndex, () => []).add(event);
    }

    // Calculate concurrent event count per time slot
    final Map<int, int> slotEventCount = {};
    for (final event in dateEvents) {
      final slotIndex = getSlotIndexForTime(event.startTime);
      final durationInMinutes = getDisplayDurationInMinutes(event);
      final slotsSpanned = ((durationInMinutes / 15).ceil()).clamp(1, 48);

      // Increment count for all slots this event occupies
      for (int spanOffset = 0; spanOffset < slotsSpanned; spanOffset++) {
        final occupiedSlot = slotIndex + spanOffset;
        slotEventCount[occupiedSlot] = (slotEventCount[occupiedSlot] ?? 0) + 1;
      }
    }

    // Process events in order of time slots
    final sortedSlotIndices = eventsBySlot.keys.toList()..sort();

    for (final slotIndex in sortedSlotIndices) {
      final slotEvents = eventsBySlot[slotIndex]!;

      // Separate close-end and open-end events
      final closeEndEvents = slotEvents
          .where((e) => !shouldDisplayAsOpenEnd(e))
          .toList();
      final openEndEvents = slotEvents
          .where((e) => shouldDisplayAsOpenEnd(e))
          .toList();

      // Sort each list by creation time for stable ordering (with ID as fallback)
      closeEndEvents.sort((a, b) {
        final timeComparison = a.createdAt.compareTo(b.createdAt);
        return timeComparison != 0
            ? timeComparison
            : (a.id ?? '').compareTo(b.id ?? '');
      });
      openEndEvents.sort((a, b) {
        final timeComparison = a.createdAt.compareTo(b.createdAt);
        return timeComparison != 0
            ? timeComparison
            : (a.id ?? '').compareTo(b.id ?? '');
      });

      // Process in order: close-end events first, then open-end events
      final orderedEvents = [...closeEndEvents, ...openEndEvents];

      for (final event in orderedEvents) {
        // Calculate display duration and slots spanned
        final durationInMinutes = getDisplayDurationInMinutes(event);
        final slotsSpanned = ((durationInMinutes / 15).ceil()).clamp(1, 48);

        // Calculate max concurrent events for this event across all slots it spans
        int maxConcurrentForThisEvent = 4; // Default minimum of 4
        for (int spanOffset = 0; spanOffset < slotsSpanned; spanOffset++) {
          final checkSlot = slotIndex + spanOffset;
          final concurrentInSlot = slotEventCount[checkSlot] ?? 0;
          maxConcurrentForThisEvent = max(
            maxConcurrentForThisEvent,
            concurrentInSlot,
          );
        }

        // Calculate event width based on concurrent events
        final eventWidth = availableWidth / maxConcurrentForThisEvent;

        // Find leftmost available horizontal position across all spanned slots
        int horizontalPosition = 0;
        bool positionFound = false;

        for (int pos = 0; pos < maxConcurrentForThisEvent; pos++) {
          bool positionAvailable = true;

          // Check if this position is available in all spanned slots
          for (int spanOffset = 0; spanOffset < slotsSpanned; spanOffset++) {
            final checkSlot = slotIndex + spanOffset;
            if (slotOccupancy[checkSlot]?.contains(pos) ?? false) {
              positionAvailable = false;
              break;
            }
          }

          if (positionAvailable) {
            horizontalPosition = pos;
            positionFound = true;
            break;
          }
        }

        // If no position found, skip this event (should not happen with dynamic positioning)
        if (!positionFound) {
          continue;
        }

        // Mark position as occupied in all spanned slots
        for (int spanOffset = 0; spanOffset < slotsSpanned; spanOffset++) {
          final occupySlot = slotIndex + spanOffset;
          slotOccupancy
              .putIfAbsent(occupySlot, () => {})
              .add(horizontalPosition);
        }

        // Calculate position and height
        final topPosition = calculateEventTopPosition(
          event.startTime,
          slotHeight,
        );
        final tileHeight = (slotsSpanned * slotHeight) - 1; // Subtract margin

        // Add positioned event data
        positionedEvents.add(
          PositionedEventData(
            event: event,
            slotIndex: slotIndex,
            slotsSpanned: slotsSpanned,
            horizontalPosition: horizontalPosition,
            maxConcurrentEvents: maxConcurrentForThisEvent,
            topPosition: topPosition,
            width: eventWidth,
            height: tileHeight,
          ),
        );
      }
    }

    return positionedEvents;
  }
}
