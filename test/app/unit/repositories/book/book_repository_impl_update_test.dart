@Tags(['book', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/book.dart';
import 'package:schedule_note_app/repositories/book_repository_impl.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/test_db_path.dart';

class _FakeBookUpdateApiClient extends ApiClient {
  _FakeBookUpdateApiClient() : super(baseUrl: 'http://fake.local');

  int updateCalls = 0;
  String? lastBookUuid;
  String? lastName;
  String? lastDeviceId;
  String? lastDeviceToken;

  @override
  Future<Map<String, dynamic>> updateBook({
    required String bookUuid,
    required String name,
    required String deviceId,
    required String deviceToken,
  }) async {
    updateCalls += 1;
    lastBookUuid = bookUuid;
    lastName = name;
    lastDeviceId = deviceId;
    lastDeviceToken = deviceToken;
    return {'bookUuid': bookUuid, 'name': name, 'version': 2};
  }
}

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  late BookRepositoryImpl repository;
  _FakeBookUpdateApiClient? fakeApiClient;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('book_repository_update');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');

    repository = BookRepositoryImpl(() => dbService.database);
    fakeApiClient = _FakeBookUpdateApiClient();
  });

  tearDown(() async {
    fakeApiClient?.dispose();
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  Future<void> insertBookRow({
    required String uuid,
    required String name,
  }) async {
    await db.insert('books', {
      'book_uuid': uuid,
      'name': name,
      'created_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
      'archived_at': null,
    });
  }

  test(
    'BOOK-UNIT-006: update() trims book name and persists the change',
    () async {
      // Arrange
      await insertBookRow(uuid: 'book-update-1', name: 'Old Name');
      final original = Book(
        uuid: 'book-update-1',
        name: '  New Name  ',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      // Act
      final updated = await repository.update(original);
      final row = await db.query(
        'books',
        where: 'book_uuid = ?',
        whereArgs: ['book-update-1'],
        limit: 1,
      );

      // Assert
      expect(updated.name, 'New Name');
      expect(row.single['name'], 'New Name');
    },
  );

  test('BOOK-UNIT-006: update() rejects empty book name', () async {
    // Arrange
    final invalid = Book(
      uuid: 'book-update-1',
      name: '   ',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    // Act
    final action = () => repository.update(invalid);

    // Assert
    await expectLater(action, throwsA(isA<ArgumentError>()));
  });

  test(
    'BOOK-UNIT-007: update() throws when target book does not exist',
    () async {
      // Arrange
      final missing = Book(
        uuid: 'book-missing',
        name: 'Any Name',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      // Act
      final action = () => repository.update(missing);

      // Assert
      await expectLater(
        action,
        throwsA(
          predicate((error) {
            return error.toString().contains('Book not found');
          }),
        ),
      );
    },
  );

  test(
    'BOOK-UNIT-013: update() syncs rename to server when API client is configured',
    () async {
      // Arrange
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      await insertBookRow(uuid: 'book-update-2', name: 'Old Name');
      final withServer = BookRepositoryImpl(
        () => dbService.database,
        apiClient: fakeApiClient,
        dbService: dbService,
      );
      final payload = Book(
        uuid: 'book-update-2',
        name: '  Server Name  ',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      // Act
      await withServer.update(payload);

      // Assert
      expect(fakeApiClient!.updateCalls, 1);
      expect(fakeApiClient!.lastBookUuid, 'book-update-2');
      expect(fakeApiClient!.lastName, 'Server Name');
      expect(fakeApiClient!.lastDeviceId, 'device-001');
      expect(fakeApiClient!.lastDeviceToken, 'token-001');
    },
  );
}
