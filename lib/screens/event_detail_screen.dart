import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/event.dart';
import '../models/note.dart';
import '../services/prd_database_service.dart';
import '../services/web_prd_database_service.dart';
import '../widgets/handwriting_canvas.dart';

/// Event Detail screen with handwriting notes as per PRD
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
  late TextEditingController _nameController;
  late TextEditingController _recordNumberController;
  late TextEditingController _eventTypeController;
  late DateTime _startTime;
  DateTime? _endTime;
  Note? _note;
  bool _isLoading = false;
  bool _hasChanges = false;

  // Use appropriate database service based on platform
  dynamic get _dbService => kIsWeb
      ? WebPRDDatabaseService()
      : PRDDatabaseService();
  final GlobalKey<HandwritingCanvasState> _canvasKey = GlobalKey<HandwritingCanvasState>();

  // Cache for new event when displaying time change info
  Event? _newEvent;

  // Backup storage for strokes in case canvas key is lost
  List<Stroke> _lastKnownStrokes = [];

  // Control panel visibility state
  bool _isControlPanelExpanded = false;

  // Common event types for quick selection
  List<String> get _commonEventTypes => [
    AppLocalizations.of(context)!.consultation,
    AppLocalizations.of(context)!.surgery,
    AppLocalizations.of(context)!.followUp,
    AppLocalizations.of(context)!.emergency,
    AppLocalizations.of(context)!.checkUp,
    AppLocalizations.of(context)!.treatment,
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.event.name);
    _recordNumberController = TextEditingController(text: widget.event.recordNumber);
    _eventTypeController = TextEditingController(text: widget.event.eventType);
    _startTime = widget.event.startTime;
    _endTime = widget.event.endTime;

    _nameController.addListener(_onChanged);
    _recordNumberController.addListener(_onChanged);
    _eventTypeController.addListener(_onChanged);

    if (!widget.isNew) {
      _loadNote();
      if (widget.event.hasNewTime) {
        _loadNewEvent();
      }
    }
  }

  Future<void> _loadNewEvent() async {
    if (widget.event.newEventId == null) return;
    try {
      final newEvent = await _dbService.getEventById(widget.event.newEventId!);
      setState(() {
        _newEvent = newEvent;
      });
    } catch (e) {
      debugPrint('Error loading new event: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _recordNumberController.dispose();
    _eventTypeController.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {
      _hasChanges = true;
    });
  }

  void _onStrokesChanged() {
    debugPrint('🏗️ EventDetail: onStrokesChanged callback fired');

    // Update backup strokes immediately when strokes change
    final canvasState = _canvasKey.currentState;
    if (canvasState != null) {
      final currentStrokes = canvasState.getStrokes();
      _lastKnownStrokes = List<Stroke>.from(currentStrokes);
      debugPrint('🔄 EventDetail: Updated backup strokes (${_lastKnownStrokes.length} strokes)');

      // Log first few strokes for debugging
      for (int i = 0; i < currentStrokes.length && i < 2; i++) {
        final stroke = currentStrokes[i];
        debugPrint('🔄 EventDetail: Backup stroke $i has ${stroke.points.length} points, color: ${stroke.color}');
      }
    } else {
      debugPrint('⚠️ EventDetail: Canvas state is null during onStrokesChanged');
    }

    _onChanged();
  }

  Future<void> _loadNote() async {
    if (widget.event.id == null) {
      debugPrint('🔍 EventDetail: Cannot load note - event ID is null');
      return;
    }

    debugPrint('🔍 EventDetail: Starting note load for event ID: ${widget.event.id}');
    setState(() => _isLoading = true);
    try {
      final note = await _dbService.getNoteByEventId(widget.event.id!);
      debugPrint('📖 EventDetail: Database query completed');

      if (note != null) {
        debugPrint('📖 EventDetail: Note found with ${note.strokes.length} strokes');
        // Log first few strokes for debugging
        for (int i = 0; i < note.strokes.length && i < 3; i++) {
          final stroke = note.strokes[i];
          debugPrint('📖 EventDetail: Loaded stroke $i has ${stroke.points.length} points, color: ${stroke.color}');
        }
      } else {
        debugPrint('📖 EventDetail: No note found for event ID: ${widget.event.id}');
      }

      setState(() {
        _note = note;
        _isLoading = false;
      });
      debugPrint('📖 EventDetail: Set _note state and triggered rebuild');

      // Validate canvas state after note load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final canvasState = _canvasKey.currentState;
        if (canvasState != null) {
          debugPrint('📖 EventDetail: Validating canvas state after note load...');
          canvasState.validateState();

          final stateInfo = canvasState.getStateInfo();
          debugPrint('📖 EventDetail: Canvas state after load: $stateInfo');

          // If canvas doesn't have the expected strokes, try to force refresh
          final expectedStrokes = note?.strokes.length ?? 0;
          final actualStrokes = stateInfo['strokeCount'] as int;
          if (actualStrokes != expectedStrokes) {
            debugPrint('⚠️ EventDetail: Canvas stroke mismatch! Expected: $expectedStrokes, Actual: $actualStrokes');
            if (note != null) {
              debugPrint('🔄 EventDetail: Force refreshing canvas with loaded strokes...');
              canvasState.forceRefreshState(note.strokes);
            }
          }
        }
      });

      // Note: Canvas will automatically update via didUpdateWidget
      // when _note changes and widget rebuilds with new initialStrokes
    } catch (e) {
      debugPrint('❌ EventDetail: Error loading note: $e');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.errorLoadingNoteMessage(e.toString()))),
      );
    }
  }

  Future<void> _saveEvent() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.eventNameRequired)),
      );
      return;
    }

    if (_recordNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.recordNumberRequired)),
      );
      return;
    }

    if (_eventTypeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.eventTypeRequired)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final eventToSave = widget.event.copyWith(
        name: _nameController.text.trim(),
        recordNumber: _recordNumberController.text.trim(),
        eventType: _eventTypeController.text.trim(),
        startTime: _startTime,
        endTime: _endTime,
      );

      Event savedEvent;
      if (widget.isNew) {
        savedEvent = await _dbService.createEvent(eventToSave);
      } else {
        savedEvent = await _dbService.updateEvent(eventToSave);
      }

      // Always save handwriting note (including empty ones)
      try {
        debugPrint('💾 EventDetail: Starting note save process for event ID: ${savedEvent.id}');
        final canvasState = _canvasKey.currentState;
        debugPrint('💾 EventDetail: Canvas state is ${canvasState != null ? "available" : "null"}');

        // Validate canvas state before saving
        if (canvasState != null) {
          canvasState.validateState();
          final stateInfo = canvasState.getStateInfo();
          debugPrint('💾 EventDetail: Canvas state before save: $stateInfo');
        }

        List<Stroke> strokes;
        if (canvasState != null) {
          strokes = canvasState.getStrokes();
          debugPrint('💾 EventDetail: Retrieved ${strokes.length} strokes from canvas');
        } else {
          strokes = List<Stroke>.from(_lastKnownStrokes);
          debugPrint('💾 EventDetail: Canvas state null, using backup strokes (${strokes.length} strokes)');
        }

        // Log detailed stroke information
        for (int i = 0; i < strokes.length && i < 3; i++) {
          final stroke = strokes[i];
          debugPrint('💾 EventDetail: Stroke $i has ${stroke.points.length} points, color: ${stroke.color}');
        }

        final noteToSave = Note(
          eventId: savedEvent.id!,
          strokes: strokes,
          createdAt: _note?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        );
        debugPrint('💾 EventDetail: Created Note object with ${noteToSave.strokes.length} strokes');

        await _dbService.updateNote(noteToSave);
        debugPrint('✅ EventDetail: Note saved successfully to database with ${strokes.length} strokes');
      } catch (e) {
        // Log error but don't fail the entire save operation
        debugPrint('❌ Failed to save note: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.eventSavedButNoteFailed),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.errorSavingEventMessage(e.toString()))),
      );
    }
  }

  Future<void> _deleteEvent() async {
    if (widget.isNew) return;

    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteEventTitle),
        content: Text(l10n.deleteEventConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _dbService.deleteEvent(widget.event.id!);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorDeletingEventMessage(e.toString()))),
      );
    }
  }

  Future<void> _removeEvent() async {
    if (widget.isNew) return;

    final l10n = AppLocalizations.of(context)!;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(l10n.removeEventTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.removeEventMessage),
              const SizedBox(height: 16),
              Text(l10n.reasonForRemovalField),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: l10n.enterReasonForRemoval,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(l10n.removeButton),
            ),
          ],
        );
      },
    );

    if (reason == null || reason.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await _dbService.removeEvent(widget.event.id!, reason);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorRemovingEventMessage(e.toString()))),
      );
    }
  }

  Future<void> _changeEventTime() async {
    if (widget.isNew) return;

    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        DateTime newStartTime = _startTime;
        DateTime? newEndTime = _endTime;
        final reasonController = TextEditingController();
        bool showReasonError = false;

        return StatefulBuilder(
          builder: (context, setState) {
            final bool hasValidReason = reasonController.text.trim().isNotEmpty;

            return AlertDialog(
              title: Text(l10n.changeEventTimeTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.changeTimeMessage),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: newStartTime,
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date == null) return;

                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(newStartTime),
                            );
                            if (time == null) return;

                            setState(() {
                              newStartTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                            });
                          },
                          child: Text(
                            'Start: ${DateFormat('MMM d, HH:mm').format(newStartTime)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: newEndTime ?? newStartTime,
                              firstDate: newStartTime,
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date == null) return;

                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(newEndTime ?? newStartTime.add(const Duration(hours: 1))),
                            );
                            if (time == null) return;

                            setState(() {
                              newEndTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                            });
                          },
                          child: Text(
                            newEndTime != null
                                ? 'End: ${DateFormat('MMM d, HH:mm').format(newEndTime!)}'
                                : 'Set End Time (Optional)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (newEndTime != null)
                        IconButton(
                          onPressed: () => setState(() => newEndTime = null),
                          icon: const Icon(Icons.clear, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.reasonForTimeChangeField, style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      hintText: l10n.enterReasonForTimeChange,
                      border: const OutlineInputBorder(),
                      errorText: showReasonError ? l10n.reasonRequired : null,
                      errorBorder: showReasonError
                          ? const OutlineInputBorder(borderSide: BorderSide(color: Colors.red))
                          : null,
                    ),
                    maxLines: 2,
                    autofocus: true,
                    onChanged: (value) {
                      setState(() {
                        showReasonError = false;
                      });
                    },
                  ),
                  if (showReasonError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.reasonRequiredMessage,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () {
                    final reason = reasonController.text.trim();
                    if (reason.isEmpty) {
                      setState(() {
                        showReasonError = true;
                      });
                      return;
                    }
                    Navigator.pop(context, {
                      'startTime': newStartTime,
                      'endTime': newEndTime,
                      'reason': reason,
                    });
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: hasValidReason ? Theme.of(context).primaryColor : Colors.grey.shade300,
                    foregroundColor: hasValidReason ? Colors.white : Colors.grey.shade600,
                  ),
                  child: Text(l10n.changeTimeButton),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() => _isLoading = true);
    try {
      // Show progress with a brief delay to ensure loading indicator appears
      await Future.delayed(const Duration(milliseconds: 100));

      await _dbService.changeEventTime(
        widget.event,
        result['startTime'],
        result['endTime'],
        result['reason'],
      );

      if (mounted) {
        // Show success feedback before navigating back
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.eventTimeChangedSuccess),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Small delay to allow user to see success message
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
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
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );

    if (time == null) return;

    setState(() {
      _startTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _hasChanges = true;
    });
  }

  Future<void> _selectEndTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endTime ?? _startTime,
      firstDate: _startTime,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime ?? _startTime.add(const Duration(hours: 1))),
    );

    if (time == null) return;

    setState(() {
      _endTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _hasChanges = true;
    });
  }

  void _clearEndTime() {
    setState(() {
      _endTime = null;
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? l10n.newEvent : l10n.editEvent),
        actions: [
          if (!widget.isNew && !widget.event.isRemoved) ...[
            PopupMenuButton<String>(
              enabled: !_isLoading,
              onSelected: (value) {
                if (_isLoading) return; // Additional safety check
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
                  enabled: !_isLoading,
                  child: Row(
                    children: [
                      Icon(
                        Icons.remove_circle_outline,
                        color: _isLoading ? Colors.grey : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Remove Event',
                        style: TextStyle(
                          color: _isLoading ? Colors.grey : null,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'changeTime',
                  enabled: !_isLoading,
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        color: _isLoading ? Colors.grey : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Change Time',
                        style: TextStyle(
                          color: _isLoading ? Colors.grey : null,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  enabled: !_isLoading,
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_forever,
                        color: _isLoading ? Colors.grey : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Delete Permanently',
                        style: TextStyle(
                          color: _isLoading ? Colors.grey : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveEvent,
          ),
        ],
      ),
      body: _isLoading
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
                    // Event metadata section with flexible, content-aware layout
                    Flexible(
                      flex: 0, // Don't expand, just take what's needed
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: screenHeight * 0.7, // Never take more than 70% of screen
                        ),
                        padding: EdgeInsets.all(padding),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: _buildEventMetadata(),
                        ),
                      ),
                    ),
                    // Handwriting section (remaining space)
                    Expanded(
                      child: _buildHandwritingSection(),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildEventMetadata() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
          // Event status indicators
          if (widget.event.isRemoved || widget.event.hasNewTime) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.event.isRemoved ? Colors.red.shade50 : Colors.orange.shade50,
                border: Border.all(
                  color: widget.event.isRemoved ? Colors.red.shade300 : Colors.orange.shade300,
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
                        widget.event.isRemoved ? Icons.remove_circle_outline : Icons.schedule,
                        color: widget.event.isRemoved ? Colors.red.shade700 : Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.event.isRemoved
                          ? (widget.event.hasNewTime ? 'Event Time Changed' : 'Event Removed')
                          : 'Time Changed',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: widget.event.isRemoved ? Colors.red.shade700 : Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                  if (widget.event.removalReason != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Reason: ${widget.event.removalReason}',
                      style: TextStyle(
                        color: widget.event.isRemoved ? Colors.red.shade600 : Colors.orange.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (widget.event.hasNewTime && _newEvent != null) ...[
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
                              'Moved to: ${DateFormat('EEEE, MMM d, y - HH:mm').format(_newEvent!.startTime)}',
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
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Event Name *',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 8),

          // Record Number field
          TextField(
            controller: _recordNumberController,
            decoration: const InputDecoration(
              labelText: 'Record Number *',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 8),

          // Event Type field with quick selection
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _eventTypeController,
                  decoration: const InputDecoration(
                    labelText: 'Event Type *',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (type) {
                  _eventTypeController.text = type;
                  _onChanged();
                },
                itemBuilder: (context) => _commonEventTypes
                    .map((type) => PopupMenuItem(value: type, child: Text(type)))
                    .toList(),
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
                          title: Text(AppLocalizations.of(context)!.startTime, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            DateFormat('MMM d, y - HH:mm').format(_startTime),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.access_time, size: 18),
                          onTap: _selectStartTime,
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
                                child: Text(AppLocalizations.of(context)!.endTime, style: const TextStyle(fontSize: 13)),
                              ),
                              if (_endTime != null)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 14),
                                  onPressed: _clearEndTime,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            _endTime != null
                                ? DateFormat('MMM d, y - HH:mm').format(_endTime!)
                                : AppLocalizations.of(context)!.openEnded,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.access_time, size: 18),
                          onTap: _selectEndTime,
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
                        title: Text(AppLocalizations.of(context)!.startTime),
                        subtitle: Text(DateFormat('MMM d, y - HH:mm').format(_startTime)),
                        trailing: const Icon(Icons.access_time),
                        onTap: _selectStartTime,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(AppLocalizations.of(context)!.endTime),
                            if (_endTime != null)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: _clearEndTime,
                              ),
                          ],
                        ),
                        subtitle: Text(_endTime != null
                            ? DateFormat('MMM d, y - HH:mm').format(_endTime!)
                            : 'Open-ended'),
                        trailing: const Icon(Icons.access_time),
                        onTap: _selectEndTime,
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

  /// Get color name for display
  Widget _buildHandwritingToolbar(StateSetter setState) {
    final canvasState = _canvasKey.currentState;
    final isErasing = canvasState?.isErasing ?? false;
    final currentColor = canvasState?.strokeColor ?? Colors.black;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main Toolbar
        Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'Handwriting Notes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  // Pen/Eraser toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            canvasState?.setErasing(false);
                            setState(() {});
                          },
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: !isErasing ? Colors.blue.shade100 : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: !isErasing ? Colors.blue.shade700 : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Pen',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: !isErasing ? Colors.blue.shade700 : Colors.grey.shade600,
                                    fontWeight: !isErasing ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(width: 1, height: 24, color: Colors.grey.shade300),
                        InkWell(
                          onTap: () {
                            canvasState?.setErasing(true);
                            setState(() {});
                          },
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isErasing ? Colors.orange.shade100 : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_fix_high,
                                  size: 16,
                                  color: isErasing ? Colors.orange.shade700 : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Eraser',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isErasing ? Colors.orange.shade700 : Colors.grey.shade600,
                                    fontWeight: isErasing ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Expand/Collapse button with label
                  InkWell(
                    onTap: () {
                      this.setState(() {
                        _isControlPanelExpanded = !_isControlPanelExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Controls',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _isControlPanelExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed: () => canvasState?.undo(),
                    tooltip: 'Undo',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo, size: 20),
                    onPressed: () => canvasState?.redo(),
                    tooltip: 'Redo',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () => canvasState?.clear(),
                    tooltip: 'Clear All',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          ],
        );
  }

  Widget _buildControlPanel(StateSetter setState) {
    final canvasState = _canvasKey.currentState;
    final isErasing = canvasState?.isErasing ?? false;
    final currentColor = canvasState?.strokeColor ?? Colors.black;
    final currentWidth = canvasState?.strokeWidth ?? 2.0;
    final currentEraserRadius = canvasState?.eraserRadius ?? 20.0;

    return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: _isControlPanelExpanded ? null : 0,
          child: _isControlPanelExpanded
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Size Control
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              isErasing ? Icons.radio_button_unchecked : Icons.edit,
                              size: 18,
                              color: isErasing ? Colors.orange.shade700 : Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isErasing ? 'Eraser Size:' : 'Pen Width:',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Slider(
                                value: isErasing ? currentEraserRadius : currentWidth,
                                min: isErasing ? 5.0 : 1.0,
                                max: isErasing ? 50.0 : 10.0,
                                divisions: isErasing ? 45 : 9,
                                activeColor: isErasing ? Colors.orange.shade700 : Colors.blue.shade700,
                                onChanged: (value) {
                                  setState(() {
                                    if (isErasing) {
                                      canvasState?.setEraserRadius(value);
                                    } else {
                                      canvasState?.setStrokeWidth(value);
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isErasing ? Colors.orange.shade50 : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isErasing ? Colors.orange.shade200 : Colors.blue.shade200,
                                ),
                              ),
                              child: Text(
                                '${(isErasing ? currentEraserRadius : currentWidth).toInt()} px',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isErasing ? Colors.orange.shade700 : Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Color Palette (only show in pen mode)
                      if (!isErasing)
                        Container(
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Color:',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _buildColorPalette(currentColor, (color) {
                                    setState(() {
                                      canvasState?.setStrokeColor(color);
                                    });
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        );
  }

  List<Widget> _buildColorPalette(Color currentColor, Function(Color) onColorSelected) {
    final colors = [
      Colors.black,
      Colors.grey.shade700,
      Colors.blue.shade700,
      Colors.blue.shade300,
      Colors.red.shade700,
      Colors.red.shade300,
      Colors.green.shade700,
      Colors.green.shade300,
      Colors.orange.shade700,
      Colors.amber.shade600,
      Colors.purple.shade700,
      Colors.pink.shade400,
      Colors.brown.shade600,
      Colors.teal.shade600,
    ];

    return colors.map((color) {
      final isSelected = currentColor == color;
      return GestureDetector(
        onTap: () => onColorSelected(color),
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.black : Colors.grey.shade300,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 20,
                  color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                )
              : null,
        ),
      );
    }).toList();
  }

  String _getColorName(Color color) {
    if (color == Colors.black) return 'Black';
    if (color == Colors.grey.shade700) return 'Gray';
    if (color == Colors.blue.shade700) return 'Dark Blue';
    if (color == Colors.blue.shade300) return 'Light Blue';
    if (color == Colors.red.shade700) return 'Dark Red';
    if (color == Colors.red.shade300) return 'Light Red';
    if (color == Colors.green.shade700) return 'Dark Green';
    if (color == Colors.green.shade300) return 'Light Green';
    if (color == Colors.orange.shade700) return 'Dark Orange';
    if (color == Colors.amber.shade600) return 'Amber';
    if (color == Colors.purple.shade700) return 'Purple';
    if (color == Colors.pink.shade400) return 'Pink';
    if (color == Colors.brown.shade600) return 'Brown';
    if (color == Colors.teal.shade600) return 'Teal';
    return 'Custom';
  }

  Widget _buildHandwritingSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: StatefulBuilder(
        builder: (context, setToolbarState) {
          return Stack(
            children: [
              // Handwriting canvas (full space)
              Column(
                children: [
                  // Toolbar only
                  _buildHandwritingToolbar(setToolbarState),
                  // Canvas takes remaining space
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final initialStrokes = _note?.strokes ?? [];
                        debugPrint('🏗️ EventDetail: Building HandwritingCanvas with ${initialStrokes.length} initial strokes');
                        debugPrint('🏗️ EventDetail: _note is ${_note != null ? "not null" : "null"}');
                        return HandwritingCanvas(
                          key: _canvasKey,
                          initialStrokes: initialStrokes,
                          onStrokesChanged: _onStrokesChanged,
                        );
                      },
                    ),
                  ),
                ],
              ),
              // Overlaying control panel
              Positioned(
                top: 48, // Below toolbar
                left: 0,
                right: 0,
                child: _buildControlPanel(setToolbarState),
              ),
            ],
          );
        },
      ),
    );
  }
}