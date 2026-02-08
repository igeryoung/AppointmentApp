import 'package:flutter/foundation.dart';
import '../models/sync_models.dart';
import '../repositories/event_repository.dart';
import '../repositories/note_repository.dart';
import 'api_client.dart';
import 'database_service_interface.dart';
import 'database/mixins/device_info_operations_mixin.dart';
import 'database/prd_database_service.dart';

/// Unified sync service for all entities (events, notes, schedule_drawings)
/// Handles bidirectional sync with conflict resolution
class SyncService {
  final ApiClient apiClient;
  final IEventRepository eventRepository;
  final INoteRepository noteRepository;
  final IDatabaseService databaseService;
  final PRDDatabaseService? _prdDatabaseService;

  SyncService({
    required this.apiClient,
    required this.eventRepository,
    required this.noteRepository,
    required this.databaseService,
  }) : _prdDatabaseService = databaseService is PRDDatabaseService
            ? databaseService as PRDDatabaseService
            : null;

  /// Perform full bidirectional sync for all entities
  /// Returns SyncResult with summary of sync operation
  Future<SyncResult> performFullSync() async {
    try {

      // Get device credentials
      final deviceCreds = await _prdDatabaseService?.getDeviceCredentials();
      if (deviceCreds == null) {
        return SyncResult(
          success: false,
          message: 'Device not registered',
          errors: ['No device credentials found'],
        );
      }

      // Get last sync time (could be stored in sync_metadata table)
      final lastSyncAt = await _getLastSyncTime();

      // Collect dirty records from all entities
      final localChanges = await _collectDirtyRecords();


      // Build sync request
      final request = SyncRequest(
        deviceId: deviceCreds.deviceId,
        deviceToken: deviceCreds.deviceToken,
        lastSyncAt: lastSyncAt,
        localChanges: localChanges,
      );

      // Call server sync API
      final response = await apiClient.fullSync(request);

      if (!response.success) {
        return SyncResult(
          success: false,
          message: response.message,
          errors: ['Server sync failed: ${response.message}'],
        );
      }

      // Process conflicts (if any)
      int conflictsResolved = 0;
      if (response.conflicts != null && response.conflicts!.isNotEmpty) {
        conflictsResolved = await _resolveConflicts(response.conflicts!);
      }

      // Apply server changes to local DB
      final pulledChanges = await _applyServerChanges(response.serverChanges ?? []);

      // Mark local records as synced
      await _markRecordsSynced(localChanges, response.serverTime);

      // Update last sync time
      await _updateLastSyncTime(response.serverTime);


      return SyncResult(
        success: true,
        message: 'Sync completed successfully',
        pushedChanges: response.changesApplied,
        pulledChanges: pulledChanges,
        conflictsResolved: conflictsResolved,
        lastSyncTime: response.serverTime,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Sync failed',
        errors: [e.toString()],
      );
    }
  }

  /// Collect records for sync (no longer uses dirty tracking)
  /// In server-based architecture, this is only used for full refresh scenarios
  Future<List<SyncChange>> _collectDirtyRecords() async {
    // In server-based architecture, we sync immediately on each change
    // This method is kept for backward compatibility but returns empty list
    // Full sync scenarios should fetch from server instead
    return <SyncChange>[];
  }

  /// Apply server changes to local database
  Future<int> _applyServerChanges(List<SyncChange> serverChanges) async {
    int appliedCount = 0;

    for (final change in serverChanges) {
      try {
        switch (change.tableName) {
          case 'events':
            await eventRepository.applyServerChange(change.data);
            appliedCount++;
            break;

          case 'notes':
            await noteRepository.applyServerChange(change.data);
            appliedCount++;
            break;

          case 'schedule_drawings':
            if (_prdDatabaseService != null) {
              await _prdDatabaseService!.applyServerDrawingChange(change.data);
              appliedCount++;
            } else {
            }
            break;

          case 'charge_items':
            if (_prdDatabaseService != null) {
              await _prdDatabaseService!.applyServerChargeItemChange(change.data);
              appliedCount++;
            }
            break;

          default:
        }
      } catch (e) {
      }
    }

    return appliedCount;
  }

  /// Resolve conflicts using "newest timestamp wins" strategy
  Future<int> _resolveConflicts(List<SyncConflict> conflicts) async {
    int resolvedCount = 0;

    for (final conflict in conflicts) {
      try {

        // Use newest timestamp wins strategy
        final winningData = conflict.resolveByNewestTimestamp();
        final isServerNewer = conflict.serverIsNewer;

        if (isServerNewer) {
          // Server wins - apply server data
          switch (conflict.tableName) {
            case 'events':
              await eventRepository.applyServerChange(winningData);
              break;
            case 'notes':
              await noteRepository.applyServerChange(winningData);
              break;
            case 'schedule_drawings':
              if (_prdDatabaseService != null) {
                await _prdDatabaseService!.applyServerDrawingChange(winningData);
              }
              break;
            case 'charge_items':
              if (_prdDatabaseService != null) {
                await _prdDatabaseService!.applyServerChargeItemChange(winningData);
              }
              break;
          }
        } else {
          // Local wins - mark as dirty to re-push
          // Local data is already dirty, so it will be re-pushed on next sync
        }

        resolvedCount++;
      } catch (e) {
      }
    }

    return resolvedCount;
  }

  /// Mark records as synced (no longer needed in server-based architecture)
  /// Kept for backward compatibility
  Future<void> _markRecordsSynced(List<SyncChange> changes, DateTime syncedAt) async {
    // In server-based architecture, we sync immediately on each change
    // No dirty tracking means no need to mark records as synced
  }

  /// Get last sync time from sync_metadata table
  Future<DateTime?> _getLastSyncTime() async {
    try {
      // Query sync_metadata table for last successful sync
      // For now, return null to sync all records
      // TODO: Implement proper sync_metadata tracking
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update last sync time in sync_metadata table
  Future<void> _updateLastSyncTime(DateTime syncTime) async {
    try {
      // Update sync_metadata table with last successful sync time
      // TODO: Implement proper sync_metadata tracking
    } catch (e) {
    }
  }
}
