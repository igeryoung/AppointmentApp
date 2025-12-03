import 'package:flutter/foundation.dart';

/// Service for providing current time with testing override capability
///
/// This service allows setting a custom time for testing time-dependent behaviors
/// like date change detection, current time indicators, etc.
class TimeService extends ChangeNotifier {
  static final TimeService instance = TimeService._internal();

  TimeService._internal();

  DateTime? _overrideTime;

  /// Get the current time (real or overridden for testing)
  DateTime now() {
    return _overrideTime ?? DateTime.now();
  }

  /// Check if a test time is currently set
  bool get isTestMode => _overrideTime != null;

  /// Get the override time (if set)
  DateTime? get overrideTime => _overrideTime;

  /// Set a custom time for testing
  void setTestTime(DateTime time) {
    _overrideTime = time;
    notifyListeners();
  }

  /// Reset to real time
  void resetToRealTime() {
    _overrideTime = null;
    notifyListeners();
  }
}
