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

      // Check server connectivity
      final serverReachable = await checkServerConnectivity();
      _setOfflineState(!serverReachable);

      if (context.mounted) {
        context.read<ScheduleCubit>().setOfflineStatus(_isOffline);
      }


      // Auto-sync dirty notes for this book if online
      if (serverReachable) {
        autoSyncDirtyNotes();
      }
    } catch (e) {
      // Continue without ContentService - sync will not work but UI remains functional
      _setOfflineState(true);

      if (context.mounted) {
        context.read<ScheduleCubit>().setOfflineStatus(_isOffline);
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

      _setOfflineState(!serverReachable);

      if (context.mounted) {
        context.read<ScheduleCubit>().setOfflineStatus(_isOffline);
      }


      // Network just came back online - auto-sync dirty notes
      if (serverReachable && wasOfflineBefore) {

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
    if (_contentService == null || _isSyncing) return;

    _setSyncingState(true);

    try {

      final result = await _contentService!.syncDirtyNotesForBook(book.uuid);

      _setSyncingState(false);

      // Show user feedback
      if (context.mounted) {
        if (result.nothingToSync) {
        } else if (result.allSucceeded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced ${result.total} offline note${result.total > 1 ? 's' : ''}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (result.hasFailures) {
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
      _setSyncingState(false);

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
        return;
      }
      await Future.delayed(pollInterval);
    }

    final events = getEvents();
    final waitTime = DateTime.now().difference(startTime);
    preloadNotesInBackground(events);
  }

  /// Preload notes for all events in current 3-day window (background, non-blocking)
  Future<void> preloadNotesInBackground(List<Event> events) async {
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
      // Call ContentService to preload notes with progress callback
      await _contentService!.preloadNotes(
        eventIds,
        onProgress: (loaded, total) {
          // Log progress for debugging
        },
      );

      final preloadEndTime = DateTime.now();
      final preloadDuration = preloadEndTime.difference(preloadStartTime);
    } catch (e) {
      // Preload failure is non-critical - user can still use the app
      // Notes will be fetched on-demand when user taps events
      final preloadEndTime = DateTime.now();
      final preloadDuration = preloadEndTime.difference(preloadStartTime);
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
  }
}
