import 'dart:async';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../cubits/schedule_cubit.dart';
import '../cubits/schedule_state.dart';
import '../l10n/app_localizations.dart';
import '../models/book.dart';
import '../models/event.dart';
import '../models/event_type.dart';
import '../models/schedule_drawing.dart';
import '../services/database_service_interface.dart';
import '../services/prd_database_service.dart';
import '../services/service_locator.dart';
import '../services/time_service.dart';
import '../services/content_service.dart';
import '../services/cache_manager.dart';
import '../services/api_client.dart';
import '../services/server_config_service.dart';
import '../widgets/handwriting_canvas.dart';
import '../utils/schedule/schedule_layout_utils.dart';
import '../utils/datetime_picker_utils.dart';
import '../painters/schedule_painters.dart';
import '../widgets/schedule/test_menu.dart';
import '../widgets/schedule/event_tile.dart';
import '../widgets/schedule/fab_menu.dart';
import '../widgets/schedule/drawing_toolbar.dart';
import 'event_detail_screen.dart';

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

  // Optional: ContentService for server sync
  // Nullable because: may fail to initialize on web platform or without server access
  ContentService? _contentService;

  // Optional: CacheManager for experimental cache operations
  // Nullable because: depends on ContentService initialization
  CacheManager? _cacheManager;

  // Network connectivity monitoring
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _wasOfflineLastCheck = false;
  bool _isOffline = false;
  bool _isSyncing = false;

  // Date change detection
  DateTime _lastActiveDate = TimeService.instance.now();
  Timer? _dateCheckTimer;

  // Drawing overlay state
  bool _isDrawingMode = false;
  // Nullable because: may not exist for new/empty pages
  ScheduleDrawing? _currentDrawing;
  // Cache of canvas keys for each unique page (viewMode + date combination)
  final Map<String, GlobalKey<HandwritingCanvasState>> _canvasKeys = {};

  // Race condition prevention for drawing saves
  Timer? _saveDebounceTimer;
  bool _isSaving = false;
  int _lastSavedCanvasVersion = 0;

  // FAB menu visibility state
  bool _isFabMenuVisible = false;

  // Event menu and drag state
  // Nullable because: only set when user taps on an event to show context menu
  Event? _selectedEventForMenu;
  // Nullable because: only set when context menu is active
  Offset? _menuPosition;

  // Time range settings (now using ScheduleLayoutUtils)
  static const int _startHour = ScheduleLayoutUtils.startHour;
  static const int _endHour = ScheduleLayoutUtils.endHour;
  static const int _totalSlots = ScheduleLayoutUtils.totalSlots;

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

    // Start periodic date checking (every minute)
    _startDateCheckTimer();

    // Initialize ContentService for server sync and auto-sync dirty notes
    _initializeContentService();

    // Setup network connectivity monitoring for automatic sync retry
    _setupConnectivityMonitoring();

    // Cubit is initialized in BlocProvider - it automatically loads events
    _loadDrawing();
  }

  /// Initialize ContentService for server sync
  Future<void> _initializeContentService() async {
    try {
      final prdDb = _dbService as PRDDatabaseService;
      final serverConfig = ServerConfigService(prdDb);
      final serverUrl = await serverConfig.getServerUrlOrDefault(
        defaultUrl: 'http://localhost:8080',
      );
      final apiClient = ApiClient(baseUrl: serverUrl);
      _cacheManager = CacheManager(prdDb);
      _contentService = ContentService(apiClient, _cacheManager!, _dbService);
      debugPrint('✅ ScheduleScreen: ContentService initialized');

      // Check server connectivity
      final serverReachable = await _checkServerConnectivity();
      setState(() {
        _isOffline = !serverReachable;
        _wasOfflineLastCheck = !serverReachable;
      });

      context.read<ScheduleCubit>().setOfflineStatus(_isOffline);

      debugPrint('✅ ScheduleScreen: Initial connectivity check - offline: $_isOffline');

      // Auto-sync dirty notes for this book if online
      if (serverReachable) {
        _autoSyncDirtyNotes();
      }

      // Preloading is now triggered automatically by BlocListener when events are loaded
    } catch (e) {
      debugPrint('❌ ScheduleScreen: Failed to initialize ContentService: $e');
      // Continue without ContentService - sync will not work but UI remains functional
      setState(() {
        _isOffline = true;
      });

      if (mounted) {
        context.read<ScheduleCubit>().setOfflineStatus(_isOffline);
      }
    }
  }

  /// Setup network connectivity monitoring for automatic sync retry
  void _setupConnectivityMonitoring() {
    debugPrint('🌐 ScheduleScreen: Setting up connectivity monitoring...');

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (ConnectivityResult result) {
        _onConnectivityChanged(result);
      },
    );

    // Also check initial connectivity state
    Connectivity().checkConnectivity().then((result) {
      _onConnectivityChanged(result);
    });
  }

  /// Check actual server connectivity using health check
  /// Returns true if server is reachable, false otherwise
  Future<bool> _checkServerConnectivity() async {
    if (_contentService == null) {
      debugPrint('⚠️ ScheduleScreen: Cannot check server - ContentService not initialized');
      return false;
    }

    try {
      debugPrint('🔍 ScheduleScreen: Checking server connectivity via health check...');
      final isHealthy = await _contentService!.healthCheck();
      debugPrint(isHealthy
        ? '✅ ScheduleScreen: Server is reachable'
        : '❌ ScheduleScreen: Server health check returned false');
      return isHealthy;
    } catch (e) {
      debugPrint('❌ ScheduleScreen: Server health check failed: $e');
      return false;
    }
  }

  /// Handle connectivity changes - automatically retry sync when network returns
  void _onConnectivityChanged(ConnectivityResult result) {
    final hasConnection = result != ConnectivityResult.none;

    debugPrint('🌐 ScheduleScreen: Connectivity changed - hasConnection: $hasConnection, result: $result');

    // Verify actual server connectivity, not just network interface status
    Future.microtask(() async {
      final serverReachable = await _checkServerConnectivity();
      final wasOfflineBefore = _wasOfflineLastCheck;

      if (mounted) {
        setState(() {
          _isOffline = !serverReachable;
          _wasOfflineLastCheck = !serverReachable;
        });

        context.read<ScheduleCubit>().setOfflineStatus(_isOffline);

        debugPrint('🌐 ScheduleScreen: Offline state updated based on server check: $_isOffline');

        // Network just came back online - auto-sync dirty notes
        if (serverReachable && wasOfflineBefore) {
          debugPrint('🌐 ScheduleScreen: Server restored! Auto-syncing dirty notes...');

          // Wait a bit for network to stabilize
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && !_isSyncing) {
              _autoSyncDirtyNotes();
            }
          });
        }
      }
    });
  }

  /// Auto-sync dirty notes for this book in background
  Future<void> _autoSyncDirtyNotes() async {
    if (_contentService == null || _isSyncing) return;

    setState(() {
      _isSyncing = true;
    });

    try {
      debugPrint('🔄 ScheduleScreen: Auto-syncing dirty notes for book $_bookId...');

      final result = await _contentService!.syncDirtyNotesForBook(_bookId);

      if (mounted) {
        setState(() {
          _isSyncing = false;
        });

        // Show user feedback
        if (result.nothingToSync) {
          debugPrint('✅ ScheduleScreen: No dirty notes to sync');
        } else if (result.allSucceeded) {
          debugPrint('✅ ScheduleScreen: All ${result.total} notes synced successfully');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced ${result.total} offline note${result.total > 1 ? 's' : ''}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (result.hasFailures) {
          debugPrint('⚠️ ScheduleScreen: ${result.success}/${result.total} notes synced, ${result.failed} failed');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced ${result.success}/${result.total} notes. ${result.failed} failed - check if book is backed up'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: () {
                  // Show dialog with more info
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Sync Failed'),
                      content: const Text(
                        'Some notes failed to sync because the book doesn\'t exist on the server yet.\n\n'
                        'Solution: Use the book backup feature to sync the book to the server first.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ ScheduleScreen: Auto-sync failed: $e');
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Cancel network connectivity subscription
    _connectivitySubscription?.cancel();

    // Cancel date check timer
    _dateCheckTimer?.cancel();

    // Cancel debounced save timer
    _saveDebounceTimer?.cancel();

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

      // Check if user is viewing a 3-day window that contains "today" (the new current date)
      final windowStart = _get3DayWindowStart_LOCAL(_selectedDate);
      final windowEnd = windowStart.add(const Duration(days: 3));
      // Check if the old "today" (lastActiveDate) is in the current viewing window
      final isViewingWindowContainingToday = lastActiveDate.isAfter(windowStart.subtract(const Duration(days: 1))) &&
                                          lastActiveDate.isBefore(windowEnd);

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

        if (mounted) {
          context.read<ScheduleCubit>().selectDate(_selectedDate);
        }

        // Reload drawing for new date
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

  /// Get unique page identifier for the current view and date
  String _getPageId() {
    // For 3-day view, use window start to keep same page across days in window
    final normalizedDate = _get3DayWindowStart_LOCAL(_selectedDate);
    return '3day_${normalizedDate.millisecondsSinceEpoch}';
  }

  /// Get or create canvas key for the current page
  GlobalKey<HandwritingCanvasState> _getCanvasKeyForCurrentPage() {
    final pageId = _getPageId();
    if (!_canvasKeys.containsKey(pageId)) {
      _canvasKeys[pageId] = GlobalKey<HandwritingCanvasState>();
    }
    return _canvasKeys[pageId]!;
  }

  Future<void> _loadDrawing() async {
    try {
      // Reset current drawing to avoid carrying old IDs
      setState(() {
        _currentDrawing = null;
      });

      // Use effective date to ensure consistency with UI rendering
      // For 3-Day View, this uses the window start date
      final effectiveDate = _getEffectiveDate_LOCAL();

      // Use ContentService for cache-first strategy with server fallback
      // This enables automatic server fetch when cache is empty
      ScheduleDrawing? drawing;
      if (_contentService != null) {
        debugPrint('📖 Loading drawing via ContentService (cache-first with server fallback)...');
        drawing = await _contentService!.getDrawing(
          bookId: _bookId,
          date: effectiveDate,
          viewMode: ScheduleDrawing.VIEW_MODE_3DAY,
          forceRefresh: false, // Use cache if available
        );
      } else {
        // Fallback to direct database access if ContentService not initialized
        debugPrint('⚠️ ContentService not available, loading drawing from cache only');
        drawing = await _dbService.getCachedDrawing(
          _bookId,
          effectiveDate,
          ScheduleDrawing.VIEW_MODE_3DAY,
        );
      }

      setState(() {
        _currentDrawing = drawing;
      });

      context.read<ScheduleCubit>().loadDrawing(viewMode: ScheduleDrawing.VIEW_MODE_3DAY, forceRefresh: false);

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
  /// RACE CONDITION FIX: Debounce saves by 500ms to prevent excessive saves
  void _scheduleSaveDrawing() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveDrawing();
    });
    debugPrint('⏱️ Scheduled debounced save (500ms)');
  }

  Future<void> _saveDrawing() async {
    // RACE CONDITION FIX: Prevent concurrent saves
    if (_isSaving) {
      debugPrint('⚠️ Save already in progress, skipping...');
      return;
    }

    final canvasState = _getCanvasKeyForCurrentPage().currentState;
    if (canvasState == null) {
      debugPrint('⚠️ Cannot save: canvas state is null');
      return;
    }

    // Check if canvas version has changed since last save
    final currentCanvasVersion = canvasState.canvasVersion;
    if (currentCanvasVersion == _lastSavedCanvasVersion) {
      debugPrint('⏩ Canvas unchanged (version: $currentCanvasVersion), skipping save');
      return;
    }

    _isSaving = true;
    try {
      final strokes = canvasState.getStrokes();
      final now = TimeService.instance.now();

      // Use effective date to ensure consistency with UI rendering
      // For 3-Day View, this uses the window start date
      final effectiveDate = _getEffectiveDate_LOCAL();

      // Only use existing ID, createdAt, and version if it matches the current page
      // This prevents reusing old values when switching pages
      int? drawingId;
      DateTime? createdAt;
      int version = 1; // Default version for new drawings
      if (_currentDrawing != null &&
          _currentDrawing!.bookId == _bookId &&
          _currentDrawing!.viewMode == ScheduleDrawing.VIEW_MODE_3DAY &&
          _currentDrawing!.date.year == effectiveDate.year &&
          _currentDrawing!.date.month == effectiveDate.month &&
          _currentDrawing!.date.day == effectiveDate.day) {
        drawingId = _currentDrawing!.id;
        createdAt = _currentDrawing!.createdAt;
        version = _currentDrawing!.version; // Preserve version for optimistic locking
      }

      final drawing = ScheduleDrawing(
        id: drawingId,
        bookId: _bookId,
        date: effectiveDate,
        viewMode: ScheduleDrawing.VIEW_MODE_3DAY,
        strokes: strokes,
        version: version, // Use preserved version from current drawing
        createdAt: createdAt ?? now,
        updatedAt: now,
      );

      debugPrint('💾 Saving ${strokes.length} strokes for page ${_getPageId()} (effectiveDate: $effectiveDate, id: $drawingId, version: $version)');

      // Use ContentService to save drawing (syncs to server and cache)
      // Falls back to direct database save if ContentService not available
      if (_contentService != null) {
        debugPrint('💾 Saving drawing via ContentService (syncs to server + cache)...');
        await _contentService!.saveDrawing(drawing);

        // RACE CONDITION FIX: Check if canvas changed during async save
        final currentStateAfterSave = _getCanvasKeyForCurrentPage().currentState;
        if (currentStateAfterSave != null &&
            currentStateAfterSave.canvasVersion != currentCanvasVersion) {
          debugPrint('⚠️ Canvas changed during save (v$currentCanvasVersion → v${currentStateAfterSave.canvasVersion}), skipping state update');
          return; // Don't update _currentDrawing with stale data
        }

        // Update current drawing state - fetch back from cache to get server-assigned ID
        final savedDrawing = await _dbService.getCachedDrawing(
          _bookId,
          effectiveDate,
          1,
        );
        if (mounted) {
          setState(() {
            _currentDrawing = savedDrawing ?? drawing;
          });
        }

        if (mounted) {
          context.read<ScheduleCubit>().saveDrawing(savedDrawing ?? drawing);
        }
      } else {
        debugPrint('⚠️ ContentService not available, saving to cache only');
        final savedDrawing = await _dbService.saveCachedDrawing(drawing);

        // RACE CONDITION FIX: Check if canvas changed during async save
        final currentStateAfterSave = _getCanvasKeyForCurrentPage().currentState;
        if (currentStateAfterSave != null &&
            currentStateAfterSave.canvasVersion != currentCanvasVersion) {
          debugPrint('⚠️ Canvas changed during save (v$currentCanvasVersion → v${currentStateAfterSave.canvasVersion}), skipping state update');
          return; // Don't update _currentDrawing with stale data
        }

        if (mounted) {
          setState(() {
            _currentDrawing = savedDrawing;
          });
        }

        if (mounted) {
          context.read<ScheduleCubit>().saveDrawing(savedDrawing);
        }
      }

      debugPrint('✅ Save successful, id: ${_currentDrawing?.id}');
      // Update last saved version to prevent redundant saves
      _lastSavedCanvasVersion = currentCanvasVersion;
    } catch (e) {
      debugPrint('❌ Error saving drawing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorSavingDrawing(e.toString()))),
        );
      }
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _toggleDrawingMode() async {
    if (_isDrawingMode) {
      // Exiting drawing mode - cancel pending debounced save and save immediately
      _saveDebounceTimer?.cancel();
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

  DateTime _get3DayWindowStart_LOCAL(DateTime date) {
    // Use fixed anchor to calculate stable 3-day windows
    // This ensures the same 3-day window is shown even when the real-world date changes
    final anchor = DateTime(2000, 1, 1); // Fixed epoch anchor
    final daysSinceAnchor = date.difference(anchor).inDays;
    final windowIndex = daysSinceAnchor ~/ 3;
    final windowStart = anchor.add(Duration(days: windowIndex * 3));
    return DateTime(windowStart.year, windowStart.month, windowStart.day);
  }


  /// Get the effective date for data operations (loading/saving events and drawings)
  /// This ensures consistency between UI rendering and data layer
  DateTime _getEffectiveDate_LOCAL() {
    return _get3DayWindowStart_LOCAL(_selectedDate); // Always 3-day view
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
    return const Duration(days: 3); // Always 3-day view
  }

  /// Check if currently viewing today's date
  bool _isViewingToday_LOCAL() {
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
      bookId: _bookId,
      name: '',
      recordNumber: '',
      eventType: EventType.consultation, // Default to consultation for new events
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
      context.read<ScheduleCubit>().loadEvents();
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
      context.read<ScheduleCubit>().loadEvents();
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
    } else if (action == 'changeTime') {
      await _changeEventTimeFromSchedule(event);
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

        final newEvent = await _dbService.changeEventTime(event, newStartTime, newEndTime, reason);
        _closeEventMenu();

        context.read<ScheduleCubit>().loadEvents();

        // Sync to server in background (best effort, no error handling needed)
        _syncEventToServer(newEvent);

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

  /// Sync event and note to server in background (best effort)
  Future<void> _syncEventToServer(Event event) async {
    if (_contentService == null) {
      debugPrint('⚠️ ScheduleScreen: ContentService not available, cannot sync event ${event.id}');
      return;
    }

    if (event.id == null) {
      debugPrint('⚠️ ScheduleScreen: Event ID is null, cannot sync');
      return;
    }

    try {
      debugPrint('🔄 ScheduleScreen: Syncing event ${event.id} and note to server...');
      await _contentService!.syncNote(event.id!);
      debugPrint('✅ ScheduleScreen: Event ${event.id} synced to server successfully');
    } catch (e) {
      // Silent failure - data is already saved locally and marked as dirty
      // It will be synced when the user opens the event detail screen
      debugPrint('⚠️ ScheduleScreen: Background sync failed (will retry later): $e');
    }
  }

  /// Get localized string for EventType
  String _getLocalizedEventType(BuildContext context, EventType type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case EventType.consultation:
        return l10n.consultation;
      case EventType.surgery:
        return l10n.surgery;
      case EventType.followUp:
        return l10n.followUp;
      case EventType.emergency:
        return l10n.emergency;
      case EventType.checkUp:
        return l10n.checkUp;
      case EventType.treatment:
        return l10n.treatment;
      case EventType.other:
        return 'Other'; // Default for unspecified types
    }
  }

  Future<void> _changeEventType(Event event) async {
    final l10n = AppLocalizations.of(context)!;
    final eventTypes = [
      EventType.consultation,
      EventType.surgery,
      EventType.followUp,
      EventType.emergency,
      EventType.checkUp,
      EventType.treatment,
    ];

    final selectedType = await showDialog<EventType>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changeEventType),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: eventTypes.map((type) => ListTile(
            title: Text(_getLocalizedEventType(context, type)),
            leading: Radio<EventType>(
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
        context.read<ScheduleCubit>().updateEvent(updatedEvent);

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

  Future<void> _changeEventTimeFromSchedule(Event event) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        DateTime newStartTime = event.startTime;
        DateTime? newEndTime = event.endTime;
        final reasonController = TextEditingController();
        bool showReasonError = false;

        return StatefulBuilder(
          builder: (context, setState) {
            final bool hasValidReason = reasonController.text.trim().isNotEmpty;

            return AlertDialog(
              title: Text(l10n.changeEventTime),
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
                            final result = await DateTimePickerUtils.pickDateTime(
                              context,
                              initialDateTime: newStartTime,
                            );
                            if (result == null) return;

                            setState(() {
                              newStartTime = result;
                            });
                          },
                          child: Text(
                            'Start: ${DateFormat('MMM d, HH:mm', Localizations.localeOf(context).toString()).format(newStartTime)}',
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
                            final result = await DateTimePickerUtils.pickDateTime(
                              context,
                              initialDateTime: newEndTime ?? newStartTime,
                              firstDate: newStartTime,
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (result == null) return;

                            setState(() {
                              newEndTime = result;
                            });
                          },
                          child: Text(
                            newEndTime != null
                                ? 'End: ${DateFormat('MMM d, HH:mm', Localizations.localeOf(context).toString()).format(newEndTime!)}'
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

    try {
      // Use cubit method to change event time (creates new event + soft-deletes old)
      await context.read<ScheduleCubit>().changeEventTime(
        event,
        result['startTime'],
        result['endTime'],
        result['reason'],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.eventTimeChangedSuccess),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorChangingEventTime(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
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
        await context.read<ScheduleCubit>().deleteEvent(event.id!, reason: reason);

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
        // Use cubit method for hard delete (permanent deletion)
        await context.read<ScheduleCubit>().hardDeleteEvent(event.id!);

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
            // Date navigation - Previous button
            IconButton(
              onPressed: () async {
                if (_isDrawingMode) {
                  _saveDebounceTimer?.cancel();
                  await _saveDrawing();
                }
                setState(() {
                  _selectedDate = _selectedDate.subtract(_getNavigationIncrement());
                });

                context.read<ScheduleCubit>().selectDate(_selectedDate);
                await _loadDrawing();
              },
              icon: const Icon(Icons.chevron_left, size: 18),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 4),
            // Date display
            GestureDetector(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  if (_isDrawingMode) {
                    _saveDebounceTimer?.cancel();
                    await _saveDrawing();
                  }
                  setState(() {
                    _selectedDate = date;
                  });

                  context.read<ScheduleCubit>().selectDate(_selectedDate);
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
            const SizedBox(width: 4),
            // Date navigation - Next button
            IconButton(
              onPressed: () async {
                if (_isDrawingMode) {
                  _saveDebounceTimer?.cancel();
                  await _saveDrawing();
                }
                setState(() {
                  _selectedDate = _selectedDate.add(_getNavigationIncrement());
                });

                context.read<ScheduleCubit>().selectDate(_selectedDate);
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
              if (_isDrawingMode) {
                _saveDebounceTimer?.cancel();
                await _saveDrawing();
              }
              setState(() {
                _selectedDate = TimeService.instance.now();
                _lastActiveDate = TimeService.instance.now();
              });

              context.read<ScheduleCubit>().selectDate(_selectedDate);
              await _loadDrawing();
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
          // Event context menu overlay
          if (_buildEventContextMenuOverlay(events) != null)
            _buildEventContextMenuOverlay(events)!,
            ],
          );
        },
      ), // BlocBuilder
      floatingActionButton: ScheduleFabMenuHelper.buildFabMenu(
        context: context,
        isMenuVisible: _isFabMenuVisible,
        onToggleMenu: _toggleFabMenu,
        isDrawingMode: _isDrawingMode,
        isViewingToday: _isViewingToday_LOCAL,
        selectedDate: _selectedDate,
        lastActiveDate: _lastActiveDate,
        saveDrawing: _saveDrawing,
        loadDrawing: _loadDrawing,
        toggleDrawingMode: _toggleDrawingMode,
        createEvent: () => _createEvent(),
        dbService: _dbService,
        bookId: _bookId,
        get3DayWindowStart: _get3DayWindowStart_LOCAL,
        cacheManager: _cacheManager,
        getEffectiveDate: _getEffectiveDate_LOCAL,
        preloadNotes: _preloadNotesInBackground,
        onDateChange: _changeDateTo,
      ),
    ), // Scaffold
    ), // PopScope
    ); // BlocListener
  }

  String _getDateDisplayText() {
    // Always show 3-day range
    final windowStart = _get3DayWindowStart_LOCAL(_selectedDate);
    final windowEnd = windowStart.add(const Duration(days: 2));
    return '${DateFormat('MMM d', Localizations.localeOf(context).toString()).format(windowStart)} - ${DateFormat('MMM d, y', Localizations.localeOf(context).toString()).format(windowEnd)}';
  }

  Widget _build3DayView(List<Event> events, bool showOldEvents) {
    // Use stable 3-day window instead of _selectedDate to prevent page changes on date changes
    final windowStart = _get3DayWindowStart_LOCAL(_selectedDate);
    final dates = List.generate(3, (index) => windowStart.add(Duration(days: index)));
    return _buildTimeSlotView(dates, _getCanvasKeyForCurrentPage(), events, showOldEvents);
  }

  Widget _buildTimeSlotView(
    List<DateTime> dates,
    GlobalKey<HandwritingCanvasState> canvasKey,
    List<Event> events,
    bool showOldEvents,
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

        debugPrint('📐 Schedule Layout: constraints=(${constraints.maxWidth.toStringAsFixed(2)}, ${constraints.maxHeight.toStringAsFixed(2)}) dateHeader=${dateHeaderHeight.toStringAsFixed(2)} availableForSlots=${availableHeightForSlots.toStringAsFixed(2)} viewMode=3day drawingMode=$_isDrawingMode');

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
                              DateFormat('EEE d', Localizations.localeOf(context).toString()).format(date),
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
                              _buildEventsOverlay(dates, slotHeight, dateHeaderHeight, events, showOldEvents),
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
                            setState(() {}); // Rebuild toolbar to update undo/redo/clear buttons
                            // RACE CONDITION FIX: Schedule debounced save instead of immediate save
                            // This reduces server load and prevents race conditions during fast drawing
                            _scheduleSaveDrawing();
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

  /// Build events overlay with absolute positioning to allow spanning multiple time slots
  Widget _buildEventsOverlay(List<DateTime> dates, double slotHeight, double dateHeaderHeight, List<Event> events, bool showOldEvents) {
    return Row(
      children: [
        const SizedBox(width: 60), // Time column width
        ...dates.map((date) {
          final dateEvents = _getEventsForDate_LOCAL(date, events, showOldEvents);

          return Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth - 4; // Account for padding/borders

                // Build slot occupancy map: slot index -> set of occupied horizontal positions
                final Map<int, Set<int>> slotOccupancy = {};

                // Group events by start time slot
                final Map<int, List<Event>> eventsBySlot = {};
                for (final event in dateEvents) {
                  final slotIndex = _getSlotIndexForTime_LOCAL(event.startTime);
                  eventsBySlot.putIfAbsent(slotIndex, () => []).add(event);
                }

                // Calculate concurrent event count per time slot
                final Map<int, int> slotEventCount = {};

                for (final event in dateEvents) {
                  final slotIndex = _getSlotIndexForTime_LOCAL(event.startTime);
                  final durationInMinutes = ScheduleEventTileHelper.getDisplayDurationInMinutes(event);
                  final slotsSpanned = ((durationInMinutes / 15).ceil()).clamp(1, 48);

                  // Increment count for all slots this event occupies
                  for (int spanOffset = 0; spanOffset < slotsSpanned; spanOffset++) {
                    final occupiedSlot = slotIndex + spanOffset;
                    slotEventCount[occupiedSlot] = (slotEventCount[occupiedSlot] ?? 0) + 1;
                  }
                }

                // Build positioned widgets
                final List<Widget> positionedWidgets = [];

                // Process events in order of time slots
                final sortedSlotIndices = eventsBySlot.keys.toList()..sort();

                for (final slotIndex in sortedSlotIndices) {
                  final slotEvents = eventsBySlot[slotIndex]!;

                  // Separate close-end and open-end events
                  final closeEndEvents = slotEvents.where((e) => !ScheduleEventTileHelper.shouldDisplayAsOpenEnd(e)).toList();
                  final openEndEvents = slotEvents.where((e) => ScheduleEventTileHelper.shouldDisplayAsOpenEnd(e)).toList();

                  // Sort each list by ID
                  closeEndEvents.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
                  openEndEvents.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));

                  // Process in order: close-end events first, then open-end events
                  final orderedEvents = [...closeEndEvents, ...openEndEvents];

                  for (final event in orderedEvents) {
                    // Calculate display duration and slots spanned
                    final durationInMinutes = ScheduleEventTileHelper.getDisplayDurationInMinutes(event);
                    final slotsSpanned = ((durationInMinutes / 15).ceil()).clamp(1, 48);

                    // Calculate max concurrent events for this specific event across all slots it spans
                    int maxConcurrentForThisEvent = 4; // Default minimum of 4
                    for (int spanOffset = 0; spanOffset < slotsSpanned; spanOffset++) {
                      final checkSlot = slotIndex + spanOffset;
                      final concurrentInSlot = slotEventCount[checkSlot] ?? 0;
                      maxConcurrentForThisEvent = max(maxConcurrentForThisEvent, concurrentInSlot);
                    }

                    // Calculate event width: keep 25% for up to 4 events, adjust for this event's specific grid
                    final eventWidth = availableWidth / maxConcurrentForThisEvent;

                    // Find leftmost available horizontal position across all spanned slots
                    int horizontalPosition = 0;
                    bool positionFound = false;

                    for (int pos = 0; pos < maxConcurrentForThisEvent; pos++) {
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

                    // If no position found, skip this event (should not happen with dynamic positioning)
                    if (!positionFound) {
                      debugPrint('⚠️ No position found for event ${event.id} at slot $slotIndex (max concurrent: $maxConcurrentForThisEvent)');
                      continue;
                    }

                    // Mark position as occupied in all spanned slots
                    for (int spanOffset = 0; spanOffset < slotsSpanned; spanOffset++) {
                      final occupySlot = slotIndex + spanOffset;
                      slotOccupancy.putIfAbsent(occupySlot, () => {}).add(horizontalPosition);
                    }

                    // Calculate position and height
                    final topPosition = _calculateEventTopPosition(event, slotHeight);
                    final tileHeight = (slotsSpanned * slotHeight) - 1; // Subtract margin

                    // Create positioned widget
                    positionedWidgets.add(
                      Positioned(
                        top: topPosition,
                        left: horizontalPosition * eventWidth,
                        width: eventWidth,
                        height: tileHeight,
                        child: ScheduleEventTileHelper.buildEventTile(
                          context: context,
                          event: event,
                          slotHeight: slotHeight,
                          events: events,
                          getEventTypeColor: _getEventTypeColor,
                          onTap: () => _editEvent(event),
                          onLongPress: (offset) => _showEventContextMenu(event, offset),
                          isMenuOpen: _selectedEventForMenu?.id == event.id,
                          dottedBorderPainter: (color) => CustomPaint(
                            painter: DottedBorderPainter(color: color, strokeWidth: 1),
                          ),
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
  int _getSlotIndexForTime_LOCAL(DateTime time) {
    final minutesFromStart = (time.hour - _startHour) * 60 + time.minute;
    return minutesFromStart ~/ 15;
  }

  /// Get all events for a specific date (used for overlay rendering)
  List<Event> _getEventsForDate_LOCAL(DateTime date, List<Event> events, bool showOldEvents) {
    return events.where((event) {
      // Filter by date
      final matchesDate = event.startTime.year == date.year &&
                          event.startTime.month == date.month &&
                          event.startTime.day == date.day;

      if (!matchesDate) return false;

      // Filter out old events if toggle is off
      // Old events = removed events or time-changed old versions
      if (!showOldEvents && (event.isRemoved || event.hasNewTime)) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Calculate the Y position offset for an event based on its start time
  double _calculateEventTopPosition(Event event, double slotHeight) {
    final totalMinutesFromStart = (event.startTime.hour - _startHour) * 60 + event.startTime.minute;
    final minutesPerSlot = 15;
    return (totalMinutesFromStart / minutesPerSlot) * slotHeight;
  }

  Color _getEventTypeColor(BuildContext context, EventType eventType) {
    // Color coding based on event type enum (type-safe)
    final Color baseColor;

    switch (eventType) {
      case EventType.consultation:
        baseColor = Colors.blue;
        break;
      case EventType.surgery:
        baseColor = Colors.red;
        break;
      case EventType.followUp:
        baseColor = Colors.green;
        break;
      case EventType.emergency:
        baseColor = Colors.orange;
        break;
      case EventType.checkUp:
        baseColor = Colors.purple;
        break;
      case EventType.treatment:
        baseColor = Colors.cyan;
        break;
      case EventType.other:
        // Default color for unknown types
        baseColor = Colors.grey;
        break;
    }

    // Reduce saturation to 60%
    final hslColor = HSLColor.fromColor(baseColor);
    return hslColor.withSaturation(0.60).toColor();
  }

  Widget? _buildEventContextMenuOverlay(List<Event> events) {
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
                leading: const Icon(Icons.access_time, size: 20),
                title: Text(l10n.changeEventTime, style: const TextStyle(fontSize: 14)),
                onTap: () => _handleMenuAction('changeTime', event),
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

}
