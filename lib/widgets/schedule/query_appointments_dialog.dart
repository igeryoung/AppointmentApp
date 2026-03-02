import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/event.dart';
import '../../repositories/event_repository.dart';
import '../../screens/event_detail/utils/event_type_localizations.dart';

/// Show dialog to query appointments by name and record number
Future<void> showQueryAppointmentsDialog(
  BuildContext context,
  String bookUuid,
  IEventRepository eventRepository,
) async {
  await showDialog(
    context: context,
    builder: (context) => _QueryAppointmentsDialog(
      bookUuid: bookUuid,
      eventRepository: eventRepository,
    ),
  );
}

class _QueryAppointmentsDialog extends StatefulWidget {
  final String bookUuid;
  final IEventRepository eventRepository;

  const _QueryAppointmentsDialog({
    required this.bookUuid,
    required this.eventRepository,
  });

  @override
  State<_QueryAppointmentsDialog> createState() =>
      _QueryAppointmentsDialogState();
}

class _QueryAppointmentsDialogState extends State<_QueryAppointmentsDialog> {
  late TextEditingController nameController;
  late TextEditingController recordNumberController;
  String? selectedRecordNumber;
  List<String> nameSuggestions = [];
  List<String> _cachedNameSuggestions = [];
  String? _nameFetchPrefix;
  bool isNameSuggestionsLoading = false;
  List<NameRecordPair> recordSuggestions = [];
  List<NameRecordPair> _cachedRecordSuggestions = [];
  String? _recordFetchPrefix;
  String? _recordNameConstraint;
  bool isRecordSuggestionsLoading = false;
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
    recordNumberController = TextEditingController();
  }

  @override
  void dispose() {
    nameController.dispose();
    recordNumberController.dispose();
    super.dispose();
  }

  String _normalize(String value) => value.trim().toLowerCase();

  void _clearNameSuggestionState() {
    setState(() {
      nameSuggestions = [];
      _cachedNameSuggestions = [];
      _nameFetchPrefix = null;
      isNameSuggestionsLoading = false;
    });
  }

  void _clearRecordSuggestionState({bool clearInput = false}) {
    setState(() {
      selectedRecordNumber = null;
      recordSuggestions = [];
      _cachedRecordSuggestions = [];
      _recordFetchPrefix = null;
      _recordNameConstraint = null;
      isRecordSuggestionsLoading = false;
      if (clearInput) {
        recordNumberController.clear();
      }
    });
  }

  List<String> _filterNameSuggestions(List<String> suggestions, String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    return suggestions
        .where((name) => _normalize(name).startsWith(normalizedQuery))
        .toList();
  }

  List<NameRecordPair> _filterRecordSuggestions(
    List<NameRecordPair> suggestions,
    String query, {
    String? nameConstraint,
  }) {
    final normalizedQuery = _normalize(query);
    final normalizedNameConstraint = nameConstraint == null
        ? null
        : _normalize(nameConstraint);
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    return suggestions.where((pair) {
      if (!_normalize(pair.recordNumber).startsWith(normalizedQuery)) {
        return false;
      }
      if (normalizedNameConstraint != null &&
          normalizedNameConstraint.isNotEmpty) {
        return _normalize(pair.name).startsWith(normalizedNameConstraint);
      }
      return true;
    }).toList();
  }

  Future<void> _fetchNameSuggestions({
    required String fetchPrefix,
    required String activeQuery,
  }) async {
    setState(() {
      isNameSuggestionsLoading = true;
      nameSuggestions = [];
    });

    try {
      final suggestions = await widget.eventRepository.fetchNameSuggestions(
        widget.bookUuid,
        fetchPrefix,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _nameFetchPrefix = fetchPrefix;
        _cachedNameSuggestions = suggestions;
        nameSuggestions = _filterNameSuggestions(suggestions, activeQuery);
        isNameSuggestionsLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _nameFetchPrefix = null;
        _cachedNameSuggestions = [];
        nameSuggestions = [];
        isNameSuggestionsLoading = false;
      });

      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.errorLoadingData)));
    }
  }

  Future<void> _fetchRecordSuggestions({
    required String fetchPrefix,
    required String activeQuery,
    String? nameConstraint,
  }) async {
    setState(() {
      isRecordSuggestionsLoading = true;
      recordSuggestions = [];
    });

    try {
      final suggestions = await widget.eventRepository
          .fetchRecordNumberSuggestions(
            widget.bookUuid,
            fetchPrefix,
            namePrefix: nameConstraint,
          );
      if (!mounted) {
        return;
      }

      setState(() {
        _recordFetchPrefix = fetchPrefix;
        _recordNameConstraint = nameConstraint == null
            ? null
            : _normalize(nameConstraint);
        _cachedRecordSuggestions = suggestions;
        recordSuggestions = _filterRecordSuggestions(
          suggestions,
          activeQuery,
          nameConstraint: nameConstraint,
        );
        isRecordSuggestionsLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _recordFetchPrefix = null;
        _recordNameConstraint = null;
        _cachedRecordSuggestions = [];
        recordSuggestions = [];
        isRecordSuggestionsLoading = false;
      });

      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.errorLoadingData)));
    }
  }

  Future<void> _handleNameChanged(String value) async {
    if (_isProgrammaticNameChange) {
      return;
    }

    final normalized = _normalize(value);
    final previousRecordText = recordNumberController.text;

    setState(() {
      nameError = null;
    });

    if (previousRecordText.isNotEmpty || selectedRecordNumber != null) {
      _clearRecordSuggestionState(clearInput: previousRecordText.isNotEmpty);
    } else {
      _clearRecordSuggestionState();
    }

    if (normalized.isEmpty) {
      _clearNameSuggestionState();
      return;
    }

    final fetchPrefix = normalized[0];
    final shouldFetch =
        _nameFetchPrefix != fetchPrefix || _cachedNameSuggestions.isEmpty;
    if (shouldFetch) {
      await _fetchNameSuggestions(
        fetchPrefix: fetchPrefix,
        activeQuery: normalized,
      );
      return;
    }

    setState(() {
      nameSuggestions = _filterNameSuggestions(
        _cachedNameSuggestions,
        normalized,
      );
    });
  }

  Future<void> _handleRecordNumberChanged(String value) async {
    final normalized = _normalize(value);
    final nameConstraint = _normalize(nameController.text);

    setState(() {
      recordNumberError = null;
      selectedRecordNumber = null;
    });

    if (normalized.isEmpty) {
      _clearRecordSuggestionState();
      return;
    }

    final fetchPrefix = normalized[0];
    final shouldFetch =
        _recordFetchPrefix != fetchPrefix ||
        _cachedRecordSuggestions.isEmpty ||
        (_recordNameConstraint ?? '') != nameConstraint;
    if (shouldFetch) {
      await _fetchRecordSuggestions(
        fetchPrefix: fetchPrefix,
        activeQuery: normalized,
        nameConstraint: nameConstraint.isEmpty ? null : nameConstraint,
      );
      return;
    }

    setState(() {
      recordSuggestions = _filterRecordSuggestions(
        _cachedRecordSuggestions,
        normalized,
        nameConstraint: nameConstraint,
      );
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
        widget.bookUuid,
        name,
        selectedRecordNumber!,
      );
      final normalizedName = name.toLowerCase();
      final normalizedRecordNumber = selectedRecordNumber!.trim().toLowerCase();
      final filteredResults =
          results
              .where(
                (event) =>
                    event.title.trim().toLowerCase().contains(normalizedName) &&
                    event.recordNumber.trim().toLowerCase() ==
                        normalizedRecordNumber,
              )
              .toList()
            ..sort((a, b) => b.startTime.compareTo(a.startTime));

      setState(() {
        searchResults = filteredResults;
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.errorSearching)));
      }
    }
  }

  /// Format date time for display
  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  /// Check if search button should be enabled
  bool get _canSearch =>
      nameController.text.trim().isNotEmpty && selectedRecordNumber != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.0)),
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
                    allNames: nameSuggestions,
                    errorText: nameError,
                    isLoading: isNameSuggestionsLoading,
                    onNameSelected: (name) {
                      setState(() {
                        nameError = null;
                        nameSuggestions = _filterNameSuggestions([name], name);
                      });
                      _clearRecordSuggestionState(clearInput: true);
                    },
                    onChanged: (value) {
                      _handleNameChanged(value);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Record number autocomplete field with name-record pairs
                  _RecordNumberAutocompleteField(
                    controller: recordNumberController,
                    labelText: l10n.recordNumber,
                    allNameRecordPairs: recordSuggestions,
                    errorText: recordNumberError,
                    isLoading: isRecordSuggestionsLoading,
                    onRecordSelected: (pair) {
                      // Set flag to prevent onChanged from clearing selection
                      _isProgrammaticNameChange = true;

                      // Auto-fill name field
                      nameController.text = pair.name;

                      setState(() {
                        selectedRecordNumber = pair.recordNumber;
                        recordNumberError = null;
                        nameError = null;
                      });

                      // Reset flag after state update
                      _isProgrammaticNameChange = false;
                    },
                    onChanged: (value) {
                      _handleRecordNumberChanged(value);
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
            Expanded(child: _buildResultsList(l10n)),
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
                    event.title,
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
                  '${l10n.recordNumber}: ${event.recordNumber.isEmpty ? '-' : event.recordNumber}',
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
  final bool isLoading;
  final ValueChanged<String>? onNameSelected;
  final ValueChanged<String>? onChanged;

  const _NameAutocompleteField({
    required this.controller,
    required this.labelText,
    required this.allNames,
    this.errorText,
    this.isLoading = false,
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
  void didUpdateWidget(covariant _NameAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus &&
        !listEquals(oldWidget.allNames, widget.allNames)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusNode.hasFocus) {
          return;
        }
        _updateOverlay();
      });
    }
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
      return const [];
    }
    return widget.allNames
        .where((name) => name.toLowerCase().startsWith(text))
        .toList();
  }

  void _showOverlay() {
    if (_getFilteredOptions().isEmpty) {
      _removeOverlay();
      return;
    }
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateOverlay() {
    final hasOptions = _getFilteredOptions().isNotEmpty;
    if (!hasOptions) {
      _removeOverlay();
      return;
    }

    if (_overlayEntry == null) {
      _showOverlay();
      return;
    }

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
                        padding: const EdgeInsets.symmetric(
                          vertical: 10.0,
                          horizontal: 12.0,
                        ),
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          suffixIcon: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// Record number autocomplete field with name-record pairs
class _RecordNumberAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final List<NameRecordPair> allNameRecordPairs;
  final String? errorText;
  final bool isLoading;
  final ValueChanged<NameRecordPair>? onRecordSelected;
  final ValueChanged<String>? onChanged;

  const _RecordNumberAutocompleteField({
    required this.controller,
    required this.labelText,
    required this.allNameRecordPairs,
    this.errorText,
    this.isLoading = false,
    this.onRecordSelected,
    this.onChanged,
  });

  @override
  State<_RecordNumberAutocompleteField> createState() =>
      _RecordNumberAutocompleteFieldState();
}

class _RecordNumberAutocompleteFieldState
    extends State<_RecordNumberAutocompleteField> {
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
  void didUpdateWidget(covariant _RecordNumberAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus &&
        !listEquals(oldWidget.allNameRecordPairs, widget.allNameRecordPairs)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusNode.hasFocus) {
          return;
        }
        _updateOverlay();
      });
    }
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

  List<NameRecordPair> _getFilteredOptions() {
    final text = widget.controller.text.toLowerCase();
    if (text.isEmpty) {
      return const [];
    }
    // Filter by record number
    return widget.allNameRecordPairs
        .where((pair) => pair.recordNumber.toLowerCase().startsWith(text))
        .toList();
  }

  void _showOverlay() {
    if (_getFilteredOptions().isEmpty) {
      _removeOverlay();
      return;
    }
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateOverlay() {
    final hasOptions = _getFilteredOptions().isNotEmpty;
    if (!hasOptions) {
      _removeOverlay();
      return;
    }

    if (_overlayEntry == null) {
      _showOverlay();
      return;
    }

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
                    final pair = options[index];
                    return InkWell(
                      onTap: () {
                        // Set field to show only record number
                        widget.controller.text = pair.recordNumber;
                        widget.onRecordSelected?.call(pair);
                        _removeOverlay();
                        _focusNode.unfocus();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10.0,
                          horizontal: 12.0,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey.shade200,
                              width: 1.0,
                            ),
                          ),
                        ),
                        // Display full format: [name] - [record number]
                        child: Text(pair.displayText),
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          suffixIcon: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
