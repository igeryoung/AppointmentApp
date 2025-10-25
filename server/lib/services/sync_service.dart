import '../database/connection.dart';
import '../models/sync_change.dart';

/// Result of applying client changes
class ApplyChangesResult {
  final int appliedCount;
  final List<SyncConflict> conflicts;

  const ApplyChangesResult({
    required this.appliedCount,
    required this.conflicts,
  });
}

/// Result of full sync operation
class FullSyncResult {
  final int appliedCount;
  final List<SyncChange> serverChanges;
  final List<SyncConflict> conflicts;

  const FullSyncResult({
    required this.appliedCount,
    required this.serverChanges,
    required this.conflicts,
  });
}

/// Service for handling sync operations
class SyncService {
  final DatabaseConnection db;

  /// Whitelist of tables allowed for sync operations
  static const _syncableTables = {
    'books',
    'events',
    'notes',
    'schedule_drawings',
  };

  /// Public accessor for whitelist (for testing purposes)
  static Set<String> get syncableTables => _syncableTables;

  SyncService(this.db);

  /// Validate table name against whitelist to prevent SQL injection
  String _validateTableName(String tableName) {
    if (!_syncableTables.contains(tableName)) {
      throw ArgumentError(
        'Invalid table name: $tableName. '
        'Allowed tables: ${_syncableTables.join(', ')}',
      );
    }
    return tableName;
  }

  /// Get changes from server since last sync
  Future<List<SyncChange>> getServerChanges(
    String deviceId,
    DateTime? lastSyncAt,
  ) async {
    final changes = <SyncChange>[];
    final tables = ['books', 'events', 'notes', 'schedule_drawings'];

    for (final table in tables) {
      final rows = await _getTableChanges(table, deviceId, lastSyncAt);
      changes.addAll(rows);
    }

    return changes;
  }

  /// Get changes for a specific table
  Future<List<SyncChange>> _getTableChanges(
    String tableName,
    String deviceId,
    DateTime? lastSyncAt,
  ) async {
    // Validate table name to prevent SQL injection
    final validTable = _validateTableName(tableName);

    final whereClause = lastSyncAt != null
        ? 'synced_at > @lastSync AND device_id != @deviceId'
        : 'device_id != @deviceId';

    final rows = await db.queryRows(
      '''
      SELECT * FROM $validTable
      WHERE $whereClause
      ORDER BY synced_at ASC
      ''',
      parameters: {
        if (lastSyncAt != null) 'lastSync': lastSyncAt,
        'deviceId': deviceId,
      },
    );

    return rows.map((row) {
      final operation = row['is_deleted'] == true ? 'delete' : 'update';
      return SyncChange(
        tableName: validTable,
        recordId: row['id'] as int,
        operation: operation,
        data: _cleanRowData(row),
        timestamp: row['synced_at'] as DateTime,
        version: row['version'] as int,
      );
    }).toList();
  }

  /// Apply client changes to server
  Future<ApplyChangesResult> applyClientChanges(
    String deviceId,
    List<SyncChange> changes,
  ) async {
    int appliedCount = 0;
    final conflicts = <SyncConflict>[];

    await db.transaction((session) async {
      for (final change in changes) {
        try {
          final conflict = await _applyChange(deviceId, change, session);
          if (conflict != null) {
            conflicts.add(conflict);
          } else {
            appliedCount++;
          }

          // Log sync operation
          await _logSyncOperation(
            deviceId,
            'push',
            change.tableName,
            change.recordId,
            conflict == null ? 'success' : 'conflict',
            conflict != null ? 'Conflict detected' : null,
            session,
          );
        } catch (e) {
          print('❌ Failed to apply change: ${change.tableName}/${change.recordId}: $e');

          // Log failure
          await _logSyncOperation(
            deviceId,
            'push',
            change.tableName,
            change.recordId,
            'failed',
            e.toString(),
            session,
          );
        }
      }
    });

    return ApplyChangesResult(
      appliedCount: appliedCount,
      conflicts: conflicts,
    );
  }

  /// Apply a single change and detect conflicts
  Future<SyncConflict?> _applyChange(
    String deviceId,
    SyncChange change,
    dynamic session,
  ) async {
    final tableName = change.tableName;
    final recordId = change.recordId;

    // Check if record exists and get current version
    final existing = await _getRecord(tableName, recordId);

    if (change.operation == 'delete') {
      // Soft delete
      if (existing != null && existing['version'] != change.version) {
        // Conflict: server version differs
        return SyncConflict(
          tableName: tableName,
          recordId: recordId,
          localData: change.data,
          serverData: existing,
          localVersion: change.version,
          serverVersion: existing['version'] as int,
          localTimestamp: change.timestamp,
          serverTimestamp: existing['updated_at'] as DateTime,
        );
      }

      await _softDelete(tableName, recordId, session);
      return null;
    }

    if (existing == null) {
      // Create new record
      await _insertRecord(tableName, deviceId, change.data, session);
      return null;
    }

    // Check for conflicts
    final serverVersion = existing['version'] as int;
    if (serverVersion > change.version) {
      // Conflict: server has newer version
      return SyncConflict(
        tableName: tableName,
        recordId: recordId,
        localData: change.data,
        serverData: existing,
        localVersion: change.version,
        serverVersion: serverVersion,
        localTimestamp: change.timestamp,
        serverTimestamp: existing['updated_at'] as DateTime,
      );
    }

    // Update record
    await _updateRecord(tableName, recordId, deviceId, change.data, session);
    return null;
  }

