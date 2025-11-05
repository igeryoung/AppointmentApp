import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/book.dart';

/// Dialog for confirming book archival
/// Returns true if confirmed, false/null if cancelled
class ArchiveBookConfirmDialog {
  /// Show the dialog and return true if confirmed
  static Future<bool?> show(BuildContext context, {required Book book}) {
    final l10n = AppLocalizations.of(context)!;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.archiveBook),
        content: Text(l10n.archiveBookConfirmation(book.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.archive),
          ),
        ],
      ),
    );
  }
}
