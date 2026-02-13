@Tags(['event', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/repositories/event_repository_impl.dart';
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
    await setUniqueDatabasePath('event_repository_sync');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');
    repository = EventRepositoryImpl(() => dbService.database);

    await seedBook(db, bookUuid: 'book-a');
    await seedRecord(
      db,
      recordUuid: 'record-a1',
      name: 'Alice',
      recordNumber: '001',
    );
  });

  tearDown(() async {
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  test(
    'EVENT-UNIT-009: applyServerChange() inserts missing event and updates existing event',
    () async {
      // Arrange
      final baseEvent = makeEvent(
        id: 'event-sync-1',
        bookUuid: 'book-a',
        recordUuid: 'record-a1',
        title: 'Server Title V1',
        version: 1,
        eventTypes: [EventType.consultation],
      );

      // Act
      await repository.applyServerChange(baseEvent.toMap());
      final inserted = await repository.getById('event-sync-1');

      final updatedMap = Map<String, dynamic>.from(baseEvent.toMap());
      updatedMap['title'] = 'Server Title V2';
      updatedMap['version'] = 2;
      await repository.applyServerChange(updatedMap);
      final updated = await repository.getById('event-sync-1');

      // Assert
      expect(inserted, isNotNull);
      expect(inserted!.title, 'Server Title V1');
      expect(updated, isNotNull);
      expect(updated!.title, 'Server Title V2');
      expect(updated.version, 2);
    },
  );

  test(
    'EVENT-UNIT-010: getByServerId() returns event by ID and null when missing',
    () async {
      // Arrange
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-server-id-1',
          bookUuid: 'book-a',
          recordUuid: 'record-a1',
        ),
      );

      // Act
      final found = await repository.getByServerId('event-server-id-1');
      final missing = await repository.getByServerId('event-server-id-missing');

      // Assert
      expect(found, isNotNull);
      expect(found!.id, 'event-server-id-1');
      expect(missing, isNull);
    },
  );
}
