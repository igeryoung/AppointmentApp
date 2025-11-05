import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

/// Dialog to remove event with a reason
class RemoveEventDialog {
  static Future<String?> show(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.removeEventTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.removeEventMessage),
              const SizedBox(height: 16),
              Text(l10n.reasonForRemovalField),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: l10n.enterReasonForRemoval,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(l10n.removeButton),
            ),
          ],
        );
      },
    );

    return result;
  }
}
