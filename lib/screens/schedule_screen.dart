import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/schedule_cubit.dart';
import '../cubits/schedule_state.dart';
import '../l10n/app_localizations.dart';
import '../models/book.dart';
import '../models/event.dart';
import '../models/schedule_drawing.dart';
import '../services/database_service_interface.dart';
import '../services/service_locator.dart';
import '../services/time_service.dart';
import '../services/content_service.dart';
import '../services/cache_manager.dart';
import '../widgets/handwriting_canvas.dart';
import '../utils/schedule/schedule_layout_utils.dart';
import '../widgets/schedule/fab_menu.dart';
import '../widgets/schedule/drawing_toolbar.dart';
import 'schedule/schedule_body.dart';
import 'schedule/services/schedule_drawing_service.dart';
import 'schedule/services/schedule_date_service.dart';
import 'schedule/services/schedule_connectivity_service.dart';
import 'schedule/services/event_management_service.dart';

/// Schedule screen implementing 3-Day view only
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
  late TransformationController _transformationController;
  DateTime _selectedDate = TimeService.instance.now();

  // Book ID must be non-null for ScheduleScreen (book must exist in database)
  late final int _bookId;

  // Optional: ContentService for server sync (now managed by ScheduleConnectivityService)
  // Nullable because: may fail to initialize on web platform or without server access
  ContentService? _contentService;

  // Optional: CacheManager for experimental cache operations (now managed by ScheduleConnectivityService)
  // Nullable because: depends on ContentService initialization
  CacheManager? _cacheManager;

  // Date change detection (now managed by ScheduleDateService)
  DateTime _lastActiveDate = TimeService.instance.now();

  // Drawing overlay state
  bool _isDrawingMode = false;
  // Service manages: _currentDrawing, _canvasKeys, _saveDebounceTimer, _isSaving, _lastSavedCanvasVersion
  ScheduleDrawingService? _drawingService;

  // Date management service
  ScheduleDateService? _dateService;

  // Connectivity and sync service
  ScheduleConnectivityService? _connectivityService;

  // Event management service
  EventManagementService? _eventService;

  // FAB menu visibility state
  bool _isFabMenuVisible = false;

  // Get database service from service locator
  final IDatabaseService _dbService = getIt<IDatabaseService>();

  @override
  void initState() {
    super.initState();

    // Ensure book has a valid ID (must be persisted in database before opening ScheduleScreen)
    assert(widget.book.id != null, 'Book must have a valid ID to open ScheduleScreen');
    _bookId = widget.book.id!;

    _transformationController = TransformationController();

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize drawing service
    _drawingService = ScheduleDrawingService(
      dbService: _dbService,
      bookId: _bookId,
      contentService: _contentService,
      onDrawingChanged: () {
        if (mounted) setState(() {});
      },
    );

    // Initialize date service
    _dateService = ScheduleDateService(
      initialDate: _selectedDate,
      onDateChanged: (selectedDate, lastActiveDate) {
        setState(() {
          _selectedDate = selectedDate;
          _lastActiveDate = lastActiveDate;
        });
      },
      onSaveDrawing: () async => await _saveDrawing(),
      onLoadDrawing: () async => await _loadDrawing(),
      onUpdateCubit: (date) => context.read<ScheduleCubit>().selectDate(date),
      onShowNotification: (messageKey) {
        if (messageKey == 'dateChangedToToday') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.dateChangedToToday),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      isMounted: () => mounted,
      isInDrawingMode: () => _isDrawingMode,
      onCancelPendingSave: () => _drawingService?.cancelPendingSave(),
    );

    // Initialize connectivity service
    _connectivityService = ScheduleConnectivityService(
      dbService: _dbService,
      bookId: _bookId,
      onStateChanged: (isOffline, isSyncing) {
        if (mounted) setState(() {});
      },
      onUpdateCubitOfflineStatus: (isOffline) {
        context.read<ScheduleCubit>().setOfflineStatus(isOffline);
      },
      onShowSnackbar: (message, {backgroundColor, durationSeconds, action}) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: Duration(seconds: durationSeconds ?? 2),
            action: action,
          ),
        );
      },
      onShowDialog: (title, message) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
      isMounted: () => mounted,
      onUpdateDrawingServiceContentService: (contentService) {
        if (_drawingService != null) {
          _drawingService!.contentService = contentService;
        }
      },
    );

    // Initialize event management service
    _eventService = EventManagementService(
      dbService: _dbService,
      bookId: _bookId,
      onMenuStateChanged: (selectedEvent, position) {
        if (mounted) setState(() {});
      },
      onNavigate: (screen) async {
        return await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      },
      onReloadEvents: () => context.read<ScheduleCubit>().loadEvents(),
      onUpdateEvent: (event) => context.read<ScheduleCubit>().updateEvent(event),
      onDeleteEvent: (eventId, reason) async {
        await context.read<ScheduleCubit>().deleteEvent(eventId, reason: reason);
      },
      onHardDeleteEvent: (eventId) async {
        await context.read<ScheduleCubit>().hardDeleteEvent(eventId);
      },
      onChangeEventTime: (event, startTime, endTime, reason) async {
        await context.read<ScheduleCubit>().changeEventTime(event, startTime, endTime, reason);
      },
      onShowSnackbar: (message, {backgroundColor, durationSeconds}) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: Duration(seconds: durationSeconds ?? 2),
          ),
        );
      },
      isMounted: () => mounted,
      getLocalizedString: (getter) => getter(AppLocalizations.of(context)!),
      onSyncEvent: (event) async => await _connectivityService?.syncEventToServer(event),
    );

    // Start services
    _dateService?.startPeriodicCheck();
    _connectivityService?.initialize();
    _connectivityService?.setupConnectivityMonitoring();

    // Cubit is initialized in BlocProvider - it automatically loads events
    _drawingService?.loadDrawing(_selectedDate);
  }


  @override
  void dispose() {
    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Dispose all services
    _dateService?.dispose();
    _connectivityService?.dispose();
    _drawingService?.dispose();

    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      debugPrint('📅 App resumed - checking for date changes');
      _dateService?.checkAndHandleDateChange();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint('📅 App backgrounding - saving drawing if in drawing mode');
      // Auto-save drawing before going to background
      if (_isDrawingMode) {
        _saveDrawing();
      }
    }
  }

  /// Get unique page identifier for the current view and date
  String _getPageId() => _drawingService!.getPageId(_selectedDate);

  /// Get or create canvas key for the current page
  GlobalKey<HandwritingCanvasState> _getCanvasKeyForCurrentPage() => _drawingService!.getCanvasKey(_selectedDate);

  Future<void> _loadDrawing() async {
    await _drawingService?.loadDrawing(_selectedDate);
    context.read<ScheduleCubit>().loadDrawing(viewMode: ScheduleDrawing.VIEW_MODE_3DAY, forceRefresh: false);
  }

  /// Preload notes for all events in current 3-day window (background, non-blocking)
  ///
  /// This method is automatically triggered by BlocListener when events are loaded
  /// from the ScheduleCubit. It improves UX by preloading notes so they're instantly
  /// available when user taps events.
  Future<void> _preloadNotesInBackground(List<Event> events) async {
    if (events.isEmpty) {
      debugPrint('📦 ScheduleScreen: No events to preload');
      return;
    }

    if (_contentService == null) {
      debugPrint('⚠️ ScheduleScreen: Cannot preload - ContentService not initialized');
      return;
    }

    final preloadStartTime = DateTime.now();
    debugPrint('📦 ScheduleScreen: [${preloadStartTime.toIso8601String()}] Starting preload for ${events.length} events');

    // Extract all event IDs (filter out null IDs)
    final eventIds = events
        .where((e) => e.id != null)
        .map((e) => e.id!)
        .toList();

    if (eventIds.isEmpty) {
      debugPrint('📦 ScheduleScreen: No valid event IDs to preload');
      return;
    }

    debugPrint('📦 ScheduleScreen: Calling ContentService.preloadNotes with ${eventIds.length} event IDs');

    try {
      // Call ContentService to preload notes with progress callback
      await _contentService!.preloadNotes(
        eventIds,
        onProgress: (loaded, total) {
          // Log progress for debugging
          debugPrint('📦 ScheduleScreen: Progress update - $loaded/$total notes loaded');
        },
      );

      final preloadEndTime = DateTime.now();
      final preloadDuration = preloadEndTime.difference(preloadStartTime);
      debugPrint('✅ ScheduleScreen: Preload call completed in ${preloadDuration.inMilliseconds}ms (initiated for ${eventIds.length} notes)');
    } catch (e) {
      // Preload failure is non-critical - user can still use the app
      // Notes will be fetched on-demand when user taps events
      final preloadEndTime = DateTime.now();
      final preloadDuration = preloadEndTime.difference(preloadStartTime);
      debugPrint('⚠️ ScheduleScreen: Preload failed after ${preloadDuration.inMilliseconds}ms (non-critical): $e');
    }
  }

  /// Schedule a debounced save to reduce save frequency during fast drawing
  void _scheduleSaveDrawing() => _drawingService?.scheduleSave(_selectedDate);

  Future<void> _saveDrawing() async {
    try {
      await _drawingService?.saveDrawing(_selectedDate);
      final savedDrawing = _drawingService?.currentDrawing;
      if (mounted && savedDrawing != null) {
        context.read<ScheduleCubit>().saveDrawing(savedDrawing);
      }
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
      // Exiting drawing mode - save immediately
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

  void _toggleFabMenu() {
    setState(() {
      _isFabMenuVisible = !_isFabMenuVisible;
    });
  }

  void _changeDateTo(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
      _lastActiveDate = newDate;
    });
  }


  void _panToCurrentTime() {
    // Reset transformation to default view (scale 1.0, no pan)
    // At default zoom, all time slots are visible including current time
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transformationController.value = Matrix4.identity();
    });
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocListener<ScheduleCubit, ScheduleState>(
      listener: (context, state) {
        // Trigger preloading when events are loaded
        if (state is ScheduleLoaded) {
          _preloadNotesInBackground(state.events);
        }
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          if (didPop) return;

          // Auto-save drawing before navigating back
          if (_isDrawingMode) {
            await _saveDrawing();
          }

          if (mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Date navigation - Previous 180 days
            IconButton(
              onPressed: () => _dateService?.navigate180DaysPrevious(),
              icon: const Text('-180', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
              padding: EdgeInsets.zero,
              tooltip: '-180 days',
            ),
            // Date navigation - Previous 90 days
            IconButton(
              onPressed: () => _dateService?.navigate90DaysPrevious(),
              icon: const Text('-90', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              padding: EdgeInsets.zero,
              tooltip: '-90 days',
            ),
            // Date navigation - Previous 1 day (<)
            IconButton(
              onPressed: () => _dateService?.navigate1DayPrevious(),
              icon: const Icon(Icons.chevron_left, size: 18),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              tooltip: '-1 day',
            ),
            const SizedBox(width: 4),
            // Date display
            GestureDetector(
              onTap: () => _dateService?.showDatePickerDialog(context),
              child: Text(
                _dateService?.getDateDisplayText(context) ?? '',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            // Date navigation - Next 1 day (>)
            IconButton(
              onPressed: () => _dateService?.navigate1DayNext(),
              icon: const Icon(Icons.chevron_right, size: 18),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              tooltip: '+1 day',
            ),
            // Date navigation - Next 90 days
            IconButton(
              onPressed: () => _dateService?.navigate90DaysNext(),
              icon: const Text('+90', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              padding: EdgeInsets.zero,
              tooltip: '+90 days',
            ),
            // Date navigation - Next 180 days
            IconButton(
              onPressed: () => _dateService?.navigate180DaysNext(),
              icon: const Text('+180', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
              padding: EdgeInsets.zero,
              tooltip: '+180 days',
            ),
          ],
        ),
        actions: [
          // Toggle old events visibility
          BlocBuilder<ScheduleCubit, ScheduleState>(
            builder: (context, state) {
              final showOldEvents = state is ScheduleLoaded ? state.showOldEvents : true;
              return IconButton(
                icon: Icon(showOldEvents ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  context.read<ScheduleCubit>().toggleOldEvents();
                },
                tooltip: showOldEvents ? l10n.hideOldEvents : l10n.showOldEvents,
              );
            },
          ),
          // Go to today button
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () async {
              await _dateService?.jumpToToday();
              _panToCurrentTime();
            },
            tooltip: l10n.goToToday,
          ),
        ],
      ),
      body: BlocBuilder<ScheduleCubit, ScheduleState>(
        builder: (context, state) {
          // Handle error state
          if (state is ScheduleError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${state.message}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<ScheduleCubit>().loadEvents(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final isLoading = state is ScheduleLoading;
          final events = state is ScheduleLoaded ? state.events : <Event>[];
          final showOldEvents = state is ScheduleLoaded ? state.showOldEvents : true;

          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _build3DayView(events, showOldEvents),
                  ),
                ],
              ),
          // Drawing toolbar overlay (positioned on top of date header)
          if (_isDrawingMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ScheduleDrawingToolbarHelper.buildDrawingToolbar(
                context: context,
                getCanvasKey: _getCanvasKeyForCurrentPage,
                onCanvasStateChange: () => setState(() {}),
                saveDrawing: _saveDrawing,
              ),
            ),
            ],
          );
        },
      ), // BlocBuilder
      floatingActionButton: ScheduleFabMenuHelper.buildFabMenu(
        context: context,
        isMenuVisible: _isFabMenuVisible,
        onToggleMenu: _toggleFabMenu,
        isDrawingMode: _isDrawingMode,
        isViewingToday: () => _dateService?.isViewingToday() ?? false,
        selectedDate: _selectedDate,
        lastActiveDate: _lastActiveDate,
        saveDrawing: _saveDrawing,
        loadDrawing: _loadDrawing,
        toggleDrawingMode: _toggleDrawingMode,
        createEvent: () => _eventService?.createEvent(),
        dbService: _dbService,
        bookId: _bookId,
        get3DayWindowStart: (date) => ScheduleLayoutUtils.get3DayWindowStart(date),
        cacheManager: _cacheManager,
        getEffectiveDate: () => ScheduleLayoutUtils.getEffectiveDate(_selectedDate),
        preloadNotes: _preloadNotesInBackground,
        onDateChange: _changeDateTo,
      ),
    ), // Scaffold
    ), // PopScope
    ); // BlocListener
  }


  /// Build 3-day view using ScheduleBody component
  Widget _build3DayView(List<Event> events, bool showOldEvents) {
    final windowStart = ScheduleLayoutUtils.get3DayWindowStart(_selectedDate);
    final dates = List.generate(3, (index) => windowStart.add(Duration(days: index)));

    return ScheduleBody(
      dates: dates,
      events: events,
      showOldEvents: showOldEvents,
      isDrawingMode: _isDrawingMode,
      canvasKey: _getCanvasKeyForCurrentPage(),
      currentDrawing: _drawingService?.currentDrawing,
      transformationController: _transformationController,
      getEventTypeColor: (context, eventType) => _eventService?.getEventTypeColor(eventType) ?? Colors.grey,
      onEditEvent: (event) => _eventService?.editEvent(event),
      onShowEventContextMenu: (event, position) => _eventService?.showEventContextMenu(event, position),
      onCreateEvent: (startTime) => _eventService?.createEvent(startTime: startTime),
      onEventDrop: (event, newStartTime) => _eventService?.handleEventDrop(event, newStartTime, context),
      onCloseEventMenu: () => _eventService?.closeEventMenu(),
      onDrawingStrokesChanged: () {
        setState(() {});
        _scheduleSaveDrawing();
      },
      selectedEventForMenu: _eventService?.selectedEventForMenu,
      menuPosition: _eventService?.menuPosition,
      onChangeType: _eventService?.selectedEventForMenu != null ? () => _eventService?.handleMenuAction('changeType', _eventService!.selectedEventForMenu!, context) : null,
      onChangeTime: _eventService?.selectedEventForMenu != null ? () => _eventService?.handleMenuAction('changeTime', _eventService!.selectedEventForMenu!, context) : null,
      onRemove: _eventService?.selectedEventForMenu != null ? () => _eventService?.handleMenuAction('remove', _eventService!.selectedEventForMenu!, context) : null,
      onDelete: _eventService?.selectedEventForMenu != null ? () => _eventService?.handleMenuAction('delete', _eventService!.selectedEventForMenu!, context) : null,
    );
  }


}

