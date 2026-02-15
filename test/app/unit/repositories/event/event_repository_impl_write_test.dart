@Tags(['event', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/repositories/event_repository_impl.dart';
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
  late EventRepositoryImpl repository;
  late NoteRepositoryImpl noteRepository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('event_repository_write');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');
    repository = EventRepositoryImpl(() => dbService.database);
    noteRepository = NoteRepositoryImpl(() => dbService.database);

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
    await seedRecord(
      db,
      recordUuid: 'record-empty-1',
      name: 'WalkIn',
      recordNumber: '',
    );
  });

  tearDown(() async {
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  test(
    'EVENT-UNIT-004: create() writes event with version=1 and timestamps updated to now',
    () async {
      // Arrange
      final before = DateTime.now().toUtc().subtract(
        const Duration(seconds: 1),
      );
      final input = makeEvent(
        id: 'event-create-1',
        bookUuid: 'book-a',
        recordUuid: 'record-a1',
        eventTypes: [EventType.followUp],
        createdAt: DateTime.utc(2000, 1, 1),
        updatedAt: DateTime.utc(2000, 1, 1),
        version: 99,
      );

      // Act
      final created = await repository.create(input);
      final row = await db.query(
        'events',
        where: 'id = ?',
        whereArgs: ['event-create-1'],
        limit: 1,
      );

      // Assert
      expect(created.version, 1);
      expect(created.createdAt.isAfter(before), isTrue);
      expect(created.updatedAt.isAfter(before), isTrue);
      expect(row.length, 1);
    },
  );

  test(
    'EVENT-UNIT-005: update() increments version and persists changes',
    () async {
      // Arrange
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-update-1',
          bookUuid: 'book-a',
          recordUuid: 'record-a1',
          title: 'Old Title',
          version: 3,
        ),
      );
      final existing = (await repository.getById('event-update-1'))!;
      final updatedInput = existing.copyWith(title: 'New Title');

      // Act
      final updated = await repository.update(updatedInput);
      final persisted = await repository.getById('event-update-1');

      // Assert
      expect(updated.version, 4);
      expect(persisted, isNotNull);
      expect(persisted!.title, 'New Title');
      expect(persisted.version, 4);
    },
  );

  test('EVENT-UNIT-005: update() rejects null ID', () async {
    // Arrange
    final missingIdEvent = Event(
      id: null,
      bookUuid: 'book-a',
      recordUuid: 'record-a1',
      title: 'No ID Event',
      recordNumber: '001',
      eventTypes: const [EventType.consultation],
      startTime: DateTime.utc(2026, 1, 1, 9),
      endTime: DateTime.utc(2026, 1, 1, 10),
      createdAt: DateTime.utc(2026, 1, 1, 8),
      updatedAt: DateTime.utc(2026, 1, 1, 8),
    ).copyWith(id: null);

    // Act
    final action = () => repository.update(missingIdEvent);

    // Assert
    await expectLater(action, throwsA(isA<ArgumentError>()));
  });

  test(
    'EVENT-UNIT-006: delete() removes event and throws for missing ID',
    () async {
      // Arrange
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-delete-1',
          bookUuid: 'book-a',
          recordUuid: 'record-a1',
        ),
      );

      // Act
      await repository.delete('event-delete-1');
      final deleted = await repository.getById('event-delete-1');
      final secondDelete = () => repository.delete('event-delete-1');

      // Assert
      expect(deleted, isNull);
      await expectLater(
        secondDelete,
        throwsA(
          predicate((error) => error.toString().contains('Event not found')),
        ),
      );
    },
  );

  test(
    'EVENT-UNIT-007: removeEvent() soft removes with trimmed reason',
    () async {
      // Arrange
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-remove-1',
          bookUuid: 'book-a',
          recordUuid: 'record-a1',
          isRemoved: false,
        ),
      );

      // Act
      final removed = await repository.removeEvent(
        'event-remove-1',
        '  moved to another slot  ',
      );

      // Assert
      expect(removed.isRemoved, isTrue);
      expect(removed.removalReason, 'moved to another slot');
    },
  );

  test('EVENT-UNIT-007: removeEvent() rejects empty reason', () async {
    // Arrange
    await seedEvent(
      db,
      event: makeEvent(
        id: 'event-remove-2',
        bookUuid: 'book-a',
        recordUuid: 'record-a1',
      ),
    );

    // Act
    final action = () => repository.removeEvent('event-remove-2', '   ');

    // Assert
    await expectLater(action, throwsA(isA<ArgumentError>()));
  });

  test(
    'EVENT-UNIT-008: changeEventTime() creates new event and links old/new IDs',
    () async {
      // Arrange
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-time-1',
          bookUuid: 'book-a',
          recordUuid: 'record-a2',
          startTime: DateTime.utc(2026, 1, 3, 9),
          endTime: DateTime.utc(2026, 1, 3, 10),
        ),
      );
      final original = (await repository.getById('event-time-1'))!;
      final newStart = DateTime.utc(2026, 1, 3, 11);
      final newEnd = DateTime.utc(2026, 1, 3, 12);

      // Act
      final result = await repository.changeEventTime(
        original,
        newStart,
        newEnd,
        'rescheduled',
      );
      final oldPersisted = await repository.getById('event-time-1');
      final newPersisted = await repository.getById(result.newEvent.id!);

      // Assert
      expect(result.oldEvent.isRemoved, isTrue);
      expect(result.oldEvent.newEventId, isNotNull);
      expect(result.newEvent.originalEventId, 'event-time-1');
      expect(oldPersisted!.newEventId, result.newEvent.id);
      expect(newPersisted!.startTime.toUtc().hour, 11);
      expect(newPersisted.endTime!.toUtc().hour, 12);
    },
  );

  test(
    'EVENT-UNIT-009: no-record-number event keeps shared note across reschedule old/new events',
    () async {
      // Arrange: event with empty record_number and note saved by its record_uuid
      await seedEvent(
        db,
        event: makeEvent(
          id: 'event-no-rn-1',
          bookUuid: 'book-a',
          recordUuid: 'record-empty-1',
          title: 'WalkIn',
          recordNumber: '',
          startTime: DateTime.utc(2026, 1, 4, 9),
          endTime: DateTime.utc(2026, 1, 4, 10),
        ),
      );
      await noteRepository.saveToCache(makeNote(recordUuid: 'record-empty-1'));

      final original = (await repository.getById('event-no-rn-1'))!;

      // Act: reschedule event
      final result = await repository.changeEventTime(
        original,
        DateTime.utc(2026, 1, 4, 11),
        DateTime.utc(2026, 1, 4, 12),
        'rescheduled',
      );

      final oldPersisted = await repository.getById('event-no-rn-1');
      final newPersisted = await repository.getById(result.newEvent.id!);
      final oldEventNote = await noteRepository.getCached('event-no-rn-1');
      final newEventNote = await noteRepository.getCached(result.newEvent.id!);

      // Assert: old/new events still resolve the same shared note
      expect(oldPersisted, isNotNull);
      expect(newPersisted, isNotNull);
      expect(oldPersisted!.recordNumber, isEmpty);
      expect(newPersisted!.recordNumber, isEmpty);
      expect(oldPersisted.recordUuid, 'record-empty-1');
      expect(newPersisted.recordUuid, 'record-empty-1');
      expect(oldEventNote, isNotNull);
      expect(newEventNote, isNotNull);
      expect(oldEventNote!.recordUuid, 'record-empty-1');
      expect(newEventNote!.recordUuid, 'record-empty-1');
    },
  );
}
