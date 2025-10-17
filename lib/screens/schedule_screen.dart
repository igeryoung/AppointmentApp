import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/book.dart';
import '../models/event.dart';
import '../models/schedule_drawing.dart';
import '../services/prd_database_service.dart';
import '../services/web_prd_database_service.dart';
import '../services/time_service.dart';
import '../widgets/handwriting_canvas.dart';
import 'event_detail_screen.dart';

/// Schedule screen implementing PRD requirements: Day, 3-Day, Week views
class ScheduleScreen extends StatefulWidget {
  final Book book;

  const ScheduleScreen({
    super.key,
    required this.book,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with WidgetsBindingObserver {
  int _selectedViewMode = 1; // 0: Day, 1: 3-Day (default), 2: Week
  late TransformationController _transformationController;
  DateTime _selectedDate = TimeService.instance.now();
  List<Event> _events = [];
  bool _isLoading = false;

  // Date change detection
  DateTime _lastActiveDate = TimeService.instance.now();
  Timer? _dateCheckTimer;

  // Drawing overlay state
  bool _isDrawingMode = false;
  ScheduleDrawing? _currentDrawing;
  // Cache of canvas keys for each unique page (viewMode + date combination)
  final Map<String, GlobalKey<HandwritingCanvasState>> _canvasKeys = {};

  // Event menu and drag state
  Event? _selectedEventForMenu;
  Offset? _menuPosition;

  // Time range settings
  static const double _baseSlotHeight = 60.0; // Base slot height for readable size
  static const int _startHour = 9;  // 9:00 AM
  static const int _endHour = 21;   // 9:00 PM
  static const int _totalSlots = (_endHour - _startHour) * 4; // 48 slots

  // Use appropriate database service based on platform
  dynamic get _dbService => kIsWeb
      ? WebPRDDatabaseService()
      : PRDDatabaseService();

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Start periodic date checking (every minute)
    _startDateCheckTimer();

    _loadEvents();
    _loadDrawing();
  }

  @override
  void dispose() {
    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Cancel date check timer
    _dateCheckTimer?.cancel();

    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      debugPrint('📅 App resumed - checking for date changes');
      _checkAndHandleDateChange();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint('📅 App backgrounding - saving drawing if in drawing mode');
      // Auto-save drawing before going to background
      if (_isDrawingMode) {
        _saveDrawing();
      }
    }
  }

  /// Start timer to periodically check for date changes (every minute)
  void _startDateCheckTimer() {
    _dateCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkAndHandleDateChange();
    });
  }

  /// Check if the system date has changed and handle it
  Future<void> _checkAndHandleDateChange() async {
    final now = TimeService.instance.now();
    final currentDate = DateTime(now.year, now.month, now.day);
    final lastActiveDate = DateTime(_lastActiveDate.year, _lastActiveDate.month, _lastActiveDate.day);

    if (currentDate != lastActiveDate) {
      debugPrint('📅 Date changed detected: $lastActiveDate → $currentDate');

      // Check if user is viewing a window that contains "today" (the new current date)
      // This handles multi-day views (3-Day, Week) correctly
      bool isViewingWindowContainingToday = false;

      switch (_selectedViewMode) {
        case 0: // Day View
          final selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
          isViewingWindowContainingToday = selectedDate == lastActiveDate;
          break;
        case 1: // 3-Day View
          final windowStart = _get3DayWindowStart(_selectedDate);
          final windowEnd = windowStart.add(const Duration(days: 3));
          // Check if the old "today" (lastActiveDate) is in the current viewing window
          isViewingWindowContainingToday = lastActiveDate.isAfter(windowStart.subtract(const Duration(days: 1))) &&
                                          lastActiveDate.isBefore(windowEnd);
          break;
        case 2: // Week View
          final weekStart = _getWeekStart(_selectedDate);
          final weekEnd = weekStart.add(const Duration(days: 7));
          // Check if the old "today" (lastActiveDate) is in the current viewing week
          isViewingWindowContainingToday = lastActiveDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
                                          lastActiveDate.isBefore(weekEnd);
          break;
      }

      if (isViewingWindowContainingToday) {
        debugPrint('📅 User was viewing window containing "today" - auto-updating to new today');

        // Save current drawing before switching dates
        if (_isDrawingMode) {
          await _saveDrawing();
        }

        // Update to new today
        setState(() {
          _selectedDate = now;
          _lastActiveDate = now;
        });

        // Reload events and drawing for new date
        await _loadEvents();
        await _loadDrawing();

        // Show notification to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.dateChangedToToday),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // User is viewing a different window - just update last active date
        debugPrint('📅 User viewing different window - keeping current view');
        _lastActiveDate = now;
      }
    }
  }

  Future<void> _onViewChanged(int? newMode) async {
    if (newMode != null && newMode != _selectedViewMode) {
      // Save current drawing before switching
      if (_isDrawingMode) {
        await _saveDrawing();
      }

      setState(() {
        _selectedViewMode = newMode;
        _selectedDate = TimeService.instance.now(); // Reset to current day when switching modes
      });
      _loadEvents();

      // Always load drawing for new view (canvas is always visible)
      await _loadDrawing();

      // Pan/zoom to current time after view switch
      _panToCurrentTime();
    }
  }

  /// Get unique page identifier for the current view and date
  String _getPageId() {
    // Normalize date to midnight for consistent keys
    DateTime normalizedDate;
    if (_selectedViewMode == 1) {
      // For 3-day mode, use window start to keep same page across days in window
      normalizedDate = _get3DayWindowStart(_selectedDate);
    } else {
      normalizedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    }
    return '${_selectedViewMode}_${normalizedDate.millisecondsSinceEpoch}';
  }

  /// Get or create canvas key for the current page
  GlobalKey<HandwritingCanvasState> _getCanvasKeyForCurrentPage() {
    final pageId = _getPageId();
    if (!_canvasKeys.containsKey(pageId)) {
      _canvasKeys[pageId] = GlobalKey<HandwritingCanvasState>();
    }
    return _canvasKeys[pageId]!;
  }

  /// Get canvas key for a specific view mode (used by view builders)
  GlobalKey<HandwritingCanvasState> _getCanvasKeyForView(int viewMode) {
    // Temporarily compute page ID for the given view mode
    DateTime normalizedDate;
    if (viewMode == 1) {
      // For 3-day mode, use window start to keep same page across days in window
      normalizedDate = _get3DayWindowStart(_selectedDate);
    } else {
      normalizedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    }
    final pageId = '${viewMode}_${normalizedDate.millisecondsSinceEpoch}';
    if (!_canvasKeys.containsKey(pageId)) {
      _canvasKeys[pageId] = GlobalKey<HandwritingCanvasState>();
    }
    return _canvasKeys[pageId]!;
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    try {
      // Use effective date to ensure consistency with UI rendering
      final effectiveDate = _getEffectiveDate();

      List<Event> events;
      switch (_selectedViewMode) {
        case 0: // Day View
          events = await _dbService.getEventsByDay(widget.book.id!, effectiveDate);
          break;
        case 1: // 3-Day View
          // effectiveDate is already the window start from _get3DayWindowStart()
          events = await _dbService.getEventsBy3Days(widget.book.id!, effectiveDate);
          break;
        case 2: // Week View
          // effectiveDate is already the week start from _getWeekStart()
          events = await _dbService.getEventsByWeek(widget.book.id!, effectiveDate);
          break;
        default:
          events = [];
      }

      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorLoadingEvents(e.toString()))),
        );
      }
    }
  }

  Future<void> _loadDrawing() async {
    try {
      // Reset current drawing to avoid carrying old IDs
      setState(() {
        _currentDrawing = null;
      });

      // Use effective date to ensure consistency with UI rendering
      // For 3-Day View, this uses the window start date
      final effectiveDate = _getEffectiveDate();

      final drawing = await _dbService.getScheduleDrawing(
        widget.book.id!,
        effectiveDate,
        _selectedViewMode,
      );

      setState(() {
        _currentDrawing = drawing;
      });

      // Load strokes into canvas if drawing exists
      // Use post-frame callback to ensure canvas is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final canvasKey = _getCanvasKeyForCurrentPage();
        if (drawing != null && drawing.strokes.isNotEmpty) {
          debugPrint('📖 Loading ${drawing.strokes.length} strokes for page ${_getPageId()} (effectiveDate: $effectiveDate)');
          canvasKey.currentState?.loadStrokes(drawing.strokes);
        } else {
          debugPrint('📖 Clearing canvas for empty page ${_getPageId()} (effectiveDate: $effectiveDate)');
          canvasKey.currentState?.clear();
        }
      });
    } catch (e) {
      debugPrint('❌ Error loading drawing: $e');
    }
  }

  Future<void> _saveDrawing() async {
    final canvasState = _getCanvasKeyForCurrentPage().currentState;
    if (canvasState == null) {
      debugPrint('⚠️ Cannot save: canvas state is null');
      return;
    }

    try {
      final strokes = canvasState.getStrokes();
      final now = TimeService.instance.now();

      // Use effective date to ensure consistency with UI rendering
      // For 3-Day View, this uses the window start date
      final effectiveDate = _getEffectiveDate();

      // Only use existing ID if it matches the current page
      // This prevents reusing old IDs when switching pages
      int? drawingId;
      DateTime? createdAt;
      if (_currentDrawing != null &&
          _currentDrawing!.bookId == widget.book.id! &&
          _currentDrawing!.viewMode == _selectedViewMode &&
          _currentDrawing!.date.year == effectiveDate.year &&
          _currentDrawing!.date.month == effectiveDate.month &&
          _currentDrawing!.date.day == effectiveDate.day) {
        drawingId = _currentDrawing!.id;
        createdAt = _currentDrawing!.createdAt;
      }

      final drawing = ScheduleDrawing(
        id: drawingId,
        bookId: widget.book.id!,
        date: effectiveDate,
        viewMode: _selectedViewMode,
        strokes: strokes,
        createdAt: createdAt ?? now,
        updatedAt: now,
      );

      debugPrint('💾 Saving ${strokes.length} strokes for page ${_getPageId()} (effectiveDate: $effectiveDate, id: $drawingId)');
      final savedDrawing = await _dbService.updateScheduleDrawing(drawing);
      setState(() {
        _currentDrawing = savedDrawing;
      });
      debugPrint('✅ Save successful, new id: ${savedDrawing.id}');
    } catch (e) {
      debugPrint('❌ Error saving drawing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorSavingDrawing(e.toString()))),
        );
      }
    }
  }

  Future<void> _toggleDrawingMode() async {
    if (_isDrawingMode) {
      // Exiting drawing mode - save drawing first
      await _saveDrawing();
      setState(() {
        _isDrawingMode = false;
      });
    } else {
      // Entering drawing mode
      setState(() {
        _isDrawingMode = true;
      });
      // Load drawing after state update
      await _loadDrawing();
    }
  }

  DateTime _get3DayWindowStart(DateTime date) {
    // Use fixed anchor to calculate stable 3-day windows
    // This ensures the same 3-day window is shown even when the real-world date changes
    final anchor = DateTime(2000, 1, 1); // Fixed epoch anchor
    final daysSinceAnchor = date.difference(anchor).inDays;
    final windowIndex = daysSinceAnchor ~/ 3;
    final windowStart = anchor.add(Duration(days: windowIndex * 3));
    return DateTime(windowStart.year, windowStart.month, windowStart.day);
  }

  DateTime _getWeekStart(DateTime date) {
    // Calculate Monday of the week, normalized to start of day (midnight)
    final daysFromMonday = date.weekday - 1;
    final monday = date.subtract(Duration(days: daysFromMonday));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// Get the effective date for data operations (loading/saving events and drawings)
  /// This ensures consistency between UI rendering and data layer
  DateTime _getEffectiveDate() {
    switch (_selectedViewMode) {
      case 0: // Day View
        return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      case 1: // 3-Day View
        return _get3DayWindowStart(_selectedDate);
      case 2: // Week View
        return _getWeekStart(_selectedDate);
      default:
        return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    }
  }

  void _panToCurrentTime() {
    // Reset transformation to default view (scale 1.0, no pan)
    // At default zoom, all time slots are visible including current time
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transformationController.value = Matrix4.identity();
    });
  }

  Duration _getNavigationIncrement() {
    switch (_selectedViewMode) {
      case 0: // Day View
        return const Duration(days: 1);
      case 1: // 3-Day View
        return const Duration(days: 3);
      case 2: // Week View
        return const Duration(days: 7);
      default:
        return const Duration(days: 1);
    }
  }

  /// Check if currently viewing today's date
  bool _isViewingToday() {
    final now = TimeService.instance.now();
    final today = DateTime(now.year, now.month, now.day);
    final viewingDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return viewingDate == today;
  }

  Future<void> _createEvent({DateTime? startTime}) async {
    final now = TimeService.instance.now();
    final defaultStartTime = startTime ??
        DateTime(now.year, now.month, now.day, now.hour, (now.minute ~/ 15) * 15);

    final newEvent = Event(
      bookId: widget.book.id!,
      name: '',
      recordNumber: '',
      eventType: '',
      startTime: defaultStartTime,
      createdAt: now,
      updatedAt: now,
    );

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EventDetailScreen(
          event: newEvent,
          isNew: true,
        ),
      ),
    );

    if (result == true) {
      _loadEvents();
    }
  }

  Future<void> _editEvent(Event event) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EventDetailScreen(
          event: event,
          isNew: false,
        ),
      ),
    );

    if (result == true) {
      _loadEvents();
    }
  }

  void _showEventContextMenu(Event event, Offset position) {
    setState(() {
      _selectedEventForMenu = event;
      _menuPosition = position;
    });
  }

  void _closeEventMenu() {
    setState(() {
      _selectedEventForMenu = null;
      _menuPosition = null;
    });
  }

  Future<void> _handleMenuAction(String action, Event event) async {
    if (action == 'changeType') {
      await _changeEventType(event);
      _closeEventMenu();
    } else if (action == 'remove') {
      await _removeEventFromSchedule(event);
      _closeEventMenu();
    } else if (action == 'delete') {
      await _deleteEventFromSchedule(event);
      _closeEventMenu();
    }
  }

  Future<void> _handleEventDrop(Event event, DateTime newStartTime) async {
    // Check if time actually changed
    if (event.startTime.year == newStartTime.year &&
        event.startTime.month == newStartTime.month &&
        event.startTime.day == newStartTime.day &&
        event.startTime.hour == newStartTime.hour &&
        event.startTime.minute == newStartTime.minute) {
      _closeEventMenu();
      return;
    }

    final l10n = AppLocalizations.of(context)!;

    // Show reason dialog
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final reasonController = TextEditingController(text: l10n.timeChangedViaDrag);
        return AlertDialog(
          title: Text(l10n.changeEventType),
          content: TextField(
            controller: reasonController,
            decoration: InputDecoration(
              labelText: l10n.reasonForTimeChangeLabel,
              hintText: l10n.enterReasonHint,
            ),
            autofocus: true,
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                if (reasonController.text.trim().isNotEmpty) {
                  Navigator.pop(context, reasonController.text.trim());
                }
              },
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );

    if (reason != null && reason.isNotEmpty) {
      try {
        // Calculate new end time if original event had one
        DateTime? newEndTime;
        if (event.endTime != null) {
          final duration = event.endTime!.difference(event.startTime);
          newEndTime = newStartTime.add(duration);
        }

        await _dbService.changeEventTime(event, newStartTime, newEndTime, reason);
        _closeEventMenu();
        _loadEvents();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.eventTimeChangedSuccessfully)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorChangingTime(e.toString()))),
          );
        }
      }
    } else {
      _closeEventMenu();
    }
  }

  Future<void> _changeEventType(Event event) async {
    final l10n = AppLocalizations.of(context)!;
    final eventTypes = [
      l10n.consultation,
      l10n.surgery,
      l10n.followUp,
      l10n.emergency,
      l10n.checkUp,
      l10n.treatment,
    ];

    final selectedType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changeEventType),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: eventTypes.map((type) => ListTile(
            title: Text(type),
            leading: Radio<String>(
              value: type,
              groupValue: event.eventType,
              onChanged: (value) => Navigator.pop(context, value),
            ),
            onTap: () => Navigator.pop(context, type),
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );

    if (selectedType != null && selectedType != event.eventType) {
      try {
        final updatedEvent = event.copyWith(
          eventType: selectedType,
          updatedAt: TimeService.instance.now(),
        );
        await _dbService.updateEvent(updatedEvent);
        _loadEvents();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.eventTypeChanged)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorUpdatingEvent(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _removeEventFromSchedule(Event event) async {
    final l10n = AppLocalizations.of(context)!;

    // Show reason dialog
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final reasonController = TextEditingController();
        return AlertDialog(
          title: Text(l10n.removeEvent),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.removeEventDescription),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: l10n.reasonForRemovalLabel,
                  hintText: l10n.enterReasonHint,
                ),
                autofocus: true,
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                if (reasonController.text.trim().isNotEmpty) {
                  Navigator.pop(context, reasonController.text.trim());
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    );

    if (reason != null && reason.isNotEmpty) {
      try {
        await _dbService.removeEvent(event.id!, reason);
        _loadEvents();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.eventRemovedSuccessfully)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorRemovingEventMessage(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _deleteEventFromSchedule(Event event) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteEvent),
        content: Text(l10n.confirmDeleteEvent(event.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _dbService.deleteEvent(event.id!);
        _loadEvents();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.eventDeleted)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorDeletingEvent(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _showGenerateEventsDialog() async {
    final controller = TextEditingController(text: '5');
    bool clearAll = false;
    bool openEndOnly = false;

    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.generateRandomEvents),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: l10n.numberOfEvents,
                  hintText: l10n.enterNumber,
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: Text(l10n.clearAllExistingEventsFirst),
                value: clearAll,
                onChanged: (value) {
                  setState(() {
                    clearAll = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              CheckboxListTile(
                title: Text(l10n.generateOpenEndedEventsOnly),
                subtitle: Text(l10n.noEndTime),
                value: openEndOnly,
                onChanged: (value) {
                  setState(() {
                    openEndOnly = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                final value = int.tryParse(controller.text);
                if (value != null && value > 0 && value <= 50) {
                  Navigator.pop(context, {
                    'count': value,
                    'clearAll': clearAll,
                    'openEndOnly': openEndOnly,
                  });
                }
              },
              child: Text(l10n.generate),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _generateRandomEvents(
        result['count'] as int,
        clearAll: result['clearAll'] as bool,
        openEndOnly: result['openEndOnly'] as bool,
      );
    }
  }

  /// Show test time dialog for testing time change behavior
  Future<void> _showTestTimeDialog() async {
    final l10n = AppLocalizations.of(context)!;
    // If test mode is active, show option to reset
    if (TimeService.instance.isTestMode) {
      final reset = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.testTimeActive),
          content: Text(
            l10n.currentTestTime(DateFormat('yyyy-MM-dd HH:mm:ss').format(TimeService.instance.overrideTime!)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.resetToRealTime),
            ),
          ],
        ),
      );

      if (reset == true) {
        TimeService.instance.resetToRealTime();
        setState(() {
          _selectedDate = TimeService.instance.now();
          _lastActiveDate = TimeService.instance.now();
        });
        await _loadEvents();
        await _loadDrawing();
      }
      return;
    }

    // Show date and time picker
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: TimeService.instance.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (selectedDate == null || !mounted) return;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(TimeService.instance.now()),
    );

    if (selectedTime == null || !mounted) return;

    final testTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    TimeService.instance.setTestTime(testTime);
    setState(() {
      _selectedDate = TimeService.instance.now();
      _lastActiveDate = TimeService.instance.now();
    });
    await _loadEvents();
    await _loadDrawing();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.testTimeSetTo(DateFormat('yyyy-MM-dd HH:mm').format(testTime))),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _clearAllEventsInView() async {
    if (_events.isEmpty) return;

    final eventIds = _events.where((e) => e.id != null).map((e) => e.id!).toList();

    for (final id in eventIds) {
      try {
        await _dbService.deleteEvent(id);
      } catch (e) {
        debugPrint('Error deleting event $id: $e');
      }
    }

    await _loadEvents();
  }

  Future<void> _generateRandomEvents(
    int count, {
    bool clearAll = false,
    bool openEndOnly = false,
  }) async {
    // Clear existing events if requested
    if (clearAll) {
      await _clearAllEventsInView();
    }

    final l10n = AppLocalizations.of(context)!;
    final random = Random();
    final now = TimeService.instance.now();

    // Get available event types
    final eventTypes = [
      l10n.consultation,
      l10n.surgery,
      l10n.followUp,
      l10n.emergency,
      l10n.checkUp,
      l10n.treatment,
    ];

    // Get date range based on current view
    List<DateTime> availableDates;
    switch (_selectedViewMode) {
      case 0: // Day View
        availableDates = [_selectedDate];
        break;
      case 1: // 3-Day View
        final windowStart = _get3DayWindowStart(_selectedDate);
        availableDates = List.generate(3, (i) => windowStart.add(Duration(days: i)));
        break;
      case 2: // Week View
        final weekStart = _getWeekStart(_selectedDate);
        availableDates = List.generate(7, (i) => weekStart.add(Duration(days: i)));
        break;
      default:
        availableDates = [_selectedDate];
    }

    int created = 0;
    int attempts = 0;
    final maxAttempts = count * 10; // Prevent infinite loop

    while (created < count && attempts < maxAttempts) {
      attempts++;

      // Random date from available dates
      final date = availableDates[random.nextInt(availableDates.length)];

      // Random time slot (9 AM - 9 PM, 15-min intervals)
      final slotIndex = random.nextInt(_totalSlots);
      final hour = _startHour + (slotIndex ~/ 4);
      final minute = (slotIndex % 4) * 15;

      final startTime = DateTime(date.year, date.month, date.day, hour, minute);

      // Check if this time slot already has 4 events
      final eventsAtSlot = _events.where((e) {
        return e.startTime.year == startTime.year &&
               e.startTime.month == startTime.month &&
               e.startTime.day == startTime.day &&
               e.startTime.hour == startTime.hour &&
               e.startTime.minute == startTime.minute;
      }).length;

      if (eventsAtSlot >= 4) {
        continue; // Skip this slot, try another
      }

      // Random duration (15, 30, 45, or 60 minutes) or null for open-ended
      DateTime? endTime;
      if (!openEndOnly) {
        final durations = [15, 30, 45, 60];
        final duration = durations[random.nextInt(durations.length)];
        endTime = startTime.add(Duration(minutes: duration));
      }

      // Random event type
      final eventType = eventTypes[random.nextInt(eventTypes.length)];

      // Random name
      final names = [
        '王小明', '李小華', '張美玲', '陳志豪',
        '林淑芬', '黃建國', '吳雅婷', '鄭明哲',
        '劉佳穎', '許文祥', '楊淑惠', '蔡明道',
      ];
      final name = names[random.nextInt(names.length)];

      // Random record number
      final recordNumber = 'REC-${random.nextInt(90000) + 10000}';

      final event = Event(
        bookId: widget.book.id!,
        name: name,
        recordNumber: recordNumber,
        eventType: eventType,
        startTime: startTime,
        endTime: endTime,
        createdAt: now,
        updatedAt: now,
      );

      try {
        await _dbService.createEvent(event);
        created++;
      } catch (e) {
        debugPrint('Error creating random event: $e');
      }
    }

    // Reload events to show the new ones
    await _loadEvents();

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      String message;
      if (clearAll && openEndOnly) {
        message = created == count
            ? l10n.clearedAndGeneratedOpenEndedEvents(created)
            : l10n.clearedAndGeneratedOpenEndedEventsSomeFull(created);
      } else if (clearAll) {
        message = created == count
            ? l10n.clearedAndGeneratedEvents(created)
            : l10n.clearedAndGeneratedEventsSomeFull(created);
      } else if (openEndOnly) {
        message = created == count
            ? l10n.generatedOpenEndedEvents(created)
            : l10n.generatedOpenEndedEventsSomeFull(created);
      } else {
        message = created == count
            ? l10n.generatedEvents(created)
            : l10n.generatedEventsSomeFull(created);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final viewModeOptions = [l10n.day, l10n.threeDays, l10n.week];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // View mode dropdown
            DropdownButton<int>(
              value: _selectedViewMode,
              onChanged: _onViewChanged,
              underline: const SizedBox(),
              dropdownColor: Theme.of(context).primaryColor,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              items: List.generate(viewModeOptions.length, (index) {
                return DropdownMenuItem<int>(
                  value: index,
                  child: Text(viewModeOptions[index]),
                );
              }),
            ),
            const SizedBox(width: 8),
            // Date navigation - Previous button
            IconButton(
              onPressed: () async {
                if (_isDrawingMode) await _saveDrawing();
                setState(() {
                  _selectedDate = _selectedDate.subtract(_getNavigationIncrement());
                });
                _loadEvents();
                await _loadDrawing();
              },
              icon: const Icon(Icons.chevron_left, size: 18),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
            // Date display
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    if (_isDrawingMode) await _saveDrawing();
                    setState(() {
                      _selectedDate = date;
                    });
                    _loadEvents();
                    await _loadDrawing();
                  }
                },
                child: Text(
                  _getDateDisplayText(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
            // Date navigation - Next button
            IconButton(
              onPressed: () async {
                if (_isDrawingMode) await _saveDrawing();
                setState(() {
                  _selectedDate = _selectedDate.add(_getNavigationIncrement());
                });
                _loadEvents();
                await _loadDrawing();
              },
              icon: const Icon(Icons.chevron_right, size: 18),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _selectedDate = TimeService.instance.now();
                _lastActiveDate = TimeService.instance.now();
              });
              _loadEvents();
              _panToCurrentTime();
            },
            tooltip: l10n.goToToday,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : IndexedStack(
                        index: _selectedViewMode,
                        children: [
                          _buildDayView(),
                          _build3DayView(),
                          _buildWeekView(),
                        ],
                      ),
              ),
            ],
          ),
          // Drawing toolbar overlay (positioned on top of date header)
          if (_isDrawingMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildDrawingToolbar(),
            ),
          // Event context menu overlay
          if (_buildEventContextMenuOverlay() != null)
            _buildEventContextMenuOverlay()!,
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Test Time FAB (for testing time change behavior)
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return FloatingActionButton.small(
                heroTag: 'test_time',
                onPressed: _showTestTimeDialog,
                backgroundColor: TimeService.instance.isTestMode ? Colors.red : Colors.grey.shade700,
                child: Icon(
                  TimeService.instance.isTestMode ? Icons.schedule : Icons.access_time,
                  size: 20,
                ),
                tooltip: TimeService.instance.isTestMode ? l10n.resetToRealTime : l10n.testTimeActive,
              );
            },
          ),
          const SizedBox(height: 12),
          // Go to Today FAB (only show when not viewing today)
          if (!_isViewingToday())
            FloatingActionButton(
              heroTag: 'goto_today',
              onPressed: () async {
                if (_isDrawingMode) await _saveDrawing();
                setState(() {
                  _selectedDate = TimeService.instance.now();
                  _lastActiveDate = TimeService.instance.now();
                });
                _loadEvents();
                _loadDrawing();
              },
              backgroundColor: Colors.green,
              child: const Icon(Icons.today),
              tooltip: AppLocalizations.of(context)!.goToTodayTooltip,
            ),
          if (!_isViewingToday())
            const SizedBox(height: 12),
          // Generate random events FAB (disabled in drawing mode)
          FloatingActionButton(
            heroTag: 'generate_events',
            onPressed: _isDrawingMode ? null : _showGenerateEventsDialog,
            backgroundColor: _isDrawingMode ? Colors.grey : Colors.purple,
            child: const Icon(Icons.science),
            tooltip: _isDrawingMode ? null : 'Generate Random Events',
          ),
          const SizedBox(height: 12),
          // Drawing mode toggle FAB
          FloatingActionButton(
            heroTag: 'drawing_toggle',
            onPressed: _toggleDrawingMode,
            backgroundColor: _isDrawingMode ? Colors.orange : Colors.blue,
            child: Icon(_isDrawingMode ? Icons.draw : Icons.draw_outlined),
            tooltip: _isDrawingMode ? 'Exit Drawing Mode' : 'Enter Drawing Mode',
          ),
          const SizedBox(height: 12),
          // Create event FAB (disabled in drawing mode)
          FloatingActionButton(
            heroTag: 'create_event',
            onPressed: _isDrawingMode ? null : () => _createEvent(),
            backgroundColor: _isDrawingMode ? Colors.grey : null,
            child: const Icon(Icons.add),
            tooltip: l10n.createEvent,
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () async {
              // Save current drawing before navigating
              if (_isDrawingMode) {
                await _saveDrawing();
              }
              setState(() {
                _selectedDate = _selectedDate.subtract(_getNavigationIncrement());
              });
              _loadEvents();
              // Always load drawing for new date (canvas is always visible)
              await _loadDrawing();
            },
            icon: const Icon(Icons.chevron_left, size: 20),
            iconSize: 20,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          GestureDetector(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                // Save current drawing before changing date
                if (_isDrawingMode) {
                  await _saveDrawing();
                }
                setState(() {
                  _selectedDate = date;
                });
                _loadEvents();
                // Always load drawing for new date (canvas is always visible)
                await _loadDrawing();
              }
            },
            child: Text(
              _getDateDisplayText(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            onPressed: () async {
              // Save current drawing before navigating
              if (_isDrawingMode) {
                await _saveDrawing();
              }
              setState(() {
                _selectedDate = _selectedDate.add(_getNavigationIncrement());
              });
              _loadEvents();
              // Always load drawing for new date (canvas is always visible)
              await _loadDrawing();
            },
            icon: const Icon(Icons.chevron_right, size: 20),
            iconSize: 20,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  String _getDateDisplayText() {
    switch (_selectedViewMode) {
      case 0: // Day
        return DateFormat('EEEE, MMM d, y').format(_selectedDate);
      case 1: // 3-Day
        final endDate = _selectedDate.add(const Duration(days: 2));
        return '${DateFormat('MMM d').format(_selectedDate)} - ${DateFormat('MMM d, y').format(endDate)}';
      case 2: // Week
        final weekStart = _getWeekStart(_selectedDate);
        final weekEnd = weekStart.add(const Duration(days: 6));
        return '${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d, y').format(weekEnd)}';
      default:
        return DateFormat('MMM d, y').format(_selectedDate);
    }
  }

  Widget _buildDayView() {
    return _buildTimeSlotView([_selectedDate], _getCanvasKeyForView(0));
  }

  Widget _build3DayView() {
    // Use stable 3-day window instead of _selectedDate to prevent page changes on date changes
    final windowStart = _get3DayWindowStart(_selectedDate);
    final dates = List.generate(3, (index) => windowStart.add(Duration(days: index)));
    return _buildTimeSlotView(dates, _getCanvasKeyForView(1));
  }

  Widget _buildWeekView() {
    final weekStart = _getWeekStart(_selectedDate);
    final dates = List.generate(7, (index) => weekStart.add(Duration(days: index)));
    return _buildTimeSlotView(dates, _getCanvasKeyForView(2));
  }

  Widget _buildTimeSlotView(
    List<DateTime> dates,
    GlobalKey<HandwritingCanvasState> canvasKey,
  ) {
    final now = TimeService.instance.now();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate dynamic slot height to fit screen perfectly
        final dateHeaderHeight = dates.length > 1 ? 50.0 : 0.0;
        final availableHeightForSlots = constraints.maxHeight - dateHeaderHeight;
        final slotHeight = availableHeightForSlots / _totalSlots;

        // Content dimensions - exactly match screen
        final contentWidth = constraints.maxWidth;
        final contentHeight = constraints.maxHeight;

        debugPrint('📐 Schedule Layout: constraints=(${constraints.maxWidth.toStringAsFixed(2)}, ${constraints.maxHeight.toStringAsFixed(2)}) dateHeader=${dateHeaderHeight.toStringAsFixed(2)} availableForSlots=${availableHeightForSlots.toStringAsFixed(2)} viewMode=$_selectedViewMode drawingMode=$_isDrawingMode');

        return InteractiveViewer(
          transformationController: _transformationController,
          minScale: 1.0, // Cannot zoom out - this IS the most zoomed out
          maxScale: 4.0, // Max zoom in
          boundaryMargin: EdgeInsets.zero, // Strict boundaries - no blank space
          constrained: true, // Respect size constraints
          panEnabled: !_isDrawingMode, // Disable pan when drawing
          scaleEnabled: true, // Always allow pinch zoom
          child: SizedBox(
            width: contentWidth,
            height: contentHeight,
            child: Column(
              children: [
                // Date headers - zoom/pan with content
                if (dates.length > 1)
                  Container(
                    height: dateHeaderHeight,
                    child: Row(
                      children: [
                        const SizedBox(width: 60), // Time column width
                        ...dates.map((date) => Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              DateFormat('EEE d').format(date),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                // Time slots + events + drawing overlay
                Expanded(
                  child: Stack(
                    children: [
                      // Schedule grid (dimmed when in drawing mode)
                      Opacity(
                        opacity: _isDrawingMode ? 0.6 : 1.0,
                        child: AbsorbPointer(
                          absorbing: _isDrawingMode, // Disable event interactions in drawing mode
                          child: Stack(
                            children: [
                              // Time slot grid
                              Column(
                                children: List.generate(_totalSlots, (index) {
                                  return _buildTimeSlot(index, dates, slotHeight);
                                }),
                              ),
                              // Current time indicator
                              _buildCurrentTimeIndicator(dates, now, slotHeight),
                              // Events overlay - positioned absolutely to span multiple slots
                              _buildEventsOverlay(dates, slotHeight, dateHeaderHeight),
                            ],
                          ),
                        ),
                      ),
                      // Drawing overlay - same coordinate space as grid
                      IgnorePointer(
                        ignoring: !_isDrawingMode, // Only allow drawing when in drawing mode
                        child: HandwritingCanvas(
                          key: canvasKey,
                          initialStrokes: _currentDrawing?.strokes ?? [],
                          onStrokesChanged: () {
                            // Auto-save on stroke changes
                            if (_isDrawingMode) {
                              _saveDrawing();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentTimeIndicator(List<DateTime> dates, DateTime now, double slotHeight) {
    // Only show indicator if current time is within visible range
    if (now.hour < _startHour || now.hour >= _endHour) {
      return const SizedBox.shrink();
    }

    // Calculate the precise position based on current time relative to _startHour
    final totalMinutesFromStart = (now.hour - _startHour) * 60 + now.minute;
    final minutesPerSlot = 15;
    // Calculate absolute position from top of the content
    final yPosition = (totalMinutesFromStart / minutesPerSlot) * slotHeight;

    return Positioned(
      top: yPosition,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Row(
          children: [
            const SizedBox(width: 60), // Time column offset
            ...dates.asMap().entries.map((entry) {
              final date = entry.value;
              final isToday = date.year == now.year &&
                             date.month == now.month &&
                             date.day == now.day;

              return Expanded(
                child: isToday
                    ? CustomPaint(
                        painter: const CurrentTimeLinePainter(),
                        size: const Size(double.infinity, 2),
                      )
                    : const SizedBox.shrink(),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSlot(int index, List<DateTime> dates, double slotHeight) {
    final hour = _startHour + (index ~/ 4);
    final minute = (index % 4) * 15;
    final timeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    return Container(
      height: slotHeight,
      child: Row(
        children: [
          // Time label - only show on hour boundaries
          Container(
            width: 60,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              timeStr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
              ),
            ),
          ),
          // Grid cells for each date (events rendered separately in overlay)
          ...dates.map((date) {
            return Expanded(
              child: DragTarget<Event>(
                onWillAcceptWithDetails: (details) => !_isDrawingMode,
                onAcceptWithDetails: (details) {
                  final newStartTime = DateTime(date.year, date.month, date.day, hour, minute);
                  _handleEventDrop(details.data, newStartTime);
                },
                builder: (context, candidateData, rejectedData) {
                  final isHovering = candidateData.isNotEmpty;
                  return GestureDetector(
                    onTap: () {
                      if (_selectedEventForMenu != null) {
                        _closeEventMenu();
                      } else {
                        final startTime = DateTime(date.year, date.month, date.day, hour, minute);
                        _createEvent(startTime: startTime);
                      }
                    },
                    child: Container(
                      height: slotHeight,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isHovering ? Colors.blue.shade300 : Colors.grey.shade400,
                          width: isHovering ? 2.0 : 0.5,
                        ),
                        color: isHovering ? Colors.blue.shade50.withOpacity(0.3) : null,
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Determine if an event should be displayed as open-end (single slot)
  bool _shouldDisplayAsOpenEnd(Event event) {
    // Removed events or old events with new time should be displayed as open-end (single slot)
    // NEW events (isTimeChanged) should display normally with full duration
    return event.isRemoved || event.hasNewTime || event.isOpenEnded;
  }

  /// Get the display duration in minutes for an event
  int _getDisplayDurationInMinutes(Event event) {
    if (_shouldDisplayAsOpenEnd(event)) {
      return 15; // Always 15 minutes (1 slot) for open-end display
    }
    return event.durationInMinutes ?? 15;
  }

  /// Build events overlay with absolute positioning to allow spanning multiple time slots
  Widget _buildEventsOverlay(List<DateTime> dates, double slotHeight, double dateHeaderHeight) {
    return Row(
      children: [
        const SizedBox(width: 60), // Time column width
        ...dates.map((date) {
          final dateEvents = _getEventsForDate(date);

          return Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth - 4; // Account for padding/borders
                final eventWidth = availableWidth / 4;

                // Build slot occupancy map: slot index -> set of occupied horizontal positions (0-3)
                final Map<int, Set<int>> slotOccupancy = {};

                // Group events by start time slot
                final Map<int, List<Event>> eventsBySlot = {};
                for (final event in dateEvents) {
                  final slotIndex = _getSlotIndexForTime(event.startTime);
                  eventsBySlot.putIfAbsent(slotIndex, () => []).add(event);
                }

                // Build positioned widgets
                final List<Widget> positionedWidgets = [];

                // Process events in order of time slots
                final sortedSlotIndices = eventsBySlot.keys.toList()..sort();

                for (final slotIndex in sortedSlotIndices) {
                  final slotEvents = eventsBySlot[slotIndex]!;

                  // Separate close-end and open-end events
                  final closeEndEvents = slotEvents.where((e) => !_shouldDisplayAsOpenEnd(e)).toList();
                  final openEndEvents = slotEvents.where((e) => _shouldDisplayAsOpenEnd(e)).toList();

                  // Sort each list by ID
                  closeEndEvents.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
                  openEndEvents.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));

                  // Process in order: close-end events first, then open-end events
                  final orderedEvents = [...closeEndEvents, ...openEndEvents];

                  for (final event in orderedEvents) {
                    // Calculate display duration and slots spanned
                    final durationInMinutes = _getDisplayDurationInMinutes(event);
                    final slotsSpanned = ((durationInMinutes / 15).ceil()).clamp(1, 48);

                    // Find leftmost available horizontal position across all spanned slots
                    int horizontalPosition = 0;
                    bool positionFound = false;

                    for (int pos = 0; pos < 4; pos++) {
                      bool positionAvailable = true;

                      // Check if this position is available in all spanned slots
                      for (int spanOffset = 0; spanOffset < slotsSpanned; spanOffset++) {
                        final checkSlot = slotIndex + spanOffset;
                        if (slotOccupancy[checkSlot]?.contains(pos) ?? false) {
                          positionAvailable = false;
                          break;
                        }
                      }

                      if (positionAvailable) {
                        horizontalPosition = pos;
                        positionFound = true;
                        break;
                      }
                    }

                    // If no position found, skip this event (shouldn't happen with max 4 events)
                    if (!positionFound) {
                      debugPrint('⚠️ No position found for event ${event.id} at slot $slotIndex');
                      continue;
                    }

                    // Mark position as occupied in all spanned slots
                    for (int spanOffset = 0; spanOffset < slotsSpanned; spanOffset++) {
                      final occupySlot = slotIndex + spanOffset;
                      slotOccupancy.putIfAbsent(occupySlot, () => {}).add(horizontalPosition);
                    }

                    // Calculate position and height
                    final topPosition = _calculateEventTopPosition(event, slotHeight);
                    final tileHeight = (slotsSpanned * slotHeight) - 2; // Subtract margin

                    // Create positioned widget
                    positionedWidgets.add(
                      Positioned(
                        top: topPosition,
                        left: horizontalPosition * eventWidth,
                        width: eventWidth,
                        height: tileHeight,
                        child: Padding(
                          padding: const EdgeInsets.all(1),
                          child: _buildEventTile(event, slotHeight),
                        ),
                      ),
                    );
                  }
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: positionedWidgets,
                );
              },
            ),
          );
        }),
      ],
    );
  }

  /// Get slot index (0-47) for a given time
  int _getSlotIndexForTime(DateTime time) {
    final minutesFromStart = (time.hour - _startHour) * 60 + time.minute;
    return minutesFromStart ~/ 15;
  }

  List<Event> _getEventsForTimeSlot(DateTime date, int hour, int minute) {
    return _events.where((event) {
      return event.startTime.year == date.year &&
             event.startTime.month == date.month &&
             event.startTime.day == date.day &&
             event.startTime.hour == hour &&
             event.startTime.minute >= minute &&
             event.startTime.minute < minute + 15;
    }).toList();
  }

  /// Get all events for a specific date (used for overlay rendering)
  List<Event> _getEventsForDate(DateTime date) {
    return _events.where((event) {
      return event.startTime.year == date.year &&
             event.startTime.month == date.month &&
             event.startTime.day == date.day;
    }).toList();
  }

  /// Calculate the Y position offset for an event based on its start time
  double _calculateEventTopPosition(Event event, double slotHeight) {
    final totalMinutesFromStart = (event.startTime.hour - _startHour) * 60 + event.startTime.minute;
    final minutesPerSlot = 15;
    return (totalMinutesFromStart / minutesPerSlot) * slotHeight;
  }

  /// Get the new event that this event was moved to (if it has a newEventId)
  Event? _getNewEventForTimeChange(Event event) {
    if (event.newEventId == null) return null;
    try {
      return _events.firstWhere((e) => e.id == event.newEventId);
    } catch (e) {
      return null;
    }
  }

  /// Format the new time info for display
  String _getNewTimeDisplay(Event? newEvent) {
    if (newEvent == null) return '';
    return '→ ${DateFormat('MMM d, HH:mm').format(newEvent.startTime)}';
  }

  Widget _buildEventTile(Event event, double slotHeight) {
    // Calculate how many 15-minute slots this event spans
    final durationInMinutes = _getDisplayDurationInMinutes(event);
    final slotsSpanned = ((durationInMinutes / 15).ceil()).clamp(1, 16); // Max 4 hours
    final tileHeight = (slotsSpanned * slotHeight) - 2; // Subtract margin

    final isMenuOpen = _selectedEventForMenu?.id == event.id;

    Widget eventWidget = GestureDetector(
      onTap: isMenuOpen ? null : () => _editEvent(event),
      onLongPressStart: (details) {
        if (!isMenuOpen) {
          _showEventContextMenu(event, details.globalPosition);
        }
      },
      child: Container(
        height: tileHeight,
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        decoration: BoxDecoration(
          color: event.isRemoved
              ? _getEventTypeColor(event.eventType).withOpacity(0.3)
              : _getEventTypeColor(event.eventType),
          borderRadius: BorderRadius.circular(2),
          border: isMenuOpen
              ? Border.all(color: Colors.white, width: 2)
              : event.isRemoved
              ? Border.all(
                  color: _getEventTypeColor(event.eventType).withOpacity(0.6),
                  width: 1,
                  style: BorderStyle.solid,
                )
              : null,
        ),
        child: Stack(
          children: [
            // Dotted line overlay for removed events
            if (event.isRemoved)
              Positioned.fill(
                child: CustomPaint(
                  painter: DottedBorderPainter(
                    color: _getEventTypeColor(event.eventType).withOpacity(0.8),
                    strokeWidth: 1,
                  ),
                ),
              ),
            // Content with height-adaptive rendering
            _buildEventTileContent(event, tileHeight),
          ],
        ),
      ),
    );

    // Make event draggable only when menu is open
    if (isMenuOpen) {
      eventWidget = Draggable<Event>(
        data: event,
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(2),
          child: Opacity(
            opacity: 0.7,
            child: Container(
              width: 100,
              height: tileHeight,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: BoxDecoration(
                color: _getEventTypeColor(event.eventType),
                borderRadius: BorderRadius.circular(2),
              ),
              child: _buildEventTileContent(event, tileHeight),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: eventWidget,
        ),
        onDragEnd: (details) {
          // Drag ended, no action needed
        },
        child: eventWidget,
      );
    }

    return eventWidget;
  }

  Widget _buildEventTileContent(Event event, double tileHeight) {
    // For closed-end events (with both start and end times), always show simplified content
    // Open-end events get height-adaptive rendering
    final isClosedEnd = !_shouldDisplayAsOpenEnd(event);

    if (isClosedEnd) {
      // Closed-end events: Always show just the name with consistent styling
      // Use fixed small font size to match open-end events (not calculated from tileHeight)
      final fontSize = 9.0;
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            event.name,
            style: TextStyle(
              fontSize: fontSize,
              color: event.isRemoved ? Colors.white70 : Colors.white,
              height: 1.2,
              decoration: event.isRemoved ? TextDecoration.lineThrough : null,
              decorationColor: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );
    }

    // Open-end events: Height-adaptive rendering
    // Height breakpoints for adaptive rendering
    if (tileHeight < 20) {
      // Very small: Only show name with tiny font
      final fontSize = (tileHeight * 0.4).clamp(8.0, 10.0);
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            event.name,
            style: TextStyle(
              fontSize: fontSize,
              color: event.isRemoved ? Colors.white70 : Colors.white,
              height: 1.2,
              decoration: event.isRemoved ? TextDecoration.lineThrough : null,
              decorationColor: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );
    } else if (tileHeight < 35) {
      // Small: Only show name with small font
      final fontSize = (tileHeight * 0.35).clamp(8.0, 10.0);
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            event.name,
            style: TextStyle(
              fontSize: fontSize,
              color: event.isRemoved ? Colors.white70 : Colors.white,
              height: 1.2,
              decoration: event.isRemoved ? TextDecoration.lineThrough : null,
              decorationColor: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );
    } else if (tileHeight < 50) {
      // Medium: Show time + name
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            event.timeRangeDisplay,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: event.isRemoved ? Colors.white70 : Colors.white,
              height: 1.2,
              decoration: event.isRemoved ? TextDecoration.lineThrough : null,
              decorationColor: Colors.white70,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (event.name.isNotEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  event.name,
                  style: TextStyle(
                    fontSize: 12.6,
                    color: event.isRemoved ? Colors.white70 : Colors.white,
                    height: 1.3,
                    decoration: event.isRemoved ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
        ],
      );
    } else if (tileHeight < 70) {
      // Large: Show time + name + record number
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            event.timeRangeDisplay,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: event.isRemoved ? Colors.white70 : Colors.white,
              height: 1.2,
              decoration: event.isRemoved ? TextDecoration.lineThrough : null,
              decorationColor: Colors.white70,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (event.name.isNotEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  event.name,
                  style: TextStyle(
                    fontSize: 14.4,
                    color: event.isRemoved ? Colors.white70 : Colors.white,
                    height: 1.3,
                    decoration: event.isRemoved ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ),
          if (event.recordNumber.isNotEmpty)
            Builder(
              builder: (context) => Text(
                '${AppLocalizations.of(context)!.record}${event.recordNumber}',
                style: TextStyle(
                  fontSize: 7,
                  color: event.isRemoved ? Colors.white60 : Colors.white70,
                  height: 1.2,
                  decoration: event.isRemoved ? TextDecoration.lineThrough : null,
                  decorationColor: Colors.white60,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
        ],
      );
    } else {
      // Extra large: Show all details
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            event.timeRangeDisplay,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: event.isRemoved ? Colors.white70 : Colors.white,
              height: 1.2,
              decoration: event.isRemoved ? TextDecoration.lineThrough : null,
              decorationColor: Colors.white70,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (event.name.isNotEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  event.name,
                  style: TextStyle(
                    fontSize: 16.2,
                    color: event.isRemoved ? Colors.white70 : Colors.white,
                    height: 1.3,
                    decoration: event.isRemoved ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ),
          if (event.recordNumber.isNotEmpty)
            Builder(
              builder: (context) => Text(
                '${AppLocalizations.of(context)!.record}${event.recordNumber}',
                style: TextStyle(
                  fontSize: 7,
                  color: event.isRemoved ? Colors.white60 : Colors.white70,
                  height: 1.2,
                  decoration: event.isRemoved ? TextDecoration.lineThrough : null,
                  decorationColor: Colors.white60,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          // Show new time if event was moved
          if (event.hasNewTime)
            Builder(
              builder: (context) {
                final newEvent = _getNewEventForTimeChange(event);
                final newTimeDisplay = _getNewTimeDisplay(newEvent);
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${AppLocalizations.of(context)!.moved} $newTimeDisplay',
                    style: const TextStyle(
                      fontSize: 7,
                      color: Colors.white70,
                      height: 1.2,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                );
              },
            ),
          // Show removal reason or time change indicator
          if ((event.isRemoved || event.isTimeChanged) && event.removalReason != null)
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  event.isTimeChanged
                    ? AppLocalizations.of(context)!.timeChanged(event.removalReason!)
                    : AppLocalizations.of(context)!.removedReason(event.removalReason!),
                  style: const TextStyle(
                    fontSize: 6,
                    color: Colors.white60,
                    height: 1.2,
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
        ],
      );
    }
  }

  Color _getEventTypeColor(String eventType) {
    // Simple color coding based on event type
    switch (eventType.toLowerCase()) {
      case 'consultation':
        return Colors.blue;
      case 'surgery':
        return Colors.red;
      case 'follow-up':
        return Colors.green;
      case 'emergency':
        return Colors.orange;
      default:
        return Colors.purple;
    }
  }

  Widget? _buildEventContextMenuOverlay() {
    if (_selectedEventForMenu == null || _menuPosition == null) return null;

    final l10n = AppLocalizations.of(context)!;
    final event = _selectedEventForMenu!;
    final screenSize = MediaQuery.of(context).size;

    // Determine if menu should appear above or below
    final showAbove = _menuPosition!.dy > screenSize.height / 2;

    return Positioned(
      left: _menuPosition!.dx.clamp(20.0, screenSize.width - 200),
      top: showAbove ? null : _menuPosition!.dy + 10,
      bottom: showAbove ? screenSize.height - _menuPosition!.dy + 10 : null,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        event.name.isEmpty ? AppLocalizations.of(context)!.eventOptions : event.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _closeEventMenu,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Menu items
              ListTile(
                dense: true,
                leading: const Icon(Icons.category, size: 20),
                title: Text(l10n.changeEventType, style: const TextStyle(fontSize: 14)),
                onTap: () => _handleMenuAction('changeType', event),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.remove_circle_outline, color: Colors.orange, size: 20),
                title: Text(l10n.removeEvent, style: const TextStyle(color: Colors.orange, fontSize: 14)),
                onTap: () => _handleMenuAction('remove', event),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.delete, color: Colors.red, size: 20),
                title: Text(l10n.deleteEvent, style: const TextStyle(color: Colors.red, fontSize: 14)),
                onTap: () => _handleMenuAction('delete', event),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawingToolbar() {
    final canvasState = _getCanvasKeyForCurrentPage().currentState;
    final isErasing = canvasState?.isErasing ?? false;
    final currentColor = canvasState?.strokeColor ?? Colors.black;

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade50.withOpacity(0.95),
        border: Border(
          bottom: BorderSide(color: Colors.orange.shade300, width: 2),
        ),
      ),
      child: Row(
        children: [
          // Pen/Eraser toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => setState(() => canvasState?.setErasing(false)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: !isErasing ? Colors.blue.shade100 : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 18,
                      color: !isErasing ? Colors.blue.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
                Container(width: 1, height: 20, color: Colors.grey.shade300),
                InkWell(
                  onTap: () => setState(() => canvasState?.setErasing(true)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isErasing ? Colors.orange.shade100 : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                    ),
                    child: Icon(
                      Icons.auto_fix_high,
                      size: 18,
                      color: isErasing ? Colors.orange.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Color picker (only show when not erasing)
          if (!isErasing) ...[
            ...[ Colors.black,
              Colors.red,
              Colors.blue,
              Colors.green,
              Colors.orange,
              Colors.purple,
            ].map((color) {
              final isSelected = currentColor == color;
              return GestureDetector(
                onTap: () => setState(() => canvasState?.setStrokeColor(color)),
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.grey.shade400,
                      width: isSelected ? 3 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 14,
                          color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                        )
                      : null,
                ),
              );
            }),
          ],
          const Spacer(),
          // Action buttons
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed: canvasState?.canUndo ?? false ? () => setState(() => canvasState?.undo()) : null,
                    tooltip: l10n.undo,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo, size: 20),
                    onPressed: canvasState?.canRedo ?? false ? () => setState(() => canvasState?.redo()) : null,
                    tooltip: l10n.redo,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () {
                      setState(() => canvasState?.clear());
                      _saveDrawing();
                    },
                    tooltip: l10n.clear,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Custom painter for drawing the current time indicator line
class CurrentTimeLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const CurrentTimeLinePainter({
    this.color = Colors.red,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Draw dashed line
    const dashWidth = 8.0;
    const dashSpace = 4.0;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }

    // Draw circles at both ends
    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(0, 0), 4, circlePaint); // Left circle
    canvas.drawCircle(Offset(size.width, 0), 4, circlePaint); // Right circle
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for creating dotted border effect on removed events
class DottedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  const DottedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.dashLength = 3.0,
    this.gapLength = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Create dotted border path
    final path = Path();

    // Top border
    double currentX = 0;
    while (currentX < size.width) {
      path.moveTo(currentX, 0);
      path.lineTo((currentX + dashLength).clamp(0, size.width), 0);
      currentX += dashLength + gapLength;
    }

    // Right border
    double currentY = 0;
    while (currentY < size.height) {
      path.moveTo(size.width, currentY);
      path.lineTo(size.width, (currentY + dashLength).clamp(0, size.height));
      currentY += dashLength + gapLength;
    }

    // Bottom border
    currentX = size.width;
    while (currentX > 0) {
      path.moveTo(currentX, size.height);
      path.lineTo((currentX - dashLength).clamp(0, size.width), size.height);
      currentX -= dashLength + gapLength;
    }

    // Left border
    currentY = size.height;
    while (currentY > 0) {
      path.moveTo(0, currentY);
      path.lineTo(0, (currentY - dashLength).clamp(0, size.height));
      currentY -= dashLength + gapLength;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}