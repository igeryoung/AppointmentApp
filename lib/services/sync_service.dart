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

  /// Collect dirty records from all repositories
  /// Groups events with their related notes for atomic sync
  Future<List<SyncChange>> _collectDirtyRecords() async {
    final changes = <SyncChange>[];
    final syncedEventIds = <String>{};

    // Collect dirty events
    try {
      final dirtyEvents = await eventRepository.getDirtyEvents();
      for (final event in dirtyEvents) {
        if (event.id == null) continue;

        final operation = event.isRemoved ? 'delete' : 'update';
        changes.add(SyncChange(
          tableName: 'events',
          recordId: event.id!,
          operation: operation,
          data: event.toMap(),
          timestamp: event.updatedAt,
          version: event.version,
        ));

        syncedEventIds.add(event.id!);

        // Atomically sync event's note along with the event (user choice QD.6)
        // This ensures event updates and their related note content stay in sync
        try {
          final relatedNote = await noteRepository.getCached(event.id!);
          if (relatedNote != null) {
            changes.add(SyncChange(
              tableName: 'notes',
              recordId: relatedNote.eventId,
              operation: 'update',
              data: relatedNote.toMap(),
              timestamp: relatedNote.updatedAt,
              version: relatedNote.version,
            ));
            syncedEventIds.add(relatedNote.eventId);
          }
        } catch (e) {
        }
      }
    } catch (e) {
    }

    // Collect remaining dirty notes (not already synced with their events)
    try {
      final dirtyNotes = await noteRepository.getDirtyNotes();
      for (final note in dirtyNotes) {
        // Skip if already synced with event
        if (syncedEventIds.contains(note.eventId)) {
          continue;
        }

        changes.add(SyncChange(
          tableName: 'notes',
          recordId: note.eventId,
          operation: 'update',
          data: note.toMap(),
          timestamp: note.updatedAt,
          version: note.version,
        ));
      }
    } catch (e) {
    }

    // Collect dirty schedule drawings (only supported on PRD database)
    if (_prdDatabaseService != null) {
      try {
        final dirtyDrawings = await _prdDatabaseService!.getDirtyDrawings();
        for (final drawing in dirtyDrawings) {
          if (drawing.id == null) continue;

          changes.add(SyncChange(
            tableName: 'schedule_drawings',
            recordId: drawing.id!.toString(),
            operation: 'update',
            data: drawing.toMap(),
            timestamp: drawing.updatedAt,
            version: drawing.version,
          ));
        }
      } catch (e) {
      }
    }

    return changes;
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

  /// Mark records as synced (clear dirty flag)
  Future<void> _markRecordsSynced(List<SyncChange> changes, DateTime syncedAt) async {
    for (final change in changes) {
      try {
        switch (change.tableName) {
          case 'events':
            await eventRepository.markEventSynced(change.recordId, syncedAt);
            break;

          case 'notes':
            await noteRepository.markNoteSynced(change.recordId, syncedAt);
            break;

          case 'schedule_drawings':
            final drawingId = int.tryParse(change.recordId);
            if (_prdDatabaseService != null && drawingId != null) {
              await _prdDatabaseService!.markDrawingSynced(drawingId, syncedAt);
            }
            break;
        }
      } catch (e) {
      }
    }
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
