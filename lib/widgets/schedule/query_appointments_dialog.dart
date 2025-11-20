import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/event.dart';
import '../../repositories/event_repository.dart';
import '../../screens/event_detail/utils/event_type_localizations.dart';

/// Show dialog to query appointments by name and record number
Future<void> showQueryAppointmentsDialog(
  BuildContext context,
  int bookId,
  IEventRepository eventRepository,
) async {
  await showDialog(
    context: context,
    builder: (context) => _QueryAppointmentsDialog(
      bookId: bookId,
      eventRepository: eventRepository,
    ),
  );
}

class _QueryAppointmentsDialog extends StatefulWidget {
  final int bookId;
  final IEventRepository eventRepository;

  const _QueryAppointmentsDialog({
    required this.bookId,
    required this.eventRepository,
  });

  @override
  State<_QueryAppointmentsDialog> createState() => _QueryAppointmentsDialogState();
}

class _QueryAppointmentsDialogState extends State<_QueryAppointmentsDialog> {
  late TextEditingController nameController;
  Timer? _debounceTimer;
  String? selectedRecordNumber;
  List<String> allNames = [];
  List<NameRecordPair> allNameRecordPairs = [];
  List<NameRecordPair> filteredNameRecordPairs = [];
  List<Event> searchResults = [];
  bool isLoading = false;
  bool hasSearched = false;
  bool _isProgrammaticNameChange = false; // Flag to prevent race condition
  String? nameError;
  String? recordNumberError;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    _loadAllNames();
    _loadAllNameRecordPairs();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    nameController.dispose();
    super.dispose();
  }

  /// Load all available names for autocomplete
  Future<void> _loadAllNames() async {
    try {
      final names = await widget.eventRepository.getAllNames(widget.bookId);
      setState(() {
        allNames = names;
      });
    } catch (e) {
      // Silently fail - allNames will remain empty
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorLoadingData)),
        );
      }
    }
  }

  /// Load all available name-record pairs for dropdown
  Future<void> _loadAllNameRecordPairs() async {
    try {
      final pairs = await widget.eventRepository.getAllNameRecordPairs(widget.bookId);
      setState(() {
        allNameRecordPairs = pairs;
        filteredNameRecordPairs = pairs; // Initially show all pairs
      });
    } catch (e) {
      // Silently fail - allNameRecordPairs will remain empty
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorLoadingData)),
        );
      }
    }
  }

  /// Filter name-record pairs based on entered name (case-insensitive partial match)
  void _filterNameRecordPairsByName() {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      // Empty name - show all pairs
      setState(() {
        filteredNameRecordPairs = allNameRecordPairs;
        selectedRecordNumber = null;
      });
      return;
    }

    // Filter pairs where name matches (case-insensitive, partial match)
    final filtered = allNameRecordPairs
        .where((pair) => pair.name.toLowerCase().contains(name.toLowerCase()))
        .toList();

    setState(() {
      filteredNameRecordPairs = filtered;
      selectedRecordNumber = null; // Clear selection when name changes
    });
  }

  /// Validate and perform search
  Future<void> _performSearch() async {
    final l10n = AppLocalizations.of(context)!;

    // Reset errors
    setState(() {
      nameError = null;
      recordNumberError = null;
    });

    // Validate name
    final name = nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        nameError = l10n.nameRequired;
      });
      return;
    }

    // Validate record number
    if (selectedRecordNumber == null) {
      setState(() {
        recordNumberError = l10n.recordNumberRequired;
      });
      return;
    }

    // Perform search
    setState(() {
      isLoading = true;
      hasSearched = false;
    });

    try {
      final results = await widget.eventRepository.searchByNameAndRecordNumber(
        widget.bookId,
        name,
        selectedRecordNumber!,
      );

      setState(() {
        searchResults = results;
        isLoading = false;
        hasSearched = true;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        hasSearched = true;
        searchResults = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorSearching)),
        );
      }
    }
  }

  /// Format date time for display
  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  /// Check if search button should be enabled
  bool get _canSearch => nameController.text.trim().isNotEmpty && selectedRecordNumber != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 1050),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            AppBar(
              title: Text(l10n.queryAppointments),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            // Input fields and search button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Name autocomplete field
                  _NameAutocompleteField(
                    controller: nameController,
                    labelText: l10n.eventName,
                    allNames: allNames,
                    errorText: nameError,
                    onNameSelected: (name) {
                      setState(() {
                        nameError = null;
                        selectedRecordNumber = null;
                      });
                      _filterNameRecordPairsByName();
                    },
                    onChanged: (value) {
                      // Skip if this is a programmatic change from record selection
                      if (_isProgrammaticNameChange) {
                        return;
                      }

                      setState(() {
                        nameError = null;
                        selectedRecordNumber = null;
                      });

                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                        _filterNameRecordPairsByName();
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Record number dropdown with name-record pairs
                  DropdownMenu<String>(
                    initialSelection: selectedRecordNumber,
                    label: Text(l10n.recordNumber),
                    hintText: filteredNameRecordPairs.isEmpty
                        ? l10n.noMatchingRecordNumbers
                        : l10n.selectRecordNumber,
                    expandedInsets: EdgeInsets.zero,
                    menuHeight: 300,
                    errorText: recordNumberError,
                    inputDecorationTheme: const InputDecorationTheme(
                      border: OutlineInputBorder(),
                    ),
                    dropdownMenuEntries: filteredNameRecordPairs.map((pair) {
                      return DropdownMenuEntry<String>(
                        value: pair.recordNumber,
                        label: pair.displayText, // Format: [name] - [record number]
                      );
                    }).toList(),
                    onSelected: (String? newValue) {
                      if (newValue != null) {
                        // Find the corresponding pair to extract the name
                        final selectedPair = filteredNameRecordPairs.firstWhere(
                          (pair) => pair.recordNumber == newValue,
                        );

                        // Set flag to prevent onChanged from clearing selection
                        _isProgrammaticNameChange = true;

                        // Auto-fill name field
                        nameController.text = selectedPair.name;

                        setState(() {
                          selectedRecordNumber = newValue;
                          recordNumberError = null;
                          nameError = null;
                        });

                        // Reset flag after state update
                        _isProgrammaticNameChange = false;
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Search button
                  FilledButton.icon(
                    onPressed: _canSearch && !isLoading ? _performSearch : null,
                    icon: isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(l10n.search),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Results list
            Expanded(
              child: _buildResultsList(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(AppLocalizations l10n) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              l10n.enterSearchCriteria,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              l10n.noAppointmentsFound,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: searchResults.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final event = searchResults[index];
        return _buildResultItem(event);
      },
    );
  }

  Widget _buildResultItem(Event event) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Record number
            Row(
              children: [
                Icon(Icons.badge, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  '${l10n.recordNumber}: ${event.recordNumber ?? '-'}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Start time
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  '${l10n.startTime}: ${_formatDateTime(event.startTime)}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // End time
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  '${l10n.endTime}: ${event.endTime != null ? _formatDateTime(event.endTime!) : l10n.openEnded}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Event types
            Row(
              children: [
                Icon(Icons.category, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${l10n.appointmentType}: ${event.eventTypes.map((t) => EventTypeLocalizations.getLocalizedEventType(context, t)).join(', ')}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Name autocomplete field with dropdown overlay
class _NameAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final List<String> allNames;
  final String? errorText;
  final ValueChanged<String>? onNameSelected;
  final ValueChanged<String>? onChanged;

  const _NameAutocompleteField({
    required this.controller,
    required this.labelText,
    required this.allNames,
    this.errorText,
    this.onNameSelected,
    this.onChanged,
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
    if (_focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _onTextChanged() {
    if (_focusNode.hasFocus) {
      _updateOverlay();
    }
    widget.onChanged?.call(widget.controller.text);
  }

  List<String> _getFilteredOptions() {
    final text = widget.controller.text.toLowerCase();
    if (text.isEmpty) {
      return widget.allNames;
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
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    return InkWell(
                      onTap: () {
                        widget.controller.text = option;
                        widget.onNameSelected?.call(option);
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
        decoration: InputDecoration(
          labelText: widget.labelText,
          errorText: widget.errorText,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }
}
