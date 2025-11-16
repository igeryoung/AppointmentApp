import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../constants/change_reasons.dart';

/// Dialog to remove event with a reason
class RemoveEventDialog {
  static Future<String?> show(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final additionalTextController = TextEditingController();
    String? selectedReason;
    String? errorMessage;

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final showAdditionalField = ChangeReasons.requiresAdditionalInput(selectedReason);

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
                  // Dropdown for reason selection
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    decoration: InputDecoration(
                      hintText: '請選擇原因',
                      border: const OutlineInputBorder(),
                      errorText: errorMessage,
                    ),
                    isExpanded: true,
                    items: ChangeReasons.allReasons.map((reason) {
                      return DropdownMenuItem(
                        value: reason,
                        child: Text(reason),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedReason = value;
                        errorMessage = null;
                        // Clear additional text when switching away from "other"
                        if (!ChangeReasons.requiresAdditionalInput(value)) {
                          additionalTextController.clear();
                        }
                      });
                    },
                  ),
                  // Conditional text field for "other" option
                  if (showAdditionalField) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: additionalTextController,
                      decoration: const InputDecoration(
                        hintText: '請輸入其他原因...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      autofocus: true,
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () {
                    // Validation
                    if (selectedReason == null) {
                      setState(() {
                        errorMessage = '請選擇原因';
                      });
                      return;
                    }

                    // If "other" option, validate additional text
                    if (showAdditionalField) {
                      final additionalText = additionalTextController.text.trim();
                      if (additionalText.isEmpty) {
                        // Show error for empty additional text
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('請輸入其他原因')),
                        );
                        return;
                      }
                      final formattedReason = ChangeReasons.formatReason(selectedReason!, additionalText);
                      Navigator.pop(context, formattedReason);
                    } else {
                      Navigator.pop(context, selectedReason);
                    }
                  },
                  child: Text(l10n.removeButton),
                ),
              ],
            );
          },
        );
      },
    );

    additionalTextController.dispose();
    return result;
  }
}
