import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/event.dart';
import '../../../models/event_type.dart';
import '../utils/event_type_localizations.dart';

/// Event metadata section with name, record number, type, and time fields
class EventMetadataSection extends StatelessWidget {
  final Event event;
  final Event? newEvent;
  final TextEditingController nameController;
  final String recordNumber;
  final List<String> availableRecordNumbers;
  final bool isRecordNumberFieldEnabled;
  final EventType selectedEventType;
  final DateTime startTime;
  final DateTime? endTime;
  final VoidCallback onStartTimeTap;
  final VoidCallback onEndTimeTap;
  final VoidCallback onClearEndTime;
  final ValueChanged<EventType?> onEventTypeChanged;
  final ValueChanged<String> onRecordNumberChanged;
  final Future<String?> Function() onNewRecordNumberRequested;

  const EventMetadataSection({
    super.key,
    required this.event,
    this.newEvent,
    required this.nameController,
    required this.recordNumber,
    required this.availableRecordNumbers,
    required this.isRecordNumberFieldEnabled,
    required this.selectedEventType,
    required this.startTime,
    this.endTime,
    required this.onStartTimeTap,
    required this.onEndTimeTap,
    required this.onClearEndTime,
    required this.onEventTypeChanged,
    required this.onRecordNumberChanged,
    required this.onNewRecordNumberRequested,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Event status indicators
        if (event.isRemoved || event.hasNewTime) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: event.isRemoved ? Colors.red.shade50 : Colors.orange.shade50,
              border: Border.all(
                color: event.isRemoved ? Colors.red.shade300 : Colors.orange.shade300,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      event.isRemoved ? Icons.remove_circle_outline : Icons.schedule,
                      color: event.isRemoved ? Colors.red.shade700 : Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      event.isRemoved
                          ? (event.hasNewTime ? 'Event Time Changed' : 'Event Removed')
                          : 'Time Changed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: event.isRemoved ? Colors.red.shade700 : Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
                if (event.removalReason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Reason: ${event.removalReason}',
                    style: TextStyle(
                      color: event.isRemoved ? Colors.red.shade600 : Colors.orange.shade600,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (event.hasNewTime && newEvent != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_forward, color: Colors.red.shade700, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Moved to: ${DateFormat('EEEE, MMM d, y - HH:mm', Localizations.localeOf(context).toString()).format(newEvent!.startTime)}',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Name field
        TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: l10n.eventName,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),

        // Record Number dropdown field
        _RecordNumberDropdown(
          value: recordNumber,
          availableRecordNumbers: availableRecordNumbers,
          isEnabled: isRecordNumberFieldEnabled,
          labelText: l10n.recordNumber,
          onChanged: onRecordNumberChanged,
          onNewRecordNumberRequested: onNewRecordNumberRequested,
        ),
        const SizedBox(height: 8),

        // Event Type field with quick selection
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<EventType>(
                value: selectedEventType,
                decoration: InputDecoration(
                  labelText: l10n.eventType,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: EventTypeLocalizations.commonEventTypes.map((type) {
                  return DropdownMenuItem<EventType>(
                    value: type,
                    child: Text(EventTypeLocalizations.getLocalizedEventType(context, type)),
                  );
                }).toList(),
                onChanged: onEventTypeChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Time fields with responsive layout
        LayoutBuilder(
          builder: (context, constraints) {
            final isWideEnough = constraints.maxWidth > 500;

            if (isWideEnough) {
              return Row(
                children: [
                  Expanded(
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        title: Text(l10n.startTime, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          DateFormat('MMM d, y - HH:mm', Localizations.localeOf(context).toString()).format(startTime),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.access_time, size: 18),
                        onTap: onStartTimeTap,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(l10n.endTime, style: const TextStyle(fontSize: 13)),
                            ),
                            if (endTime != null)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 14),
                                onPressed: onClearEndTime,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          endTime != null
                              ? DateFormat('MMM d, y - HH:mm', Localizations.localeOf(context).toString()).format(endTime!)
                              : l10n.openEnded,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.access_time, size: 18),
                        onTap: onEndTimeTap,
                      ),
                    ),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  Card(
                    child: ListTile(
                      title: Text(l10n.startTime),
                      subtitle: Text(DateFormat('MMM d, y - HH:mm', Localizations.localeOf(context).toString()).format(startTime)),
                      trailing: const Icon(Icons.access_time),
                      onTap: onStartTimeTap,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      title: Row(
                        children: [
                          Text(l10n.endTime),
                          if (endTime != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: onClearEndTime,
                            ),
                        ],
                      ),
                      subtitle: Text(endTime != null
                          ? DateFormat('MMM d, y - HH:mm', Localizations.localeOf(context).toString()).format(endTime!)
                          : 'Open-ended'),
                      trailing: const Icon(Icons.access_time),
                      onTap: onEndTimeTap,
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ],
    );
  }
}

/// Private widget for record number dropdown with special options
class _RecordNumberDropdown extends StatelessWidget {
  static const String _emptyOption = '__EMPTY__';
  static const String _newOption = '__NEW__';

  final String value;
  final List<String> availableRecordNumbers;
  final bool isEnabled;
  final String labelText;
  final ValueChanged<String> onChanged;
  final Future<String?> Function() onNewRecordNumberRequested;

  const _RecordNumberDropdown({
    required this.value,
    required this.availableRecordNumbers,
    required this.isEnabled,
    required this.labelText,
    required this.onChanged,
    required this.onNewRecordNumberRequested,
  });

  @override
  Widget build(BuildContext context) {
    // Build dropdown items
    final items = <DropdownMenuItem<String>>[];

    // Add available record numbers
    for (final recordNum in availableRecordNumbers) {
      items.add(DropdownMenuItem<String>(
        value: recordNum,
        child: Text(recordNum),
      ));
    }

    // Add special options
    items.add(const DropdownMenuItem<String>(
      value: _emptyOption,
      child: Text('留空'),
    ));
    items.add(const DropdownMenuItem<String>(
      value: _newOption,
      child: Text('新病例號'),
    ));

    // Determine current value for dropdown
    String dropdownValue;
    if (value.isEmpty) {
      dropdownValue = _emptyOption;
    } else if (availableRecordNumbers.contains(value)) {
      dropdownValue = value;
    } else {
      // User has a custom value not in the list, treat as regular option
      // Add it to the items if not already present
      if (!items.any((item) => item.value == value)) {
        items.insert(0, DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        ));
      }
      dropdownValue = value;
    }

    return DropdownButtonFormField<String>(
      value: dropdownValue,
      decoration: InputDecoration(
        labelText: labelText,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: isEnabled
          ? (String? newValue) async {
              if (newValue == null) return;

              if (newValue == _emptyOption) {
                // User selected "留空"
                onChanged('');
              } else if (newValue == _newOption) {
                // User selected "新病例號", show dialog
                final result = await onNewRecordNumberRequested();
                if (result != null && result.trim().isNotEmpty) {
                  onChanged(result.trim());
                }
              } else {
                // User selected an existing record number
                onChanged(newValue);
              }
            }
          : null,
    );
  }
}
