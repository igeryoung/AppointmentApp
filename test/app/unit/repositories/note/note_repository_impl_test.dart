@Tags(['note', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/repositories/note_repository_impl.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/db_seed.dart';
import '../../../support/fixtures/event_fixtures.dart';
import '../../../support/fixtures/note_fixtures.dart';
import '../../../support/test_db_path.dart';

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  late NoteRepositoryImpl repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('note_repository');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');
    repository = NoteRepositoryImpl(() => dbService.database);

    await seedBook(db, bookUuid: 'book-a');
    await seedRecord(
      db,
      recordUuid: 'record-a1',
      name: 'Alice',
      recordNumber: '001',
    );
    await seedRecord(
      db,
      recordUuid: 'record-a2',
      name: 'Bob',
      recordNumber: '002',
    );
    await seedEvent(
      db,
      event: makeEvent(
        id: 'event-a1',
        bookUuid: 'book-a',
        recordUuid: 'record-a1',
        recordNumber: '001',
      ),
    );
    await seedEvent(
      db,
      event: makeEvent(
        id: 'event-a2',
        bookUuid: 'book-a',
        recordUuid: 'record-a1',
        recordNumber: '001',
        startTime: DateTime.utc(2026, 1, 2, 11),
      ),
    );
    await seedEvent(
      db,
      event: makeEvent(
        id: 'event-b1',
        bookUuid: 'book-a',
        recordUuid: 'record-a2',
        recordNumber: '002',
      ),
    );
  });

  tearDown(() async {
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  test(
    'NOTE-UNIT-001: getCached() resolves note by event record_uuid',
    () async {
      // Arrange
      final note = makeNote(recordUuid: 'record-a1');
      await repository.saveToCache(note);

      // Act
      final cachedForFirstEvent = await repository.getCached('event-a1');
      final cachedForSecondEvent = await repository.getCached('event-a2');
      final cachedMissing = await repository.getCached('event-missing');

      // Assert
      expect(cachedForFirstEvent, isNotNull);
      expect(cachedForSecondEvent, isNotNull);
      expect(cachedForFirstEvent!.recordUuid, 'record-a1');
      expect(cachedForSecondEvent!.recordUuid, 'record-a1');
      expect(cachedMissing, isNull);
    },
  );

  test(
    'NOTE-UNIT-002: saveToCache() inserts then updates note with incremented version',
    () async {
      // Arrange
      final initial = makeNote(recordUuid: 'record-a1', version: 1);

      // Act
      await repository.saveToCache(initial);
      final firstSaved = await repository.getCached('event-a1');

      final updatedInput = initial.copyWith(
        pages: [
          ...initial.pages,
          [
            const Stroke(
              id: 'stroke-2',
              eventUuid: 'event-a1',
              points: [StrokePoint(5, 5), StrokePoint(8, 8)],
            ),
          ],
        ],
        version: firstSaved!.version,
        updatedAt: DateTime.utc(2026, 1, 3),
      );
      await repository.saveToCache(updatedInput);
      final secondSaved = await repository.getCached('event-a1');

      // Assert
      expect(firstSaved.version, 2);
      expect(secondSaved, isNotNull);
      expect(secondSaved!.version, 3);
      expect(secondSaved.pages.length, 2);
    },
  );

  test(
    'NOTE-UNIT-003: deleteCache() removes note by event record_uuid',
    () async {
      // Arrange
      await repository.saveToCache(makeNote(recordUuid: 'record-a1'));
      await repository.saveToCache(makeNote(recordUuid: 'record-a2'));

      // Act
      await repository.deleteCache('event-a1');
      final deleted = await repository.getCached('event-a1');
      final untouched = await repository.getCached('event-b1');

      // Assert
      expect(deleted, isNull);
      expect(untouched, isNotNull);
      expect(untouched!.recordUuid, 'record-a2');
    },
  );

  test(
    'NOTE-UNIT-004: getAllCachedForBook() returns distinct notes per record',
    () async {
      // Arrange
      await repository.saveToCache(makeNote(recordUuid: 'record-a1'));
      await repository.saveToCache(makeNote(recordUuid: 'record-a2'));

      // Act
      final notes = await repository.getAllCachedForBook('book-a');

      // Assert
      expect(notes.length, 2);
      expect(notes.map((n) => n.recordUuid).toSet(), {
        'record-a1',
        'record-a2',
      });
    },
  );

  test(
    'NOTE-UNIT-005: batchSaveCachedNotes()/batchGetCachedNotes() round-trip notes by record UUID',
    () async {
      // Arrange
      final noteMap = <String, Note>{
        'record-a1': makeNote(recordUuid: 'record-a1'),
        'record-a2': makeNote(recordUuid: 'record-a2'),
      };

      // Act
      await repository.batchSaveCachedNotes(noteMap);
      final loaded = await repository.batchGetCachedNotes([
        'record-a1',
        'record-a2',
        'record-missing',
      ]);

      // Assert
      expect(loaded.length, 2);
      expect(loaded.keys.toSet(), {'record-a1', 'record-a2'});
    },
  );

  test(
    'NOTE-UNIT-006: applyServerChange() inserts missing note and updates existing note',
    () async {
      // Arrange
      final serverInsert = makeNote(recordUuid: 'record-a1').toMap();
      serverInsert['record_uuid'] = 'record-a1';
      serverInsert['version'] = 5;
      serverInsert['pages_data'] = makeNote(
        recordUuid: 'record-a1',
      ).toMap()['pages_data'];

      // Act
      await repository.applyServerChange(serverInsert);
      final inserted = await repository.getCached('event-a1');

      final serverUpdate = Map<String, dynamic>.from(serverInsert);
      serverUpdate['version'] = 6;
      serverUpdate['pages_data'] = makeNote(
        recordUuid: 'record-a1',
        pages: [makeStrokePage(), makeStrokePage()],
      ).toMap()['pages_data'];
      await repository.applyServerChange(serverUpdate);
      final updated = await repository.getCached('event-a1');

      // Assert
      expect(inserted, isNotNull);
      expect(inserted!.version, 5);
      expect(updated, isNotNull);
      expect(updated!.version, 6);
      expect(updated.pages.length, 2);
    },
  );
}
