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
import '../repositories/event_repository.dart';
import '../repositories/note_repository.dart';
import '../services/api_client.dart';
import '../services/database/prd_database_service.dart';
import '../services/database_service_interface.dart';
import '../services/network_service.dart';
import '../services/server_config_service.dart';
import '../services/service_locator.dart';
import '../services/sync_coordinator.dart';
import '../services/sync_service.dart';
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
import 'book_list/utils/snackbar_utils.dart';

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
  DateTime? _previousSelectedDate;

  // Book UUID must be non-null for ScheduleScreen (book must exist in database)
  late final String _bookUuid;

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

  // Sync coordinator to push/pull updates
  SyncCoordinator? _syncCoordinator;
  SyncService? _syncService;
  Future<void>? _syncCoordinatorInit;
  final NetworkService _networkService = NetworkService();

  // FAB menu visibility state
  bool _isFabMenuVisible = false;

  // RACE CONDITION FIX: Preload generation counter to cancel stale preload operations
  int _currentPreloadGeneration = 0;

  // RACE CONDITION FIX: Navigation generation counter to prevent stale state updates
  int _navigationGeneration = 0;

  // Navigation state for loading overlay
  bool _isNavigating = false;

  // Get database service from service locator
  final IDatabaseService _dbService = getIt<IDatabaseService>();

  @override
  void initState() {
    super.initState();

    // Ensure book has a valid UUID (must be persisted in database before opening ScheduleScreen)
    assert(widget.book.uuid.isNotEmpty, 'Book must have a valid UUID to open ScheduleScreen');
    _bookUuid = widget.book.uuid;

    _transformationController = TransformationController();

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize drawing service
    _drawingService = ScheduleDrawingService(
      dbService: _dbService,
      bookUuid: _bookUuid,
      contentService: _contentService,
      onDrawingChanged: () {
        if (mounted) setState(() {});
      },
    );

    // Initialize date service
    _dateService = ScheduleDateService(
      initialDate: _selectedDate,
      onDateChanged: (selectedDate, lastActiveDate) {
        // RACE CONDITION FIX: Increment navigation generation on each date change
        _navigationGeneration++;
        setState(() {
          _selectedDate = selectedDate;
          _lastActiveDate = lastActiveDate;
        });
      },
      onSaveDrawing: () async {
        try {
          await _saveDrawing();
        } catch (e) {
          // Show error and rethrow to cancel navigation
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to save drawing: $e'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
          rethrow;
        }
      },
      onLoadDrawing: () async => await _loadDrawing(),
      onUpdateCubit: (date) {
        // RACE CONDITION FIX: Pass navigation generation to cubit
        context.read<ScheduleCubit>().selectDate(date);
      },
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

    // Set navigation state callback for loading overlay
    _dateService!.onNavigatingStateChanged = (isNavigating) {
      if (mounted) {
        setState(() {
          _isNavigating = isNavigating;
        });
      }
    };

    // Set exit drawing mode callback
    _dateService!.onExitDrawingMode = () {
      if (mounted) {
        setState(() {
          _isDrawingMode = false;
        });
      }
    };

    // Initialize connectivity service
    _connectivityService = ScheduleConnectivityService(
      dbService: _dbService,
      bookUuid: _bookUuid,
      onStateChanged: (isOffline, isSyncing) {
        if (mounted) setState(() {});
      },
      onUpdateCubitOfflineStatus: (isOffline) {
        context.read<ScheduleCubit>().setOfflineStatus(isOffline);
      },
      onShowSnackbar: (message, {backgroundColor, durationSeconds, action, detailTitle, detailMessage}) {
        // If details are provided, use SnackBarUtils with details
        if (detailTitle != null && detailMessage != null) {
          if (backgroundColor == Colors.orange) {
            SnackBarUtils.showWarningWithDetails(
              context: context,
              message: message,
              detailTitle: detailTitle,
              detailMessage: detailMessage,
            );
          } else if (backgroundColor == Colors.red) {
            SnackBarUtils.showErrorWithDetails(
              context: context,
              message: message,
              detailTitle: detailTitle,
              detailMessage: detailMessage,
            );
          } else if (backgroundColor == Colors.green) {
            SnackBarUtils.showSuccessWithDetails(
              context: context,
              message: message,
              detailTitle: detailTitle,
              detailMessage: detailMessage,
            );
          } else {
            SnackBarUtils.showInfoWithDetails(
              context: context,
              message: message,
              detailTitle: detailTitle,
              detailMessage: detailMessage,
            );
          }
        } else {
          // Otherwise, show normal snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: backgroundColor,
              duration: Duration(seconds: durationSeconds ?? 2),
              action: action,
            ),
          );
        }
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
      bookUuid: _bookUuid,
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
      onSyncEvent: (event) async {
        await _connectivityService?.syncEventToServer(event);
      },
      onSetPendingNextAppointment: (pending) => context.read<ScheduleCubit>().setPendingNextAppointment(pending),
      dateService: _dateService!,
    );

    // Start services
    _dateService?.startPeriodicCheck();
    _connectivityService?.initialize();
    _connectivityService?.setupConnectivityMonitoring();
    Future.microtask(() => _ensureSyncCoordinator());

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
    _syncCoordinator?.stopAutoSync();
    _syncCoordinator = null;

    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _dateService?.checkAndHandleDateChange();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
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
  ///
  /// [generation] - Preload generation number for race condition prevention
  Future<void> _preloadNotesInBackground(List<Event> events, int generation) async {
    if (events.isEmpty) {
      return;
    }

    if (_contentService == null) {
      return;
    }

    final preloadStartTime = DateTime.now();

    // Extract all event IDs (filter out null IDs)
    final eventIds = events
        .where((e) => e.id != null)
        .map((e) => e.id!)
        .toList();

    if (eventIds.isEmpty) {
      return;
    }


    try {
      // RACE CONDITION FIX: Pass generation and cancellation check to ContentService
      await _contentService!.preloadNotes(
        eventIds,
        generation: generation,
        isCancelled: () => generation != _currentPreloadGeneration,
        onProgress: (loaded, total) {
          // Only log progress if this preload is still active
          if (generation == _currentPreloadGeneration) {
          }
        },
      );

      final preloadEndTime = DateTime.now();
      final preloadDuration = preloadEndTime.difference(preloadStartTime);

      // Only log completion if this preload is still active
      if (generation == _currentPreloadGeneration) {
      } else {
      }
    } catch (e) {
      // Preload failure is non-critical - user can still use the app
      // Notes will be fetched on-demand when user taps events
      final preloadEndTime = DateTime.now();
      final preloadDuration = preloadEndTime.difference(preloadStartTime);
    }
  }

  Future<void> _ensureSyncCoordinator() async {
    if (_syncCoordinator != null) return;
    _syncCoordinatorInit ??= _createSyncCoordinator();
    await _syncCoordinatorInit;
  }

  Future<void> _createSyncCoordinator() async {
    if (!mounted) return;
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      final serverConfig = ServerConfigService(prdDb);
      final serverUrl = await serverConfig.getServerUrlOrDefault(
        defaultUrl: 'http://localhost:8080',
      );
      final apiClient = ApiClient(baseUrl: serverUrl);
      _syncService = SyncService(
        apiClient: apiClient,
        eventRepository: getIt<IEventRepository>(),
        noteRepository: getIt<INoteRepository>(),
        databaseService: _dbService,
      );
      _syncCoordinator = SyncCoordinator(
        syncService: _syncService!,
        networkService: _networkService,
      );
      _syncCoordinator!.startAutoSync();
      await _syncCoordinator!.syncNow();
    } catch (e) {
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
          // RACE CONDITION FIX: Increment generation to cancel previous preload
          _currentPreloadGeneration++;
          final preloadGeneration = _currentPreloadGeneration;
          _preloadNotesInBackground(state.events, preloadGeneration);

          // Check if date has changed to a different 3-day window
          final currentWindow = _previousSelectedDate != null
              ? ScheduleLayoutUtils.get3DayWindowStart(_previousSelectedDate!)
              : null;
          final newWindow = ScheduleLayoutUtils.get3DayWindowStart(state.selectedDate);
          final localWindow = ScheduleLayoutUtils.get3DayWindowStart(_selectedDate);

          if (currentWindow != newWindow) {
            // Date changed to a different 3-day window

            // RACE CONDITION FIX: Check if this state is for our current local window or a different one
            if (newWindow == localWindow) {
              // State is for the same window we're already in locally
              // This is likely a stale state from an old navigation that completed late
              _previousSelectedDate = state.selectedDate; // Track that we saw this state
            } else {
              // State is for a different window - this is a new navigation completing
              _previousSelectedDate = state.selectedDate;
              if (_selectedDate != state.selectedDate) {
                setState(() {
                  _selectedDate = state.selectedDate;
                });
              }
              // Reload drawing for the new date
              _loadDrawing();
            }
          }
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
        child: Stack(
          children: [
            Scaffold(
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.only(left: 160.0),
          child: Row(
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
              // Date navigation - Previous page (2 or 3 days depending on mode)
              BlocBuilder<ScheduleCubit, ScheduleState>(
                builder: (context, state) {
                  final viewMode = state is ScheduleLoaded ? state.viewMode : ScheduleDrawing.VIEW_MODE_2DAY;
                  final windowSize = viewMode == ScheduleDrawing.VIEW_MODE_2DAY ? 2 : 3;
                  return IconButton(
                    onPressed: () => _dateService?.navigatePagePrevious(),
                    icon: const Icon(Icons.chevron_left, size: 18),
                    iconSize: 18,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    tooltip: '-$windowSize days',
                  );
                },
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
              // Date navigation - Next page (2 or 3 days depending on mode)
              BlocBuilder<ScheduleCubit, ScheduleState>(
                builder: (context, state) {
                  final viewMode = state is ScheduleLoaded ? state.viewMode : ScheduleDrawing.VIEW_MODE_2DAY;
                  final windowSize = viewMode == ScheduleDrawing.VIEW_MODE_2DAY ? 2 : 3;
                  return IconButton(
                    onPressed: () => _dateService?.navigatePageNext(),
                    icon: const Icon(Icons.chevron_right, size: 18),
                    iconSize: 18,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    tooltip: '+$windowSize days',
                  );
                },
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
        ),
        actions: [
          // Small loading indicator for page navigation (space always reserved)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: _isNavigating
                  ? const CircularProgressIndicator(
                      strokeWidth: 2,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          // View mode dropdown
          BlocBuilder<ScheduleCubit, ScheduleState>(
            builder: (context, state) {
              final viewMode = state is ScheduleLoaded ? state.viewMode : ScheduleDrawing.VIEW_MODE_2DAY;
              return PopupMenuButton<int>(
                icon: const Icon(Icons.view_day),
                offset: const Offset(0, 40),
                onSelected: (int newViewMode) async {
                  // Update date service view mode
                  _dateService?.setViewMode(newViewMode);
                  // Update cubit view mode and reload
                  await context.read<ScheduleCubit>().changeViewMode(newViewMode);
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
                  PopupMenuItem<int>(
                    value: ScheduleDrawing.VIEW_MODE_2DAY,
                    child: Row(
                      children: [
                        if (viewMode == ScheduleDrawing.VIEW_MODE_2DAY)
                          const Icon(Icons.check, size: 16)
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(l10n.twoDays),
                      ],
                    ),
                  ),
                  PopupMenuItem<int>(
                    value: ScheduleDrawing.VIEW_MODE_3DAY,
                    child: Row(
                      children: [
                        if (viewMode == ScheduleDrawing.VIEW_MODE_3DAY)
                          const Icon(Icons.check, size: 16)
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(l10n.threeDays),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          // Toggle drawing visibility
          BlocBuilder<ScheduleCubit, ScheduleState>(
            builder: (context, state) {
              final showDrawing = state is ScheduleLoaded ? state.showDrawing : true;
              return IconButton(
                icon: Icon(showDrawing ? Icons.brush : Icons.brush_outlined),
                onPressed: () {
                  context.read<ScheduleCubit>().toggleDrawing();
                },
                tooltip: showDrawing ? l10n.hideDrawing : l10n.showDrawing,
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
          final showDrawing = state is ScheduleLoaded ? state.showDrawing : true;
          final pendingNextAppointment = state is ScheduleLoaded ? state.pendingNextAppointment : null;
          final viewMode = state is ScheduleLoaded ? state.viewMode : ScheduleDrawing.VIEW_MODE_2DAY;

          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _build3DayView(events, showOldEvents, showDrawing, pendingNextAppointment, viewMode),
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
        bookUuid: _bookUuid,
        get3DayWindowStart: (date) => ScheduleLayoutUtils.get3DayWindowStart(date),
        cacheManager: _cacheManager,
        getEffectiveDate: () => ScheduleLayoutUtils.getEffectiveDate(_selectedDate),
        preloadNotes: (events) {
          _currentPreloadGeneration++;
          _preloadNotesInBackground(events, _currentPreloadGeneration);
        },
        onDateChange: _changeDateTo,
      ),
    ), // Scaffold
          ],
        ), // Stack
    ), // PopScope
    ); // BlocListener
  }


  /// Build schedule view (2-day or 3-day) using ScheduleBody component
  Widget _build3DayView(List<Event> events, bool showOldEvents, bool showDrawing, PendingNextAppointment? pendingNextAppointment, int viewMode) {
    // Get window start based on view mode
    final windowStart = viewMode == ScheduleDrawing.VIEW_MODE_2DAY
        ? ScheduleLayoutUtils.get2DayWindowStart(_selectedDate)
        : ScheduleLayoutUtils.get3DayWindowStart(_selectedDate);

    // Generate dates based on view mode (2 or 3 days)
    final windowSize = viewMode == ScheduleDrawing.VIEW_MODE_2DAY ? 2 : 3;
    final dates = List.generate(windowSize, (index) => windowStart.add(Duration(days: index)));

    return ScheduleBody(
      dates: dates,
      events: events,
      showOldEvents: showOldEvents,
      showDrawing: showDrawing,
      isDrawingMode: _isDrawingMode,
      canvasKey: _getCanvasKeyForCurrentPage(),
      currentDrawing: _drawingService?.currentDrawing,
      transformationController: _transformationController,
      getEventTypeColor: (context, eventType) => _eventService?.getEventTypeColor(eventType) ?? Colors.grey,
      onEditEvent: (event) => _eventService?.editEvent(event),
      onShowEventContextMenu: (event, position) => _eventService?.showEventContextMenu(event, position),
      onCreateEvent: (startTime) {
        _eventService?.createEvent(
          startTime: startTime,
          name: pendingNextAppointment?.name,
          recordNumber: pendingNextAppointment?.recordNumber,
          phone: pendingNextAppointment?.phone,
          eventTypes: pendingNextAppointment?.eventTypes,
        );
        // Clear pending data after using it
        if (pendingNextAppointment != null) {
          context.read<ScheduleCubit>().clearPendingNextAppointment();
        }
      },
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
      onScheduleNextAppointment: _eventService?.selectedEventForMenu != null ? () => _eventService?.scheduleNextAppointment(_eventService!.selectedEventForMenu!, context) : null,
      onRemove: _eventService?.selectedEventForMenu != null ? () => _eventService?.handleMenuAction('remove', _eventService!.selectedEventForMenu!, context) : null,
      onDelete: _eventService?.selectedEventForMenu != null ? () => _eventService?.handleMenuAction('delete', _eventService!.selectedEventForMenu!, context) : null,
      onCheckedChanged: _eventService?.selectedEventForMenu != null ? (isChecked) => _eventService?.toggleEventChecked(_eventService!.selectedEventForMenu!, isChecked) : null,
    );
  }


}
