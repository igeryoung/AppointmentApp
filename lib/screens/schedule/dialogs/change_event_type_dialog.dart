import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/event.dart';
import '../../../models/event_type.dart';

/// Show dialog to change event types (multi-select with checkboxes)
Future<List<EventType>?> showChangeEventTypeDialog(
  BuildContext context,
  Event event,
  List<EventType> eventTypes,
  String Function(BuildContext, EventType) getLocalizedEventType,
) async {
  final l10n = AppLocalizations.of(context)!;

  return showDialog<List<EventType>>(
    context: context,
    builder: (context) => _ChangeEventTypeDialog(
      event: event,
      eventTypes: eventTypes,
      getLocalizedEventType: getLocalizedEventType,
      l10n: l10n,
    ),
  );
}

/// Stateful dialog widget for multi-select event type selection
class _ChangeEventTypeDialog extends StatefulWidget {
  final Event event;
  final List<EventType> eventTypes;
  final String Function(BuildContext, EventType) getLocalizedEventType;
  final AppLocalizations l10n;

  const _ChangeEventTypeDialog({
    required this.event,
    required this.eventTypes,
    required this.getLocalizedEventType,
    required this.l10n,
  });

  @override
  State<_ChangeEventTypeDialog> createState() => _ChangeEventTypeDialogState();
}

class _ChangeEventTypeDialogState extends State<_ChangeEventTypeDialog> {
  late Set<EventType> selectedTypes;

  @override
  void initState() {
    super.initState();
    // Initialize with current event types
    selectedTypes = Set<EventType>.from(widget.event.eventTypes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.l10n.changeEventType),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selection count indicator
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              'Selected: ${selectedTypes.length} type${selectedTypes.length != 1 ? 's' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          // Checkbox list
          ...widget.eventTypes.map((type) {
            final isSelected = selectedTypes.contains(type);
            final canDeselect = selectedTypes.length > 1 || !isSelected;

            return CheckboxListTile(
              title: Text(widget.getLocalizedEventType(context, type)),
              value: isSelected,
              onChanged: canDeselect
                  ? (checked) {
                      setState(() {
                        if (checked == true) {
                          selectedTypes.add(type);
                        } else if (selectedTypes.length > 1) {
                          selectedTypes.remove(type);
                        }
                      });
                    }
                  : null, // Disable if it's the last selected item
            );
          }).toList(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.l10n.cancel),
        ),
        TextButton(
          onPressed: selectedTypes.isNotEmpty
              ? () {
                  // Sort alphabetically before returning
                  final sorted = EventType.sortAlphabetically(selectedTypes.toList());
                  Navigator.pop(context, sorted);
                }
              : null,
          child: const Text('OK'),
        ),
      ],
    );
  }
}
