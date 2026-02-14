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

  @override
  Future<Map<String, dynamic>> updateEvent({
    required String bookUuid,
    required String eventId,
    required Map<String, dynamic> eventData,
    required String deviceId,
    required String deviceToken,
  }) async {
    updateEventCalls += 1;
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
  Note? existingNote;

  @override
  Future<Note?> getNote(String eventId, {bool forceRefresh = false}) async {
    return existingNote;
  }

  @override
  Future<Note?> getNoteByRecordUuid(String bookUuid, String recordUuid) async {
    return existingNote;
  }

  @override
  Future<Note> saveNote(String eventId, Note note) async {
    saveCalls += 1;
    return note;
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

      expect(fakeNoteSyncAdapter.saveCalls, 1);
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
}
