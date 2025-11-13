import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../screens/event_detail/utils/event_type_localizations.dart';
import '../../screens/schedule/dialogs/change_event_type_dialog.dart';

/// Data returned from schedule next appointment dialog
class ScheduleNextAppointmentResult {
  final int daysFromOriginal;
  final List<EventType> eventTypes;

  const ScheduleNextAppointmentResult({
    required this.daysFromOriginal,
    required this.eventTypes,
  });
}

/// Show dialog to schedule next appointment
Future<ScheduleNextAppointmentResult?> showScheduleNextAppointmentDialog(
  BuildContext context,
  Event originalEvent,
) async {
  final l10n = AppLocalizations.of(context)!;

  final result = await showDialog<ScheduleNextAppointmentResult>(
    context: context,
    builder: (context) => _ScheduleNextAppointmentDialog(
      originalEvent: originalEvent,
      l10n: l10n,
    ),
  );

  return result;
}

class _ScheduleNextAppointmentDialog extends StatefulWidget {
  final Event originalEvent;
  final AppLocalizations l10n;

  const _ScheduleNextAppointmentDialog({
    required this.originalEvent,
    required this.l10n,
  });

  @override
  State<_ScheduleNextAppointmentDialog> createState() => _ScheduleNextAppointmentDialogState();
}

class _ScheduleNextAppointmentDialogState extends State<_ScheduleNextAppointmentDialog> {
  late TextEditingController daysController;
  late List<EventType> selectedEventTypes;
  String? daysError;

  @override
  void initState() {
    super.initState();
    daysController = TextEditingController(text: '180');
    selectedEventTypes = List.from(widget.originalEvent.eventTypes);
  }

  @override
  void dispose() {
    daysController.dispose();
    super.dispose();
  }

  /// Calculate target date based on days input
  DateTime? _calculateTargetDate() {
    final daysText = daysController.text.trim();
    if (daysText.isEmpty) return null;

    final days = int.tryParse(daysText);
    if (days == null || days <= 0) return null;

    return widget.originalEvent.startTime.add(Duration(days: days));
  }

  /// Format date for preview
  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  /// Validate and confirm
  void _confirm() {
    final daysText = daysController.text.trim();

    if (daysText.isEmpty) {
      setState(() {
        daysError = widget.l10n.daysRequired;
      });
      return;
    }

    final days = int.tryParse(daysText);
    if (days == null || days <= 0) {
      setState(() {
        daysError = widget.l10n.daysInvalid;
      });
      return;
    }

    Navigator.of(context).pop(
      ScheduleNextAppointmentResult(
        daysFromOriginal: days,
        eventTypes: selectedEventTypes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetDate = _calculateTargetDate();

    return AlertDialog(
      title: Text(widget.l10n.scheduleNextAppointment),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Days input field
          TextField(
            controller: daysController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: widget.l10n.daysFromOriginal,
              errorText: daysError,
              suffixText: '天',
            ),
            onChanged: (value) {
              setState(() {
                daysError = null;
              });
            },
          ),
          const SizedBox(height: 16),

          // Event types selection
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.l10n.appointmentType,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Display selected types
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: selectedEventTypes.map((type) {
                        return Chip(
                          label: Text(
                            EventTypeLocalizations.getLocalizedEventType(context, type),
                            style: const TextStyle(fontSize: 12),
                          ),
                          padding: const EdgeInsets.all(2),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 4),
                    // Button to change types
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final result = await showChangeEventTypeDialog(
                            context,
                            widget.originalEvent.copyWith(eventTypes: selectedEventTypes),
                            EventTypeLocalizations.commonEventTypes,
                            EventTypeLocalizations.getLocalizedEventType,
                          );
                          if (result != null) {
                            setState(() {
                              selectedEventTypes = result;
                            });
                          }
                        },
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text('Change Types', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Target date preview
          if (targetDate != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event,
                    size: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.l10n.targetDatePreview(_formatDate(targetDate)),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.l10n.cancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(widget.l10n.confirm),
        ),
      ],
    );
  }
}
