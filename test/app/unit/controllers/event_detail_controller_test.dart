@Tags(['event', 'unit'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/charge_item.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/screens/event_detail/adapters/note_sync_adapter.dart';
import 'package:schedule_note_app/screens/event_detail/event_detail_controller.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/content_service.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/db_seed.dart';
import '../../support/fixtures/event_fixtures.dart';
import '../../support/fixtures/note_fixtures.dart';
import '../../support/test_db_path.dart';

class _FakeEventMetadataApiClient extends ApiClient {
  _FakeEventMetadataApiClient() : super(baseUrl: 'http://fake.local');

  int updateEventCalls = 0;
  int createEventCalls = 0;
  int updateRecordCalls = 0;

  String? lastUpdateBookUuid;
  String? lastUpdateEventId;
  Map<String, dynamic>? lastEventData;
  String? forcedServerRecordUuid;
  Map<String, dynamic>? fetchEventResponse;
  String? lastCreateBookUuid;
  Map<String, dynamic>? lastCreateEventData;
  String? lastEventDeviceId;
  String? lastEventDeviceToken;

  String? lastRecordUuid;
  Map<String, dynamic>? lastRecordData;
  String? lastRecordDeviceId;
  String? lastRecordDeviceToken;
  Object? updateEventError;
  Object? updateRecordError;
  String? requiredRecordUuidForUpdate;
  bool failUpdateEventWithNotFound = false;

  @override
  Future<Map<String, dynamic>> createEvent({
    required String bookUuid,
    required Map<String, dynamic> eventData,
    required String deviceId,
    required String deviceToken,
  }) async {
    createEventCalls += 1;
    lastCreateBookUuid = bookUuid;
    lastCreateEventData = Map<String, dynamic>.from(eventData);
    lastEventDeviceId = deviceId;
    lastEventDeviceToken = deviceToken;
    return {'id': eventData['id'] ?? 'created-event-id', ...eventData};
  }

  @override
  Future<Map<String, dynamic>> updateEvent({
    required String bookUuid,
    required String eventId,
    required Map<String, dynamic> eventData,
    required String deviceId,
    required String deviceToken,
  }) async {
    updateEventCalls += 1;
    if (failUpdateEventWithNotFound) {
      throw ApiException('Event not found', statusCode: 404);
    }
    if (updateEventError != null) throw updateEventError!;
    lastUpdateBookUuid = bookUuid;
    lastUpdateEventId = eventId;
    lastEventData = Map<String, dynamic>.from(eventData);
    lastEventDeviceId = deviceId;
    lastEventDeviceToken = deviceToken;
    return {
      'id': eventId,
      ...eventData,
      if (forcedServerRecordUuid != null) 'record_uuid': forcedServerRecordUuid,
    };
  }

  @override
  Future<Map<String, dynamic>?> fetchEvent({
    required String bookUuid,
    required String eventId,
    required String deviceId,
    required String deviceToken,
  }) async {
    if (fetchEventResponse != null) {
      return Map<String, dynamic>.from(fetchEventResponse!);
    }
    return {
      'id': eventId,
      if (forcedServerRecordUuid != null) 'record_uuid': forcedServerRecordUuid,
    };
  }

  @override
  Future<Map<String, dynamic>> updateRecord({
    required String recordUuid,
    required Map<String, dynamic> recordData,
    required String deviceId,
    required String deviceToken,
  }) async {
    updateRecordCalls += 1;
    if (requiredRecordUuidForUpdate != null &&
        recordUuid != requiredRecordUuidForUpdate) {
      throw ApiException('Record conflict', statusCode: 409);
    }
    if (updateRecordError != null) throw updateRecordError!;
    lastRecordUuid = recordUuid;
    lastRecordData = Map<String, dynamic>.from(recordData);
    lastRecordDeviceId = deviceId;
    lastRecordDeviceToken = deviceToken;
    return {'record_uuid': recordUuid, ...recordData};
  }
}

class _FakeNoteSyncAdapter extends NoteSyncAdapter {
  _FakeNoteSyncAdapter(super.contentService);

  int saveCalls = 0;
  int getNoteCalls = 0;
  int getNoteByRecordUuidCalls = 0;
  Note? existingNote;
  final Map<String, Note?> notesByEventId = {};
  final Map<String, Note?> notesByRecordUuid = {};
  Note? noteByRecordUuid;
  Note? saveResponse;
  int conflictResponsesRemaining = 0;
  int conflictServerVersion = 1;
  String? lastSaveEventId;
  String? lastGetNoteEventId;
  String? lastGetRecordBookUuid;
  String? lastGetRecordUuid;
  Note? lastSavedNote;
  final List<Note> savedNotes = [];
  Object? saveError;

  @override
  Future<Note?> getNote(String eventId, {bool forceRefresh = false}) async {
    getNoteCalls += 1;
    lastGetNoteEventId = eventId;
    if (notesByEventId.containsKey(eventId)) {
      return notesByEventId[eventId];
    }
    return existingNote;
  }

  @override
  Future<Note?> getNoteByRecordUuid(String bookUuid, String recordUuid) async {
    getNoteByRecordUuidCalls += 1;
    lastGetRecordBookUuid = bookUuid;
    lastGetRecordUuid = recordUuid;
    if (notesByRecordUuid.containsKey(recordUuid)) {
      return notesByRecordUuid[recordUuid];
    }
    return noteByRecordUuid ?? existingNote;
  }

  @override
  Future<Note> saveNote(String eventId, Note note) async {
    saveCalls += 1;
    lastSaveEventId = eventId;
    lastSavedNote = note;
    savedNotes.add(note);
    if (conflictResponsesRemaining > 0) {
      conflictResponsesRemaining -= 1;
      throw ApiConflictException(
        'Note version conflict',
        statusCode: 409,
        responseBody: jsonEncode({
          'error': 'VERSION_CONFLICT',
          'serverVersion': conflictServerVersion,
          'message':
              'Note version conflict. Please pull the latest note and retry.',
        }),
      );
    }
    if (saveError != null) throw saveError!;
    return saveResponse ?? note;
  }
}

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  late Event seededEvent;
  late _FakeEventMetadataApiClient fakeApiClient;
  late ContentService fakeContentService;
  late _FakeNoteSyncAdapter fakeNoteSyncAdapter;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('event_detail_controller');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');

    await seedBook(db, bookUuid: 'book-a');
    await seedRecord(
      db,
      recordUuid: 'record-a1',
      name: 'Alice',
      recordNumber: '001',
    );

    seededEvent = makeEvent(
      id: 'event-a1',
      bookUuid: 'book-a',
      recordUuid: 'record-a1',
      title: 'Alice',
      recordNumber: '001',
      eventTypes: const [EventType.consultation],
    );
    await seedEvent(db, event: seededEvent);

    fakeApiClient = _FakeEventMetadataApiClient();
    fakeContentService = ContentService(fakeApiClient, dbService);
    fakeNoteSyncAdapter = _FakeNoteSyncAdapter(fakeContentService);
  });

  tearDown(() async {
    fakeApiClient.dispose();
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  EventDetailController buildExistingController(Event event) {
    return EventDetailController(
      event: event,
      isNew: false,
      dbService: dbService,
      onStateChanged: (_) {},
      contentService: fakeContentService,
      noteSyncAdapter: fakeNoteSyncAdapter,
    );
  }

  EventDetailController buildController() {
    return buildExistingController(seededEvent);
  }

  EventDetailController buildNewController(Event event) {
    return EventDetailController(
      event: event,
      isNew: true,
      dbService: dbService,
      onStateChanged: (_) {},
      contentService: fakeContentService,
      noteSyncAdapter: fakeNoteSyncAdapter,
    );
  }

  test(
    'EVENT-DETAIL-UNIT-001: saveEvent() syncs event and record metadata to server',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      final controller = buildController();
      controller.updatePhone('0900000000');
      controller.updateEventTypes(const [
        EventType.surgery,
        EventType.followUp,
      ]);

      await controller.saveEvent();

      expect(fakeNoteSyncAdapter.saveCalls, 0);
      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 1);

      expect(fakeApiClient.lastUpdateBookUuid, 'book-a');
      expect(fakeApiClient.lastUpdateEventId, 'event-a1');
      expect(fakeApiClient.lastEventDeviceId, 'device-001');
      expect(fakeApiClient.lastEventDeviceToken, 'token-001');

      expect(fakeApiClient.lastRecordUuid, 'record-a1');
      expect(fakeApiClient.lastRecordData?['name'], 'Alice');
      expect(fakeApiClient.lastRecordData?['record_number'], '001');
      expect(fakeApiClient.lastRecordData?['phone'], '0900000000');
      expect(fakeApiClient.lastRecordDeviceId, 'device-001');
      expect(fakeApiClient.lastRecordDeviceToken, 'token-001');

      final eventTypes =
          (fakeApiClient.lastEventData?['eventTypes'] as List<dynamic>)
              .cast<String>();
      expect(eventTypes, containsAll(['followUp', 'surgery']));
      expect(fakeApiClient.lastEventData?['phone'], '0900000000');
      expect(fakeApiClient.lastEventData, isNot(contains('has_note')));
      expect(fakeApiClient.lastEventData, isNot(contains('hasNote')));
    },
  );

  test(
    'EVENT-DETAIL-UNIT-002: saveEvent() throws when metadata sync has no device credentials',
    () async {
      final controller = buildController();
      controller.updatePhone('0911222333');
      controller.updateEventTypes(const [EventType.emergency]);

      await expectLater(
        controller.saveEvent,
        throwsA(
          predicate(
            (error) => error.toString().contains('Device not registered'),
          ),
        ),
      );

      expect(fakeApiClient.updateEventCalls, 0);
      expect(fakeApiClient.updateRecordCalls, 0);
    },
  );

  test(
    'EVENT-FLOW-001: saveEvent() follows app trigger -> server -> return -> local/state update',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      fakeNoteSyncAdapter.saveResponse = makeNote(
        recordUuid: 'record-a1',
        version: 7,
      );

      final controller = buildController();
      controller.updatePhone('0955667788');
      controller.updateEventTypes(const [EventType.followUp]);
      controller.updatePages([
        const [
          Stroke(
            id: 'stroke-event-a1',
            eventUuid: 'event-a1',
            points: [StrokePoint(10, 10), StrokePoint(20, 20)],
          ),
        ],
      ]);

      await controller.saveEvent();

      expect(fakeNoteSyncAdapter.saveCalls, 1);
      expect(fakeNoteSyncAdapter.lastSaveEventId, 'event-a1');
      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 1);

      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.recordUuid, 'record-a1');
      expect(controller.state.note!.version, 7);
      expect(controller.state.lastKnownPages, isNotEmpty);
      expect(controller.state.hasChanges, isFalse);
      expect(controller.state.hasUnsyncedChanges, isFalse);
      expect(controller.state.isOffline, isFalse);

      final persistedEvent = await dbService.getEventById('event-a1');
      expect(persistedEvent, isNotNull);
      expect(persistedEvent!.eventTypes, const [EventType.followUp]);

      final recordRows = await db.query(
        'records',
        columns: ['phone'],
        where: 'record_uuid = ?',
        whereArgs: ['record-a1'],
        limit: 1,
      );
      expect(recordRows.single['phone'], '0955667788');
    },
  );

  test(
    'EVENT-FLOW-002: saveEvent() marks state offline when metadata sync fails after trigger',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      fakeApiClient.updateEventError = ApiException(
        'Server unavailable',
        statusCode: 503,
      );

      final controller = buildController();
      controller.updatePhone('0900001234');
      controller.updateEventTypes(const [EventType.emergency]);

      await expectLater(controller.saveEvent, throwsA(isA<ApiException>()));

      expect(fakeNoteSyncAdapter.saveCalls, 0);
      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 0);
      expect(controller.state.isOffline, isTrue);
      expect(controller.state.isLoading, isFalse);

      final persistedEvent = await dbService.getEventById('event-a1');
      expect(persistedEvent, isNotNull);
      expect(persistedEvent!.eventTypes, const [EventType.emergency]);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-005: new event loading existing note does not save note when untouched',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      fakeNoteSyncAdapter.noteByRecordUuid = makeNote(recordUuid: 'record-a1');

      final newEvent = makeEvent(
        id: 'event-new-1',
        bookUuid: 'book-a',
        recordUuid: '',
        title: 'Alice',
        recordNumber: '001',
        eventTypes: const [EventType.consultation],
      );
      final controller = buildNewController(newEvent);
      controller.updateName('Alice');
      controller.updateRecordNumber('001');

      await controller.saveEvent();

      expect(fakeNoteSyncAdapter.getNoteByRecordUuidCalls, 1);
      expect(fakeNoteSyncAdapter.saveCalls, 0);
      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 1);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-006: saveEvent() refill record number reuses existing record UUID',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      await seedRecord(
        db,
        recordUuid: 'record-empty-refill',
        name: 'alice',
        recordNumber: '',
      );
      final refillEvent = makeEvent(
        id: 'event-refill-1',
        bookUuid: 'book-a',
        recordUuid: 'record-empty-refill',
        title: 'alice',
        recordNumber: '',
        eventTypes: const [EventType.consultation],
      );
      await seedEvent(db, event: refillEvent);

      fakeApiClient.requiredRecordUuidForUpdate = 'record-a1';

      final controller = buildExistingController(refillEvent);
      controller.updateRecordNumber('001');

      await controller.saveEvent();

      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 1);
      expect(fakeApiClient.lastRecordUuid, 'record-a1');
      expect(fakeApiClient.lastRecordData?['record_number'], '001');

      final persisted = await dbService.getEventById('event-refill-1');
      expect(persisted, isNotNull);
      expect(persisted!.recordUuid, 'record-a1');
      expect(persisted.recordNumber, '001');
    },
  );

  test(
    'EVENT-DETAIL-UNIT-007: saveEvent() keeps existing handwriting when relinking from empty record number',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      await seedRecord(
        db,
        recordUuid: 'record-empty-note',
        name: 'WalkIn',
        recordNumber: '',
      );
      final noRecordEvent = makeEvent(
        id: 'event-refill-note-1',
        bookUuid: 'book-a',
        recordUuid: 'record-empty-note',
        title: 'WalkIn',
        recordNumber: '',
        eventTypes: const [EventType.consultation],
      );
      await seedEvent(db, event: noRecordEvent);

      fakeNoteSyncAdapter.notesByRecordUuid['record-empty-note'] = makeNote(
        recordUuid: 'record-empty-note',
        version: 3,
      );
      fakeNoteSyncAdapter.notesByRecordUuid['record-a1'] = Note(
        recordUuid: 'record-a1',
        pages: const [
          [
            Stroke(
              id: 'server-stroke-a1',
              eventUuid: 'event-server-a1',
              points: [StrokePoint(1, 1), StrokePoint(2, 2)],
            ),
          ],
        ],
        createdAt: DateTime.utc(2026, 1, 1, 9),
        updatedAt: DateTime.utc(2026, 1, 1, 9),
        version: 1,
      );
      fakeNoteSyncAdapter.conflictResponsesRemaining = 1;
      fakeNoteSyncAdapter.conflictServerVersion = 1;
      fakeNoteSyncAdapter.saveResponse = makeNote(
        recordUuid: 'record-a1',
        pages: const [
          [
            Stroke(
              id: 'server-stroke-a1',
              eventUuid: 'event-server-a1',
              points: [StrokePoint(1, 1), StrokePoint(2, 2)],
            ),
            Stroke(
              id: 'stroke-1',
              eventUuid: 'event-1',
              points: [StrokePoint(10, 10), StrokePoint(20, 20)],
            ),
          ],
        ],
        version: 2,
      );

      final controller = buildExistingController(noRecordEvent);
      await controller.loadNote();
      controller.updateName('Alice');
      controller.updateRecordNumber('001');

      await controller.saveEvent();

      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 1);
      expect(fakeApiClient.lastRecordUuid, 'record-a1');
      expect(fakeNoteSyncAdapter.saveCalls, 2);
      expect(fakeNoteSyncAdapter.lastSaveEventId, 'event-refill-note-1');
      expect(fakeNoteSyncAdapter.savedNotes.first.version, 2);
      expect(fakeNoteSyncAdapter.savedNotes.last.version, 2);
      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.recordUuid, 'record-a1');
      expect(controller.state.note!.version, 2);
      final flattenedStrokeIds = controller.state.note!.pages
          .expand((page) => page)
          .map((stroke) => stroke.id)
          .whereType<String>()
          .toSet();
      expect(flattenedStrokeIds, contains('server-stroke-a1'));
      expect(flattenedStrokeIds, contains('stroke-1'));
      expect(controller.state.hasChanges, isFalse);

      final persisted = await dbService.getEventById('event-refill-note-1');
      expect(persisted, isNotNull);
      expect(persisted!.recordUuid, 'record-a1');
      expect(persisted.recordNumber, '001');
    },
  );

  test(
    'EVENT-DETAIL-UNIT-008: saveEvent() creates event on server when new event metadata patch returns 404',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      fakeApiClient.failUpdateEventWithNotFound = true;

      final newEvent = makeEvent(
        id: 'event-new-empty-record',
        bookUuid: 'book-a',
        recordUuid: '',
        title: 'WalkIn',
        recordNumber: '',
        eventTypes: const [EventType.consultation],
      );
      final controller = buildNewController(newEvent);
      controller.updateName('WalkIn');
      controller.updateRecordNumber('');

      await controller.saveEvent();

      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.createEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 1);
      expect(fakeApiClient.lastCreateBookUuid, 'book-a');
      expect(fakeApiClient.lastCreateEventData?['record_number'], '');
      expect(controller.state.isOffline, isFalse);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-009: saveEvent() uses server remapped record UUID when syncing record metadata',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      await seedRecord(
        db,
        recordUuid: 'record-empty-remap',
        name: 'WalkIn',
        recordNumber: '',
      );
      final remapEvent = makeEvent(
        id: 'event-remap-1',
        bookUuid: 'book-a',
        recordUuid: 'record-empty-remap',
        title: 'WalkIn',
        recordNumber: '',
        eventTypes: const [EventType.consultation],
      );
      await seedEvent(db, event: remapEvent);

      fakeApiClient.forcedServerRecordUuid = 'record-server-remap-1';
      fakeApiClient.requiredRecordUuidForUpdate = 'record-server-remap-1';

      final controller = buildExistingController(remapEvent);
      controller.updateName('Remap User');
      controller.updateRecordNumber('NEW-001');

      await controller.saveEvent();

      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 1);
      expect(fakeApiClient.lastRecordUuid, 'record-server-remap-1');

      final persisted = await dbService.getEventById('event-remap-1');
      expect(persisted, isNotNull);
      expect(persisted!.recordUuid, isNotEmpty);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-010: create without record number then reenter and fill record number keeps note and updates event linkage',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      final newEvent = makeEvent(
        id: 'event-create-reenter-1',
        bookUuid: 'book-a',
        recordUuid: '',
        title: 'WalkIn',
        recordNumber: '',
        eventTypes: const [EventType.consultation],
      );

      final createController = buildNewController(newEvent);
      createController.updateName('WalkIn');
      createController.updateRecordNumber('');
      createController.updatePages([
        const [
          Stroke(
            id: 'stroke-create-reenter-1',
            eventUuid: 'event-create-reenter-1',
            points: [StrokePoint(5, 5), StrokePoint(15, 15)],
          ),
        ],
      ]);

      final createdEvent = await createController.saveEvent();
      expect(createdEvent.id, 'event-create-reenter-1');
      expect(createdEvent.recordNumber, isEmpty);
      expect(createdEvent.recordUuid, isNotEmpty);
      expect(fakeNoteSyncAdapter.saveCalls, 1);
      expect(fakeNoteSyncAdapter.lastSavedNote, isNotNull);
      final createdNote = fakeNoteSyncAdapter.lastSavedNote!;
      final createdStrokeEventUuids = createdNote.pages
          .expand((page) => page)
          .map((stroke) => stroke.eventUuid)
          .whereType<String>()
          .toSet();
      expect(createdStrokeEventUuids, contains(createdEvent.id));
      fakeNoteSyncAdapter.notesByRecordUuid[createdEvent.recordUuid] =
          createdNote;

      fakeApiClient.requiredRecordUuidForUpdate = 'record-a1';
      fakeNoteSyncAdapter.notesByRecordUuid['record-a1'] = null;

      final reopenController = buildExistingController(createdEvent);
      await reopenController.loadNote();
      expect(reopenController.state.note, isNotNull);
      final reopenStrokeIds = reopenController.state.note!.pages
          .expand((page) => page)
          .map((stroke) => stroke.id)
          .whereType<String>()
          .toSet();
      expect(reopenStrokeIds, contains('stroke-create-reenter-1'));

      reopenController.updateName('Alice');
      reopenController.updateRecordNumber('001');
      final updatedEvent = await reopenController.saveEvent();

      expect(updatedEvent.recordNumber, '001');
      expect(updatedEvent.recordUuid, 'record-a1');
      expect(fakeApiClient.updateRecordCalls, greaterThanOrEqualTo(2));
      expect(fakeApiClient.lastRecordUuid, 'record-a1');
      expect(fakeNoteSyncAdapter.saveCalls, greaterThanOrEqualTo(2));
      expect(reopenController.state.note, isNotNull);
      final updatedStrokeIds = reopenController.state.note!.pages
          .expand((page) => page)
          .map((stroke) => stroke.id)
          .whereType<String>()
          .toSet();
      expect(updatedStrokeIds, contains('stroke-create-reenter-1'));

      final persisted = await dbService.getEventById(createdEvent.id!);
      expect(persisted, isNotNull);
      expect(persisted!.recordNumber, '001');
      expect(persisted.recordUuid, 'record-a1');
    },
  );

  test(
    'EVENT-DETAIL-UNIT-003: loadNote() fetches note by record UUID',
    () async {
      fakeNoteSyncAdapter.noteByRecordUuid = makeNote(
        recordUuid: 'record-a1',
        version: 5,
      );

      final controller = buildController();
      await controller.loadNote();

      expect(fakeNoteSyncAdapter.getNoteCalls, 0);
      expect(fakeNoteSyncAdapter.getNoteByRecordUuidCalls, 1);
      expect(fakeNoteSyncAdapter.lastGetRecordBookUuid, 'book-a');
      expect(fakeNoteSyncAdapter.lastGetRecordUuid, 'record-a1');
      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.recordUuid, 'record-a1');
      expect(controller.state.note!.version, 5);
      expect(controller.state.isLoadingFromServer, isFalse);
      expect(controller.state.isOffline, isFalse);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-004: loadNote() keeps empty state when record note does not exist',
    () async {
      fakeNoteSyncAdapter.noteByRecordUuid = null;

      final controller = buildController();
      await controller.loadNote();

      expect(fakeNoteSyncAdapter.getNoteCalls, 0);
      expect(fakeNoteSyncAdapter.getNoteByRecordUuidCalls, 1);
      expect(controller.state.note, isNull);
      expect(controller.state.isLoadingFromServer, isFalse);
      expect(controller.state.isOffline, isFalse);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-013: refreshNoteFromServerInBackground() replaces stale local note with incoming server update',
    () async {
      fakeNoteSyncAdapter.noteByRecordUuid = makeNote(
        recordUuid: 'record-a1',
        version: 1,
      );
      final controller = buildController();
      await controller.loadNote();

      controller.updatePages([
        const [
          Stroke(
            id: 'local-stroke-1',
            eventUuid: 'event-a1',
            points: [StrokePoint(2, 2), StrokePoint(6, 6)],
          ),
        ],
      ]);

      fakeNoteSyncAdapter.noteByRecordUuid = makeNote(
        recordUuid: 'record-a1',
        version: 3,
        pages: const [
          [
            Stroke(
              id: 'server-stroke-3',
              eventUuid: 'event-server',
              points: [StrokePoint(10, 10), StrokePoint(20, 20)],
            ),
          ],
        ],
      );

      final applied = await controller.refreshNoteFromServerInBackground();

      expect(applied, isTrue);
      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.version, 3);
      final strokeIds = controller.state.lastKnownPages
          .expand((page) => page)
          .map((stroke) => stroke.id)
          .whereType<String>()
          .toSet();
      expect(strokeIds, contains('server-stroke-3'));
      expect(strokeIds, isNot(contains('local-stroke-1')));
    },
  );

  test(
    'EVENT-DETAIL-UNIT-014: saveEvent(isAutoSave=true) discards stale local note when server version is newer',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      fakeNoteSyncAdapter.noteByRecordUuid = makeNote(
        recordUuid: 'record-a1',
        version: 1,
      );
      final controller = buildController();
      await controller.loadNote();

      controller.updatePages([
        const [
          Stroke(
            id: 'local-unsaved-stroke',
            eventUuid: 'event-a1',
            points: [StrokePoint(3, 3), StrokePoint(7, 7)],
          ),
        ],
      ]);

      fakeNoteSyncAdapter.noteByRecordUuid = makeNote(
        recordUuid: 'record-a1',
        version: 5,
        pages: const [
          [
            Stroke(
              id: 'server-authoritative-stroke',
              eventUuid: 'event-server',
              points: [StrokePoint(10, 10), StrokePoint(20, 20)],
            ),
          ],
        ],
      );

      await controller.saveEvent(isAutoSave: true);

      expect(fakeNoteSyncAdapter.saveCalls, 0);
      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.version, 5);
      final finalStrokeIds = controller.state.lastKnownPages
          .expand((page) => page)
          .map((stroke) => stroke.id)
          .whereType<String>()
          .toSet();
      expect(finalStrokeIds, contains('server-authoritative-stroke'));
      expect(finalStrokeIds, isNot(contains('local-unsaved-stroke')));
    },
  );

  test(
    'EVENT-DETAIL-UNIT-015: auto-save conflict keeps server note without merge retry',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      fakeNoteSyncAdapter.noteByRecordUuid = makeNote(
        recordUuid: 'record-a1',
        version: 3,
        pages: const [
          [
            Stroke(
              id: 'server-v3-stroke',
              eventUuid: 'event-server-v3',
              points: [StrokePoint(10, 10), StrokePoint(15, 15)],
            ),
          ],
        ],
      );
      final controller = buildController();
      await controller.loadNote();

      controller.updatePages([
        const [
          Stroke(
            id: 'local-conflict-stroke',
            eventUuid: 'event-a1',
            points: [StrokePoint(1, 1), StrokePoint(2, 2)],
          ),
        ],
      ]);

      fakeNoteSyncAdapter.conflictResponsesRemaining = 1;
      fakeNoteSyncAdapter.conflictServerVersion = 3;
      fakeNoteSyncAdapter.notesByRecordUuid['record-a1'] = makeNote(
        recordUuid: 'record-a1',
        version: 3,
        pages: const [
          [
            Stroke(
              id: 'server-v3-stroke',
              eventUuid: 'event-server-v3',
              points: [StrokePoint(10, 10), StrokePoint(15, 15)],
            ),
          ],
        ],
      );

      await controller.saveEvent(isAutoSave: true);

      expect(fakeNoteSyncAdapter.saveCalls, 1);
      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.version, 3);
      final finalStrokeIds = controller.state.lastKnownPages
          .expand((page) => page)
          .map((stroke) => stroke.id)
          .whereType<String>()
          .toSet();
      expect(finalStrokeIds, contains('server-v3-stroke'));
      expect(finalStrokeIds, isNot(contains('local-conflict-stroke')));
    },
  );

  test(
    'EVENT-DETAIL-UNIT-011: addChargeItem() links new item to current event even when all-items filter is active',
    () async {
      final controller = buildController();
      expect(controller.state.showOnlyThisEventItems, isFalse);

      await controller.addChargeItem(
        ChargeItem(
          recordUuid: 'ignored-by-controller',
          itemName: 'X-Ray',
          itemPrice: 1200,
        ),
      );

      final savedItems = await dbService.getChargeItemsByRecordUuid(
        'record-a1',
      );
      expect(savedItems, hasLength(1));
      expect(savedItems.single.itemName, 'X-Ray');
      expect(savedItems.single.eventId, 'event-a1');

      await controller.toggleChargeItemsFilter();

      expect(controller.state.showOnlyThisEventItems, isTrue);
      expect(controller.state.chargeItems, hasLength(1));
      expect(controller.state.chargeItems.single.itemName, 'X-Ray');
      expect(controller.state.chargeItems.single.eventId, 'event-a1');
    },
  );

  test(
    'EVENT-DETAIL-UNIT-012: this-event focus mode keeps all items loaded for UI dilution behavior',
    () async {
      final otherEvent = makeEvent(
        id: 'event-a2',
        bookUuid: 'book-a',
        recordUuid: 'record-a1',
        title: 'Alice',
        recordNumber: '001',
        eventTypes: const [EventType.consultation],
      );
      await seedEvent(db, event: otherEvent);

      await dbService.saveChargeItem(
        ChargeItem(
          id: 'charge-this-event',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Current Event Item',
          itemPrice: 100,
        ),
      );
      await dbService.saveChargeItem(
        ChargeItem(
          id: 'charge-other-event',
          recordUuid: 'record-a1',
          eventId: 'event-a2',
          itemName: 'Other Event Item',
          itemPrice: 200,
        ),
      );

      final controller = buildController();
      await controller.loadChargeItems();
      expect(controller.state.chargeItems, hasLength(2));

      await controller.toggleChargeItemsFilter();

      expect(controller.state.showOnlyThisEventItems, isTrue);
      expect(controller.state.chargeItems, hasLength(2));
      expect(
        controller.state.chargeItems.map((item) => item.id),
        containsAll(<String>['charge-this-event', 'charge-other-event']),
      );
    },
  );
}
