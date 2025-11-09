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
  String? selectedRecordNumber;
  List<String> recordNumbers = [];
  List<Event> searchResults = [];
  bool isLoading = false;
  bool hasSearched = false;
  String? nameError;
  String? recordNumberError;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    _loadRecordNumbers();
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  /// Load all unique record numbers from the database
  Future<void> _loadRecordNumbers() async {
    setState(() {
      isLoading = true;
    });

    try {
      final numbers = await widget.eventRepository.getAllRecordNumbers(widget.bookId);
      setState(() {
        recordNumbers = numbers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorLoadingData)),
        );
      }
    }
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
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
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
                  // Name input field
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: l10n.eventName,
                      errorText: nameError,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        nameError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Record number dropdown
                  DropdownButtonFormField<String>(
                    value: selectedRecordNumber,
                    decoration: InputDecoration(
                      labelText: l10n.recordNumber,
                      errorText: recordNumberError,
                      border: const OutlineInputBorder(),
                    ),
                    hint: Text(recordNumbers.isEmpty
                        ? l10n.noRecordNumbers
                        : l10n.selectRecordNumber),
                    items: recordNumbers.map((number) {
                      return DropdownMenuItem(
                        value: number,
                        child: Text(number),
                      );
                    }).toList(),
                    onChanged: recordNumbers.isEmpty ? null : (String? newValue) {
                      setState(() {
                        selectedRecordNumber = newValue;
                        recordNumberError = null;
                      });
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

            // Event type
            Row(
              children: [
                Icon(Icons.category, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  '${l10n.appointmentType}: ${EventTypeLocalizations.getLocalizedEventType(context, event.eventType)}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