  /// Perform full bidirectional sync
  Future<FullSyncResult> performFullSync(
    String deviceId,
    DateTime? lastSyncAt,
    List<SyncChange> localChanges,
  ) async {
    // First, apply client changes
    final applyResult = await applyClientChanges(deviceId, localChanges);

    // Then, get server changes
    final serverChanges = await getServerChanges(deviceId, lastSyncAt);

    // Update device last sync time
    await db.query(
      'UPDATE devices SET last_sync_at = CURRENT_TIMESTAMP WHERE id = @id',
      parameters: {'id': deviceId},
    );

    return FullSyncResult(
      appliedCount: applyResult.appliedCount,
      serverChanges: serverChanges,
      conflicts: applyResult.conflicts,
    );
  }

  /// Resolve a conflict
  Future<void> resolveConflict(ConflictResolutionRequest request) async {
    await db.transaction((session) async {
      final data = switch (request.resolution) {
        'use_local' => null, // Client will handle
        'use_server' => null, // Client will handle
        'merge' => request.mergedData,
        _ => throw Exception('Invalid resolution strategy'),
      };

      if (data != null) {
        await _updateRecord(
          request.tableName,
          request.recordId,
          request.deviceId,
          data,
          session,
        );
      }
    });
  }

  /// Get a single record
  Future<Map<String, dynamic>?> _getRecord(String tableName, int recordId) async {
    final validTable = _validateTableName(tableName);
    return await db.querySingle(
      'SELECT * FROM $validTable WHERE id = @id AND is_deleted = false',
      parameters: {'id': recordId},
    );
  }

  /// Soft delete a record
  Future<void> _softDelete(String tableName, int recordId, dynamic session) async {
    final validTable = _validateTableName(tableName);
    await db.query(
      '''
      UPDATE $validTable
      SET is_deleted = true, synced_at = CURRENT_TIMESTAMP
      WHERE id = @id
      ''',
      parameters: {'id': recordId},
    );
  }

  /// Insert a new record
  Future<void> _insertRecord(
    String tableName,
    String deviceId,
    Map<String, dynamic> data,
    dynamic session,
  ) async {
    final validTable = _validateTableName(tableName);
    data['device_id'] = deviceId;
    data['synced_at'] = DateTime.now();
    data['version'] = 1;
    data['is_deleted'] = false;

    final columns = data.keys.join(', ');
    final placeholders = data.keys.map((k) => '@$k').join(', ');

    await db.query(
      'INSERT INTO $validTable ($columns) VALUES ($placeholders)',
      parameters: data,
    );
  }

  /// Update an existing record
  Future<void> _updateRecord(
    String tableName,
    int recordId,
    String deviceId,
    Map<String, dynamic> data,
    dynamic session,
  ) async {
    final validTable = _validateTableName(tableName);
    data['device_id'] = deviceId;
    data['synced_at'] = DateTime.now();

    final setClauses = data.keys.map((k) => '$k = @$k').join(', ');

    await db.query(
      'UPDATE $validTable SET $setClauses WHERE id = @id',
      parameters: {...data, 'id': recordId},
    );
  }

  /// Log sync operation
  Future<void> _logSyncOperation(
    String deviceId,
    String operation,
    String tableName,
    int? recordId,
    String status,
    String? errorMessage,
    dynamic session,
  ) async {
    await db.query(
      '''
      INSERT INTO sync_log (device_id, operation, table_name, record_id, status, error_message)
      VALUES (@deviceId, @operation, @tableName, @recordId, @status, @errorMessage)
      ''',
      parameters: {
        'deviceId': deviceId,
        'operation': operation,
        'tableName': tableName,
        'recordId': recordId,
        'status': status,
        'errorMessage': errorMessage,
      },
    );
  }

  /// Clean row data by removing internal fields
  Map<String, dynamic> _cleanRowData(Map<String, dynamic> row) {
    final cleaned = Map<String, dynamic>.from(row);
    cleaned.remove('synced_at');
    cleaned.remove('device_id');
    return cleaned;
  }
}
