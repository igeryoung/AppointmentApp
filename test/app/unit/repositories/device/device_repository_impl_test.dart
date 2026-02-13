@Tags(['device', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/repositories/device_repository_impl.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/test_db_path.dart';

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  late DeviceRepositoryImpl repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('device_repository');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');
    repository = DeviceRepositoryImpl(() => dbService.database);
  });

  tearDown(() async {
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  test(
    'DEVICE-UNIT-001: getCredentials() returns null when no credentials saved',
    () async {
      // Arrange
      // no setup required

      // Act
      final credentials = await repository.getCredentials();

      // Assert
      expect(credentials, isNull);
    },
  );

  test(
    'DEVICE-UNIT-002: saveCredentials() persists credentials for retrieval',
    () async {
      // Arrange
      const deviceId = 'device-001';
      const deviceToken = 'token-001';

      // Act
      await repository.saveCredentials(
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: 'Primary Device',
        platform: 'test',
      );
      final credentials = await repository.getCredentials();

      // Assert
      expect(credentials, isNotNull);
      expect(credentials!.deviceId, deviceId);
      expect(credentials.deviceToken, deviceToken);
    },
  );

  test(
    'DEVICE-UNIT-003: saveCredentials() replaces existing single-row credentials',
    () async {
      // Arrange
      await repository.saveCredentials(
        deviceId: 'device-old',
        deviceToken: 'token-old',
        deviceName: 'Old Device',
        platform: 'old',
      );

      // Act
      await repository.saveCredentials(
        deviceId: 'device-new',
        deviceToken: 'token-new',
        deviceName: 'New Device',
        platform: 'new',
      );
      final rows = await db.query('device_info');
      final credentials = await repository.getCredentials();

      // Assert
      expect(rows.length, 1);
      expect(credentials, isNotNull);
      expect(credentials!.deviceId, 'device-new');
      expect(credentials.deviceToken, 'token-new');
    },
  );
}
