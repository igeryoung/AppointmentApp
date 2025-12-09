import 'package:flutter/material.dart';
import 'event_time_validator.dart';

/// Utility class for date and time picker operations.
/// Consolidates duplicate date/time picker logic from multiple screens.
class DateTimePickerUtils {
  /// Shows a combined date and time picker dialog with optional business hours validation.
  ///
  /// Returns the selected [DateTime] or null if the user cancels or selects invalid time.
  ///
  /// Parameters:
  /// - [context]: The build context for showing the dialogs
  /// - [initialDateTime]: The initial date and time to display
  /// - [firstDate]: The earliest selectable date (optional, defaults to 1 year ago)
  /// - [lastDate]: The latest selectable date (optional, defaults to 1 year from now)
  /// - [validateBusinessHours]: If true, validates that selected time is within 9:00-21:00
  /// - [isEndTime]: If true, treats this as end time selection (allows 21:00 exactly)
  /// - [referenceStartTime]: For end time validation, the start time to validate against
  static Future<DateTime?> pickDateTime(
    BuildContext context, {
    required DateTime initialDateTime,
    DateTime? firstDate,
    DateTime? lastDate,
    bool validateBusinessHours = false,
    bool isEndTime = false,
    DateTime? referenceStartTime,
  }) async {
    // Default date range: 1 year before/after current date
    final defaultFirstDate = DateTime.now().subtract(const Duration(days: 365));
    final defaultLastDate = DateTime.now().add(const Duration(days: 365));

    // Step 1: Show date picker
    final date = await showDatePicker(
      context: context,
      initialDate: initialDateTime,
      firstDate: firstDate ?? defaultFirstDate,
      lastDate: lastDate ?? defaultLastDate,
    );

    // User cancelled date selection
    if (date == null) return null;

    // Step 2: Show time picker
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDateTime),
    );

    // User cancelled time selection
    if (time == null) return null;

    // Step 3: Combine date and time
    final result = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    // Step 4: Validate if required
    if (validateBusinessHours) {
      String? error;

      if (isEndTime) {
        // Validate as end time
        error = EventTimeValidator.validateEndTime(result);

        // Additional validation against reference start time
        if (error == null && referenceStartTime != null) {
          if (!EventTimeValidator.isSameDay(referenceStartTime, result)) {
            error = 'End time must be on the same day as start time';
          } else if (!result.isAfter(referenceStartTime)) {
            error = 'End time must be after start time';
          }
        }
      } else {
        // Validate as start time
        error = EventTimeValidator.validateStartTime(result);
      }

      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.orange,
          ),
        );
        return null; // Return null to indicate invalid selection
      }
    }

    return result;
  }
}
