/// Centralized event time validation utility
///
/// Business rules:
/// 1. Start and end times must be between 9:00 - 21:00
/// 2. End time must be greater than start time
/// 3. Cross-date events are not allowed (start and end must be on same day)
class EventTimeValidator {
  // Constants for business hours
  static const int scheduleStartHour = 9; // 9:00 AM
  static const int scheduleEndHour = 21; // 9:00 PM

  // Minimum event duration in minutes
  static const int minimumDurationMinutes = 15;

  /// Validate a complete time range
  /// Returns null if valid, or error message if invalid
  static String? validateTimeRange(DateTime startTime, DateTime? endTime) {
    // Rule 1: Start time must be within business hours
    final startError = validateStartTime(startTime);
    if (startError != null) return startError;

    // If no end time (open-ended event), no further validation needed
    if (endTime == null) return null;

    // Rule 2: End time must be within business hours
    final endError = validateEndTime(endTime);
    if (endError != null) return endError;

    // Rule 3: Same day check
    if (!isSameDay(startTime, endTime)) {
      return 'Events cannot span across dates';
    }

    // Rule 4: End time must be after start time
    if (!endTime.isAfter(startTime)) {
      return 'End time must be after start time';
    }

    return null; // Valid
  }

  /// Validate start time only
  /// Returns null if valid, or error message if invalid
  static String? validateStartTime(DateTime startTime) {
    if (!isValidStartTime(startTime)) {
      return 'Start time must be between ${_formatHour(scheduleStartHour)} and ${_formatHour(scheduleEndHour)}';
    }
    return null;
  }

  /// Validate end time only
  /// Returns null if valid, or error message if invalid
  static String? validateEndTime(DateTime endTime) {
    if (!isValidEndTime(endTime)) {
      return 'End time must be between ${_formatHour(scheduleStartHour)} and ${_formatHour(scheduleEndHour)}';
    }
    return null;
  }

  /// Check if start time is within business hours (9:00-20:59)
  static bool isValidStartTime(DateTime time) {
    final hour = time.hour;
    return hour >= scheduleStartHour && hour < scheduleEndHour;
  }

  /// Check if end time is within business hours (9:00-21:00 inclusive)
  /// End time can be exactly at scheduleEndHour:00
  static bool isValidEndTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;

    if (hour < scheduleStartHour) return false;
    if (hour > scheduleEndHour) return false;

    // If hour equals scheduleEndHour, only allow :00 (exactly 21:00)
    if (hour == scheduleEndHour && minute > 0) return false;

    return true;
  }

  /// Check if two DateTimes are on the same day
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Calculate maximum allowed duration in minutes from a given start time
  /// Returns the number of minutes until scheduleEndHour:00
  static int getMaxDurationMinutes(DateTime startTime) {
    final endOfDay = DateTime(
      startTime.year,
      startTime.month,
      startTime.day,
      scheduleEndHour,
      0,
    );
    return endOfDay.difference(startTime).inMinutes;
  }

  /// Calculate maximum allowed hours for duration picker
  static int getMaxDurationHours(DateTime startTime) {
    return getMaxDurationMinutes(startTime) ~/ 60;
  }

  /// Get the earliest allowed start time for a given date
  static DateTime getEarliestStartTime(DateTime date) {
    return DateTime(date.year, date.month, date.day, scheduleStartHour, 0);
  }

  /// Get the latest allowed start time for a given date
  /// (must allow at least minimum duration)
  static DateTime getLatestStartTime(DateTime date) {
    final latestHour = scheduleEndHour - 1;
    final latestMinute = 60 - minimumDurationMinutes;
    return DateTime(date.year, date.month, date.day, latestHour, latestMinute);
  }

  /// Get the latest allowed end time for a given date
  static DateTime getLatestEndTime(DateTime date) {
    return DateTime(date.year, date.month, date.day, scheduleEndHour, 0);
  }

  static String _formatHour(int hour) {
    return '${hour.toString().padLeft(2, '0')}:00';
  }
}
