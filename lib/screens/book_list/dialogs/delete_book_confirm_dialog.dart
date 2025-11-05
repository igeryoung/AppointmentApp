import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/book.dart';

/// Dialog for confirming book deletion
/// Returns true if confirmed, false/null if cancelled
class DeleteBookConfirmDialog {
  /// Show the dialog and return true if confirmed
  static Future<bool?> show(BuildContext context, {required Book book}) {
    final l10n = AppLocalizations.of(context)!;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteBook),
        content: Text(l10n.deleteBookConfirmation(book.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
