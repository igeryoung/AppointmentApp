import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/app_localizations.dart';

/// Utility class for showing standardized SnackBars
class SnackBarUtils {
  SnackBarUtils._();

  /// Show a success message with a "Details" button
  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: l10n.details,
          textColor: Colors.white,
          onPressed: () {
            _showDetailsDialog(context, l10n.success, message);
          },
        ),
      ),
    );
  }

  /// Show an error message with a "Details" button
  static void showError(BuildContext context, String message) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: l10n.details,
          textColor: Colors.white,
          onPressed: () {
            _showDetailsDialog(context, l10n.errorLabel, message);
          },
        ),
      ),
    );
  }

  /// Show a warning message with a "Details" button
  static void showWarning(BuildContext context, String message) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: l10n.details,
          textColor: Colors.white,
          onPressed: () {
            _showDetailsDialog(context, l10n.warning, message);
          },
        ),
      ),
    );
  }

  /// Show an info message with a "Details" button
  static void showInfo(BuildContext context, String message) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: l10n.details,
          textColor: Colors.white,
          onPressed: () {
            _showDetailsDialog(context, l10n.info, message);
          },
        ),
      ),
    );
  }

  /// Show a success message with a "Details" button to view full message in a popup
  static void showSuccessWithDetails({
    required BuildContext context,
    required String message,
    required String detailTitle,
    required String detailMessage,
  }) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: l10n.details,
          textColor: Colors.white,
          onPressed: () {
            _showDetailsDialog(context, detailTitle, detailMessage);
          },
        ),
      ),
    );
  }

  /// Show an error message with a "Details" button to view full message in a popup
  static void showErrorWithDetails({
    required BuildContext context,
    required String message,
    required String detailTitle,
    required String detailMessage,
  }) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: l10n.details,
          textColor: Colors.white,
          onPressed: () {
            _showDetailsDialog(context, detailTitle, detailMessage);
          },
        ),
      ),
    );
  }

  /// Show a warning message with a "Details" button to view full message in a popup
  static void showWarningWithDetails({
    required BuildContext context,
    required String message,
    required String detailTitle,
    required String detailMessage,
  }) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: l10n.details,
          textColor: Colors.white,
          onPressed: () {
            _showDetailsDialog(context, detailTitle, detailMessage);
          },
        ),
      ),
    );
  }

  /// Show an info message with a "Details" button to view full message in a popup
  static void showInfoWithDetails({
    required BuildContext context,
    required String message,
    required String detailTitle,
    required String detailMessage,
  }) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: l10n.details,
          textColor: Colors.white,
          onPressed: () {
            _showDetailsDialog(context, detailTitle, detailMessage);
          },
        ),
      ),
    );
  }

  /// Show a warning with an action button
  static void showWarningWithAction({
    required BuildContext context,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: actionLabel,
          textColor: Colors.white,
          onPressed: onAction,
        ),
      ),
    );
  }

  /// Show a details dialog with scrollable content and copy button
  static void _showDetailsDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.messageCopiedToClipboard),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Text(l10n.copy),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }
}
