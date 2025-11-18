import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/event.dart';
import '../../../models/event_type.dart';
import '../utils/event_type_localizations.dart';
import '../../schedule/dialogs/change_event_type_dialog.dart';
import '../event_detail_controller.dart';

/// Event metadata section with name, record number, type, and time fields
class EventMetadataSection extends StatelessWidget {
  final Event event;
  final Event? newEvent;
  final TextEditingController nameController;
  final TextEditingController phoneController;
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

  // New parameters for autocomplete functionality
  final FocusNode? nameFocusNode;
  final FocusNode? recordNumberFocusNode;
  final List<String> allNames;
  final List<RecordNumberOption> allRecordNumberOptions;
  final VoidCallback? onNameFieldFocused;
  final VoidCallback? onRecordNumberFieldFocused;
  final ValueChanged<String>? onNameSelected;
  final ValueChanged<String>? onRecordNumberSelected;
  final ValueChanged<String>? onRecordNumberTextChanged;  // When record number text changes (for clearing name)
  final bool isNameReadOnly;

  const EventMetadataSection({
    super.key,
    required this.event,
    this.newEvent,
    required this.nameController,
    required this.phoneController,
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
    // Autocomplete parameters
    this.nameFocusNode,
    this.recordNumberFocusNode,
    this.allNames = const [],
    this.allRecordNumberOptions = const [],
    this.onNameFieldFocused,
    this.onRecordNumberFieldFocused,
    this.onNameSelected,
    this.onRecordNumberSelected,
    this.onRecordNumberTextChanged,
    this.isNameReadOnly = false,
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

        // Two-column layout for name/recordNumber and phone/eventType
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left column: Name and Phone
            Expanded(
              child: Column(
                children: [
                  // Name field with autocomplete
                  _NameAutocompleteField(
                    controller: nameController,
                    labelText: l10n.eventName,
                    allNames: allNames,
                    isReadOnly: isNameReadOnly,
                    onNameSelected: onNameSelected,
                  ),
                  const SizedBox(height: 8),
                  // Phone field
                  TextField(
                    controller: phoneController,
                    decoration: InputDecoration(
                      labelText: l10n.phone,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Right column: Record Number and Event Type
            Expanded(
              child: Column(
                children: [
                  // Record Number autocomplete field
                  _RecordNumberAutocomplete(
                    value: recordNumber,
                    allRecordNumberOptions: allRecordNumberOptions,
                    isEnabled: true,  // Always enabled for new behavior
                    labelText: l10n.recordNumber,
                    onRecordNumberSelected: onRecordNumberSelected,
                    onRecordNumberCleared: () {
                      onRecordNumberChanged('');
                    },
                    onNewRecordNumberRequested: onNewRecordNumberRequested,
                    focusNode: recordNumberFocusNode,
                    onFocused: onRecordNumberFieldFocused,
                    onTextChanged: onRecordNumberTextChanged,  // Callback when user types to clear name
                  ),
                  const SizedBox(height: 8),
                  // Event Type field
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
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.eventType,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        _buildEventTypeDisplayText(context, selectedEventTypes),
                        style: const TextStyle(fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

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
                            if (endTime != null) ...[
                              const SizedBox(width: 4),
                              _buildClearEndTimeButton(onClearEndTime),
                            ],
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
                          if (endTime != null) ...[
                            const SizedBox(width: 4),
                            _buildClearEndTimeButton(onClearEndTime),
                          ],
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

  /// Build display text for event types with overflow handling
  /// Shows "Type1, Type2, +N more" format when there are too many types
  String _buildEventTypeDisplayText(BuildContext context, List<EventType> types) {
    if (types.isEmpty) {
      return '';
    }

    // Get localized names
    final typeNames = types
        .map((type) => EventTypeLocalizations.getLocalizedEventType(context, type))
        .toList();

    // If only 1-2 types, show all
    if (typeNames.length <= 2) {
      return typeNames.join(', ');
    }

    // If 3 types, try to show all, but check length
    if (typeNames.length == 3) {
      final fullText = typeNames.join(', ');
      // Roughly estimate if it fits (assuming ~10 chars per type on average)
      if (fullText.length <= 30) {
        return fullText;
      }
    }

    // Show first 2 types and "+N more"
    final remaining = typeNames.length - 2;
    return '${typeNames[0]}, ${typeNames[1]}, +$remaining more';
  }

  /// Compact clear button used inside the end time rows so the tile height
  /// remains stable when the optional action is shown.
  Widget _buildClearEndTimeButton(VoidCallback onClearEndTime) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onClearEndTime,
          child: const Center(
            child: Icon(Icons.clear, size: 16),
          ),
        ),
      ),
    );
  }
}

/// Record number autocomplete widget with "留空" and "新病例號" options
class _RecordNumberAutocomplete extends StatefulWidget {
  final String value;
  final List<RecordNumberOption> allRecordNumberOptions;
  final bool isEnabled;
  final String labelText;
  final ValueChanged<String>? onRecordNumberSelected;
  final VoidCallback? onRecordNumberCleared;
  final Future<String?> Function() onNewRecordNumberRequested;
  final FocusNode? focusNode;
  final VoidCallback? onFocused;
  final ValueChanged<String>? onTextChanged;  // New callback for when text changes

  const _RecordNumberAutocomplete({
    required this.value,
    required this.allRecordNumberOptions,
    required this.isEnabled,
    required this.labelText,
    this.onRecordNumberSelected,
    this.onRecordNumberCleared,
    required this.onNewRecordNumberRequested,
    this.focusNode,
    this.onFocused,
    this.onTextChanged,
  });

  @override
  State<_RecordNumberAutocomplete> createState() => _RecordNumberAutocompleteState();
}

class _RecordNumberAutocompleteState extends State<_RecordNumberAutocomplete> {
  static const String _emptyOption = '__EMPTY__';
  static const String _newOption = '__NEW__';
  bool _isProcessing = false;
  final TextEditingController _internalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _internalController.text = widget.value;
  }

  @override
  void didUpdateWidget(_RecordNumberAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update internal controller when external value changes
    if (widget.value != oldWidget.value && _internalController.text != widget.value) {
      _internalController.text = widget.value;
    }
  }

  @override
  void dispose() {
    _internalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build the combined options list
    List<_RecordNumberOptionItem> buildOptions(String query) {
      final options = <_RecordNumberOptionItem>[];

      // Always add special options first
      options.add(_RecordNumberOptionItem(displayText: '留空', value: _emptyOption, isSpecial: true));
      options.add(_RecordNumberOptionItem(displayText: '新病例號', value: _newOption, isSpecial: true));

      // Add filtered record numbers
      if (query.isEmpty) {
        options.addAll(widget.allRecordNumberOptions.map((opt) =>
          _RecordNumberOptionItem(
            displayText: opt.displayText,
            value: opt.recordNumber,
            isSpecial: false,
          )
        ));
      } else {
        final filtered = widget.allRecordNumberOptions.where((opt) {
          return opt.recordNumber.toLowerCase().contains(query.toLowerCase()) ||
                 opt.name.toLowerCase().contains(query.toLowerCase());
        });
        options.addAll(filtered.map((opt) =>
          _RecordNumberOptionItem(
            displayText: opt.displayText,
            value: opt.recordNumber,
            isSpecial: false,
          )
        ));
      }

      return options;
    }

    return Autocomplete<_RecordNumberOptionItem>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        return buildOptions(textEditingValue.text);
      },
      displayStringForOption: (_RecordNumberOptionItem option) {
        if (option.isSpecial) return option.displayText;
        return option.value;  // Show just the number in the text field
      },
      onSelected: (_RecordNumberOptionItem selection) async {
        if (selection.value == _emptyOption) {
          if (widget.onRecordNumberCleared != null) {
            widget.onRecordNumberCleared!();
          }
        } else if (selection.value == _newOption) {
          await _handleNewRecordNumber();
        } else {
          if (widget.onRecordNumberSelected != null) {
            widget.onRecordNumberSelected!(selection.value);
          }
        }
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        // Sync internal controller to autocomplete's controller
        textEditingController.text = _internalController.text;

        // Keep them in sync
        textEditingController.addListener(() {
          if (_internalController.text != textEditingController.text) {
            _internalController.text = textEditingController.text;
            if (widget.onTextChanged != null) {
              widget.onTextChanged!(textEditingController.text);
            }
          }
        });

        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          enabled: widget.isEnabled && !_isProcessing,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250, maxWidth: 300),
              child: ListView.builder(
                padding: const EdgeInsets.all(8.0),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final option = options.elementAt(index);

                  return InkWell(
                    onTap: () {
                      onSelected(option);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.shade200,
                            width: 1.0,
                          ),
                        ),
                      ),
                      child: Text(
                        option.displayText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: option.isSpecial
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
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
        if (widget.onRecordNumberSelected != null) {
          widget.onRecordNumberSelected!(result.trim());
        }
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

/// Helper class for record number dropdown items
class _RecordNumberOptionItem {
  final String displayText;
  final String value;
  final bool isSpecial;

  _RecordNumberOptionItem({
    required this.displayText,
    required this.value,
    required this.isSpecial,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _RecordNumberOptionItem &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Name field with simple autocomplete dropdown
class _NameAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final List<String> allNames;
  final bool isReadOnly;
  final ValueChanged<String>? onNameSelected;

  const _NameAutocompleteField({
    required this.controller,
    required this.labelText,
    required this.allNames,
    required this.isReadOnly,
    this.onNameSelected,
  });

  @override
  State<_NameAutocompleteField> createState() => _NameAutocompleteFieldState();
}

class _NameAutocompleteFieldState extends State<_NameAutocompleteField> {
  final TextEditingController _internalController = TextEditingController();
  bool _isInternalUpdate = false;

  @override
  void initState() {
    super.initState();
    _internalController.text = widget.controller.text;

    // Listen to external controller changes (e.g., from record number selection)
    widget.controller.addListener(_onExternalControllerChanged);

    // Listen to internal controller changes (user typing)
    _internalController.addListener(_onInternalControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalControllerChanged);
    _internalController.dispose();
    super.dispose();
  }

  void _onExternalControllerChanged() {
    if (!_isInternalUpdate && _internalController.text != widget.controller.text) {
      _internalController.text = widget.controller.text;
    }
  }

  void _onInternalControllerChanged() {
    _isInternalUpdate = true;
    if (widget.controller.text != _internalController.text) {
      widget.controller.text = _internalController.text;
    }
    _isInternalUpdate = false;
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.trim().isEmpty) {
          return const Iterable<String>.empty();
        }
        final matches = widget.allNames.where((String option) {
          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
        });
        return matches;
      },
      onSelected: (String selection) {
        if (widget.onNameSelected != null) {
          widget.onNameSelected!(selection);
        }
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        // Sync internal controller to autocomplete's controller
        textEditingController.text = _internalController.text;

        // Keep them in sync
        textEditingController.addListener(() {
          if (_internalController.text != textEditingController.text) {
            _internalController.text = textEditingController.text;
          }
        });

        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          readOnly: widget.isReadOnly,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            suffixIcon: widget.isReadOnly
                ? const Icon(Icons.lock_outline, size: 18)
                : null,
            filled: widget.isReadOnly,
            fillColor: widget.isReadOnly ? Colors.grey.shade100 : null,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
              child: ListView.builder(
                padding: const EdgeInsets.all(8.0),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final String option = options.elementAt(index);
                  return InkWell(
                    onTap: () {
                      onSelected(option);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.shade200,
                            width: 1.0,
                          ),
                        ),
                      ),
                      child: Text(option),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
