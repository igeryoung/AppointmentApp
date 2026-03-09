import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Helper class for schedule test menu functionality
///
/// Contains development/testing features for the schedule tools menu.
class ScheduleTestMenuHelper {
  /// Show test time dialog for time manipulation
  static Future<void> showTestTimeDialog(BuildContext context) async {
    // This is a simplified version - full implementation should match schedule_screen's original
    // For now, just show a placeholder
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.testTimeDialogPlaceholder)));
  }
}
