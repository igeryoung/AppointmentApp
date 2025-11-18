import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/time_service.dart';
import '../../../utils/schedule/schedule_layout_utils.dart';

/// Service for managing date navigation, selection, and automatic date change detection
/// in the schedule screen. Handles 3-day window navigation and auto-reload when
/// the system date changes.
class ScheduleDateService {
  /// Timer for periodically checking date changes
  Timer? _dateCheckTimer;

  /// Last known active date (used to detect date changes)
  DateTime _lastActiveDate;

  /// Current selected date
  DateTime _selectedDate;

  /// Day offset from "today" (for displaying relative navigation like "+180 days")
  int _dayOffset = 0;

  /// Callback to trigger state update in the parent widget
  final void Function(DateTime selectedDate, DateTime lastActiveDate) onDateChanged;

  /// Callback to save drawing before date change
  final Future<void> Function() onSaveDrawing;

  /// Callback to load drawing after date change
  final Future<void> Function() onLoadDrawing;

  /// Callback to update cubit with new date
  final void Function(DateTime date) onUpdateCubit;

  /// Callback to show snackbar notification
  final void Function(String message) onShowNotification;

  /// Callback to check if widget is still mounted
  final bool Function() isMounted;

  /// Callback to check if currently in drawing mode
  final bool Function() isInDrawingMode;

  /// Callback to cancel pending drawing saves
  final void Function() onCancelPendingSave;

  /// Callback to exit drawing mode after auto-save
  void Function()? onExitDrawingMode;

  /// Callback to notify when navigation state changes (for loading overlay)
  void Function(bool isNavigating)? onNavigatingStateChanged;

  ScheduleDateService({
    required DateTime initialDate,
    required this.onDateChanged,
    required this.onSaveDrawing,
    required this.onLoadDrawing,
    required this.onUpdateCubit,
    required this.onShowNotification,
    required this.isMounted,
    required this.isInDrawingMode,
    required this.onCancelPendingSave,
  })  : _selectedDate = initialDate,
        _lastActiveDate = TimeService.instance.now();

  /// Get the current selected date
  DateTime get selectedDate => _selectedDate;

  /// Get the last active date
  DateTime get lastActiveDate => _lastActiveDate;

