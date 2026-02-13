@Tags(['book', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/book.dart';
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
    await setUniqueDatabasePath('book_repository_update');
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
}
