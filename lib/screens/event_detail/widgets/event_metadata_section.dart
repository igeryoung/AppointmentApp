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
    this.isNameReadOnly = false,
  });

  /// Filter record number options based on current name
  /// If name is not empty, only show record numbers that match the name
  /// If name is empty, show all record numbers
  List<RecordNumberOption> _getFilteredRecordNumberOptions() {
    final currentName = nameController.text.trim();

    // If name is empty, show all record numbers
    if (currentName.isEmpty) {
      return allRecordNumberOptions;
    }

    // If name is not empty, filter by availableRecordNumbers (which are filtered by name)
    // Convert availableRecordNumbers to a Set for O(1) lookup
    final availableSet = availableRecordNumbers.toSet();

    // Filter allRecordNumberOptions to only include those in availableRecordNumbers
    return allRecordNumberOptions
        .where((option) => availableSet.contains(option.recordNumber))
        .toList();
  }

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
                    allRecordNumberOptions: _getFilteredRecordNumberOptions(),
                    isEnabled: true,  // Always enabled for new behavior
                    labelText: l10n.recordNumber,
                    onRecordNumberSelected: onRecordNumberSelected,
                    onRecordNumberCleared: () {
                      onRecordNumberChanged('');
                    },
                    onNewRecordNumberRequested: onNewRecordNumberRequested,
                    focusNode: recordNumberFocusNode,
                    onFocused: onRecordNumberFieldFocused,
                    // Removed onTextChanged callback to fix race condition bug
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
  });

  @override
  State<_RecordNumberAutocomplete> createState() => _RecordNumberAutocompleteState();
}

class _RecordNumberAutocompleteState extends State<_RecordNumberAutocomplete> {
  static const String _emptyOption = '__EMPTY__';
  static const String _newOption = '__NEW__';
  bool _isProcessing = false;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value;
    _focusNode.addListener(_onFocusChanged);
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(_RecordNumberAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Always sync controller with widget value to handle all state changes
    // This fixes the bug where record number disappears after reopening the event
    if (_controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    _removeOverlay();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && widget.isEnabled) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _onTextChanged() {
    if (_focusNode.hasFocus && widget.isEnabled) {
      _updateOverlay();
    }
  }

  List<_RecordNumberOptionItem> _getFilteredOptions() {
    final options = <_RecordNumberOptionItem>[];
    // Always add special options first
    options.add(_RecordNumberOptionItem(displayText: '留空', value: _emptyOption, isSpecial: true));
    options.add(_RecordNumberOptionItem(displayText: '新病例號', value: _newOption, isSpecial: true));

    final query = _controller.text.toLowerCase();
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
        return opt.recordNumber.toLowerCase().contains(query) ||
               opt.name.toLowerCase().contains(query);
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

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        final options = _getFilteredOptions();

        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 5),
            child: Material(
              elevation: 4.0,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    return InkWell(
                      onTap: () async {
                        if (option.value == _emptyOption) {
                          _controller.text = '';
                          if (widget.onRecordNumberCleared != null) {
                            widget.onRecordNumberCleared!();
                          }
                        } else if (option.value == _newOption) {
                          await _handleNewRecordNumber();
                        } else {
                          _controller.text = option.value;
                          if (widget.onRecordNumberSelected != null) {
                            widget.onRecordNumberSelected!(option.value);
                          }
                        }
                        _removeOverlay();
                        _focusNode.unfocus();
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
                            fontWeight: option.isSpecial ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
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
        _controller.text = result.trim();
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

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.isEnabled && !_isProcessing,
        decoration: InputDecoration(
          labelText: widget.labelText,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
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

/// Name field with RawAutocomplete dropdown
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
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && !widget.isReadOnly) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _onTextChanged() {
    if (_focusNode.hasFocus && !widget.isReadOnly) {
      _updateOverlay();
    }
  }

  List<String> _getFilteredOptions() {
    final text = widget.controller.text.toLowerCase();
    if (text.isEmpty) {
      return widget.allNames; // Show all names when empty (user requested)
    }
    return widget.allNames.where((name) => name.toLowerCase().contains(text)).toList();
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        final options = _getFilteredOptions();
        if (options.isEmpty) {
          return const SizedBox.shrink();
        }

        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 5),
            child: Material(
              elevation: 4.0,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    return InkWell(
                      onTap: () {
                        widget.controller.text = option;
                        if (widget.onNameSelected != null) {
                          widget.onNameSelected!(option);
                        }
                        _removeOverlay();
                        _focusNode.unfocus();
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
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
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
      ),
    );
  }
}
