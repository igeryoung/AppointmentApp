@Tags(['event', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/screens/event_detail/adapters/note_sync_adapter.dart';
import 'package:schedule_note_app/screens/event_detail/event_detail_controller.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/content_service.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/db_seed.dart';
import '../../support/fixtures/event_fixtures.dart';
import '../../support/fixtures/note_fixtures.dart';
import '../../support/test_db_path.dart';

class _FakeEventMetadataApiClient extends ApiClient {
  _FakeEventMetadataApiClient() : super(baseUrl: 'http://fake.local');

  int updateEventCalls = 0;
  int updateRecordCalls = 0;

  String? lastUpdateBookUuid;
  String? lastUpdateEventId;
  Map<String, dynamic>? lastEventData;
  String? lastEventDeviceId;
  String? lastEventDeviceToken;

  String? lastRecordUuid;
  Map<String, dynamic>? lastRecordData;
  String? lastRecordDeviceId;
  String? lastRecordDeviceToken;
  Object? updateEventError;
  Object? updateRecordError;

  @override
  Future<Map<String, dynamic>> updateEvent({
    required String bookUuid,
    required String eventId,
    required Map<String, dynamic> eventData,
    required String deviceId,
    required String deviceToken,
  }) async {
    updateEventCalls += 1;
    if (updateEventError != null) throw updateEventError!;
    lastUpdateBookUuid = bookUuid;
    lastUpdateEventId = eventId;
    lastEventData = Map<String, dynamic>.from(eventData);
    lastEventDeviceId = deviceId;
    lastEventDeviceToken = deviceToken;
    return {'id': eventId, ...eventData};
  }

  @override
  Future<Map<String, dynamic>> updateRecord({
    required String recordUuid,
    required Map<String, dynamic> recordData,
    required String deviceId,
    required String deviceToken,
  }) async {
    updateRecordCalls += 1;
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
  Note? noteByRecordUuid;
  Note? saveResponse;
  String? lastSaveEventId;
  String? lastGetNoteEventId;
  String? lastGetRecordBookUuid;
  String? lastGetRecordUuid;
  Note? lastSavedNote;
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
    return noteByRecordUuid ?? existingNote;
  }

  @override
  Future<Note> saveNote(String eventId, Note note) async {
    saveCalls += 1;
    lastSaveEventId = eventId;
    lastSavedNote = note;
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

  EventDetailController buildController() {
    return EventDetailController(
      event: seededEvent,
      isNew: false,
      dbService: dbService,
      onStateChanged: (_) {},
      contentService: fakeContentService,
      noteSyncAdapter: fakeNoteSyncAdapter,
    );
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
}
