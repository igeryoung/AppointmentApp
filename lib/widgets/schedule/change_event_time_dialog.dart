import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/event.dart';
import '../../utils/datetime_picker_utils.dart';

/// Data returned from change event time dialog
class ChangeEventTimeResult {
  final DateTime startTime;
  final DateTime? endTime;
  final String reason;

  const ChangeEventTimeResult({
    required this.startTime,
    required this.endTime,
    required this.reason,
  });
}

/// Show dialog to change event time with reason
Future<ChangeEventTimeResult?> showChangeEventTimeDialog(
  BuildContext context,
  Event event,
) async {
  final l10n = AppLocalizations.of(context)!;

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _ChangeEventTimeDialog(
      event: event,
      l10n: l10n,
    ),
  );

  if (result == null) return null;

  return ChangeEventTimeResult(
    startTime: result['startTime'],
    endTime: result['endTime'],
    reason: result['reason'],
  );
}

class _ChangeEventTimeDialog extends StatefulWidget {
  final Event event;
  final AppLocalizations l10n;

  const _ChangeEventTimeDialog({
    required this.event,
    required this.l10n,
  });

  @override
  State<_ChangeEventTimeDialog> createState() => _ChangeEventTimeDialogState();
}

class _ChangeEventTimeDialogState extends State<_ChangeEventTimeDialog> {
  late DateTime newStartTime;
  late DateTime? newEndTime;
  late TextEditingController reasonController;
  bool showReasonError = false;

  @override
  void initState() {
    super.initState();
    newStartTime = widget.event.startTime;
    newEndTime = widget.event.endTime;
    reasonController = TextEditingController();
  }

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasValidReason = reasonController.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(widget.l10n.changeEventTime),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.l10n.changeTimeMessage),
          const SizedBox(height: 16),
          // Start time picker
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _pickStartTime,
                  child: Text(
                    'Start: ${_formatDateTime(newStartTime)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          // End time picker
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _pickEndTime,
                  child: Text(
                    newEndTime != null
                        ? 'End: ${_formatDateTime(newEndTime!)}'
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
          // Reason field
          Text(
            widget.l10n.reasonForTimeChangeField,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: reasonController,
            decoration: InputDecoration(
              hintText: widget.l10n.enterReasonForTimeChange,
              border: const OutlineInputBorder(),
              errorText: showReasonError ? widget.l10n.reasonRequired : null,
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
                widget.l10n.reasonRequiredMessage,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(widget.l10n.cancel),
        ),
        TextButton(
          onPressed: _handleSubmit,
          style: TextButton.styleFrom(
            backgroundColor: hasValidReason
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
            foregroundColor: hasValidReason
                ? Colors.white
                : Colors.grey.shade600,
          ),
          child: Text(widget.l10n.changeTimeButton),
        ),
      ],
    );
  }

  Future<void> _pickStartTime() async {
    final result = await DateTimePickerUtils.pickDateTime(
      context,
      initialDateTime: newStartTime,
    );
    if (result == null) return;

    setState(() {
      newStartTime = result;
    });
  }

  Future<void> _pickEndTime() async {
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
  }

  void _handleSubmit() {
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
  }

  String _formatDateTime(DateTime dateTime) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('MMM d, HH:mm', locale).format(dateTime);
  }
}
