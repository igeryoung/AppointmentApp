import 'package:flutter/material.dart';

/// Helper class for schedule test menu functionality
///
/// Contains development/testing features for the schedule tools menu.
class ScheduleTestMenuHelper {
  /// Show test time dialog for time manipulation
  static Future<void> showTestTimeDialog(BuildContext context) async {
    // This is a simplified version - full implementation should match schedule_screen's original
    // For now, just show a placeholder
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test time dialog - feature extracted')),
    );
  }
}
