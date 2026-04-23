import 'package:sqflite/sqflite.dart';

/// Device credentials for API authentication
class DeviceCredentials {
  final String? accountId;
  final String? username;
  final String deviceId;
  final String deviceToken;
  final String deviceRole;

  const DeviceCredentials({
    this.accountId,
    this.username,
    required this.deviceId,
    required this.deviceToken,
    this.deviceRole = 'write',
  });

  bool get isReadOnly => deviceRole.toLowerCase() == 'read';
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
      accountId: row['account_id'] as String?,
      username: row['username'] as String?,
      deviceId: row['device_id'] as String,
      deviceToken: row['device_token'] as String,
      deviceRole: (row['device_role'] as String?) ?? 'write',
    );
  }

  /// Save device credentials after registration
  Future<void> saveDeviceCredentials({
    String? accountId,
    String? username,
    required String deviceId,
    required String deviceToken,
    required String deviceName,
    required String serverUrl,
    String? platform,
    String deviceRole = 'read',
  }) async {
    final db = await database;
    await db.insert('device_info', {
      'id': 1,
      'account_id': accountId,
      'username': username,
      'device_id': deviceId,
      'device_token': deviceToken,
      'device_name': deviceName,
      'device_role': deviceRole,
      'server_url': serverUrl,
      'platform': platform,
      'registered_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Clear local account/device credentials.
  Future<void> clearDeviceCredentials() async {
    final db = await database;
    await db.delete('device_info');
  }
}
