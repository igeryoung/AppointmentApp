import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Utility class for centralized date formatting
class DateFormatUtils {
  DateFormatUtils._();

  /// Format a date according to the current locale
  static String formatDate(DateTime date, BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('MMM d, y', locale).format(date);
  }

  /// Format a date with time according to the current locale
  static String formatDateTimeWithTime(DateTime dateTime, BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('MMM d, y HH:mm', locale).format(dateTime);
  }

  /// Format a date with full month name
  static String formatDateFull(DateTime date, BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('MMMM d, y', locale).format(date);
  }

  /// Format time only
  static String formatTime(DateTime dateTime, BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('HH:mm', locale).format(dateTime);
  }
}
