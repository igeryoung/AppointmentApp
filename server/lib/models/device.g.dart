// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Device _$DeviceFromJson(Map<String, dynamic> json) => Device(
  id: json['id'] as String,
  deviceName: json['deviceName'] as String,
  deviceToken: json['deviceToken'] as String,
  platform: json['platform'] as String?,
  registeredAt: DateTime.parse(json['registeredAt'] as String),
  lastSyncAt: json['lastSyncAt'] == null
      ? null
      : DateTime.parse(json['lastSyncAt'] as String),
  isActive: json['isActive'] as bool? ?? true,
);

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'id': instance.id,
  'deviceName': instance.deviceName,
  'deviceToken': instance.deviceToken,
  'platform': instance.platform,
  'registeredAt': instance.registeredAt.toIso8601String(),
  'lastSyncAt': instance.lastSyncAt?.toIso8601String(),
  'isActive': instance.isActive,
};

DeviceRegisterRequest _$DeviceRegisterRequestFromJson(
  Map<String, dynamic> json,
) => DeviceRegisterRequest(
  deviceName: json['deviceName'] as String,
  platform: json['platform'] as String?,
  password: json['password'] as String,
);

Map<String, dynamic> _$DeviceRegisterRequestToJson(
  DeviceRegisterRequest instance,
) => <String, dynamic>{
  'deviceName': instance.deviceName,
  'platform': instance.platform,
  'password': instance.password,
};

DeviceRegisterResponse _$DeviceRegisterResponseFromJson(
  Map<String, dynamic> json,
) => DeviceRegisterResponse(
  deviceId: json['deviceId'] as String,
  deviceToken: json['deviceToken'] as String,
  message: json['message'] as String,
);

Map<String, dynamic> _$DeviceRegisterResponseToJson(
  DeviceRegisterResponse instance,
) => <String, dynamic>{
  'deviceId': instance.deviceId,
  'deviceToken': instance.deviceToken,
  'message': instance.message,
};
