import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubits/schedule_cubit.dart';
import '../../models/book.dart';
import '../../models/event.dart';
import '../api_client.dart';
import '../cache_manager.dart';
import '../content_service.dart';
import '../database_service_interface.dart';
import '../prd_database_service.dart';
import '../server_config_service.dart';
import '../book_backup_service.dart';

/// Service responsible for server synchronization in the schedule screen
/// Handles connectivity monitoring, auto-sync, and note preloading
class ScheduleSyncService {
  final BuildContext context;
  final Book book;
  final IDatabaseService dbService;
  final Function(bool) onOfflineStateChanged;
  final Function() onSyncingStateChanged;

  ContentService? _contentService;
  CacheManager? _cacheManager;
  BookBackupService? _bookBackupService;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  bool _isOffline = false;
  bool _wasOfflineLastCheck = false;
  bool _isSyncing = false;

  ScheduleSyncService({
    required this.context,
    required this.book,
    required this.dbService,
    required this.onOfflineStateChanged,
    required this.onSyncingStateChanged,
  });

  bool get isOffline => _isOffline;
  bool get isSyncing => _isSyncing;
  ContentService? get contentService => _contentService;
  CacheManager? get cacheManager => _cacheManager;

  /// Initialize ContentService for server sync
  Future<void> initialize() async {
    try {
      final prdDb = dbService as PRDDatabaseService;
      final serverConfig = ServerConfigService(prdDb);
      final serverUrl = await serverConfig.getServerUrlOrDefault(
        defaultUrl: 'http://localhost:8080',
      );
      final apiClient = ApiClient(baseUrl: serverUrl);
      _cacheManager = CacheManager(prdDb);
      _contentService = ContentService(apiClient, _cacheManager!, dbService);
      _bookBackupService = BookBackupService(dbService: prdDb);
      debugPrint('✅ ScheduleSyncService: ContentService and BookBackupService initialized');

      // Check server connectivity
      final serverReachable = await checkServerConnectivity();
      _setOfflineState(!serverReachable);

      if (context.mounted) {
        context.read<ScheduleCubit>().setOfflineStatus(_isOffline);
      }

      debugPrint('✅ ScheduleSyncService: Initial connectivity check - offline: $_isOffline');

      // Auto-sync dirty notes for this book if online
      if (serverReachable) {
        autoSyncDirtyNotes();
      }
    } catch (e) {
      debugPrint('❌ ScheduleSyncService: Failed to initialize ContentService: $e');
      // Continue without ContentService - sync will not work but UI remains functional
      _setOfflineState(true);

      if (context.mounted) {
        context.read<ScheduleCubit>().setOfflineStatus(_isOffline);
      }
    }
  }

