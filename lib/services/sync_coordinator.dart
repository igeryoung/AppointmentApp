import 'dart:async';
import 'package:flutter/foundation.dart';
import 'sync_service.dart';
import 'network_service.dart';
import '../models/sync_models.dart';

/// SyncCoordinator - Coordinates automatic background sync for all entities
///
/// Responsibilities:
/// - Automatic background sync (every 30 seconds)
/// - Manual sync on demand
/// - Network connectivity checks
/// - Sync error handling and retry logic
/// - Report sync progress and results
class SyncCoordinator {
  final SyncService _syncService;
  final NetworkService _networkService;

  Timer? _syncTimer;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  SyncResult? _lastSyncResult;

  /// Sync interval (default: 30 seconds)
  final Duration syncInterval;

  SyncCoordinator({
    required SyncService syncService,
    required NetworkService networkService,
    this.syncInterval = const Duration(seconds: 30),
  })  : _syncService = syncService,
        _networkService = networkService;

  // ===================
  // Automatic Sync Control
  // ===================

  /// Start automatic background sync
  /// Triggers sync at regular intervals
  void startAutoSync() {
    if (_syncTimer != null && _syncTimer!.isActive) {
      debugPrint('⚠️  Auto-sync already running');
      return;
    }

    debugPrint('🔄 Starting auto-sync (interval: ${syncInterval.inSeconds}s)');

    // Perform initial sync immediately
    syncNow();

    // Schedule periodic sync
    _syncTimer = Timer.periodic(syncInterval, (_) async {
      await syncNow();
    });
  }

  /// Stop automatic background sync
  void stopAutoSync() {
    if (_syncTimer != null) {
      _syncTimer!.cancel();
      _syncTimer = null;
      debugPrint('🛑 Auto-sync stopped');
    }
  }

  /// Check if auto-sync is currently running
  bool get isAutoSyncActive => _syncTimer != null && _syncTimer!.isActive;

  // ===================
  // Manual Sync Operations
  // ===================

  /// Perform sync now (manual trigger)
  /// Returns true if sync was successful
  Future<bool> syncNow() async {
    // Prevent concurrent syncs
    if (_isSyncing) {
      debugPrint('⚠️  Sync already in progress, skipping...');
      return false;
    }

    _isSyncing = true;

    try {
      // Check network connectivity
      final hasConnection = await _networkService.hasConnectivity();
      if (!hasConnection) {
        debugPrint('📡 No network connection, skipping sync');
        _lastSyncResult = SyncResult(
          success: false,
          message: 'No network connection',
          errors: ['Network unavailable'],
        );
        return false;
      }

      // Perform full sync
      debugPrint('🔄 Performing full sync...');
      final result = await _syncService.performFullSync();

      _lastSyncTime = DateTime.now();
      _lastSyncResult = result;

      if (result.success) {
        debugPrint('✅ Sync completed successfully');
        debugPrint('   - Pushed: ${result.pushedChanges}');
        debugPrint('   - Pulled: ${result.pulledChanges}');
        debugPrint('   - Conflicts: ${result.conflictsResolved}');
        return true;
      } else {
        debugPrint('❌ Sync failed: ${result.message}');
        if (result.errors.isNotEmpty) {
          for (final error in result.errors) {
            debugPrint('   - $error');
          }
        }
        return false;
      }
    } catch (e) {
      debugPrint('❌ Sync error: $e');
      _lastSyncResult = SyncResult(
        success: false,
        message: 'Sync error',
        errors: [e.toString()],
      );
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  /// Force sync (ignores sync-in-progress check)
  /// Use with caution - may cause conflicts
  Future<bool> forceSyncNow() async {
    _isSyncing = false; // Reset flag
    return await syncNow();
  }

  // ===================
  // Sync Status & Info
  // ===================

  /// Check if sync is currently in progress
  bool get isSyncing => _isSyncing;

  /// Get last sync time
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Get last sync result
  SyncResult? get lastSyncResult => _lastSyncResult;

  /// Get time since last sync
  Duration? get timeSinceLastSync {
    if (_lastSyncTime == null) return null;
    return DateTime.now().difference(_lastSyncTime!);
  }

  /// Check if sync is overdue (hasn't synced in 2x interval)
  bool get isSyncOverdue {
    if (_lastSyncTime == null) return true;
    final timeSince = timeSinceLastSync!;
    return timeSince > syncInterval * 2;
  }

  /// Get sync status summary
  String get syncStatusSummary {
    if (_isSyncing) {
      return 'Syncing...';
    }

    if (_lastSyncTime == null) {
      return 'Never synced';
    }

    final timeSince = timeSinceLastSync!;
    final lastResult = _lastSyncResult;

    if (lastResult == null) {
      return 'Last sync: ${_formatDuration(timeSince)} ago';
    }

    if (lastResult.success) {
      return 'Last sync: ${_formatDuration(timeSince)} ago (${lastResult.pushedChanges} pushed, ${lastResult.pulledChanges} pulled)';
    } else {
      return 'Last sync failed: ${_formatDuration(timeSince)} ago';
    }
  }

  // ===================
  // Cleanup
  // ===================

  /// Dispose resources
  void dispose() {
    stopAutoSync();
  }

  // ===================
  // Helpers
  // ===================

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m';
    } else if (duration.inHours < 24) {
      return '${duration.inHours}h';
    } else {
      return '${duration.inDays}d';
    }
  }
}

/// Legacy support - keep for backwards compatibility
/// Result object for bulk sync operations
class BulkSyncResult {
  final int total;
  final int success;
  final int failed;
  final List<int> failedEventIds;

  BulkSyncResult({
    required this.total,
    required this.success,
    required this.failed,
    required this.failedEventIds,
  });

  bool get hasFailures => failed > 0;
  bool get allSucceeded => failed == 0 && total > 0;
  bool get nothingToSync => total == 0;

  @override
  String toString() {
    return 'BulkSyncResult(total: $total, success: $success, failed: $failed)';
  }
}
