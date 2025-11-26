import 'package:flutter/foundation.dart';

/// Service for providing current time with testing override capability
///
/// This service allows setting a custom time for testing time-dependent behaviors
/// like date change detection, current time indicators, etc.
class TimeService extends ChangeNotifier {
  static final TimeService instance = TimeService._internal();

  TimeService._internal();

  DateTime? _overrideTime;

  /// Get the current time in UTC (real or overridden for testing)
  /// Use this for storing timestamps
  DateTime now() {
    return (_overrideTime ?? DateTime.now()).toUtc();
  }

  /// Get the current time in local timezone
  /// Use this for displaying times to users
  DateTime nowLocal() {
    return (_overrideTime ?? DateTime.now()).toLocal();
  }

  /// Check if a test time is currently set
  bool get isTestMode => _overrideTime != null;

  /// Get the override time (if set)
  DateTime? get overrideTime => _overrideTime;

  /// Set a custom time for testing
  void setTestTime(DateTime time) {
    _overrideTime = time;
    notifyListeners();
    debugPrint('⏰ Test time set to: $time');
  }

  /// Reset to real time
  void resetToRealTime() {
    _overrideTime = null;
    notifyListeners();
    debugPrint('⏰ Reset to real time');
  }
}
