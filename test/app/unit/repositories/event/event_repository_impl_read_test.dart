@Tags(['event', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/repositories/event_repository_impl.dart';
import 'package:schedule_note_app/repositories/event_repository.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/db_seed.dart';
import '../../../support/fixtures/event_fixtures.dart';
import '../../../support/test_db_path.dart';

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  late EventRepositoryImpl repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('event_repository_read');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');
    repository = EventRepositoryImpl(() => dbService.database);
  });

  tearDown(() async {
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  test(
    'EVENT-UNIT-001: getByBookId() returns only target book events ordered by start_time',
    () async {
      // Arrange
      await seedBook(db, bookUuid: 'book-a');
      await seedBook(db, bookUuid: 'book-b');
      await seedRecord(
        db,
        recordUuid: 'record-a1',
        name: 'Alpha',
        recordNumber: '001',
      );
      await seedRecord(
        db,
        recordUuid: 'record-a2',
        name: 'Beta',
        recordNumber: '002',
      );
      await seedRecord(
        db,
        recordUuid: 'record-b1',
        name: 'Gamma',
        recordNumber: '003',
      );

      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-a-late',
          bookUuid: 'book-a',
          recordUuid: 'record-a1',
          startTime: DateTime.utc(2026, 1, 2, 10),
        ),
      );
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-a-early',
          bookUuid: 'book-a',
          recordUuid: 'record-a2',
          startTime: DateTime.utc(2026, 1, 2, 8),
        ),
      );
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-b-only',
          bookUuid: 'book-b',
          recordUuid: 'record-b1',
          startTime: DateTime.utc(2026, 1, 2, 9),
        ),
      );

      // Act
      final result = await repository.getByBookId('book-a');

      // Assert
      expect(result.map((e) => e.id).toList(), [
        'event-a-early',
        'event-a-late',
      ]);
    },
  );

  test(
    'EVENT-UNIT-002: getByDateRange() uses inclusive start and exclusive end',
    () async {
      // Arrange
      await seedBook(db, bookUuid: 'book-a');
      await seedRecord(
        db,
        recordUuid: 'record-a1',
        name: 'Alpha',
        recordNumber: '001',
      );
      await seedRecord(
        db,
        recordUuid: 'record-a2',
        name: 'Beta',
        recordNumber: '002',
      );
      await seedRecord(
        db,
        recordUuid: 'record-a3',
        name: 'Gamma',
        recordNumber: '003',
      );

      final start = DateTime.utc(2026, 1, 10, 0);
      final end = DateTime.utc(2026, 1, 11, 0);

      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-at-start',
          bookUuid: 'book-a',
          recordUuid: 'record-a1',
          startTime: start,
        ),
      );
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-before-end',
          bookUuid: 'book-a',
          recordUuid: 'record-a2',
          startTime: end.subtract(const Duration(seconds: 1)),
        ),
      );
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-at-end',
          bookUuid: 'book-a',
          recordUuid: 'record-a3',
          startTime: end,
        ),
      );

      // Act
      final result = await repository.getByDateRange('book-a', start, end);

      // Assert
      expect(result.map((e) => e.id).toList(), [
        'event-at-start',
        'event-before-end',
      ]);
    },
  );

  test(
    'EVENT-UNIT-003: name/record lookup APIs use record-based schema correctly',
    () async {
      // Arrange
      await seedBook(db, bookUuid: 'book-a');
      await seedRecord(
        db,
        recordUuid: 'record-1',
        name: 'Alice',
        recordNumber: 'A-001',
      );
      await seedRecord(
        db,
        recordUuid: 'record-2',
        name: 'Bob',
        recordNumber: 'B-001',
      );
      await seedRecord(
        db,
        recordUuid: 'record-3',
        name: 'Alice',
        recordNumber: 'A-002',
      );

      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-1',
          bookUuid: 'book-a',
          recordUuid: 'record-1',
          recordNumber: 'A-001',
        ),
      );
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-2',
          bookUuid: 'book-a',
          recordUuid: 'record-2',
          recordNumber: 'B-001',
        ),
      );
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-3',
          bookUuid: 'book-a',
          recordUuid: 'record-3',
          recordNumber: 'A-002',
        ),
      );

      // Act
      final names = await repository.getAllNames('book-a');
      final numbers = await repository.getAllRecordNumbers('book-a');
      final pairs = await repository.getAllNameRecordPairs('book-a');
      final aliceNumbers = await repository.getRecordNumbersByName(
        'book-a',
        'alice',
      );
      final search = await repository.searchByNameAndRecordNumber(
        'book-a',
        'ALICE',
        'A-001',
      );

      // Assert
      expect(names, ['Alice', 'Bob']);
      expect(numbers, ['A-001', 'A-002', 'B-001']);
      expect(pairs, [
        const NameRecordPair(name: 'Alice', recordNumber: 'A-001'),
        const NameRecordPair(name: 'Alice', recordNumber: 'A-002'),
        const NameRecordPair(name: 'Bob', recordNumber: 'B-001'),
      ]);
      expect(aliceNumbers, ['A-001', 'A-002']);
      expect(search.map((e) => e.id).toList(), ['event-1']);
    },
  );
}
