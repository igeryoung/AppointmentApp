import 'package:json_annotation/json_annotation.dart';

part 'sync_change.g.dart';

/// Represents a single change in a sync operation
@JsonSerializable()
class SyncChange {
  final String tableName;
  final int recordId;
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

  factory SyncChange.fromJson(Map<String, dynamic> json) =>
      _$SyncChangeFromJson(json);
  Map<String, dynamic> toJson() => _$SyncChangeToJson(this);
}

/// Sync request from client to server
@JsonSerializable()
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

  factory SyncRequest.fromJson(Map<String, dynamic> json) =>
      _$SyncRequestFromJson(json);
  Map<String, dynamic> toJson() => _$SyncRequestToJson(this);
}

/// Sync response from server to client
@JsonSerializable()
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

  factory SyncResponse.fromJson(Map<String, dynamic> json) =>
      _$SyncResponseFromJson(json);
  Map<String, dynamic> toJson() => _$SyncResponseToJson(this);
}

/// Represents a conflict between local and server data
@JsonSerializable()
class SyncConflict {
  final String tableName;
  final int recordId;
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

  factory SyncConflict.fromJson(Map<String, dynamic> json) =>
      _$SyncConflictFromJson(json);
  Map<String, dynamic> toJson() => _$SyncConflictToJson(this);
}

/// Conflict resolution request
@JsonSerializable()
class ConflictResolutionRequest {
  final String deviceId;
  final String deviceToken;
  final String tableName;
  final int recordId;
  final String resolution; // 'use_local', 'use_server', 'merge'
  final Map<String, dynamic>? mergedData; // For merge resolution

  const ConflictResolutionRequest({
    required this.deviceId,
    required this.deviceToken,
    required this.tableName,
    required this.recordId,
    required this.resolution,
    this.mergedData,
  });

  factory ConflictResolutionRequest.fromJson(Map<String, dynamic> json) =>
      _$ConflictResolutionRequestFromJson(json);
  Map<String, dynamic> toJson() => _$ConflictResolutionRequestToJson(this);
}
