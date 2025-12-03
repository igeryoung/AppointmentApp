/// Sync data models for client-server synchronization
/// Mirrors server-side models from server/lib/models/sync_change.dart

/// Represents a single change in a sync operation
class SyncChange {
  final String tableName;
  final String recordId;
  final String operation; // 'create', 'update', 'delete'
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int version;

  const SyncChange({
    required this.tableName,
    required this.recordId,
    required this.operation,
    required this.data,
    required this.timestamp,
    required this.version,
  });

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    return SyncChange(
      tableName: json['tableName'] as String,
          recordId: json['recordId'].toString(),
      operation: json['operation'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
      timestamp: DateTime.parse(json['timestamp'] as String),
      version: json['version'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tableName': tableName,
      'recordId': recordId,
      'operation': operation,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'version': version,
    };
  }

  @override
  String toString() {
    return 'SyncChange(table: $tableName, id: $recordId, op: $operation, ver: $version)';
  }
}

/// Sync request from client to server
class SyncRequest {
  final String deviceId;
  final String deviceToken;
  final DateTime? lastSyncAt;
  final List<SyncChange>? localChanges;

  const SyncRequest({
    required this.deviceId,
    required this.deviceToken,
    this.lastSyncAt,
    this.localChanges,
  });

  factory SyncRequest.fromJson(Map<String, dynamic> json) {
    return SyncRequest(
      deviceId: json['deviceId'] as String,
      deviceToken: json['deviceToken'] as String,
      lastSyncAt: json['lastSyncAt'] != null
          ? DateTime.parse(json['lastSyncAt'] as String)
          : null,
      localChanges: json['localChanges'] != null
          ? (json['localChanges'] as List)
              .map((e) => SyncChange.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceToken': deviceToken,
      if (lastSyncAt != null) 'lastSyncAt': lastSyncAt!.toIso8601String(),
      if (localChanges != null)
        'localChanges': localChanges!.map((e) => e.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'SyncRequest(deviceId: $deviceId, lastSync: $lastSyncAt, changes: ${localChanges?.length ?? 0})';
  }
}

/// Sync response from server to client
class SyncResponse {
  final bool success;
  final String message;
  final List<SyncChange>? serverChanges;
  final List<SyncConflict>? conflicts;
  final DateTime serverTime;
  final int changesApplied;

  const SyncResponse({
    required this.success,
    required this.message,
    this.serverChanges,
    this.conflicts,
    required this.serverTime,
    this.changesApplied = 0,
  });

  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    return SyncResponse(
      success: json['success'] as bool,
      message: json['message'] as String,
      serverChanges: json['serverChanges'] != null
          ? (json['serverChanges'] as List)
              .map((e) => SyncChange.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      conflicts: json['conflicts'] != null
          ? (json['conflicts'] as List)
              .map((e) => SyncConflict.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      serverTime: DateTime.parse(json['serverTime'] as String),
      changesApplied: json['changesApplied'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      if (serverChanges != null)
        'serverChanges': serverChanges!.map((e) => e.toJson()).toList(),
      if (conflicts != null)
        'conflicts': conflicts!.map((e) => e.toJson()).toList(),
      'serverTime': serverTime.toIso8601String(),
      'changesApplied': changesApplied,
    };
  }

  @override
  String toString() {
    return 'SyncResponse(success: $success, serverChanges: ${serverChanges?.length ?? 0}, conflicts: ${conflicts?.length ?? 0})';
  }
}

/// Represents a conflict between local and server data
class SyncConflict {
  final String tableName;
  final String recordId;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> serverData;
  final int localVersion;
  final int serverVersion;
  final DateTime localTimestamp;
  final DateTime serverTimestamp;

  const SyncConflict({
    required this.tableName,
    required this.recordId,
    required this.localData,
    required this.serverData,
    required this.localVersion,
    required this.serverVersion,
    required this.localTimestamp,
    required this.serverTimestamp,
  });

  factory SyncConflict.fromJson(Map<String, dynamic> json) {
    return SyncConflict(
      tableName: json['tableName'] as String,
          recordId: json['recordId'].toString(),
      localData: Map<String, dynamic>.from(json['localData'] as Map),
      serverData: Map<String, dynamic>.from(json['serverData'] as Map),
      localVersion: json['localVersion'] as int,
      serverVersion: json['serverVersion'] as int,
      localTimestamp: DateTime.parse(json['localTimestamp'] as String),
      serverTimestamp: DateTime.parse(json['serverTimestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tableName': tableName,
      'recordId': recordId,
      'localData': localData,
      'serverData': serverData,
      'localVersion': localVersion,
      'serverVersion': serverVersion,
      'localTimestamp': localTimestamp.toIso8601String(),
      'serverTimestamp': serverTimestamp.toIso8601String(),
    };
  }

  /// Resolves the conflict using "newest timestamp wins" strategy
  /// Returns the data that should be kept (either local or server)
  Map<String, dynamic> resolveByNewestTimestamp() {
    return serverTimestamp.isAfter(localTimestamp) ? serverData : localData;
  }

  /// Returns true if server version is newer
  bool get serverIsNewer => serverTimestamp.isAfter(localTimestamp);

  @override
  String toString() {
    return 'SyncConflict(table: $tableName, id: $recordId, local: v$localVersion@$localTimestamp, server: v$serverVersion@$serverTimestamp)';
  }
}

/// Result of a sync operation
class SyncResult {
  final bool success;
  final String message;
  final int pushedChanges;
  final int pulledChanges;
  final int conflictsResolved;
  final List<String> errors;
  final DateTime? lastSyncTime;

  const SyncResult({
    required this.success,
    required this.message,
    this.pushedChanges = 0,
    this.pulledChanges = 0,
    this.conflictsResolved = 0,
    this.errors = const [],
    this.lastSyncTime,
  });

  @override
  String toString() {
    return 'SyncResult(success: $success, pushed: $pushedChanges, pulled: $pulledChanges, conflicts: $conflictsResolved)';
  }
}
