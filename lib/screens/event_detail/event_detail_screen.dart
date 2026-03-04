import 'dart:async';

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
  final bool isReadOnlyMode;

  const EventDetailScreen({
    super.key,
    required this.event,
    required this.isNew,
    this.isReadOnlyMode = false,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen>
    with WidgetsBindingObserver {
  static const Duration _notePollInterval = Duration(seconds: 30);

  late EventDetailController _controller;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  final GlobalKey<HandwritingCanvasState> _canvasKey =
      GlobalKey<HandwritingCanvasState>();

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
  Timer? _notePollingTimer;
  bool _isAppResumed = true;
  bool _isNoteRefreshInFlight = false;
  bool _hasDeferredRefreshAfterStroke = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize text controllers
    _nameController = TextEditingController(text: widget.event.title);
    _phoneController = TextEditingController(
      text: '',
    ); // Phone is now on records table

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
            _lastNameValue = state.name; // Update tracking variable first!
            _nameController.text = state.name; // Then update controller
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
      _startNotePolling();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to initialize services. Some features may not work. Error: $e',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _stopNotePolling();
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _phoneController.dispose();
    _nameFocusNode.dispose();
    _recordNumberFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppResumed = true;
      _startNotePolling();
      unawaited(_pollLatestNoteFromServer(force: true));
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isAppResumed = false;
      _stopNotePolling();
    }
  }

  bool get _canPollNote {
    if (!_isAppResumed) return false;
    if (widget.isNew) return false;
    if (!mounted) return false;
    if (_controller.state.isLoading) return false;
    return widget.event.recordUuid.isNotEmpty;
  }

  void _startNotePolling() {
    _stopNotePolling();
    if (!_canPollNote) return;
    _notePollingTimer = Timer.periodic(_notePollInterval, (_) {
      unawaited(_pollLatestNoteFromServer());
    });
  }

  void _stopNotePolling() {
    _notePollingTimer?.cancel();
    _notePollingTimer = null;
  }

  Future<void> _pollLatestNoteFromServer({bool force = false}) async {
    if (!force && !_canPollNote) {
      return;
    }
    if (_isNoteRefreshInFlight) {
      return;
    }

    final canvasState = _canvasKey.currentState;
    if (!force && canvasState != null && canvasState.isStrokeInProgress) {
      _hasDeferredRefreshAfterStroke = true;
      return;
    }

    _isNoteRefreshInFlight = true;
    try {
      await _controller.refreshNoteFromServerInBackground();
      _hasDeferredRefreshAfterStroke = false;
    } finally {
      _isNoteRefreshInFlight = false;
    }
  }

  void _flushDeferredNoteRefreshIfReady() {
    if (!_hasDeferredRefreshAfterStroke) {
      return;
    }
    final canvasState = _canvasKey.currentState;
    if (canvasState != null && canvasState.isStrokeInProgress) {
      return;
    }
    _hasDeferredRefreshAfterStroke = false;
    unawaited(_pollLatestNoteFromServer(force: true));
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
    final recordNumbers = await _controller
        .getAllRecordNumbersForAutocomplete();
    if (mounted) {
      setState(() {
        _allNames = names;
        _allRecordNumberOptions = recordNumbers;
      });
    }
  }

  void _handleRecordNumberChanged(String newRecordNumber) {
    _controller.updateRecordNumber(newRecordNumber);
  }

  Future<void> _handleRecordNumberBlur() async {
    await _controller.validateRecordNumberOnBlur();
  }

  void _onPagesChanged(List<List<Stroke>> pages) {
    _controller.updatePages(pages);
    _flushDeferredNoteRefreshIfReady();
  }

  Size? _getCanvasSize() => _canvasKey.currentState?.canvasSize;

  Future<void> _saveAndPop({required bool isAutoSave}) async {
    final capturedCanvasSize = _getCanvasSize();

    try {
      await _controller.saveEvent(
        canvasSize: capturedCanvasSize,
        isAutoSave: isAutoSave,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            )!.errorSavingEventMessage(error.toString()),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteEvent() async {
    if (widget.isReadOnlyMode) return;
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
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.errorDeletingEventMessage(e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _removeEvent() async {
    if (widget.isReadOnlyMode) return;
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
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.errorRemovingEventMessage(e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _changeEventTime() async {
    if (widget.isReadOnlyMode) return;
    if (widget.isNew) return;

    final l10n = AppLocalizations.of(context)!;
    final result = await ChangeTimeDialog.show(
      context,
      initialStartTime: _controller.state.startTime,
      initialEndTime: _controller.state.endTime,
    );

    if (result == null) return;

    try {
      await _controller.changeEventTime(
        result.startTime,
        result.endTime,
        result.reason,
      );

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
      final error = EventTimeValidator.validateTimeRange(
        result,
        currentEndTime,
      );
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
    final currentEndTime =
        _controller.state.endTime ?? startTime.add(const Duration(minutes: 30));

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
    if (widget.isReadOnlyMode) {
      return true;
    }
    if (_controller.state.isLoading) {
      return false;
    }
    final hasName = _nameController.text.trim().isNotEmpty;

    // Block auto-save if there's a record number validation error
    if (_controller.state.recordNumberError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('請修正病例號錯誤後再儲存'),
          backgroundColor: Colors.red,
        ),
      );
      return false; // Don't pop, stay on screen to fix error
    }

    // For NEW events with a name (even without changes), auto-save
    // This handles the case where data is pre-filled from "schedule next appointment"
    if (widget.isNew && hasName) {
      await _saveAndPop(isAutoSave: true);
      return false; // Prevent default pop (we already popped manually)
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
    await _saveAndPop(isAutoSave: true);
    return false; // Prevent default pop (we already popped manually)
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = _controller.state;
    final isBlockingOverlayVisible =
        state.isLoading || state.isLoadingFromServer;
    final loadingMessage = state.isLoading
        ? 'Syncing event...'
        : 'Loading event...';

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isReadOnlyMode
                ? 'View Event'
                : (widget.isNew ? l10n.newEvent : l10n.editEvent),
          ),
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
            if (widget.isReadOnlyMode)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Tooltip(
                  message:
                      'Read-only mode: data editing and handwriting are disabled.',
                  child: Icon(
                    Icons.lock_outline,
                    semanticLabel: 'Read-only mode',
                    size: 20,
                  ),
                ),
              ),
            if (!widget.isReadOnlyMode &&
                !widget.isNew &&
                !widget.event.isRemoved) ...[
              PopupMenuButton<String>(
                enabled: !isBlockingOverlayVisible,
                onSelected: (value) {
                  if (isBlockingOverlayVisible) return;
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
                    enabled: !isBlockingOverlayVisible,
                    child: Row(
                      children: [
                        Icon(
                          Icons.remove_circle_outline,
                          color: isBlockingOverlayVisible ? Colors.grey : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Remove Event',
                          style: TextStyle(
                            color: isBlockingOverlayVisible
                                ? Colors.grey
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'changeTime',
                    enabled: !isBlockingOverlayVisible,
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          color: isBlockingOverlayVisible ? Colors.grey : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Change Time',
                          style: TextStyle(
                            color: isBlockingOverlayVisible
                                ? Colors.grey
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: !isBlockingOverlayVisible,
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_forever,
                          color: isBlockingOverlayVisible
                              ? Colors.grey
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        const Text('Delete Permanently'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (isBlockingOverlayVisible)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
          ],
        ),
        body: Stack(
          children: [
            AbsorbPointer(
              absorbing: isBlockingOverlayVisible,
              child: LayoutBuilder(
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
                              isRecordNumberFieldEnabled: _nameController.text
                                  .trim()
                                  .isNotEmpty,
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
                              // New autocomplete parameters
                              nameFocusNode: _nameFocusNode,
                              recordNumberFocusNode: _recordNumberFocusNode,
                              allNames: _allNames,
                              allRecordNumberOptions: _allRecordNumberOptions,
                              onNameSelected: (name) =>
                                  _controller.onNameSelected(name),
                              onRecordNumberSelected: (recordNumber) =>
                                  unawaited(
                                    _controller.onRecordNumberSelected(
                                      recordNumber,
                                    ),
                                  ),
                              isNameReadOnly: state.isNameReadOnly,
                              isReadOnlyMode: widget.isReadOnlyMode,
                              // Record number validation
                              recordNumberError: state.recordNumberError,
                              isValidatingRecordNumber:
                                  state.isValidatingRecordNumber,
                              onRecordNumberBlur: _handleRecordNumberBlur,
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
                          hasRecordUuid: widget.event.recordUuid.isNotEmpty,
                          showOnlyThisEventItems: state.showOnlyThisEventItems,
                          isReadOnlyMode: widget.isReadOnlyMode,
                        ),
                      ),
                      // Handwriting section
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final initialPages =
                                state.note?.pages ?? state.lastKnownPages;
                            return HandwritingSection(
                              canvasKey: _canvasKey,
                              initialPages: initialPages,
                              onPagesChanged: _onPagesChanged,
                              currentEventUuid: widget.event.id,
                              isReadOnlyMode: widget.isReadOnlyMode,
                              onStrokesErased: (erasedStrokeIds) {
                                _controller.onStrokesErased(erasedStrokeIds);
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
            if (isBlockingOverlayVisible)
              Positioned.fill(
                child: ColoredBox(
                  color: state.isLoadingFromServer
                      ? Colors.grey.withValues(alpha: 0.36)
                      : Colors.black.withValues(alpha: 0.22),
                  child: Center(
                    child: _LoadingOverlayCard(message: loadingMessage),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingOverlayCard extends StatelessWidget {
  final String message;

  const _LoadingOverlayCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.8),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
