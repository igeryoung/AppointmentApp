import 'dart:convert';
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

  /// Allowed columns per table (used to sanitize inbound sync payloads)
  static const Map<String, Set<String>> _allowedColumns = {
    'books': {
      'book_uuid',
      'device_id',
      'name',
      'created_at',
      'updated_at',
      'archived_at',
      'synced_at',
      'version',
      'is_deleted',
    },
    'events': {
      'id',
      'book_uuid',
      'name',
      'record_number',
      'phone',
      'event_type',
      'event_types',
      'has_charge_items',
      'start_time',
      'end_time',
      'created_at',
      'updated_at',
      'is_removed',
      'removal_reason',
      'original_event_id',
      'new_event_id',
      'is_checked',
      'has_note',
      'version',
      'is_deleted',
    },
    'notes': {
      'id',
      'event_id',
      'pages_data',
      'created_at',
      'updated_at',
      'version',
      'is_deleted',
    },
    'schedule_drawings': {
      'id',
      'book_uuid',
      'date',
      'view_mode',
      'strokes_data',
      'created_at',
      'updated_at',
      'synced_at',
      'version',
      'is_deleted',
    },
  };

  static const Map<String, String> _primaryKeyColumns = {
    'books': 'book_uuid',
    'events': 'id',
    'notes': 'event_id',
    'schedule_drawings': 'id',
  };

  static const Set<String> _numericPrimaryKeyTables = {
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

    final pkColumn = _getPrimaryKeyColumn(validTable);

    return rows.map((row) {
      final idValue = row[pkColumn];
      if (idValue == null) {
        throw Exception('Missing primary key $pkColumn for $validTable row');
      }
      final operation = row['is_deleted'] == true ? 'delete' : 'update';
      return SyncChange(
        tableName: validTable,
        recordId: idValue.toString(),
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
  Future<Map<String, dynamic>?> _getRecord(String tableName, String recordId) async {
    final validTable = _validateTableName(tableName);
    final pkColumn = _getPrimaryKeyColumn(validTable);
    final convertedId = _convertRecordIdValue(validTable, recordId);
    if (convertedId == null) {
      return null;
    }

    return await db.querySingle(
      'SELECT * FROM $validTable WHERE $pkColumn = @id AND is_deleted = false',
      parameters: {'id': convertedId},
    );
  }

  /// Soft delete a record
  Future<void> _softDelete(String tableName, String recordId, dynamic session) async {
    final validTable = _validateTableName(tableName);
    final pkColumn = _getPrimaryKeyColumn(validTable);
    final convertedId = _convertRecordIdValue(validTable, recordId);
    if (convertedId == null) {
      return;
    }

    await db.query(
      '''
      UPDATE $validTable
      SET is_deleted = true, synced_at = CURRENT_TIMESTAMP
      WHERE $pkColumn = @id
      ''',
      parameters: {'id': convertedId},
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
    final sanitizedData = _sanitizeChangeData(validTable, data);
    if (sanitizedData.isEmpty) {
      throw ArgumentError('No valid columns provided for $validTable insert');
    }

    final pkColumn = _getPrimaryKeyColumn(validTable);
    if (!sanitizedData.containsKey(pkColumn)) {
      throw ArgumentError('Missing $pkColumn for $validTable insert');
    }

    sanitizedData['device_id'] = deviceId;
    sanitizedData['synced_at'] = DateTime.now();
    sanitizedData['version'] = sanitizedData['version'] ?? 1;
    sanitizedData['is_deleted'] = sanitizedData['is_deleted'] ?? false;
    sanitizedData['created_at'] = sanitizedData['created_at'] ?? DateTime.now();
    sanitizedData['updated_at'] = sanitizedData['updated_at'] ?? DateTime.now();

    final columns = sanitizedData.keys.join(', ');
    final placeholders = sanitizedData.keys.map((k) => '@$k').join(', ');

    await db.query(
      'INSERT INTO $validTable ($columns) VALUES ($placeholders)',
      parameters: sanitizedData,
    );
  }

  /// Update an existing record
  Future<void> _updateRecord(
    String tableName,
    String recordId,
    String deviceId,
    Map<String, dynamic> data,
    dynamic session,
  ) async {
    final validTable = _validateTableName(tableName);
    final sanitizedData = _sanitizeChangeData(validTable, data);
    if (sanitizedData.isEmpty) {
      print('⚠️  No valid fields to update for $validTable/$recordId');
      return;
    }

    _removePrimaryKey(sanitizedData, validTable);
    sanitizedData['device_id'] = deviceId;
    sanitizedData['synced_at'] = DateTime.now();
    sanitizedData['updated_at'] = sanitizedData['updated_at'] ?? DateTime.now();

    final setClauses = sanitizedData.keys.map((k) => '$k = @$k').join(', ');
    final pkColumn = _getPrimaryKeyColumn(validTable);
    final convertedId = _convertRecordIdValue(validTable, recordId);
    if (convertedId == null) {
      print('⚠️  Invalid record id for $validTable/$recordId');
      return;
    }

    await db.query(
      'UPDATE $validTable SET $setClauses WHERE $pkColumn = @recordId',
      parameters: {...sanitizedData, 'recordId': convertedId},
    );
  }

  /// Log sync operation
  Future<void> _logSyncOperation(
    String deviceId,
    String operation,
    String tableName,
    String? recordId,
    String status,
    String? errorMessage,
    dynamic session,
  ) async {
    int? logId;
    if (recordId != null && _numericPrimaryKeyTables.contains(tableName)) {
      logId = int.tryParse(recordId);
    }
    await db.query(
      '''
      INSERT INTO sync_log (device_id, operation, table_name, record_id, status, error_message)
      VALUES (@deviceId, @operation, @tableName, @recordId, @status, @errorMessage)
      ''',
      parameters: {
        'deviceId': deviceId,
        'operation': operation,
        'tableName': tableName,
        'recordId': logId,
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
    cleaned.updateAll((key, value) {
      if (value is DateTime) {
        return value.millisecondsSinceEpoch ~/ 1000;
      }
      return value;
    });
    return cleaned;
  }

  String _getPrimaryKeyColumn(String tableName) {
    return _primaryKeyColumns[tableName] ?? 'id';
  }

  dynamic _convertRecordIdValue(String tableName, String recordId) {
    if (_numericPrimaryKeyTables.contains(tableName)) {
      final value = int.tryParse(recordId);
      if (value == null) {
        print('⚠️  Invalid numeric record id "$recordId" for table $tableName');
      }
      return value;
    }
    return recordId;
  }

  Map<String, dynamic> _sanitizeChangeData(String tableName, Map<String, dynamic> rawData) {
    final allowed = _allowedColumns[tableName];
    if (allowed == null) return {};

    final data = <String, dynamic>{};
    rawData.forEach((key, value) {
      if (allowed.contains(key)) {
        data[key] = value;
      }
    });

    switch (tableName) {
      case 'events':
        return _normalizeEventData(data);
      case 'notes':
        return _normalizeNoteData(data);
      case 'schedule_drawings':
        return _normalizeDrawingData(data);
      case 'books':
        return _normalizeBookData(data);
      default:
        return data;
    }
  }

  Map<String, dynamic> _normalizeEventData(Map<String, dynamic> data) {
    DateTime? parseUserTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value);
      }
      return null;
    }

    DateTime? parseSystemTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
      }
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value).toUtc();
      }
      return null;
    }

    String _normalizePhone(dynamic value) {
      if (value == null) return '';
      final trimmed = value.toString().trim();
      return trimmed;
    }

    String _normalizeEventTypes(dynamic rawValue) {
      try {
        List<dynamic> rawList;
        if (rawValue == null) {
          return '["other"]';
        } else if (rawValue is List) {
          rawList = rawValue;
        } else if (rawValue is String) {
          final trimmed = rawValue.trim();
          if (trimmed.isEmpty) {
            return '["other"]';
          }
          final decoded = jsonDecode(trimmed);
          rawList = decoded is List ? decoded : [decoded];
        } else {
          rawList = [rawValue];
        }

        final cleaned = rawList
            .map((value) => value == null ? null : value.toString().trim())
            .where((value) => value != null && value!.isNotEmpty)
            .map((value) => value!)
            .toList();

        if (cleaned.isEmpty) {
          return '["other"]';
        }

        cleaned.sort((a, b) => a.compareTo(b));
        return jsonEncode(cleaned);
      } catch (_) {
        return '["other"]';
      }
    }

    bool? _normalizeBool(dynamic value) {
      if (value == null) return null;
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        return normalized == 'true' || normalized == '1';
      }
      return null;
    }

    if (data.containsKey('start_time')) {
      data['start_time'] = parseUserTimestamp(data['start_time']);
    }
    if (data.containsKey('end_time')) {
      data['end_time'] = parseUserTimestamp(data['end_time']);
    }
    if (data.containsKey('created_at')) {
      data['created_at'] = parseSystemTimestamp(data['created_at']);
    }
    if (data.containsKey('updated_at')) {
      data['updated_at'] = parseSystemTimestamp(data['updated_at']);
    }

    if (data.containsKey('phone')) {
      final phone = _normalizePhone(data['phone']);
      data['phone'] = phone.isEmpty ? null : phone;
    }

    if (data.containsKey('event_types')) {
      final normalized = _normalizeEventTypes(data['event_types']);
      data['event_types'] = normalized;
      final decoded = jsonDecode(normalized) as List<dynamic>;
      if (decoded.isNotEmpty) {
        data['event_type'] = decoded.first.toString();
      }
    } else if (data.containsKey('event_type')) {
      final primary = data['event_type']?.toString().trim();
      final normalized = (primary != null && primary.isNotEmpty)
          ? jsonEncode([primary])
          : '["other"]';
      data['event_types'] = normalized;
    } else {
      data['event_types'] = '["other"]';
      data['event_type'] = 'other';
    }

    final hasChargeItems = _normalizeBool(data['has_charge_items']);
    if (hasChargeItems != null) {
      data['has_charge_items'] = hasChargeItems;
    }

    final boolFields = ['is_removed', 'is_checked', 'has_note', 'is_deleted'];
    for (final field in boolFields) {
      final normalized = _normalizeBool(data[field]);
      if (normalized != null) {
        data[field] = normalized;
      }
    }

    return data;
  }

  Map<String, dynamic> _normalizeNoteData(Map<String, dynamic> data) {
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
      }
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value).toUtc();
      }
      return null;
    }

    if (data.containsKey('created_at')) {
      data['created_at'] = parseTimestamp(data['created_at']);
    }
    if (data.containsKey('updated_at')) {
      data['updated_at'] = parseTimestamp(data['updated_at']);
    }

    final isDeleted = data['is_deleted'];
    if (isDeleted != null) {
      data['is_deleted'] = (isDeleted is bool)
          ? isDeleted
          : (isDeleted is num ? isDeleted != 0 : false);
    }

    return data;
  }

  Map<String, dynamic> _normalizeDrawingData(Map<String, dynamic> data) {
    DateTime? parseUserTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value);
      }
      return null;
    }

    DateTime? parseSystemTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
      }
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value).toUtc();
      }
      return null;
    }

    if (data.containsKey('date')) {
      data['date'] = parseUserTimestamp(data['date']);
    }
    if (data.containsKey('created_at')) {
      data['created_at'] = parseSystemTimestamp(data['created_at']);
    }
    if (data.containsKey('updated_at')) {
      data['updated_at'] = parseSystemTimestamp(data['updated_at']);
    }
    if (data.containsKey('synced_at')) {
      data['synced_at'] = parseSystemTimestamp(data['synced_at']);
    }

    if (data.containsKey('is_deleted')) {
      final value = data['is_deleted'];
      data['is_deleted'] = (value is bool)
          ? value
          : (value is num ? value != 0 : false);
    }

    return data;
  }

  Map<String, dynamic> _normalizeBookData(Map<String, dynamic> data) {
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
      }
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value).toUtc();
      }
      return null;
    }

    if (data.containsKey('created_at')) {
      data['created_at'] = parseTimestamp(data['created_at']);
    }
    if (data.containsKey('updated_at')) {
      data['updated_at'] = parseTimestamp(data['updated_at']);
    }
    if (data.containsKey('archived_at')) {
      data['archived_at'] = parseTimestamp(data['archived_at']);
    }

    if (data.containsKey('is_deleted')) {
      final value = data['is_deleted'];
      data['is_deleted'] = (value is bool)
          ? value
          : (value is num ? value != 0 : false);
    }

    return data;
  }

  void _removePrimaryKey(Map<String, dynamic> data, String tableName) {
    final pk = _getPrimaryKeyColumn(tableName);
    data.remove(pk);
  }
}
