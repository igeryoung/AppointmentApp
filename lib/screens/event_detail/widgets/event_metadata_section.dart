import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/event.dart';
import '../../../models/event_type.dart';
import '../utils/event_type_localizations.dart';
import '../../schedule/dialogs/change_event_type_dialog.dart';

/// Event metadata section with name, record number, type, and time fields
class EventMetadataSection extends StatelessWidget {
  final Event event;
  final Event? newEvent;
  final TextEditingController nameController;
  final String recordNumber;
  final List<String> availableRecordNumbers;
  final bool isRecordNumberFieldEnabled;
  final List<EventType> selectedEventTypes;
  final DateTime startTime;
  final DateTime? endTime;
  final VoidCallback onStartTimeTap;
  final VoidCallback onEndTimeTap;
  final VoidCallback onClearEndTime;
  final ValueChanged<List<EventType>> onEventTypesChanged;
  final ValueChanged<String> onRecordNumberChanged;
  final Future<String?> Function() onNewRecordNumberRequested;
  final Color Function(BuildContext, EventType)? getEventTypeColor;

  const EventMetadataSection({
    super.key,
    required this.event,
    this.newEvent,
    required this.nameController,
    required this.recordNumber,
    required this.availableRecordNumbers,
    required this.isRecordNumberFieldEnabled,
    required this.selectedEventTypes,
    required this.startTime,
    this.endTime,
    required this.onStartTimeTap,
    required this.onEndTimeTap,
    required this.onClearEndTime,
    required this.onEventTypesChanged,
    required this.onRecordNumberChanged,
    required this.onNewRecordNumberRequested,
    this.getEventTypeColor,
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
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _RecordNumberDropdown(
            value: recordNumber,
            availableRecordNumbers: availableRecordNumbers,
            isEnabled: isRecordNumberFieldEnabled,
            labelText: l10n.recordNumber,
            onChanged: onRecordNumberChanged,
            onNewRecordNumberRequested: onNewRecordNumberRequested,
          ),
        ),
        const SizedBox(height: 8),

        // Event Type field with inline chips and (+) button
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                l10n.eventType,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Display selected types as chips
                  ...selectedEventTypes.map((type) {
                    // Get color for this type if callback is provided
                    final chipColor = getEventTypeColor != null
                        ? getEventTypeColor!(context, type).withOpacity(0.3)
                        : Theme.of(context).colorScheme.primaryContainer;

                    return Chip(
                      label: Text(
                        EventTypeLocalizations.getLocalizedEventType(context, type),
                        style: const TextStyle(fontSize: 13),
                      ),
                      backgroundColor: chipColor,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                  // (+) button to add/change types
                  InkWell(
                    onTap: () async {
                      final result = await showChangeEventTypeDialog(
                        context,
                        event.copyWith(eventTypes: selectedEventTypes),
                        EventTypeLocalizations.commonEventTypes,
                        EventTypeLocalizations.getLocalizedEventType,
                      );
                      if (result != null) {
                        onEventTypesChanged(result);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 18,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
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
class _RecordNumberDropdown extends StatefulWidget {
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
  State<_RecordNumberDropdown> createState() => _RecordNumberDropdownState();
}

class _RecordNumberDropdownState extends State<_RecordNumberDropdown> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    // Build popup menu items
    final items = <PopupMenuItem<String>>[];

    // Add available record numbers
    for (final recordNum in widget.availableRecordNumbers) {
      items.add(PopupMenuItem<String>(
        value: recordNum,
        child: Text(recordNum),
      ));
    }

    // Add special options
    items.add(PopupMenuItem<String>(
      value: _RecordNumberDropdown._emptyOption,
      child: Text('留空'),
    ));
    items.add(PopupMenuItem<String>(
      value: _RecordNumberDropdown._newOption,
      child: Text('新病例號'),
    ));

    // Determine display text
    String displayText;
    if (widget.value.isEmpty) {
      displayText = '留空';
    } else {
      displayText = widget.value;
    }

    // Add custom value to items if not in list
    if (widget.value.isNotEmpty && !widget.availableRecordNumbers.contains(widget.value)) {
      if (!items.any((item) => item.value == widget.value)) {
        items.insert(0, PopupMenuItem<String>(
          value: widget.value,
          child: Text(widget.value),
        ));
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return PopupMenuButton<String>(
          position: PopupMenuPosition.under,
          offset: Offset(constraints.maxWidth - 200, 0),
          elevation: 16,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          constraints: const BoxConstraints(maxHeight: 300, minWidth: 200, maxWidth: 200),
          enabled: widget.isEnabled && !_isProcessing,
          onSelected: (String newValue) {
            if (newValue == _RecordNumberDropdown._emptyOption) {
              // User selected "留空"
              widget.onChanged('');
            } else if (newValue == _RecordNumberDropdown._newOption) {
              // User selected "新病例號", show dialog
              _handleNewRecordNumber();
            } else {
              // User selected an existing record number
              widget.onChanged(newValue);
            }
          },
          itemBuilder: (context) => items,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: widget.labelText,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              suffixIcon: const Icon(Icons.arrow_drop_down),
              enabled: widget.isEnabled && !_isProcessing,
            ),
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 16,
                color: widget.isEnabled && !_isProcessing ? null : Colors.grey,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleNewRecordNumber() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await widget.onNewRecordNumberRequested();
      if (result != null && result.trim().isNotEmpty && mounted) {
        widget.onChanged(result.trim());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
}
