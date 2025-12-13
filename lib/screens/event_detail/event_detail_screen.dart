import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/event.dart';
import '../../models/note.dart';
import '../../services/database_service_interface.dart';
import '../../services/service_locator.dart';
import '../../utils/datetime_picker_utils.dart';
import '../../utils/event_time_validator.dart';
import '../../widgets/handwriting_canvas.dart';
import 'event_detail_controller.dart';
import 'event_detail_state.dart';
import 'widgets/status_bar.dart';
import 'widgets/event_metadata_section.dart';
import 'widgets/handwriting_section.dart';
import 'widgets/charge_items_section.dart';
import 'dialogs/confirm_discard_dialog.dart';
import 'dialogs/delete_event_dialog.dart';
import 'dialogs/remove_event_dialog.dart';
import '../../widgets/dialogs/change_time_dialog.dart';


/// Event Detail screen with handwriting notes - refactored version
class EventDetailScreen extends StatefulWidget {
  final Event event;
  final bool isNew;

  const EventDetailScreen({
    super.key,
    required this.event,
    required this.isNew,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late EventDetailController _controller;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  final GlobalKey<HandwritingCanvasState> _canvasKey = GlobalKey<HandwritingCanvasState>();

  // Callback to save current page before final save
  VoidCallback? _saveCurrentPageCallback;

  // Track the last checked record number to prevent dialog loop
  String? _lastCheckedRecordNumber;

  // Available record numbers for dropdown
  List<String> _availableRecordNumbers = [];

  // Focus nodes for autocomplete
  late FocusNode _nameFocusNode;
  late FocusNode _recordNumberFocusNode;

  // Autocomplete options
  List<String> _allNames = [];
  List<RecordNumberOption> _allRecordNumberOptions = [];

  // Tracks for clearing behavior - clear record number when starting to type name
  String _lastNameValue = '';

  // Get database service from service locator
  final IDatabaseService _dbService = getIt<IDatabaseService>();

  @override
  void initState() {
    super.initState();

    // Initialize text controllers
    _nameController = TextEditingController(text: widget.event.title);
    _phoneController = TextEditingController(text: ''); // Phone is now on records table

    // Initialize last values for clearing behavior
    _lastNameValue = widget.event.title;

    // Initialize focus nodes
    _nameFocusNode = FocusNode();
    _recordNumberFocusNode = FocusNode();

    // Initialize controller FIRST
    _controller = EventDetailController(
      event: widget.event,
      isNew: widget.isNew,
      dbService: _dbService,
      onStateChanged: (state) {
        if (mounted) {
          // Update name controller if state changed (e.g., from record number selection)
          // Check to avoid infinite loop: only update if different
          // IMPORTANT: Update _lastNameValue BEFORE _nameController.text to prevent
          // the name listener from thinking user typed and clearing record number
          if (_nameController.text != state.name) {
            _lastNameValue = state.name;  // Update tracking variable first!
            _nameController.text = state.name;  // Then update controller
          }

          // Update phone controller if state changed
          // Check to avoid infinite loop: only update if different
          if (_phoneController.text != state.phone) {
            _phoneController.text = state.phone;
          }
          setState(() {});
        }
      },
    );

    // Add listener for name changes AFTER controller is initialized
    _nameController.addListener(() {
      final newValue = _nameController.text;

      // Clear record number when user starts typing in name field
      if (newValue != _lastNameValue && newValue.isNotEmpty) {
        if (_controller.state.recordNumber.isNotEmpty) {
          _controller.updateRecordNumber('');
        }
      }

      _controller.updateName(newValue);
      _lastNameValue = newValue;

      // Fetch available record numbers when name changes
      _fetchAvailableRecordNumbers();
    });

    // Add listener for phone changes
    _phoneController.addListener(() {
      _controller.updatePhone(_phoneController.text);
    });

    // Initialize services and load data asynchronously
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Fetch available record numbers after controller is ready
      await _fetchAvailableRecordNumbers();
      // Fetch all names and record numbers for autocomplete
      await _fetchAllNamesAndRecordNumbers();
      await _controller.initialize();
      _controller.setupConnectivityMonitoring();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize services. Some features may not work. Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nameFocusNode.dispose();
    _recordNumberFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailableRecordNumbers() async {
    final recordNumbers = await _controller.getRecordNumbersForCurrentName();
    if (mounted) {
      setState(() {
        _availableRecordNumbers = recordNumbers;
      });
    }
  }

  Future<void> _fetchAllNamesAndRecordNumbers() async {
    final names = await _controller.getAllNamesForAutocomplete();
    final recordNumbers = await _controller.getAllRecordNumbersForAutocomplete();
    if (mounted) {
      setState(() {
        _allNames = names;
        _allRecordNumberOptions = recordNumbers;
      });
    }
  }

  void _handleRecordNumberChanged(String newRecordNumber) {
    _controller.updateRecordNumber(newRecordNumber);

    // Reset tracker if value changed from last checked
    if (newRecordNumber.trim() != _lastCheckedRecordNumber) {
      setState(() {
        _lastCheckedRecordNumber = null;
      });
    }

    // Check for existing person note after selection
    _checkAndShowPersonNoteDialog();
  }

  void _onPagesChanged(List<List<Stroke>> pages) {

    _controller.updatePages(pages);

    final totalStrokes = pages.fold<int>(0, (sum, page) => sum + page.length);
  }

  Future<void> _saveEvent() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.eventNameRequired)),
      );
      return;
    }

    try {
      // Ensure current canvas state is saved before reading pages
      _saveCurrentPageCallback?.call();

      // Save is handled by the controller which already has the latest pages
      // from onPagesChanged callbacks
      await _controller.saveEvent();

      if (mounted) {
        // Show success feedback
        final isOffline = _controller.state.isOffline;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOffline
                        ? 'Saved locally (offline - will sync when online)'
                        : 'Saved locally (syncing to server...)',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorSavingEventMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _deleteEvent() async {
    if (widget.isNew) return;

    final confirmed = await DeleteEventDialog.show(context);
    if (!confirmed) return;

    try {
      await _controller.deleteEvent();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorDeletingEventMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _removeEvent() async {
    if (widget.isNew) return;

    final reason = await RemoveEventDialog.show(context);
    if (reason == null || reason.isEmpty) return;

    try {
      await _controller.removeEvent(reason);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorRemovingEventMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _changeEventTime() async {
    if (widget.isNew) return;

    final l10n = AppLocalizations.of(context)!;
    final result = await ChangeTimeDialog.show(
      context,
      initialStartTime: _controller.state.startTime,
      initialEndTime: _controller.state.endTime,
    );

    if (result == null) return;

    try {
      await _controller.changeEventTime(result.startTime, result.endTime, result.reason);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.eventTimeChangedSuccess),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorChangingEventTimeMessage(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: l10n.retry,
              textColor: Colors.white,
              onPressed: () => _changeEventTime(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _checkAndShowPersonNoteDialog() async {
    // Only check for NEW events
    if (!widget.isNew) return;

    final currentRecordNumber = _controller.state.recordNumber.trim();

    // Skip if we already checked this value
    if (currentRecordNumber == _lastCheckedRecordNumber) {
      return;
    }

    final existingNote = await _controller.checkExistingPersonNote();

    if (existingNote != null && mounted) {
      // Mark as checked BEFORE showing dialog to prevent re-triggering
      setState(() {
        _lastCheckedRecordNumber = currentRecordNumber;
      });

      // Check if current event has any handwriting
      final canvasState = _canvasKey.currentState;
      final currentStrokes = canvasState?.getStrokes() ?? [];
      final hasCurrentHandwriting = currentStrokes.isNotEmpty;

      // If current event has no handwriting, auto-load without dialog
      if (!hasCurrentHandwriting) {
        await _controller.loadExistingPersonNote(existingNote);
        // Canvas will be updated by rebuilding HandwritingSection with new note pages
        setState(() {});
        return;
      }

      // Current event has handwriting, show confirmation dialog
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: Text('此病歷號已有筆記，要載入現有筆記嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留當前'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('載入現有'),
            ),
          ],
        ),
      );

      // Unfocus the record number field to prevent re-triggering the dialog
      if (mounted) {
        FocusScope.of(context).unfocus();
      }

      if (result == true && mounted) {
        await _controller.loadExistingPersonNote(existingNote);
        // Canvas will be updated by rebuilding HandwritingSection with new note pages
        setState(() {});
      }
    }
  }

  Future<String?> _showNewRecordNumberDialog() async {
    // Fetch latest available record numbers before showing dialog
    await _fetchAvailableRecordNumbers();

    return await showDialog<String>(
      context: context,
      builder: (context) => _NewRecordNumberDialog(
        existingRecordNumbers: _availableRecordNumbers,
      ),
    );
  }

  Future<void> _selectStartTime() async {
    final result = await DateTimePickerUtils.pickDateTime(
      context,
      initialDateTime: _controller.state.startTime,
      validateBusinessHours: true,
      isEndTime: false,
    );

    if (result == null) return;

    _controller.updateStartTime(result);

    // If end time exists and is now invalid (before start or exceeds 21:00), clear it
    final currentEndTime = _controller.state.endTime;
    if (currentEndTime != null) {
      final error = EventTimeValidator.validateTimeRange(result, currentEndTime);
      if (error != null) {
        _controller.clearEndTime();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('End time cleared: $error'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  Future<void> _selectEndTime() async {
    final startTime = _controller.state.startTime;
    final currentEndTime = _controller.state.endTime ?? startTime.add(const Duration(minutes: 30));

    // Ensure initial value is on same day as start time
    final adjustedInitial = DateTime(
      startTime.year,
      startTime.month,
      startTime.day,
      currentEndTime.hour,
      currentEndTime.minute,
    );

    final result = await DateTimePickerUtils.pickDateTime(
      context,
      initialDateTime: adjustedInitial,
      firstDate: startTime,
      lastDate: EventTimeValidator.getLatestEndTime(startTime),
      validateBusinessHours: true,
      isEndTime: true,
      referenceStartTime: startTime,
    );

    if (result == null) return;

    _controller.updateEndTime(result);
  }

  Future<bool> _onWillPop() async {
    final hasName = _nameController.text.trim().isNotEmpty;

    // For NEW events with a name (even without changes), auto-save
    // This handles the case where data is pre-filled from "schedule next appointment"
    if (widget.isNew && hasName) {
      try {
        // Save current canvas state
        _saveCurrentPageCallback?.call();

        // Save the event
        await _controller.saveEvent();

        if (mounted) {
          // Show success feedback
          final isOffline = _controller.state.isOffline;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOffline
                          ? 'Saved locally (offline - will sync when online)'
                          : 'Saved locally (syncing to server...)',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          // Navigate back with result=true to trigger schedule reload
          Navigator.pop(context, true);
        }

        return false; // Prevent default pop (we already popped manually)
      } catch (e) {
        if (mounted) {
          // Show error but still navigate back
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );

          // Navigate back with result=true to trigger schedule reload (data might be partially saved)
          Navigator.pop(context, true);
        }

        return false; // Prevent default pop (we already popped manually)
      }
    }

    // For NEW events without a name, allow default pop without saving
    if (widget.isNew && !hasName) {
      return true; // No name, nothing to save
    }

    // For EXISTING events without changes, allow default pop
    if (!_controller.state.hasChanges) {
      return true; // No changes, allow default pop
    }

    // For EXISTING events with changes but no name, show discard dialog
    if (!hasName) {
      final shouldDiscard = await ConfirmDiscardDialog.show(context);
      if (shouldDiscard && mounted) {
        // User chose to discard changes, pop without reloading schedule
        Navigator.pop(context, false);
        return false; // Prevent default pop
      }
      return false; // User chose to keep editing
    }

    // For EXISTING events with changes and a name, auto-save
    try {
      // Save current canvas state
      _saveCurrentPageCallback?.call();

      // Save the event
      await _controller.saveEvent();

      if (mounted) {
        // Show success feedback
        final isOffline = _controller.state.isOffline;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOffline
                        ? 'Saved locally (offline - will sync when online)'
                        : 'Saved locally (syncing to server...)',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Navigate back with result=true to trigger schedule reload
        Navigator.pop(context, true);
      }

      return false; // Prevent default pop (we already popped manually)
    } catch (e) {
      if (mounted) {
        // Show error but still navigate back
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );

        // Navigate back with result=true to trigger schedule reload (data might be partially saved)
        Navigator.pop(context, true);
      }

      return false; // Prevent default pop (we already popped manually)
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = _controller.state;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? l10n.newEvent : l10n.editEvent),
          actions: [
            // Sync status indicators in AppBar
            if (state.hasUnsyncedChanges)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.cloud_upload,
                  color: Colors.orange,
                  semanticLabel: 'Unsynced changes',
                  size: 24,
                ),
              ),
            if (state.isOffline && !state.hasUnsyncedChanges)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.cloud_off,
                  color: Colors.grey,
                  semanticLabel: 'Offline',
                  size: 24,
                ),
              ),
            if (!widget.isNew && !widget.event.isRemoved) ...[
              PopupMenuButton<String>(
                enabled: !state.isLoading,
                onSelected: (value) {
                  if (state.isLoading) return;
                  switch (value) {
                    case 'remove':
                      _removeEvent();
                      break;
                    case 'changeTime':
                      _changeEventTime();
                      break;
                    case 'delete':
                      _deleteEvent();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'remove',
                    enabled: !state.isLoading,
                    child: Row(
                      children: [
                        Icon(
                          Icons.remove_circle_outline,
                          color: state.isLoading ? Colors.grey : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Remove Event',
                          style: TextStyle(
                            color: state.isLoading ? Colors.grey : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'changeTime',
                    enabled: !state.isLoading,
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          color: state.isLoading ? Colors.grey : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Change Time',
                          style: TextStyle(
                            color: state.isLoading ? Colors.grey : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: !state.isLoading,
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_forever,
                          color: state.isLoading ? Colors.grey : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        const Text('Delete Permanently'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        body: state.isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Processing...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isTablet = constraints.maxWidth > 600;
                  final screenHeight = constraints.maxHeight;
                  final padding = isTablet ? 12.0 : 10.0;

                  return Column(
                    children: [
                      // Status bar
                      EventDetailStatusBar(
                        hasUnsyncedChanges: state.hasUnsyncedChanges,
                        isOffline: state.isOffline,
                        isLoadingFromServer: state.isLoadingFromServer,
                      ),
                      // Event metadata section
                      Flexible(
                        flex: 0,
                        child: Container(
                          constraints: BoxConstraints(
                            maxHeight: screenHeight * 0.7,
                          ),
                          padding: EdgeInsets.all(padding),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            clipBehavior: Clip.none,
                            child: EventMetadataSection(
                              event: widget.event,
                              newEvent: state.newEvent,
                              nameController: _nameController,
                              phoneController: _phoneController,
                              recordNumber: state.recordNumber,
                              availableRecordNumbers: _availableRecordNumbers,
                              isRecordNumberFieldEnabled: _nameController.text.trim().isNotEmpty,
                              selectedEventTypes: state.selectedEventTypes,
                              startTime: state.startTime,
                              endTime: state.endTime,
                              onStartTimeTap: _selectStartTime,
                              onEndTimeTap: _selectEndTime,
                              onClearEndTime: () => _controller.clearEndTime(),
                              onEventTypesChanged: (eventTypes) {
                                _controller.updateEventTypes(eventTypes);
                              },
                              onRecordNumberChanged: _handleRecordNumberChanged,
                              onNewRecordNumberRequested: _showNewRecordNumberDialog,
                              // New autocomplete parameters
                              nameFocusNode: _nameFocusNode,
                              recordNumberFocusNode: _recordNumberFocusNode,
                              allNames: _allNames,
                              allRecordNumberOptions: _allRecordNumberOptions,
                              onNameSelected: (name) => _controller.onNameSelected(name),
                              onRecordNumberSelected: (recordNumber) => _controller.onRecordNumberSelected(recordNumber),
                              // Removed onRecordNumberTextChanged to fix race condition bug
                              // Only name field typing clears record number, not vice versa
                              isNameReadOnly: state.isNameReadOnly,
                            ),
                          ),
                        ),
                      ),
                      // Charge Items Section (between metadata and handwriting)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        child: ChargeItemsSection(
                          chargeItems: state.chargeItems,
                          controller: _controller,
                          hasRecordNumber: state.recordNumber.trim().isNotEmpty,
                        ),
                      ),
                      // Handwriting section
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final initialPages = state.note?.pages ?? state.lastKnownPages;
                            final totalStrokes = initialPages.fold<int>(0, (sum, page) => sum + page.length);
                            return HandwritingSection(
                              canvasKey: _canvasKey,
                              initialPages: initialPages,
                              onPagesChanged: _onPagesChanged,
                              onSaveCurrentPageCallbackSet: (callback) {
                                _saveCurrentPageCallback = callback;
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

/// Dialog for entering a new record number with duplicate validation
class _NewRecordNumberDialog extends StatefulWidget {
  final List<String> existingRecordNumbers;

  const _NewRecordNumberDialog({
    required this.existingRecordNumbers,
  });

  @override
  State<_NewRecordNumberDialog> createState() => _NewRecordNumberDialogState();
}

class _NewRecordNumberDialogState extends State<_NewRecordNumberDialog> {
  late TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _validateAndSubmit() {
    final value = _controller.text.trim();


    if (value.isEmpty) {
      setState(() {
        _errorText = '請輸入病例號';
      });
      return false;
    }

    // Check for duplicates (case-insensitive)
    final isDuplicate = widget.existingRecordNumbers.any(
      (existing) => existing.toLowerCase() == value.toLowerCase(),
    );


    if (isDuplicate) {
      setState(() {
        _errorText = '此病例號已存在，請輸入不同的病例號';
      });
      return false;
    }

    return true;
  }

  void _handleSubmit() {
    if (_validateAndSubmit()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新病例號'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '病例號',
          hintText: '請輸入新的病例號',
          errorText: _errorText,
        ),
        onChanged: (_) {
          // Clear error when user types
          if (_errorText != null) {
            setState(() {
              _errorText = null;
            });
          }
        },
        onSubmitted: (_) => _handleSubmit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _handleSubmit,
          child: const Text('確定'),
        ),
      ],
    );
  }
}
