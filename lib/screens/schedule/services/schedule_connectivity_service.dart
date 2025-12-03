import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../../../services/database_service_interface.dart';
import '../../../services/database/prd_database_service.dart';
import '../../../services/content_service.dart';
import '../../../services/cache_manager.dart';
import '../../../services/api_client.dart';
import '../../../services/server_config_service.dart';
import '../../../models/event.dart';

/// Service for managing server connectivity, network monitoring, and automatic
/// synchronization of offline changes. Handles ContentService initialization,
/// connectivity change detection, and background sync operations.
class ScheduleConnectivityService {
  /// ContentService for server sync operations
  ContentService? _contentService;

  /// Cache manager for offline data
  CacheManager? _cacheManager;

  /// Database service reference
  final IDatabaseService _dbService;

  /// Book UUID for filtering sync operations
  final String _bookUuid;

  /// Whether currently offline (no server connection)
  bool _isOffline = false;

  /// Last checked offline state (for detecting transitions)
  bool _wasOfflineLastCheck = false;

  /// Whether currently performing sync operation
  bool _isSyncing = false;

  /// Connectivity subscription
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  /// Callback to update offline and syncing state
  final void Function(bool isOffline, bool isSyncing) onStateChanged;

  /// Callback to update cubit with offline status
  final void Function(bool isOffline) onUpdateCubitOfflineStatus;

  /// Callback to show snackbar
  final void Function(String message, {Color? backgroundColor, int? durationSeconds, SnackBarAction? action, String? detailTitle, String? detailMessage}) onShowSnackbar;

  /// Callback to check if widget is mounted
  final bool Function() isMounted;

  /// Callback to update drawing service with ContentService
  final void Function(ContentService? contentService) onUpdateDrawingServiceContentService;

  ScheduleConnectivityService({
    required IDatabaseService dbService,
    required String bookUuid,
    required this.onStateChanged,
    required this.onUpdateCubitOfflineStatus,
    required this.onShowSnackbar,
    required this.isMounted,
    required this.onUpdateDrawingServiceContentService,
  })  : _dbService = dbService,
        _bookUuid = bookUuid;

  /// Get current offline status
  bool get isOffline => _isOffline;

  /// Get current syncing status
  bool get isSyncing => _isSyncing;

  /// Get ContentService instance (may be null if initialization failed)
  ContentService? get contentService => _contentService;

  /// Initialize ContentService for server sync
  Future<void> initialize() async {
    try {
      final prdDb = _dbService as PRDDatabaseService;
      final serverConfig = ServerConfigService(prdDb);
      final serverUrl = await serverConfig.getServerUrlOrDefault(
        defaultUrl: 'http://localhost:8080',
      );
      final apiClient = ApiClient(baseUrl: serverUrl);
      _cacheManager = CacheManager(prdDb);
      _contentService = ContentService(apiClient, _cacheManager!, _dbService);

      // Update drawing service with ContentService
      onUpdateDrawingServiceContentService(_contentService);


      // Check server connectivity
      final serverReachable = await checkServerConnectivity();
      _isOffline = !serverReachable;
      _wasOfflineLastCheck = !serverReachable;
      onStateChanged(_isOffline, _isSyncing);
      onUpdateCubitOfflineStatus(_isOffline);


      // Auto-sync dirty notes for this book if online
      if (serverReachable) {
        autoSyncDirtyNotes();
      }
    } catch (e) {
      // Continue without ContentService - sync will not work but UI remains functional
      _isOffline = true;
      onStateChanged(_isOffline, _isSyncing);

      if (isMounted()) {
        onUpdateCubitOfflineStatus(_isOffline);
      }
    }
  }

  /// Setup network connectivity monitoring for automatic sync retry
  void setupConnectivityMonitoring() {

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
  Future<bool> checkServerConnectivity() async {
    if (_contentService == null) {
      return false;
    }

    try {
      final isHealthy = await _contentService!.healthCheck();
      return isHealthy;
    } catch (e) {
      return false;
    }
  }

  /// Handle connectivity changes - automatically retry sync when network returns
  void _onConnectivityChanged(ConnectivityResult result) {
    final hasConnection = result != ConnectivityResult.none;


    // Verify actual server connectivity, not just network interface status
    Future.microtask(() async {
      final serverReachable = await checkServerConnectivity();
      final wasOfflineBefore = _wasOfflineLastCheck;

      if (isMounted()) {
        _isOffline = !serverReachable;
        _wasOfflineLastCheck = !serverReachable;
        onStateChanged(_isOffline, _isSyncing);
        onUpdateCubitOfflineStatus(_isOffline);


        // Network just came back online - auto-sync dirty notes
        if (serverReachable && wasOfflineBefore) {

          // Wait a bit for network to stabilize
          Future.delayed(const Duration(seconds: 1), () {
            if (isMounted() && !_isSyncing) {
              autoSyncDirtyNotes();
            }
          });
        }
      }
    });
  }

  /// Auto-sync dirty notes for this book in background
  Future<void> autoSyncDirtyNotes() async {
    if (_contentService == null || _isSyncing) return;

    _isSyncing = true;
    onStateChanged(_isOffline, _isSyncing);

    try {

      final result = await _contentService!.syncDirtyNotesForBook(_bookUuid);

      if (isMounted()) {
        _isSyncing = false;
        onStateChanged(_isOffline, _isSyncing);

        // Show user feedback
        if (result.nothingToSync) {
        } else if (result.allSucceeded) {
          onShowSnackbar(
            'Synced ${result.total} offline note${result.total > 1 ? 's' : ''}',
            backgroundColor: Colors.green,
            durationSeconds: 2,
          );
        } else if (result.hasFailures) {
          onShowSnackbar(
            'Synced ${result.success}/${result.total} notes. ${result.failed} failed - check if book is backed up',
            backgroundColor: Colors.orange,
            durationSeconds: 5,
            detailTitle: 'Sync Failed',
            detailMessage: 'Some notes failed to sync because the book doesn\'t exist on the server yet.\n\n'
                'Solution: Use the book backup feature to sync the book to the server first.',
          );
        }
      }
    } catch (e) {
      if (isMounted()) {
        _isSyncing = false;
        onStateChanged(_isOffline, _isSyncing);
      }
    }
  }

  /// Sync event and note to server in background (best effort)
  Future<void> syncEventToServer(Event event) async {
    if (_contentService == null) {
      return;
    }

    if (event.id == null) {
      return;
    }

    try {
      await _contentService!.syncNote(event.id!);
    } catch (e) {
      // Silent failure - data is already saved locally and marked as dirty
      // It will be synced when the user opens the event detail screen
    }
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }
}
