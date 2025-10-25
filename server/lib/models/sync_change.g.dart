// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_change.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncChange _$SyncChangeFromJson(Map<String, dynamic> json) => SyncChange(
  tableName: json['tableName'] as String,
  recordId: (json['recordId'] as num).toInt(),
  operation: json['operation'] as String,
  data: json['data'] as Map<String, dynamic>,
  timestamp: DateTime.parse(json['timestamp'] as String),
  version: (json['version'] as num).toInt(),
);

Map<String, dynamic> _$SyncChangeToJson(SyncChange instance) =>
    <String, dynamic>{
      'tableName': instance.tableName,
      'recordId': instance.recordId,
      'operation': instance.operation,
      'data': instance.data,
      'timestamp': instance.timestamp.toIso8601String(),
      'version': instance.version,
    };

SyncRequest _$SyncRequestFromJson(Map<String, dynamic> json) => SyncRequest(
  deviceId: json['deviceId'] as String,
  deviceToken: json['deviceToken'] as String,
  lastSyncAt: json['lastSyncAt'] == null
      ? null
      : DateTime.parse(json['lastSyncAt'] as String),
  localChanges: (json['localChanges'] as List<dynamic>?)
      ?.map((e) => SyncChange.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SyncRequestToJson(SyncRequest instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'deviceToken': instance.deviceToken,
      'lastSyncAt': instance.lastSyncAt?.toIso8601String(),
      'localChanges': instance.localChanges,
    };

SyncResponse _$SyncResponseFromJson(Map<String, dynamic> json) => SyncResponse(
  success: json['success'] as bool,
  message: json['message'] as String,
  serverChanges: (json['serverChanges'] as List<dynamic>?)
      ?.map((e) => SyncChange.fromJson(e as Map<String, dynamic>))
      .toList(),
  conflicts: (json['conflicts'] as List<dynamic>?)
      ?.map((e) => SyncConflict.fromJson(e as Map<String, dynamic>))
      .toList(),
  serverTime: DateTime.parse(json['serverTime'] as String),
  changesApplied: (json['changesApplied'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$SyncResponseToJson(SyncResponse instance) =>
    <String, dynamic>{
      'success': instance.success,
      'message': instance.message,
      'serverChanges': instance.serverChanges,
      'conflicts': instance.conflicts,
      'serverTime': instance.serverTime.toIso8601String(),
      'changesApplied': instance.changesApplied,
    };

SyncConflict _$SyncConflictFromJson(Map<String, dynamic> json) => SyncConflict(
  tableName: json['tableName'] as String,
  recordId: (json['recordId'] as num).toInt(),
  localData: json['localData'] as Map<String, dynamic>,
  serverData: json['serverData'] as Map<String, dynamic>,
  localVersion: (json['localVersion'] as num).toInt(),
  serverVersion: (json['serverVersion'] as num).toInt(),
  localTimestamp: DateTime.parse(json['localTimestamp'] as String),
  serverTimestamp: DateTime.parse(json['serverTimestamp'] as String),
);

Map<String, dynamic> _$SyncConflictToJson(SyncConflict instance) =>
    <String, dynamic>{
      'tableName': instance.tableName,
      'recordId': instance.recordId,
      'localData': instance.localData,
      'serverData': instance.serverData,
      'localVersion': instance.localVersion,
      'serverVersion': instance.serverVersion,
      'localTimestamp': instance.localTimestamp.toIso8601String(),
      'serverTimestamp': instance.serverTimestamp.toIso8601String(),
    };

ConflictResolutionRequest _$ConflictResolutionRequestFromJson(
  Map<String, dynamic> json,
) => ConflictResolutionRequest(
  deviceId: json['deviceId'] as String,
  deviceToken: json['deviceToken'] as String,
  tableName: json['tableName'] as String,
  recordId: (json['recordId'] as num).toInt(),
  resolution: json['resolution'] as String,
  mergedData: json['mergedData'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$ConflictResolutionRequestToJson(
  ConflictResolutionRequest instance,
) => <String, dynamic>{
  'deviceId': instance.deviceId,
  'deviceToken': instance.deviceToken,
  'tableName': instance.tableName,
  'recordId': instance.recordId,
  'resolution': instance.resolution,
  'mergedData': instance.mergedData,
};
