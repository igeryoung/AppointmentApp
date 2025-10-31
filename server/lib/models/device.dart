import 'package:json_annotation/json_annotation.dart';

part 'device.g.dart';

/// Device model - Represents a registered device
@JsonSerializable()
class Device {
  final String id;
  final String deviceName;
  final String deviceToken;
  final String? platform;
  final DateTime registeredAt;
  final DateTime? lastSyncAt;
  final bool isActive;

  const Device({
    required this.id,
    required this.deviceName,
    required this.deviceToken,
    this.platform,
    required this.registeredAt,
    this.lastSyncAt,
    this.isActive = true,
  });

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceToJson(this);

  factory Device.fromDatabase(Map<String, dynamic> row) {
    return Device(
      id: row['id'].toString(),
      deviceName: row['device_name'] as String,
      deviceToken: row['device_token'] as String,
      platform: row['platform'] as String?,
      registeredAt: row['registered_at'] as DateTime,
      lastSyncAt: row['last_sync_at'] as DateTime?,
      isActive: row['is_active'] as bool? ?? true,
    );
  }

  Device copyWith({
    String? id,
    String? deviceName,
    String? deviceToken,
    String? platform,
    DateTime? registeredAt,
    DateTime? lastSyncAt,
    bool? isActive,
  }) {
    return Device(
      id: id ?? this.id,
      deviceName: deviceName ?? this.deviceName,
      deviceToken: deviceToken ?? this.deviceToken,
      platform: platform ?? this.platform,
      registeredAt: registeredAt ?? this.registeredAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Device registration request
@JsonSerializable()
class DeviceRegisterRequest {
  final String deviceName;
  final String? platform;
  final String password;

  const DeviceRegisterRequest({
    required this.deviceName,
    this.platform,
    required this.password,
  });

  factory DeviceRegisterRequest.fromJson(Map<String, dynamic> json) =>
      _$DeviceRegisterRequestFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceRegisterRequestToJson(this);
}

/// Device registration response
@JsonSerializable()
class DeviceRegisterResponse {
  final String deviceId;
  final String deviceToken;
  final String message;

  const DeviceRegisterResponse({
    required this.deviceId,
    required this.deviceToken,
    required this.message,
  });

  factory DeviceRegisterResponse.fromJson(Map<String, dynamic> json) =>
      _$DeviceRegisterResponseFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceRegisterResponseToJson(this);
}
