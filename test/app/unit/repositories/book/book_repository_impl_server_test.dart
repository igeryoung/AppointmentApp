@Tags(['book', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/repositories/book_repository_impl.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/test_db_path.dart';

class _FakeBookServerApiClient extends ApiClient {
  _FakeBookServerApiClient() : super(baseUrl: 'http://fake.local');

  int listCalls = 0;
  int pullCalls = 0;
  int infoCalls = 0;

  String? lastListDeviceId;
  String? lastListDeviceToken;
  String? lastListSearchQuery;

  String? lastPullDeviceId;
  String? lastPullDeviceToken;
  String? lastPullBookUuid;

  String? lastInfoDeviceId;
  String? lastInfoDeviceToken;
  String? lastInfoBookUuid;

  List<Map<String, dynamic>> listResponse = const [];
  Map<String, dynamic> pullResponse = {
    'book': {
      'book_uuid': 'server-book-default',
      'name': 'Server Book Default',
      'created_at': '2026-01-01T00:00:00Z',
      'version': 1,
    },
    'events': [],
    'notes': [],
    'drawings': [],
  };
  Map<String, dynamic> infoResponse = const {
    'bookUuid': 'server-book-default',
    'name': 'Server Book Default',
    'eventCount': 0,
  };

  Object? listError;
  Object? pullError;
  Object? infoError;

  @override
  Future<List<Map<String, dynamic>>> listServerBooks({
    required String deviceId,
    required String deviceToken,
    String? searchQuery,
  }) async {
    listCalls += 1;
    lastListDeviceId = deviceId;
    lastListDeviceToken = deviceToken;
    lastListSearchQuery = searchQuery;
    if (listError != null) throw listError!;
    return listResponse;
  }

  @override
  Future<Map<String, dynamic>> pullBook({
    required String bookUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    pullCalls += 1;
    lastPullBookUuid = bookUuid;
    lastPullDeviceId = deviceId;
    lastPullDeviceToken = deviceToken;
    if (pullError != null) throw pullError!;
    return pullResponse;
  }

  @override
  Future<Map<String, dynamic>> getServerBookInfo({
    required String bookUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    infoCalls += 1;
    lastInfoBookUuid = bookUuid;
    lastInfoDeviceId = deviceId;
    lastInfoDeviceToken = deviceToken;
    if (infoError != null) throw infoError!;
    return infoResponse;
  }
}

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  _FakeBookServerApiClient? fakeApiClient;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('book_repository_server');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');
    fakeApiClient = _FakeBookServerApiClient();
  });

  tearDown(() async {
    fakeApiClient?.dispose();
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  Future<void> saveCredentials() async {
    await dbService.saveDeviceCredentials(
      deviceId: 'device-001',
      deviceToken: 'token-001',
      deviceName: 'Test Device',
      serverUrl: 'https://server.local',
      platform: 'test',
    );
  }

  BookRepositoryImpl buildRepository() {
    return BookRepositoryImpl(
      () => dbService.database,
      apiClient: fakeApiClient,
      dbService: dbService,
    );
  }

  test(
    'BOOK-UNIT-008: listServerBooks() fails when device credentials are missing',
    () async {
      // Arrange
      final repository = buildRepository();

      // Act
      final action = () => repository.listServerBooks();

      // Assert
      await expectLater(
        action,
        throwsA(
          predicate((error) {
            return error.toString().contains('Device not registered');
          }),
        ),
      );
      expect(fakeApiClient!.listCalls, 0);
    },
  );

  test(
    'BOOK-UNIT-009: listServerBooks() forwards search query and returns server list',
    () async {
      // Arrange
      await saveCredentials();
      fakeApiClient!.listResponse = [
        {'bookUuid': 'server-book-1', 'name': 'Server Book 1'},
      ];
      final repository = buildRepository();

      // Act
      final result = await repository.listServerBooks(searchQuery: 'server');

      // Assert
      expect(fakeApiClient!.listCalls, 1);
      expect(fakeApiClient!.lastListDeviceId, 'device-001');
      expect(fakeApiClient!.lastListDeviceToken, 'token-001');
      expect(fakeApiClient!.lastListSearchQuery, 'server');
      expect(result.length, 1);
      expect(result.single['bookUuid'], 'server-book-1');
    },
  );

  test(
    'BOOK-UNIT-010: getServerBookInfo() returns null when API responds 404',
    () async {
      // Arrange
      await saveCredentials();
      fakeApiClient!.infoError = ApiException(
        'Book not found',
        statusCode: 404,
      );
      final repository = buildRepository();

      // Act
      final result = await repository.getServerBookInfo('missing-book');

      // Assert
      expect(fakeApiClient!.infoCalls, 1);
      expect(result, isNull);
    },
  );

  test(
    'BOOK-UNIT-011: pullBookFromServer() rejects when book already exists locally',
    () async {
      // Arrange
      await saveCredentials();
      await db.insert('books', {
        'book_uuid': 'local-book-1',
        'name': 'Local Book 1',
        'created_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
        'archived_at': null,
      });
      final repository = buildRepository();

      // Act
      final action = () => repository.pullBookFromServer('local-book-1');

      // Assert
      await expectLater(
        action,
        throwsA(
          predicate((error) {
            return error.toString().contains('already exists locally');
          }),
        ),
      );
      expect(fakeApiClient!.pullCalls, 0);
    },
  );

  test(
    'BOOK-UNIT-012: pullBookFromServer() stores pulled book when server payload is valid',
    () async {
      // Arrange
      await saveCredentials();
      fakeApiClient!.pullResponse = {
        'book': {
          'book_uuid': 'server-book-2',
          'name': 'Pulled Book 2',
          'created_at': '2026-02-01T08:00:00Z',
          'version': 3,
        },
        'events': [],
        'notes': [],
        'drawings': [],
      };
      final repository = buildRepository();

      // Act
      await repository.pullBookFromServer('server-book-2');
      final inserted = await repository.getByUuid('server-book-2');

      // Assert
      expect(fakeApiClient!.pullCalls, 1);
      expect(fakeApiClient!.lastPullBookUuid, 'server-book-2');
      expect(fakeApiClient!.lastPullDeviceId, 'device-001');
      expect(fakeApiClient!.lastPullDeviceToken, 'token-001');
      expect(inserted, isNotNull);
      expect(inserted!.name, 'Pulled Book 2');
      expect(inserted.archivedAt, isNull);
    },
  );
}
