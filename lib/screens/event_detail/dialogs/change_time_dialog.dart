import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/datetime_picker_utils.dart';
import '../../../constants/change_reasons.dart';

/// Result class for change time dialog
class ChangeTimeResult {
  final DateTime startTime;
  final DateTime? endTime;
  final String reason;

  ChangeTimeResult({
    required this.startTime,
    required this.endTime,
    required this.reason,
  });
}

/// Dialog to change event time with reason
class ChangeTimeDialog {
  static Future<ChangeTimeResult?> show(
    BuildContext context, {
    required DateTime initialStartTime,
    required DateTime? initialEndTime,
  }) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        DateTime newStartTime = initialStartTime;
        DateTime? newEndTime = initialEndTime;
        final additionalTextController = TextEditingController();
        String? selectedReason;
        String? reasonErrorMessage;

        return StatefulBuilder(
          builder: (context, setState) {
            final showAdditionalField = ChangeReasons.requiresAdditionalInput(selectedReason);
            final bool hasValidReason = selectedReason != null &&
                (!showAdditionalField || additionalTextController.text.trim().isNotEmpty);

            return AlertDialog(
              title: Text(l10n.changeEventTimeTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.changeTimeMessage),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final result = await DateTimePickerUtils.pickDateTime(
                              context,
                              initialDateTime: newStartTime,
                            );
                            if (result == null) return;

                            setState(() {
                              newStartTime = result;
                            });
                          },
                          child: Text(
                            'Start: ${DateFormat('MMM d, HH:mm', Localizations.localeOf(context).toString()).format(newStartTime)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final result = await DateTimePickerUtils.pickDateTime(
                              context,
                              initialDateTime: newEndTime ?? newStartTime,
                              firstDate: newStartTime,
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (result == null) return;

                            setState(() {
                              newEndTime = result;
                            });
                          },
                          child: Text(
                            newEndTime != null
                                ? 'End: ${DateFormat('MMM d, HH:mm', Localizations.localeOf(context).toString()).format(newEndTime!)}'
                                : 'Set End Time (Optional)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (newEndTime != null)
                        IconButton(
                          onPressed: () => setState(() => newEndTime = null),
                          icon: const Icon(Icons.clear, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.reasonForTimeChangeField, style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  // Dropdown for reason selection
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    decoration: InputDecoration(
                      hintText: '請選擇原因',
                      border: const OutlineInputBorder(),
                      errorText: reasonErrorMessage,
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
                        reasonErrorMessage = null;
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
                      onChanged: (value) {
                        setState(() {
                          // Trigger rebuild to update button state
                        });
                      },
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
                        reasonErrorMessage = '請選擇原因';
                      });
                      return;
                    }

                    // Format the reason based on selection
                    String finalReason;
                    if (showAdditionalField) {
                      final additionalText = additionalTextController.text.trim();
                      if (additionalText.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('請輸入其他原因')),
                        );
                        return;
                      }
                      finalReason = ChangeReasons.formatReason(selectedReason!, additionalText);
                    } else {
                      finalReason = selectedReason!;
                    }

                    Navigator.pop(context, {
                      'startTime': newStartTime,
                      'endTime': newEndTime,
                      'reason': finalReason,
                    });
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: hasValidReason ? Theme.of(context).primaryColor : Colors.grey.shade300,
                    foregroundColor: hasValidReason ? Colors.white : Colors.grey.shade600,
                  ),
                  child: Text(l10n.changeTimeButton),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return null;

    return ChangeTimeResult(
      startTime: result['startTime'],
      endTime: result['endTime'],
      reason: result['reason'],
    );
  }
}
