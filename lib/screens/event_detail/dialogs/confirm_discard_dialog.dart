import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

/// Dialog to confirm discarding unsaved changes
class ConfirmDiscardDialog {
  static Future<bool> show(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.unsavedChanges),
        content: Text(l10n.unsavedChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.keepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text(l10n.discard),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}
