import '../../models/event.dart';
import '../../services/time_service.dart';

/// Utility class for schedule layout calculations
class ScheduleLayoutUtils {
  // Time range constants
  static const int startHour = 9;  // 9:00 AM
  static const int endHour = 21;   // 9:00 PM
  static const int totalSlots = (endHour - startHour) * 4; // 48 slots

  // Large screen detection threshold for text scaling
  static const double largeScreenSlotHeightThreshold = 15.0;

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
  static DateTime getEffectiveDate(DateTime selectedDate) {
    return get3DayWindowStart(selectedDate);
  }

  /// Get unique page identifier for the current view and date
  static String getPageId(DateTime selectedDate) {
    final effectiveDate = getEffectiveDate(selectedDate);
    return 'page_1_${effectiveDate.year}_${effectiveDate.month}_${effectiveDate.day}';
  }

  /// Get navigation increment (always 3 days)
  static Duration getNavigationIncrement() {
    return const Duration(days: 3);
  }

  /// Check if currently viewing today's date
  static bool isViewingToday(DateTime selectedDate) {
    final now = TimeService.instance.now();
    final today = DateTime(now.year, now.month, now.day);
    final viewingDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    return viewingDate == today;
  }

  /// Determine if an event should be displayed as open-end (single slot)
  static bool shouldDisplayAsOpenEnd(Event event) {
    // Removed events or old events with new time should be displayed as open-end (single slot)
    // NEW events (isTimeChanged) should display normally with full duration
    return event.isRemoved || event.hasNewTime || event.isOpenEnded;
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
  static double calculateEventTopPosition(DateTime startTime, double slotHeight) {
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
      if (!showOldEvents && (event.isRemoved || event.hasNewTime)) {
        return false;
      }
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
}
