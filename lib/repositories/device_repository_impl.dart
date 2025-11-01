import 'package:sqflite/sqflite.dart';
import '../services/prd_database_service.dart'; // For DeviceCredentials class
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
      deviceId: map['device_id'] as String,
      deviceToken: map['device_token'] as String,
    );
  }

  @override
  Future<void> saveCredentials({
    required String deviceId,
    required String deviceToken,
    required String deviceName,
    String? platform,
  }) async {
    final db = await _getDatabaseFn();
    await db.insert(
      'device_info',
      {
        'id': 1,
        'device_id': deviceId,
        'device_token': deviceToken,
        'device_name': deviceName,
        'platform': platform,
        'registered_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