  /// Setup network connectivity monitoring for automatic sync retry
  void setupConnectivityMonitoring() {
    debugPrint('🌐 ScheduleSyncService: Setting up connectivity monitoring...');

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
  Future<bool> checkServerConnectivity() async {
    if (_contentService == null) {
      debugPrint('⚠️ ScheduleSyncService: Cannot check server - ContentService not initialized');
      return false;
    }

    try {
      debugPrint('🔍 ScheduleSyncService: Checking server connectivity via health check...');
      final isHealthy = await _contentService!.healthCheck();
      debugPrint(isHealthy
        ? '✅ ScheduleSyncService: Server is reachable'
        : '❌ ScheduleSyncService: Server health check returned false');
      return isHealthy;
    } catch (e) {
      debugPrint('❌ ScheduleSyncService: Server health check failed: $e');
      return false;
    }
  }

  /// Handle connectivity changes - automatically retry sync when network returns
  void _onConnectivityChanged(ConnectivityResult result) {
    final hasConnection = result != ConnectivityResult.none;

    debugPrint('🌐 ScheduleSyncService: Connectivity changed - hasConnection: $hasConnection, result: $result');

    // Verify actual server connectivity, not just network interface status
    Future.microtask(() async {
      final serverReachable = await checkServerConnectivity();
      final wasOfflineBefore = _wasOfflineLastCheck;

      _setOfflineState(!serverReachable);

      if (context.mounted) {
        context.read<ScheduleCubit>().setOfflineStatus(_isOffline);
      }

      debugPrint('🌐 ScheduleSyncService: Offline state updated based on server check: $_isOffline');

      // Network just came back online - auto-sync dirty notes
      if (serverReachable && wasOfflineBefore) {
        debugPrint('🌐 ScheduleSyncService: Server restored! Auto-syncing dirty notes...');

        // Wait a bit for network to stabilize
        Future.delayed(const Duration(seconds: 1), () {
          if (!_isSyncing) {
            autoSyncDirtyNotes();
          }
        });
      }
    });
  }

  /// Auto-sync dirty notes for this book in background
  Future<void> autoSyncDirtyNotes() async {
    if (_contentService == null || _bookBackupService == null || _isSyncing || book.id == null) return;

    _setSyncingState(true);

    try {
      // Step 1: Check if book needs backup first
      final needsBackup = await _bookBackupService!.checkIfBookNeedsBackup(book.id!);

      if (needsBackup) {
        debugPrint('📤 ScheduleSyncService: Book ${book.id} needs backup before syncing notes...');

        try {
          // Auto-backup the book
          await _bookBackupService!.uploadBook(book.id!);
          debugPrint('✅ ScheduleSyncService: Book ${book.id} backed up successfully');

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Book "${book.name}" backed up to server'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (backupError) {
          // Backup failed - show error and stop (don't sync notes)
          _setSyncingState(false);
          debugPrint('❌ ScheduleSyncService: Book backup failed: $backupError');

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to backup book: $backupError'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Details',
                  textColor: Colors.white,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Backup Failed'),
                        content: Text(
                          'Unable to backup book "${book.name}" to server.\n\n'
                          'Error: $backupError\n\n'
                          'Notes cannot be synced until the book is backed up. '
                          'Please check your connection and try again.',
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
          return; // Stop here - don't sync notes
        }
      }

      // Step 2: Now sync dirty notes (book is guaranteed to exist on server)
      debugPrint('🔄 ScheduleSyncService: Auto-syncing dirty notes for book ${book.id}...');

      final result = await _contentService!.syncDirtyNotesForBook(book.id!);

      _setSyncingState(false);

      // Show user feedback
      if (context.mounted) {
        if (result.nothingToSync) {
          debugPrint('✅ ScheduleSyncService: No dirty notes to sync');
        } else if (result.allSucceeded) {
          debugPrint('✅ ScheduleSyncService: All ${result.total} notes synced successfully');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced ${result.total} offline note${result.total > 1 ? 's' : ''}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (result.hasFailures) {
          debugPrint('⚠️ ScheduleSyncService: ${result.success}/${result.total} notes synced, ${result.failed} failed');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced ${result.success}/${result.total} notes. ${result.failed} failed'),
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
                        'Some notes failed to sync. This may be due to network issues.\n\n'
                        'Please try again or check your connection.',
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
      _setSyncingState(false);
      debugPrint('❌ ScheduleSyncService: Auto-sync failed: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Wait for events to load, then trigger preload
  Future<void> waitForEventsAndPreload(List<Event> Function() getEvents) async {
    // Poll for events to be loaded (max 5 seconds)
    const maxWaitTime = Duration(seconds: 5);
    const pollInterval = Duration(milliseconds: 100);
    final startTime = DateTime.now();

    while (getEvents().isEmpty) {
      if (DateTime.now().difference(startTime) > maxWaitTime) {
        debugPrint('⚠️ ScheduleSyncService: Timeout waiting for events to load (waited ${maxWaitTime.inMilliseconds}ms), skipping preload');
        return;
      }
      await Future.delayed(pollInterval);
    }

    final events = getEvents();
    final waitTime = DateTime.now().difference(startTime);
    debugPrint('✅ ScheduleSyncService: Events loaded after ${waitTime.inMilliseconds}ms (${events.length} events), triggering preload...');
    preloadNotesInBackground(events);
  }

  /// Preload notes for all events in current 3-day window (background, non-blocking)
  Future<void> preloadNotesInBackground(List<Event> events) async {
    if (events.isEmpty) {
      debugPrint('📦 ScheduleSyncService: No events to preload');
      return;
    }

    if (_contentService == null) {
      debugPrint('⚠️ ScheduleSyncService: Cannot preload - ContentService not initialized');
      return;
    }

    final preloadStartTime = DateTime.now();
    debugPrint('📦 ScheduleSyncService: [${preloadStartTime.toIso8601String()}] Starting preload for ${events.length} events');

    // Extract all event IDs (filter out null IDs)
    final eventIds = events
        .where((e) => e.id != null)
        .map((e) => e.id!)
        .toList();

    if (eventIds.isEmpty) {
      debugPrint('📦 ScheduleSyncService: No valid event IDs to preload');
      return;
    }

    debugPrint('📦 ScheduleSyncService: Calling ContentService.preloadNotes with ${eventIds.length} event IDs');

    try {
      // Call ContentService to preload notes with progress callback
      await _contentService!.preloadNotes(
        eventIds,
        onProgress: (loaded, total) {
          // Log progress for debugging
          debugPrint('📦 ScheduleSyncService: Progress update - $loaded/$total notes loaded');
        },
      );

      final preloadEndTime = DateTime.now();
      final preloadDuration = preloadEndTime.difference(preloadStartTime);
      debugPrint('✅ ScheduleSyncService: Preload call completed in ${preloadDuration.inMilliseconds}ms (initiated for ${eventIds.length} notes)');
    } catch (e) {
      // Preload failure is non-critical - user can still use the app
      // Notes will be fetched on-demand when user taps events
      final preloadEndTime = DateTime.now();
      final preloadDuration = preloadEndTime.difference(preloadStartTime);
      debugPrint('⚠️ ScheduleSyncService: Preload failed after ${preloadDuration.inMilliseconds}ms (non-critical): $e');
    }
  }

  /// Sync event and note to server in background (best effort)
  Future<void> syncEventToServer(Event event) async {
    if (_contentService == null) {
      debugPrint('⚠️ ScheduleSyncService: ContentService not available, cannot sync event ${event.id}');
      return;
    }

    if (event.id == null) {
      debugPrint('⚠️ ScheduleSyncService: Event ID is null, cannot sync');
      return;
    }

    try {
      debugPrint('🔄 ScheduleSyncService: Syncing event ${event.id} and note to server...');
      await _contentService!.syncNote(event.id!);
      debugPrint('✅ ScheduleSyncService: Event ${event.id} synced to server successfully');
    } catch (e) {
      // Silent failure - data is already saved locally and marked as dirty
      // It will be synced when the user opens the event detail screen
      debugPrint('⚠️ ScheduleSyncService: Background sync failed (will retry later): $e');
    }
  }

  /// Set offline state and notify listeners
  void _setOfflineState(bool offline) {
    _isOffline = offline;
    _wasOfflineLastCheck = offline;
    onOfflineStateChanged(offline);
  }

  /// Set syncing state and notify listeners
  void _setSyncingState(bool syncing) {
    _isSyncing = syncing;
    onSyncingStateChanged();
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _bookBackupService?.dispose();
    debugPrint('🧹 ScheduleSyncService: Disposed');
  }
}