  /// Start timer to periodically check for date changes (every minute)
  void startPeriodicCheck() {
    _dateCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      checkAndHandleDateChange();
    });
  }

  /// Stop the periodic date check timer
  void dispose() {
    _dateCheckTimer?.cancel();
    _dateCheckTimer = null;
  }

  /// Check if the system date has changed and handle it
  Future<void> checkAndHandleDateChange() async {
    final now = TimeService.instance.now();
    final currentDate = DateTime(now.year, now.month, now.day);
    final lastActiveDate = DateTime(_lastActiveDate.year, _lastActiveDate.month, _lastActiveDate.day);

    if (currentDate != lastActiveDate) {
      debugPrint('📅 Date changed detected: $lastActiveDate → $currentDate');

      // Check if user is viewing a 3-day window that contains "today" (the new current date)
      final windowStart = ScheduleLayoutUtils.get3DayWindowStart(_selectedDate);
      final windowEnd = windowStart.add(const Duration(days: 3));
      // Check if the old "today" (lastActiveDate) is in the current viewing window
      final isViewingWindowContainingToday = lastActiveDate.isAfter(windowStart.subtract(const Duration(days: 1))) &&
                                          lastActiveDate.isBefore(windowEnd);

      if (isViewingWindowContainingToday) {
        debugPrint('📅 User was viewing window containing "today" - auto-updating to new today');

        // Save current drawing before switching dates
        if (isInDrawingMode()) {
          await onSaveDrawing();
        }

        // Update to new today
        _selectedDate = now;
        _lastActiveDate = now;
        _dayOffset = 0; // Reset day offset when auto-updating to today
        onDateChanged(_selectedDate, _lastActiveDate);

        if (isMounted()) {
          onUpdateCubit(_selectedDate);
        }

        // Reload drawing for new date
        await onLoadDrawing();

        // Show notification to user
        if (isMounted()) {
          // Note: The message will be localized in the parent widget
          onShowNotification('dateChangedToToday');
        }
      } else {
        // User is viewing a different window - just update last active date
        // Recalculate day offset based on new "today"
        debugPrint('📅 User viewing different window - keeping current view, recalculating offset');
        _lastActiveDate = now;
        _dayOffset = _calculateDayOffsetFromToday(_selectedDate);
      }
    }
  }

  /// Auto-save and exit drawing mode before navigation
  /// Returns true if successful, false if save failed
  Future<bool> _autoSaveAndExitDrawingMode() async {
    if (isInDrawingMode()) {
      debugPrint('📝 Auto-saving drawing before navigation...');
      try {
        onCancelPendingSave();
        await onSaveDrawing();
        onExitDrawingMode?.call();
        debugPrint('✅ Drawing saved and exited drawing mode');
        return true;
      } catch (e) {
        debugPrint('❌ Failed to save drawing: $e');
        return false;
      }
    }
    return true;
  }

  /// Show date picker and handle date selection
  /// Returns true if date was changed, false otherwise
  Future<bool> showDatePickerDialog(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null) {
      onNavigatingStateChanged?.call(true);
      try {
        // Auto-save and exit drawing mode if needed
        final saveSuccess = await _autoSaveAndExitDrawingMode();
        if (!saveSuccess) {
          return false; // Cancel navigation if save failed
        }

        _selectedDate = date;
        // Calculate day offset from today
        _dayOffset = _calculateDayOffsetFromToday(date);
        onDateChanged(_selectedDate, _lastActiveDate);
        onUpdateCubit(_selectedDate);
        await onLoadDrawing();
        return true;
      } finally {
        onNavigatingStateChanged?.call(false);
      }
    }

    return false;
  }

  /// Calculate day offset from today's date
  /// Returns the number of days difference between target date's window start and today's window start
  int _calculateDayOffsetFromToday(DateTime date) {
    final now = TimeService.instance.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    final windowStartToday = ScheduleLayoutUtils.get3DayWindowStart(today);
    final windowStartTarget = ScheduleLayoutUtils.get3DayWindowStart(targetDate);

    return windowStartTarget.difference(windowStartToday).inDays;
  }

  /// Navigate to previous 3-day window
  Future<void> navigatePrevious() async {
    onNavigatingStateChanged?.call(true);
    try {
      // Auto-save and exit drawing mode if needed
      final saveSuccess = await _autoSaveAndExitDrawingMode();
      if (!saveSuccess) {
        return; // Cancel navigation if save failed
      }

      _selectedDate = _selectedDate.subtract(getNavigationIncrement());
      onDateChanged(_selectedDate, _lastActiveDate);
      onUpdateCubit(_selectedDate);
      await onLoadDrawing();
    } finally {
      onNavigatingStateChanged?.call(false);
    }
  }

  /// Navigate to next 3-day window
  Future<void> navigateNext() async {
    onNavigatingStateChanged?.call(true);
    try {
      // Auto-save and exit drawing mode if needed
      final saveSuccess = await _autoSaveAndExitDrawingMode();
      if (!saveSuccess) {
        return; // Cancel navigation if save failed
      }

      _selectedDate = _selectedDate.add(getNavigationIncrement());
      onDateChanged(_selectedDate, _lastActiveDate);
      onUpdateCubit(_selectedDate);
      await onLoadDrawing();
    } finally {
      onNavigatingStateChanged?.call(false);
    }
  }

  /// Navigate 3 days backward
  Future<void> navigate3DaysPrevious() async {
    onNavigatingStateChanged?.call(true);
    try {
      // Auto-save and exit drawing mode if needed
      final saveSuccess = await _autoSaveAndExitDrawingMode();
      if (!saveSuccess) {
        return; // Cancel navigation if save failed
      }

      _selectedDate = _selectedDate.subtract(const Duration(days: 3));
      _dayOffset -= 3; // Decrement by 3 days
      onDateChanged(_selectedDate, _lastActiveDate);
      onUpdateCubit(_selectedDate);
      await onLoadDrawing();
    } finally {
      onNavigatingStateChanged?.call(false);
    }
  }

  /// Navigate 3 days forward
  Future<void> navigate3DaysNext() async {
    onNavigatingStateChanged?.call(true);
    try {
      // Auto-save and exit drawing mode if needed
      final saveSuccess = await _autoSaveAndExitDrawingMode();
      if (!saveSuccess) {
        return; // Cancel navigation if save failed
      }

      _selectedDate = _selectedDate.add(const Duration(days: 3));
      _dayOffset += 3; // Increment by 3 days
      onDateChanged(_selectedDate, _lastActiveDate);
      onUpdateCubit(_selectedDate);
      await onLoadDrawing();
    } finally {
      onNavigatingStateChanged?.call(false);
    }
  }

  /// Navigate 90 days backward
  Future<void> navigate90DaysPrevious() async {
    onNavigatingStateChanged?.call(true);
    try {
      // Auto-save and exit drawing mode if needed
      final saveSuccess = await _autoSaveAndExitDrawingMode();
      if (!saveSuccess) {
        return; // Cancel navigation if save failed
      }

      _selectedDate = _selectedDate.subtract(const Duration(days: 90));
      _dayOffset -= 90; // Decrement by 90 days
      onDateChanged(_selectedDate, _lastActiveDate);
      onUpdateCubit(_selectedDate);
      await onLoadDrawing();
    } finally {
      onNavigatingStateChanged?.call(false);
    }
  }

  /// Navigate 90 days forward
  Future<void> navigate90DaysNext() async {
    onNavigatingStateChanged?.call(true);
    try {
      // Auto-save and exit drawing mode if needed
      final saveSuccess = await _autoSaveAndExitDrawingMode();
      if (!saveSuccess) {
        return; // Cancel navigation if save failed
      }

      _selectedDate = _selectedDate.add(const Duration(days: 90));
      _dayOffset += 90; // Increment by 90 days
      onDateChanged(_selectedDate, _lastActiveDate);
      onUpdateCubit(_selectedDate);
      await onLoadDrawing();
    } finally {
      onNavigatingStateChanged?.call(false);
    }
  }

  /// Navigate 180 days backward
  Future<void> navigate180DaysPrevious() async {
    onNavigatingStateChanged?.call(true);
    try {
      // Auto-save and exit drawing mode if needed
      final saveSuccess = await _autoSaveAndExitDrawingMode();
      if (!saveSuccess) {
        return; // Cancel navigation if save failed
      }

      _selectedDate = _selectedDate.subtract(const Duration(days: 180));
      _dayOffset -= 180; // Decrement by 180 days
      onDateChanged(_selectedDate, _lastActiveDate);
      onUpdateCubit(_selectedDate);
      await onLoadDrawing();
    } finally {
      onNavigatingStateChanged?.call(false);
    }
  }

  /// Navigate 180 days forward
  Future<void> navigate180DaysNext() async {
    onNavigatingStateChanged?.call(true);
    try {
      // Auto-save and exit drawing mode if needed
      final saveSuccess = await _autoSaveAndExitDrawingMode();
      if (!saveSuccess) {
        return; // Cancel navigation if save failed
      }

      _selectedDate = _selectedDate.add(const Duration(days: 180));
      _dayOffset += 180; // Increment by 180 days
      onDateChanged(_selectedDate, _lastActiveDate);
      onUpdateCubit(_selectedDate);
      await onLoadDrawing();
    } finally {
      onNavigatingStateChanged?.call(false);
    }
  }

  /// Jump to today's date
  Future<void> jumpToToday() async {
    final now = TimeService.instance.now();
    if (_selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day) {
      return; // Already on today
    }

    onNavigatingStateChanged?.call(true);
    try {
      // Auto-save and exit drawing mode if needed
      final saveSuccess = await _autoSaveAndExitDrawingMode();
      if (!saveSuccess) {
        return; // Cancel navigation if save failed
      }

      _selectedDate = now;
      _dayOffset = 0; // Reset day offset when jumping to today
      onDateChanged(_selectedDate, _lastActiveDate);
      onUpdateCubit(_selectedDate);
      await onLoadDrawing();
    } finally {
      onNavigatingStateChanged?.call(false);
    }
  }

  /// Get navigation increment duration (always 3 days for 3-day view)
  Duration getNavigationIncrement() {
    return const Duration(days: 3);
  }

  /// Get date display text for the current 3-day window
  String getDateDisplayText(BuildContext context) {
    final windowStart = ScheduleLayoutUtils.get3DayWindowStart(_selectedDate);
    final windowEnd = windowStart.add(const Duration(days: 2));
    final locale = Localizations.localeOf(context).toString();
    final dateRange = '${DateFormat('MMM d', locale).format(windowStart)} - ${DateFormat('MMM d, y', locale).format(windowEnd)}';

    // If day offset is not zero, append the offset
    if (_dayOffset != 0) {
      final sign = _dayOffset > 0 ? '+' : '';
      return '$dateRange ($sign$_dayOffset days)';
    }

    // Otherwise show only absolute dates
    return dateRange;
  }

  /// Check if currently viewing today
  bool isViewingToday() {
    final now = TimeService.instance.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  /// Get the start of the current 3-day window
  DateTime getWindowStart() {
    return ScheduleLayoutUtils.get3DayWindowStart(_selectedDate);
  }
}
