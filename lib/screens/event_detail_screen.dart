import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/event.dart';
import '../models/note.dart';
import '../services/database_service_interface.dart';
import '../services/prd_database_service.dart';
import '../services/web_prd_database_service.dart';
import '../services/content_service.dart';
import '../services/cache_manager.dart';
import '../services/api_client.dart';
import '../services/server_config_service.dart';
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

  // Offline-first state variables
  bool _isLoadingFromServer = false;
  bool _isOffline = false;
  bool _hasUnsyncedChanges = false;
  bool _isServicesReady = false; // Track if ContentService is initialized

  // Use appropriate database service based on platform
  IDatabaseService get _dbService => kIsWeb
      ? WebPRDDatabaseService()
      : PRDDatabaseService();

  // ContentService for cache-first and offline-first operations
  ContentService? _contentService; // Make nullable to handle initialization race

  final GlobalKey<HandwritingCanvasState> _canvasKey = GlobalKey<HandwritingCanvasState>();

  // Cache for new event when displaying time change info
  Event? _newEvent;

  // Backup storage for strokes in case canvas key is lost
  List<Stroke> _lastKnownStrokes = [];

  // Control panel visibility state
  bool _isControlPanelExpanded = false;

  // Network connectivity monitoring
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _wasOfflineLastCheck = false;

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

    // Initialize services and load data asynchronously
    _initialize();

    // Setup network connectivity monitoring for automatic sync retry
    _setupConnectivityMonitoring();
  }

  /// Initialize ContentService and load initial data
  Future<void> _initialize() async {
    try {
      debugPrint('🔧 EventDetail: Starting ContentService initialization...');

      // Step 1: Initialize ContentService with correct server URL
      final prdDb = _dbService as PRDDatabaseService;
      final serverConfig = ServerConfigService(prdDb);

      // Get server URL from device settings (or use localhost:8080 as fallback)
      final serverUrl = await serverConfig.getServerUrlOrDefault(
        defaultUrl: 'http://localhost:8080',
      );

      debugPrint('🔧 EventDetail: Initializing ContentService with server URL: $serverUrl');

      // Get device credentials for logging
      final credentials = await prdDb.getDeviceCredentials();
      if (credentials != null) {
        debugPrint('🔧 EventDetail: Device registered - ID: ${credentials.deviceId.substring(0, 8)}..., Token: ${credentials.deviceToken.substring(0, 16)}...');
      } else {
        debugPrint('⚠️ EventDetail: No device credentials found! User needs to register device first.');
      }

      final apiClient = ApiClient(baseUrl: serverUrl);
      final cacheManager = CacheManager(prdDb);
      _contentService = ContentService(apiClient, cacheManager, _dbService);

      // Mark services as ready
      if (mounted) {
        setState(() {
          _isServicesReady = true;
        });
      }

      debugPrint('✅ EventDetail: ContentService initialized successfully');

      // Step 1.5: Check actual server connectivity on startup
      debugPrint('🔍 EventDetail: Checking initial server connectivity...');
      final serverReachable = await _checkServerConnectivity();
      if (mounted) {
        setState(() {
          _isOffline = !serverReachable;
          _wasOfflineLastCheck = !serverReachable;
        });
        debugPrint('✅ EventDetail: Initial connectivity check complete - offline: $_isOffline');
      }

      // Step 2: Load initial data (now that ContentService is ready)
      if (!widget.isNew) {
        await _loadNote();
        if (widget.event.hasNewTime) {
          await _loadNewEvent();
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ EventDetail: Failed to initialize ContentService: $e');
      debugPrint('❌ EventDetail: Stack trace: $stackTrace');

      // Mark services as ready anyway to avoid blocking UI forever
      if (mounted) {
        setState(() {
          _isServicesReady = true;
          _isOffline = true; // Mark as offline since initialization failed
        });

        // Show error to user
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

  /// Setup network connectivity monitoring for automatic sync retry
  void _setupConnectivityMonitoring() {
    debugPrint('🌐 EventDetail: Setting up connectivity monitoring...');

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
      debugPrint('⚠️ EventDetail: Cannot check server - ContentService not initialized');
      return false;
    }

    try {
      debugPrint('🔍 EventDetail: Checking server connectivity via health check...');
      final isHealthy = await _contentService!.healthCheck();
      debugPrint(isHealthy
        ? '✅ EventDetail: Server is reachable'
        : '❌ EventDetail: Server health check returned false');
      return isHealthy;
    } catch (e) {
      debugPrint('❌ EventDetail: Server health check failed: $e');
      return false;
    }
  }

  /// Handle connectivity changes - automatically retry sync when network returns
  void _onConnectivityChanged(ConnectivityResult result) {
    final hasConnection = result != ConnectivityResult.none;

    debugPrint('🌐 EventDetail: Connectivity changed - hasConnection: $hasConnection, result: $result');

    // Verify actual server connectivity, not just network interface status
    // connectivity_plus can give false negatives/positives
    Future.microtask(() async {
      final serverReachable = await _checkServerConnectivity();
      final wasOfflineBefore = _wasOfflineLastCheck;

      if (mounted) {
        setState(() {
          _isOffline = !serverReachable;
          _wasOfflineLastCheck = !serverReachable;
        });

        debugPrint('🌐 EventDetail: Offline state updated based on server check: $_isOffline');

        // Network just came back online
        if (serverReachable && wasOfflineBefore) {
          debugPrint('🌐 EventDetail: Server restored! Checking for unsynced changes...');

          // If we have unsynced changes, automatically retry sync
          if (_hasUnsyncedChanges && widget.event.id != null) {
            debugPrint('🌐 EventDetail: Auto-retrying sync after server restoration...');

            // Wait a bit for network to stabilize
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted && _hasUnsyncedChanges) {
                _syncNoteInBackground(widget.event.id!);
              }
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _recordNumberController.dispose();
    _eventTypeController.dispose();
    _connectivitySubscription?.cancel();
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

  /// Load note with cache-first strategy
  ///
  /// Phase 4-01 Implementation:
  /// 1. Load from cache immediately (instant display)
  /// 2. Background refresh from server (don't block UI)
  /// 3. Handle offline gracefully with status indicators
  Future<void> _loadNote() async {
    if (widget.event.id == null) {
      debugPrint('🔍 EventDetail: Cannot load note - event ID is null');
      return;
    }

    if (_contentService == null) {
      debugPrint('⚠️ EventDetail: Cannot load note - ContentService not initialized');
      return;
    }

    debugPrint('📖 EventDetail: Loading note for event ${widget.event.id}');

    // **Step 1: Load from cache immediately (不阻塞UI)**
    final cachedNote = await _contentService!.getCachedNote(widget.event.id!);
    if (cachedNote != null) {
      setState(() {
        _note = cachedNote;
        _hasUnsyncedChanges = cachedNote.isDirty; // 显示"未同步"提示
      });
      debugPrint('✅ EventDetail: Loaded from cache (${cachedNote.strokes.length} strokes, isDirty: ${cachedNote.isDirty})');

      // Validate canvas state after note load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final canvasState = _canvasKey.currentState;
        if (canvasState != null) {
          canvasState.validateState();
          final stateInfo = canvasState.getStateInfo();
          final expectedStrokes = cachedNote.strokes.length;
          final actualStrokes = stateInfo['strokeCount'] as int;
          if (actualStrokes != expectedStrokes) {
            debugPrint('⚠️ EventDetail: Canvas stroke mismatch! Expected: $expectedStrokes, Actual: $actualStrokes');
            canvasState.forceRefreshState(cachedNote.strokes);
          }
        }
      });
    }

    // **Step 2: Background refresh from server (不阻塞UI)**
    // BUT: If cached note is dirty, prioritize local changes and push to server instead
    if (cachedNote != null && cachedNote.isDirty) {
      debugPrint('📤 EventDetail: Cached note is dirty, syncing to server instead of fetching');
      setState(() => _isLoadingFromServer = true);

      // Push local changes to server instead of fetching
      try {
        await _contentService!.syncNote(widget.event.id!);
        if (mounted) {
          setState(() {
            _hasUnsyncedChanges = false;
            _isLoadingFromServer = false;
            _isOffline = false;
          });
        }
        debugPrint('✅ EventDetail: Dirty note synced to server successfully');
      } catch (e) {
        debugPrint('⚠️ EventDetail: Failed to sync dirty note: $e');
        if (mounted) {
          setState(() {
            _isLoadingFromServer = false;
            _isOffline = true;
          });
        }
      }
      return; // Don't fetch from server - we just pushed our changes
    }

    // Normal flow: Fetch from server (only if note is not dirty)
    setState(() => _isLoadingFromServer = true);

    try {
      final serverNote = await _contentService!.getNote(
        widget.event.id!,
        forceRefresh: true, // 跳过cache，强制fetch
      );

      if (serverNote != null && mounted) {
        setState(() {
          _note = serverNote;
          _hasUnsyncedChanges = false; // Server数据是最新的
          _isLoadingFromServer = false;
          _isOffline = false;
        });
        debugPrint('✅ EventDetail: Refreshed from server');

        // Refresh canvas with server data
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final canvasState = _canvasKey.currentState;
          if (canvasState != null) {
            canvasState.forceRefreshState(serverNote.strokes);
          }
        });
      } else if (mounted) {
        setState(() {
          _isLoadingFromServer = false;
        });
      }
    } catch (e) {
      // Network failure → 继续使用cache
      if (mounted) {
        setState(() {
          _isLoadingFromServer = false;
          _isOffline = true; // 标记离线模式
        });
        debugPrint('⚠️ EventDetail: Server fetch failed, using cache: $e');

        // 显示友好提示（不是错误）
        if (cachedNote != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.showingCachedData),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
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

      // **Data Safety First**: Always save handwriting note using offline-first strategy
      try {
        await _saveNoteWithOfflineFirst(savedEvent.id!);
      } catch (e) {
        // Log error but don't fail the entire save operation
        debugPrint('❌ Failed to save note: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.errorSavingNote(e.toString())),
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

  /// Save note with offline-first strategy (Phase 4-01 Implementation)
  ///
  /// **Data Safety First Principle**:
  /// 1. Save locally first (always succeeds unless disk full)
  /// 2. Show immediate success feedback to user
  /// 3. Sync to server in background (best effort)
  Future<void> _saveNoteWithOfflineFirst(int eventId) async {
    debugPrint('💾 EventDetail: Starting offline-first note save for event $eventId');

    // Check if services are ready
    if (_contentService == null) {
      throw Exception('ContentService not initialized. Cannot save note.');
    }

    final canvasState = _canvasKey.currentState;

    // Validate canvas state before saving
    if (canvasState != null) {
      canvasState.validateState();
    }

    // Get strokes from canvas or backup
    List<Stroke> strokes;
    if (canvasState != null) {
      strokes = canvasState.getStrokes();
      debugPrint('💾 EventDetail: Retrieved ${strokes.length} strokes from canvas');
    } else {
      strokes = List<Stroke>.from(_lastKnownStrokes);
      debugPrint('💾 EventDetail: Canvas state null, using backup strokes (${strokes.length} strokes)');
    }

    // Log stroke details for debugging
    debugPrint('💾 EventDetail: Saving note with ${strokes.length} strokes');
    for (int i = 0; i < strokes.length && i < 3; i++) {
      final stroke = strokes[i];
      debugPrint('   Stroke $i: ${stroke.points.length} points, width: ${stroke.strokeWidth}, color: ${stroke.color}');
    }

    // Create note object
    final noteToSave = Note(
      eventId: eventId,
      strokes: strokes,
      createdAt: _note?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      // **数据安全第一原则**: 先保存到本地
      debugPrint('💾 EventDetail: Calling ContentService.saveNote()...');
      await _contentService!.saveNote(eventId, noteToSave);
      debugPrint('✅ EventDetail: ContentService.saveNote() completed');

      // **CRITICAL: Verify local save succeeded by reading back**
      debugPrint('🔍 EventDetail: Verifying local save by reading back from cache...');
      final verifyNote = await _contentService!.getCachedNote(eventId);

      if (verifyNote == null) {
        throw Exception('Local save verification failed: Note not found in cache after save');
      }

      if (verifyNote.strokes.length != strokes.length) {
        throw Exception('Local save verification failed: Expected ${strokes.length} strokes but found ${verifyNote.strokes.length}');
      }

      debugPrint('✅ EventDetail: Local save verified - ${verifyNote.strokes.length} strokes in cache, isDirty: ${verifyNote.isDirty}');

      setState(() {
        _note = noteToSave;
        _hasChanges = false;
        _hasUnsyncedChanges = true; // 标记为dirty，等待同步
      });

      // 立即给用户反馈 - 明确说明是本地保存
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isOffline
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
      }

      debugPrint('✅ EventDetail: Note saved locally with ${strokes.length} strokes');

      // 后台同步到server（best effort）
      _syncNoteInBackground(eventId);

    } catch (e, stackTrace) {
      debugPrint('❌ EventDetail: Failed to save note: $e');
      debugPrint('❌ EventDetail: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Background sync note to server (不阻塞UI，静默失败)
  ///
  /// Phase 4-01: Best-effort sync, doesn't show errors to user
  /// Keeps dirty flag if sync fails for later retry
  ///
  /// IMPORTANT: This method learns from actual sync results to update
  /// connectivity status, not relying solely on connectivity_plus
  Future<void> _syncNoteInBackground(int eventId) async {
    if (_contentService == null) {
      debugPrint('⚠️ EventDetail: Cannot sync note - ContentService not initialized');
      return;
    }

    try {
      debugPrint('🔄 EventDetail: Starting background sync for note $eventId...');
      await _contentService!.syncNote(eventId);
      debugPrint('✅ EventDetail: Background sync completed successfully');

      if (mounted) {
        setState(() {
          _hasUnsyncedChanges = false; // 同步成功
          // Learn from success: if sync worked, server is definitely reachable
          _isOffline = false;
          _wasOfflineLastCheck = false;
        });
      }

      debugPrint('✅ EventDetail: Note synced to server (eventId: $eventId), offline status updated');
    } catch (e) {
      // 同步失败？没关系，保留dirty标记，后续重试
      debugPrint('⚠️ EventDetail: Background sync failed (will retry later): $e');

      // Learn from failure: if sync failed, verify server connectivity
      // (Don't immediately assume offline - could be auth issue, version conflict, etc.)
      final serverReachable = await _checkServerConnectivity();

      if (mounted) {
        setState(() {
          _isOffline = !serverReachable;
          _wasOfflineLastCheck = !serverReachable;
        });
      }

      debugPrint('ℹ️ EventDetail: Verified connectivity after sync failure - offline: $_isOffline');
      // 不显示错误给用户，因为本地数据已安全保存
    }
  }

  /// Manual retry sync - triggered by user pressing "Retry Sync" button
  Future<void> _manualRetrySync(int eventId) async {
    if (_contentService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot sync - Services not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading indicator
    setState(() => _isLoadingFromServer = true);

    try {
      debugPrint('🔄 EventDetail: Manual retry sync requested for note $eventId...');
      await _contentService!.syncNote(eventId);

      if (mounted) {
        setState(() {
          _hasUnsyncedChanges = false;
          // Learn from success: server is reachable
          _isOffline = false;
          _wasOfflineLastCheck = false;
          _isLoadingFromServer = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Successfully synced to server!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      debugPrint('✅ EventDetail: Manual sync succeeded');
    } catch (e) {
      debugPrint('❌ EventDetail: Manual sync failed: $e');

      // Verify actual server connectivity after failure
      final serverReachable = await _checkServerConnectivity();

      if (mounted) {
        setState(() {
          _isOffline = !serverReachable;
          _wasOfflineLastCheck = !serverReachable;
          _isLoadingFromServer = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Sync failed: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _manualRetrySync(eventId),
            ),
          ),
        );
      }
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
          // Phase 4-01: Sync status indicators in AppBar
          if (_hasUnsyncedChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.cloud_upload,
                color: Colors.orange,
                semanticLabel: 'Unsynced changes',
                size: 24,
              ),
            ),
          if (_isOffline && !_hasUnsyncedChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.cloud_off,
                color: Colors.grey,
                semanticLabel: 'Offline',
                size: 24,
              ),
            ),
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
            onPressed: (_isLoading || !_isServicesReady) ? null : _saveEvent,
            tooltip: _isServicesReady ? 'Save' : 'Initializing...',
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
                    // Phase 4-01: Status bar for offline/syncing indicators
                    _buildStatusBar(),
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

  /// Phase 4-01: Status bar for offline/syncing indicators
  Widget _buildStatusBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Offline banner with retry button
        if (_isOffline)
          Material(
            color: Colors.orange.shade700,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _hasUnsyncedChanges
                        ? 'Offline - Changes not synced'
                        : AppLocalizations.of(context)!.offlineMode,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  if (_hasUnsyncedChanges && widget.event.id != null)
                    TextButton(
                      onPressed: () => _manualRetrySync(widget.event.id!),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('Retry Sync', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

        // Unsynced changes banner
        if (_hasUnsyncedChanges && !_isOffline)
          Material(
            color: Colors.blue.shade700,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.syncingToServer,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

        // Background loading indicator
        if (_isLoadingFromServer && !_hasUnsyncedChanges)
          const LinearProgressIndicator(minHeight: 2),
      ],
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
                            _canvasKey.currentState?.setErasing(false);
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
                            _canvasKey.currentState?.setErasing(true);
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
                    onPressed: () => _canvasKey.currentState?.undo(),
                    tooltip: 'Undo',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo, size: 20),
                    onPressed: () => _canvasKey.currentState?.redo(),
                    tooltip: 'Redo',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () => _canvasKey.currentState?.clear(),
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
                                      _canvasKey.currentState?.setEraserRadius(value);
                                    } else {
                                      _canvasKey.currentState?.setStrokeWidth(value);
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
                                      _canvasKey.currentState?.setStrokeColor(color);
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