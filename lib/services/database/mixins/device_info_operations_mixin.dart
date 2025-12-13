import 'package:sqflite/sqflite.dart';

/// Device credentials for API authentication
class DeviceCredentials {
  final String deviceId;
  final String deviceToken;

  const DeviceCredentials({
    required this.deviceId,
    required this.deviceToken,
  });
}

/// Mixin providing Device Info operations for PRDDatabaseService
mixin DeviceInfoOperationsMixin {
  /// Subclasses must provide database access
  Future<Database> get database;

  // ===================
  // Device Info Operations
  // ===================

  /// Get device credentials for API authentication
  ///
  /// Returns null if device is not registered yet
  Future<DeviceCredentials?> getDeviceCredentials() async {
    final db = await database;
    final maps = await db.query('device_info', where: 'id = 1', limit: 1);

    if (maps.isEmpty) {
      return null;
    }

    final row = maps.first;
    return DeviceCredentials(
      deviceId: row['device_id'] as String,
      deviceToken: row['device_token'] as String,
    );
  }

  /// Save device credentials after registration
  Future<void> saveDeviceCredentials({
    required String deviceId,
    required String deviceToken,
    required String deviceName,
    required String serverUrl,
    String? platform,
  }) async {
    final db = await database;
    await db.insert(
      'device_info',
      {
        'id': 1,
        'device_id': deviceId,
        'device_token': deviceToken,
        'device_name': deviceName,
        'server_url': serverUrl,
        'platform': platform,
        'registered_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
