@Tags(['book', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/repositories/book_repository_impl.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/test_db_path.dart';

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  late BookRepositoryImpl repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('book_repository_read');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');

    repository = BookRepositoryImpl(() => dbService.database);
  });

  tearDown(() async {
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  Future<void> insertBookRow({
    required String uuid,
    required String name,
    int? archivedAtSeconds,
  }) async {
    await db.insert('books', {
      'book_uuid': uuid,
      'name': name,
      'created_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
      'archived_at': archivedAtSeconds,
    });
  }

  test('BOOK-UNIT-001: getAll() excludes archived books by default', () async {
    // Arrange
    await insertBookRow(uuid: 'book-active', name: 'Active Book');
    await insertBookRow(
      uuid: 'book-archived',
      name: 'Archived Book',
      archivedAtSeconds:
          DateTime.utc(2026, 1, 10).millisecondsSinceEpoch ~/ 1000,
    );

    // Act
    final activeBooks = await repository.getAll();
    final allBooks = await repository.getAll(includeArchived: true);

    // Assert
    expect(activeBooks.length, 1);
    expect(activeBooks.single.uuid, 'book-active');
    expect(allBooks.length, 2);
  });

  test(
    'BOOK-UNIT-001: getByUuid() returns matching book when it exists',
    () async {
      // Arrange
      await insertBookRow(uuid: 'book-lookup', name: 'Lookup Book');

      // Act
      final found = await repository.getByUuid('book-lookup');
      final missing = await repository.getByUuid('book-missing');

      // Assert
      expect(found, isNotNull);
      expect(found!.uuid, 'book-lookup');
      expect(found.name, 'Lookup Book');
      expect(missing, isNull);
    },
  );
}
