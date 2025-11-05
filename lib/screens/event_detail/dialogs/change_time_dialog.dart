import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/datetime_picker_utils.dart';

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
        final reasonController = TextEditingController();
        bool showReasonError = false;

        return StatefulBuilder(
          builder: (context, setState) {
            final bool hasValidReason = reasonController.text.trim().isNotEmpty;

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
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      hintText: l10n.enterReasonForTimeChange,
                      border: const OutlineInputBorder(),
                      errorText: showReasonError ? l10n.reasonRequired : null,
                      errorBorder: showReasonError
                          ? const OutlineInputBorder(borderSide: BorderSide(color: Colors.red))
                          : null,
                    ),
                    maxLines: 2,
                    autofocus: true,
                    onChanged: (value) {
                      setState(() {
                        showReasonError = false;
                      });
                    },
                  ),
                  if (showReasonError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.reasonRequiredMessage,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () {
                    final reason = reasonController.text.trim();
                    if (reason.isEmpty) {
                      setState(() {
                        showReasonError = true;
                      });
                      return;
                    }
                    Navigator.pop(context, {
                      'startTime': newStartTime,
                      'endTime': newEndTime,
                      'reason': reason,
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
