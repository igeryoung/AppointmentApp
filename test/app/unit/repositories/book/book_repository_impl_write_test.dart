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
    await setUniqueDatabasePath('book_repository_write');
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
  }) async {
    await db.insert('books', {
      'book_uuid': uuid,
      'name': name,
      'created_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
      'archived_at': null,
    });
  }

  test(
    'BOOK-UNIT-002: archive() marks book archived and hides it from active listing',
    () async {
      // Arrange
      await insertBookRow(uuid: 'book-archive', name: 'Archive Target');

      // Act
      await repository.archive('book-archive');
      final archivedBook = await repository.getByUuid('book-archive');
      final activeBooks = await repository.getAll();

      // Assert
      expect(archivedBook, isNotNull);
      expect(archivedBook!.archivedAt, isNotNull);
      expect(activeBooks.any((b) => b.uuid == 'book-archive'), isFalse);
    },
  );

  test('BOOK-UNIT-002: delete() removes book row permanently', () async {
    // Arrange
    await insertBookRow(uuid: 'book-delete', name: 'Delete Target');

    // Act
    await repository.delete('book-delete');
    final deleted = await repository.getByUuid('book-delete');

    // Assert
    expect(deleted, isNull);
  });
}
