@Tags(['book', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/repositories/book_repository_impl.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/test_db_path.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://fake.local');

  int createBookCalls = 0;
  Map<String, dynamic> createBookResponse = {
    'success': true,
    'uuid': 'server-book-uuid',
    'name': 'Server Book',
  };

  @override
  Future<Map<String, dynamic>> createBook({
    required String name,
    required String deviceId,
    required String deviceToken,
  }) async {
    createBookCalls += 1;
    return createBookResponse;
  }
}

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  _FakeApiClient? fakeApiClient;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('book_repository_create');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');

    fakeApiClient = _FakeApiClient();
  });

  tearDown(() async {
    fakeApiClient?.dispose();
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  test(
    'BOOK-UNIT-003: create() fails when device credentials are missing',
    () async {
      // Arrange
      final repository = BookRepositoryImpl(
        () => dbService.database,
        apiClient: fakeApiClient,
        dbService: dbService,
      );

      // Act
      final action = () => repository.create('New Book');

      // Assert
      await expectLater(
        action,
        throwsA(
          predicate((error) {
            return error.toString().contains('Device not registered');
          }),
        ),
      );
      expect(fakeApiClient!.createBookCalls, 0);
    },
  );

  test('BOOK-UNIT-004: create() stores local book with server UUID', () async {
    // Arrange
    await dbService.saveDeviceCredentials(
      deviceId: 'device-001',
      deviceToken: 'token-001',
      deviceName: 'Test Device',
      serverUrl: 'https://server.local',
      platform: 'test',
    );
    fakeApiClient!.createBookResponse = {
      'success': true,
      'uuid': 'uuid-from-server-001',
      'name': 'My Book',
    };

    final repository = BookRepositoryImpl(
      () => dbService.database,
      apiClient: fakeApiClient,
      dbService: dbService,
    );

    // Act
    final created = await repository.create('My Book');
    final row = await db.query(
      'books',
      where: 'book_uuid = ?',
      whereArgs: ['uuid-from-server-001'],
      limit: 1,
    );

    // Assert
    expect(fakeApiClient!.createBookCalls, 1);
    expect(created.uuid, 'uuid-from-server-001');
    expect(created.name, 'My Book');
    expect(row.length, 1);
    expect(row.first['name'], 'My Book');
  });

  test('BOOK-UNIT-004: create() rejects empty book name', () async {
    // Arrange
    final repository = BookRepositoryImpl(
      () => dbService.database,
      apiClient: fakeApiClient,
      dbService: dbService,
    );

    // Act
    final action = () => repository.create('   ');

    // Assert
    await expectLater(action, throwsA(isA<ArgumentError>()));
    expect(fakeApiClient!.createBookCalls, 0);
  });
}
