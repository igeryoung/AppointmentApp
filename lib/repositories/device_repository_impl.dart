import 'package:sqflite/sqflite.dart';
import '../services/database/prd_database_service.dart'; // For DeviceCredentials class
import 'device_repository.dart';

/// Implementation of DeviceRepository using SQLite
class DeviceRepositoryImpl implements IDeviceRepository {
  final Future<Database> Function() _getDatabaseFn;

  DeviceRepositoryImpl(this._getDatabaseFn);

  @override
  Future<DeviceCredentials?> getCredentials() async {
    final db = await _getDatabaseFn();
    final maps = await db.query('device_info', limit: 1);

    if (maps.isEmpty) return null;

    final map = maps.first;
    return DeviceCredentials(
      accountId: map['account_id'] as String?,
      username: map['username'] as String?,
      deviceId: map['device_id'] as String,
      deviceToken: map['device_token'] as String,
      deviceRole: (map['device_role'] as String?) ?? 'write',
    );
  }

  @override
  Future<void> saveCredentials({
    String? accountId,
    String? username,
    required String deviceId,
    required String deviceToken,
    required String deviceName,
    String? platform,
    String deviceRole = 'read',
  }) async {
    final db = await _getDatabaseFn();
    await db.insert('device_info', {
      'id': 1,
      'account_id': accountId,
      'username': username,
      'device_id': deviceId,
      'device_token': deviceToken,
      'device_name': deviceName,
      'device_role': deviceRole,
      'platform': platform,
      'registered_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
