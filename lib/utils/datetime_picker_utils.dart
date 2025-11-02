import 'package:flutter/material.dart';

/// Utility class for date and time picker operations.
/// Consolidates duplicate date/time picker logic from multiple screens.
class DateTimePickerUtils {
  /// Shows a combined date and time picker dialog.
  ///
  /// Returns the selected [DateTime] or null if the user cancels.
  ///
  /// Parameters:
  /// - [context]: The build context for showing the dialogs
  /// - [initialDateTime]: The initial date and time to display
  /// - [firstDate]: The earliest selectable date (optional, defaults to 1 year ago)
  /// - [lastDate]: The latest selectable date (optional, defaults to 1 year from now)
  static Future<DateTime?> pickDateTime(
    BuildContext context, {
    required DateTime initialDateTime,
    DateTime? firstDate,
    DateTime? lastDate,
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
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }
}
