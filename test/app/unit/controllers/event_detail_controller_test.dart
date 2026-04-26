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

List<ChargeItemPayment> _singlePaidItem(int amount, DateTime paidDate) {
  return [
    ChargeItemPayment(
      id: 'payment-$amount-${paidDate.millisecondsSinceEpoch}',
      amount: amount,
      paidDate: paidDate,
    ),
  ];
}

class _FakeEventMetadataApiClient extends ApiClient {
  _FakeEventMetadataApiClient() : super(baseUrl: 'http://fake.local');

  int updateEventCalls = 0;
  int updateEventDetailBundleCalls = 0;
  int createEventCalls = 0;
  int updateRecordCalls = 0;
  int getOrCreateRecordCalls = 0;
  int saveChargeItemCalls = 0;
  int deleteChargeItemCalls = 0;

  String? lastUpdateBookUuid;
  String? lastUpdateEventId;
  Map<String, dynamic>? lastEventData;
  String? forcedServerRecordUuid;
  Map<String, dynamic>? fetchEventResponse;
  Map<String, dynamic>? fetchEventDetailBundleResponse;
  String? lastCreateBookUuid;
  Map<String, dynamic>? lastCreateEventData;
  String? lastEventDeviceId;
  String? lastEventDeviceToken;

  String? lastRecordUuid;
  Map<String, dynamic>? lastRecordData;
  String? lastRecordDeviceId;
  String? lastRecordDeviceToken;
  Map<String, dynamic>? lastGetOrCreateRecordData;
  String? lastSaveChargeItemRecordUuid;
  Map<String, dynamic>? lastSaveChargeItemData;
  String? lastDeleteChargeItemId;
  String? lastDeleteChargeItemBookUuid;
  String? lastFetchedRecordNumber;
  String? lastFetchRecordDeviceId;
  String? lastFetchRecordDeviceToken;
  String? lastValidatedRecordNumber;
  String? lastValidatedName;
  String? lastValidateRecordDeviceId;
  String? lastValidateRecordDeviceToken;
  final Map<String, Map<String, dynamic>?> fetchRecordByNumberResponses = {};
  final Map<String, RecordValidationResult> validateRecordNumberResponses = {};
  Object? updateEventError;
  Object? updateEventDetailBundleError;
  Object? updateRecordError;
  Object? getOrCreateRecordError;
  Object? saveChargeItemError;
  Object? deleteChargeItemError;
  Object? validateRecordNumberError;
  Duration saveChargeItemDelay = Duration.zero;
  Duration deleteChargeItemDelay = Duration.zero;
  String? requiredRecordUuidForUpdate;
  bool failUpdateEventWithNotFound = false;
  final Map<String, String> recordUuidsByRecordNumber = {};
  int _generatedRecordCounter = 0;

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
  Future<Map<String, dynamic>?> fetchEventDetailBundle({
    required String bookUuid,
    required String eventId,
    required String deviceId,
    required String deviceToken,
  }) async {
    lastEventDeviceId = deviceId;
    lastEventDeviceToken = deviceToken;
    if (fetchEventDetailBundleResponse != null) {
      return Map<String, dynamic>.from(fetchEventDetailBundleResponse!);
    }
    final eventPayload = await fetchEvent(
      bookUuid: bookUuid,
      eventId: eventId,
      deviceId: deviceId,
      deviceToken: deviceToken,
    );
    return {
      'event': eventPayload,
      'record': {
        'record_uuid': forcedServerRecordUuid ?? 'record-a1',
        'record_number': '001',
        'name': 'Alice',
        'phone': null,
        'version': 1,
      },
      'note': null,
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

  @override
  Future<Map<String, dynamic>> updateEventDetailBundle({
    required String bookUuid,
    required String eventId,
    required Map<String, dynamic> eventData,
    required Map<String, dynamic> recordData,
    required String deviceId,
    required String deviceToken,
  }) async {
    updateEventDetailBundleCalls += 1;
    updateEventCalls += 1;
    if (updateEventDetailBundleError != null) {
      throw updateEventDetailBundleError!;
    }
    if (updateEventError != null) throw updateEventError!;
    lastUpdateBookUuid = bookUuid;
    lastUpdateEventId = eventId;
    lastEventData = Map<String, dynamic>.from(eventData);
    lastEventDeviceId = deviceId;
    lastEventDeviceToken = deviceToken;

    final recordUuid =
        forcedServerRecordUuid ??
        (eventData['record_uuid'] ?? eventData['recordUuid'])?.toString() ??
        'record-a1';
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

    return {
      'event': {'id': eventId, ...eventData, 'record_uuid': recordUuid},
      'record': {'record_uuid': recordUuid, ...recordData},
      'note': null,
    };
  }

  @override
  Future<Map<String, dynamic>> getOrCreateRecord({
    required String recordNumber,
    required String name,
    String? phone,
    required String deviceId,
    required String deviceToken,
  }) async {
    getOrCreateRecordCalls += 1;
    if (getOrCreateRecordError != null) throw getOrCreateRecordError!;
    lastGetOrCreateRecordData = {
      'record_number': recordNumber,
      'name': name,
      'phone': phone,
      'device_id': deviceId,
      'device_token': deviceToken,
    };
    final existed = recordUuidsByRecordNumber.containsKey(recordNumber);
    final recordUuid =
        recordUuidsByRecordNumber[recordNumber] ??
        'generated-record-${++_generatedRecordCounter}';
    if (recordNumber.isNotEmpty) {
      recordUuidsByRecordNumber[recordNumber] = recordUuid;
    }
    return {
      'record_uuid': recordUuid,
      'record_number': recordNumber,
      'name': name,
      'phone': phone,
      'created': !existed,
    };
  }

  @override
  Future<Map<String, dynamic>?> fetchRecordByNumber({
    required String recordNumber,
    required String deviceId,
    required String deviceToken,
  }) async {
    lastFetchedRecordNumber = recordNumber;
    lastFetchRecordDeviceId = deviceId;
    lastFetchRecordDeviceToken = deviceToken;
    final response = fetchRecordByNumberResponses[recordNumber];
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  @override
  Future<RecordValidationResult> validateRecordNumber({
    required String recordNumber,
    required String name,
    required String deviceId,
    required String deviceToken,
  }) async {
    lastValidatedRecordNumber = recordNumber;
    lastValidatedName = name;
    lastValidateRecordDeviceId = deviceId;
    lastValidateRecordDeviceToken = deviceToken;
    if (validateRecordNumberError != null) {
      throw validateRecordNumberError!;
    }
    return validateRecordNumberResponses['$recordNumber::$name'] ??
        RecordValidationResult(exists: false, valid: true);
  }

  @override
  Future<Map<String, dynamic>> saveChargeItem({
    required String recordUuid,
    required Map<String, dynamic> chargeItemData,
    required String deviceId,
    required String deviceToken,
  }) async {
    saveChargeItemCalls += 1;
    if (saveChargeItemError != null) throw saveChargeItemError!;
    if (saveChargeItemDelay > Duration.zero) {
      await Future<void>.delayed(saveChargeItemDelay);
    }
    lastSaveChargeItemRecordUuid = recordUuid;
    lastSaveChargeItemData = Map<String, dynamic>.from(chargeItemData);
    return {
      ...chargeItemData,
      'record_uuid': chargeItemData['recordUuid'] ?? recordUuid,
      'event_id': chargeItemData['eventId'],
      'item_name': chargeItemData['itemName'],
      'item_price': chargeItemData['itemPrice'],
      'received_amount': chargeItemData['receivedAmount'],
      'paidItems': chargeItemData['paidItems'] ?? const [],
      'paid_items_json': jsonEncode(chargeItemData['paidItems'] ?? const []),
      'is_deleted': chargeItemData['isDeleted'] == true,
      'is_dirty': 0,
      'version': chargeItemData['version'] ?? 1,
      'synced_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
  }

  @override
  Future<void> deleteChargeItem({
    required String chargeItemId,
    required String deviceId,
    required String deviceToken,
    String? bookUuid,
  }) async {
    deleteChargeItemCalls += 1;
    if (deleteChargeItemError != null) throw deleteChargeItemError!;
    if (deleteChargeItemDelay > Duration.zero) {
      await Future<void>.delayed(deleteChargeItemDelay);
    }
    lastDeleteChargeItemId = chargeItemId;
    lastDeleteChargeItemBookUuid = bookUuid;
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
    fakeApiClient.recordUuidsByRecordNumber['001'] = 'record-a1';
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

  Future<void> waitForBackgroundSync() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 10));
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
      await waitForBackgroundSync();

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
      expect(fakeApiClient.lastEventData, isNot(contains('has_charge_items')));
      expect(fakeApiClient.lastEventData, isNot(contains('hasChargeItems')));
      expect(fakeApiClient.lastEventData, isNot(contains('has_note')));
      expect(fakeApiClient.lastEventData, isNot(contains('hasNote')));
    },
  );

  test(
    'EVENT-DETAIL-UNIT-002: saveEvent() fails fast when device credentials are missing',
    () async {
      final controller = buildController();
      controller.updatePhone('0911222333');
      controller.updateEventTypes(const [EventType.emergency]);

      await expectLater(controller.saveEvent(), throwsException);
      expect(fakeApiClient.updateEventCalls, 0);
      expect(fakeApiClient.updateRecordCalls, 0);
      expect(controller.state.hasUnsyncedChanges, isTrue);
      expect(controller.state.isOffline, isTrue);
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
      await waitForBackgroundSync();

      expect(fakeNoteSyncAdapter.saveCalls, 1);
      expect(fakeNoteSyncAdapter.getNoteByRecordUuidCalls, 0);
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
    'EVENT-FLOW-002: saveEvent() throws and marks state offline when server metadata save fails',
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

      await expectLater(controller.saveEvent(), throwsA(isA<ApiException>()));
      expect(fakeNoteSyncAdapter.saveCalls, 0);
      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 0);
      expect(controller.state.isOffline, isTrue);
      expect(controller.state.isLoading, isFalse);

      final persistedEvent = await dbService.getEventById('event-a1');
      expect(persistedEvent, isNotNull);
      expect(persistedEvent!.eventTypes, const [EventType.consultation]);
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
      await waitForBackgroundSync();

      expect(fakeNoteSyncAdapter.getNoteByRecordUuidCalls, 1);
      expect(fakeNoteSyncAdapter.saveCalls, 0);
      expect(fakeApiClient.createEventCalls, 1);
      expect(fakeApiClient.updateEventCalls, 0);
      expect(fakeApiClient.updateRecordCalls, 1);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-018: new event with same record UUID saves edited shared note',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      final existingSharedNote = makeNote(
        recordUuid: 'record-a1',
        version: 4,
        pages: const [
          [
            Stroke(
              id: 'shared-stroke-a1',
              eventUuid: 'event-origin-a1',
              points: [StrokePoint(1, 1), StrokePoint(5, 5)],
            ),
          ],
        ],
      );
      fakeNoteSyncAdapter.notesByRecordUuid['record-a1'] = existingSharedNote;
      fakeNoteSyncAdapter.saveResponse = makeNote(
        recordUuid: 'record-a1',
        version: 5,
        pages: const [
          [
            Stroke(
              id: 'shared-stroke-a1',
              eventUuid: 'event-origin-a1',
              points: [StrokePoint(1, 1), StrokePoint(5, 5)],
            ),
            Stroke(
              id: 'new-shared-stroke-a1',
              eventUuid: 'event-new-same-record-a1',
              points: [StrokePoint(8, 8), StrokePoint(12, 12)],
            ),
          ],
        ],
      );

      final newEvent = makeEvent(
        id: 'event-new-same-record-a1',
        bookUuid: 'book-a',
        recordUuid: 'record-a1',
        title: 'Alice',
        recordNumber: '001',
        eventTypes: const [EventType.consultation],
      );
      final controller = buildNewController(newEvent);
      await controller.loadExistingPersonNote(existingSharedNote);
      controller.updatePages([
        const [
          Stroke(
            id: 'shared-stroke-a1',
            eventUuid: 'event-origin-a1',
            points: [StrokePoint(1, 1), StrokePoint(5, 5)],
          ),
          Stroke(
            id: 'new-shared-stroke-a1',
            eventUuid: 'event-new-same-record-a1',
            points: [StrokePoint(8, 8), StrokePoint(12, 12)],
          ),
        ],
      ]);

      await controller.saveEvent();
      await waitForBackgroundSync();

      expect(fakeNoteSyncAdapter.getNoteByRecordUuidCalls, 1);
      expect(fakeNoteSyncAdapter.saveCalls, 1);
      expect(fakeNoteSyncAdapter.lastSaveEventId, 'event-new-same-record-a1');
      expect(fakeNoteSyncAdapter.lastSavedNote, isNotNull);
      expect(fakeNoteSyncAdapter.lastSavedNote!.version, 5);

      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.version, 5);
      final savedStrokeIds = controller.state.note!.pages
          .expand((page) => page)
          .map((stroke) => stroke.id)
          .whereType<String>()
          .toSet();
      expect(savedStrokeIds, contains('new-shared-stroke-a1'));
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
      await waitForBackgroundSync();

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
      await waitForBackgroundSync();

      expect(fakeApiClient.updateEventCalls, 1);
      expect(fakeApiClient.updateRecordCalls, 1);
      expect(fakeApiClient.lastRecordUuid, 'record-a1');
      expect(fakeNoteSyncAdapter.saveCalls, 2);
      expect(fakeNoteSyncAdapter.lastSaveEventId, 'event-refill-note-1');
      expect(fakeNoteSyncAdapter.savedNotes.first.version, 4);
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
      await waitForBackgroundSync();

      expect(fakeApiClient.updateEventCalls, 0);
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
      await waitForBackgroundSync();

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
      await waitForBackgroundSync();
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
      await waitForBackgroundSync();

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
    'EVENT-DETAIL-UNIT-025: initialize() hydrates prefilled new event with existing note and charge items',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      final note = makeNote(recordUuid: 'record-a1', version: 3);
      fakeApiClient.fetchRecordByNumberResponses['001'] = {
        'record_uuid': 'record-a1',
        'record_number': '001',
        'name': 'Alice',
        'phone': null,
      };
      fakeNoteSyncAdapter.notesByRecordUuid['record-a1'] = note;

      await dbService.saveChargeItem(
        ChargeItem(
          id: 'charge-prefill-1',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Follow-up Fee',
          itemPrice: 1200,
          receivedAmount: 300,
          paidItems: _singlePaidItem(300, DateTime(2026, 3, 20)),
        ),
      );

      final controller = buildNewController(
        makeEvent(
          id: 'event-next-prefill-1',
          bookUuid: 'book-a',
          recordUuid: '',
          title: 'Alice',
          recordNumber: '001',
          eventTypes: const [EventType.followUp],
        ),
      );

      await controller.initialize();

      expect(controller.state.recordNumber, '001');
      expect(controller.state.name, 'Alice');
      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.recordUuid, 'record-a1');
      expect(controller.state.note!.version, 3);
      expect(controller.state.chargeItems, hasLength(1));
      expect(controller.state.chargeItems.single.itemName, 'Follow-up Fee');
      expect(controller.state.isLoadingFromServer, isFalse);
      expect(controller.state.isValidatingRecordNumber, isFalse);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-017: validateRecordNumberOnBlur() hydrates canonical record data for existing record number',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      final existingNote = makeNote(
        recordUuid: 'record-server-lookup-1',
        version: 4,
      );
      fakeApiClient.fetchRecordByNumberResponses['SRV-001'] = {
        'record_uuid': 'record-server-lookup-1',
        'record_number': 'SRV-001',
        'name': 'Server Lookup',
        'phone': '0900111222',
      };
      fakeNoteSyncAdapter.notesByRecordUuid['record-server-lookup-1'] =
          existingNote;

      final controller = buildNewController(
        makeEvent(
          id: 'event-lookup-blur-1',
          bookUuid: 'book-a',
          recordUuid: '',
          title: '',
          recordNumber: '',
          eventTypes: const [EventType.consultation],
        ),
      );

      controller.updateRecordNumber('SRV-001');
      final isValid = await controller.validateRecordNumberOnBlur();

      expect(isValid, isTrue);
      expect(fakeApiClient.lastFetchedRecordNumber, 'SRV-001');
      expect(controller.state.recordNumber, 'SRV-001');
      expect(controller.state.name, 'Server Lookup');
      expect(controller.state.phone, '0900111222');
      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.recordUuid, 'record-server-lookup-1');
      expect(controller.state.note!.version, 4);
      expect(controller.state.isNameReadOnly, isTrue);
      expect(controller.state.isLoadingFromServer, isFalse);
      expect(controller.state.isValidatingRecordNumber, isFalse);
      expect(controller.state.recordNumberError, isNull);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-019: validateRecordNumberOnBlur() blocks fetch when record number conflicts with typed name',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      fakeApiClient.validateRecordNumberResponses['SRV-003::Alice Typed'] =
          RecordValidationResult(exists: true, valid: false);
      fakeApiClient.fetchRecordByNumberResponses['SRV-003'] = {
        'record_uuid': 'record-server-lookup-3',
        'record_number': 'SRV-003',
        'name': 'Server Name',
        'phone': '0933555666',
      };

      final controller = buildNewController(
        makeEvent(
          id: 'event-lookup-blur-2',
          bookUuid: 'book-a',
          recordUuid: '',
          title: '',
          recordNumber: '',
          eventTypes: const [EventType.consultation],
        ),
      );

      controller.updateName('Alice Typed');
      controller.updateRecordNumber('SRV-003');
      final isValid = await controller.validateRecordNumberOnBlur();

      expect(isValid, isFalse);
      expect(fakeApiClient.lastValidatedRecordNumber, 'SRV-003');
      expect(fakeApiClient.lastValidatedName, 'Alice Typed');
      expect(fakeApiClient.lastFetchedRecordNumber, isNull);
      expect(controller.state.name, 'Alice Typed');
      expect(controller.state.recordNumber, isEmpty);
      expect(controller.state.recordNumberError, '病例號已存在，且其病人不為 Alice Typed.');
      expect(controller.state.isLoadingFromServer, isFalse);
      expect(controller.state.isValidatingRecordNumber, isFalse);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-018: onRecordNumberSelected() hydrates canonical record data without validation dialog state',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      final existingNote = makeNote(
        recordUuid: 'record-server-lookup-2',
        version: 6,
      );
      fakeApiClient.fetchRecordByNumberResponses['SRV-002'] = {
        'record_uuid': 'record-server-lookup-2',
        'record_number': 'SRV-002',
        'name': 'Dropdown Match',
        'phone': '0911333444',
      };
      fakeNoteSyncAdapter.notesByRecordUuid['record-server-lookup-2'] =
          existingNote;

      final controller = buildNewController(
        makeEvent(
          id: 'event-lookup-select-1',
          bookUuid: 'book-a',
          recordUuid: '',
          title: '',
          recordNumber: '',
          eventTypes: const [EventType.consultation],
        ),
      );

      await controller.onRecordNumberSelected('SRV-002');

      expect(fakeApiClient.lastFetchedRecordNumber, 'SRV-002');
      expect(controller.state.recordNumber, 'SRV-002');
      expect(controller.state.name, 'Dropdown Match');
      expect(controller.state.phone, '0911333444');
      expect(controller.state.note, isNotNull);
      expect(controller.state.note!.recordUuid, 'record-server-lookup-2');
      expect(controller.state.note!.version, 6);
      expect(controller.state.isNameReadOnly, isTrue);
      expect(controller.state.isLoadingFromServer, isFalse);
      expect(controller.state.recordNumberError, isNull);
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
      await waitForBackgroundSync();

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
      await waitForBackgroundSync();

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
    'EVENT-DETAIL-UNIT-016: manual saveNoteToServer() does not prefetch server note before write',
    () async {
      final controller = buildController();
      await controller.loadExistingPersonNote(
        makeNote(recordUuid: 'record-a1', version: 4),
      );

      await controller.saveNoteToServer('event-a1', [
        const [
          Stroke(
            id: 'manual-save-stroke',
            eventUuid: 'event-a1',
            points: [StrokePoint(3, 3), StrokePoint(9, 9)],
          ),
        ],
      ]);

      expect(fakeNoteSyncAdapter.getNoteByRecordUuidCalls, 0);
      expect(fakeNoteSyncAdapter.saveCalls, 1);
      expect(fakeNoteSyncAdapter.lastSavedNote, isNotNull);
      expect(fakeNoteSyncAdapter.lastSavedNote!.version, 5);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-019: ensureChargeItemsReady() resolves record UUID via server and enables charge-item linkage',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      final newEvent = makeEvent(
        id: 'event-new-charge-1',
        bookUuid: 'book-a',
        recordUuid: '',
        title: 'New Person',
        recordNumber: 'NEW-CHARGE-001',
        eventTypes: const [EventType.consultation],
      );

      final controller = buildNewController(newEvent);
      controller.updateName('New Person');
      controller.updateRecordNumber('NEW-CHARGE-001');

      final ready = await controller.ensureChargeItemsReady();
      expect(ready, isTrue);
      expect(fakeApiClient.getOrCreateRecordCalls, 1);
      expect(fakeApiClient.createEventCalls, 0);
      expect(fakeApiClient.updateRecordCalls, 0);

      await controller.addChargeItem(
        ChargeItem(
          recordUuid: 'ignored-by-controller',
          itemName: 'CT',
          itemPrice: 1800,
        ),
      );

      final savedItems = await dbService.getChargeItemsByRecordUuid(
        'generated-record-1',
      );
      expect(savedItems, hasLength(1));
      expect(savedItems.single.itemName, 'CT');
      expect(savedItems.single.eventId, isNull);
      expect(controller.state.chargeItems, hasLength(1));
      expect(controller.state.chargeItems.single.itemName, 'CT');
    },
  );

  test(
    'EVENT-DETAIL-UNIT-020: ensureChargeItemsReady() returns false when record number is missing and no record UUID exists',
    () async {
      final newEvent = makeEvent(
        id: 'event-new-charge-2',
        bookUuid: 'book-a',
        recordUuid: '',
        title: 'WalkIn',
        recordNumber: '',
        eventTypes: const [EventType.consultation],
      );

      final controller = buildNewController(newEvent);
      controller.updateName('WalkIn');
      controller.updateRecordNumber('');

      final ready = await controller.ensureChargeItemsReady();
      expect(ready, isFalse);
      expect(fakeApiClient.getOrCreateRecordCalls, 0);
      expect(fakeApiClient.createEventCalls, 0);
      expect(fakeApiClient.updateRecordCalls, 0);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-021: ensureChargeItemsReady() throws when server getOrCreate fails',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      fakeApiClient.getOrCreateRecordError = ApiException(
        'Server error',
        statusCode: 500,
      );

      final newEvent = makeEvent(
        id: 'event-new-charge-3',
        bookUuid: 'book-a',
        recordUuid: '',
        title: 'Fallback Person',
        recordNumber: 'LOCAL-FALLBACK-001',
        eventTypes: const [EventType.consultation],
      );

      final controller = buildNewController(newEvent);
      controller.updateName('Fallback Person');
      controller.updateRecordNumber('LOCAL-FALLBACK-001');

      await expectLater(
        controller.ensureChargeItemsReady(),
        throwsA(isA<ApiException>()),
      );
      expect(fakeApiClient.getOrCreateRecordCalls, 1);
      expect(fakeApiClient.createEventCalls, 0);
      expect(fakeApiClient.updateRecordCalls, 0);

      final localRecord = await dbService.getRecordByRecordNumber(
        'LOCAL-FALLBACK-001',
      );
      expect(localRecord, isNull);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-024: ensureChargeItemsReady() upgrades legacy non-UUID local record linkage via server getOrCreate',
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
        recordUuid: 'legacy-record-id-1',
        recordNumber: 'LEGACY-001',
        name: 'Legacy Person',
      );

      final newEvent = makeEvent(
        id: 'event-new-charge-legacy',
        bookUuid: 'book-a',
        recordUuid: '',
        title: 'Legacy Person',
        recordNumber: 'LEGACY-001',
        eventTypes: const [EventType.consultation],
      );

      final controller = buildNewController(newEvent);
      controller.updateName('Legacy Person');
      controller.updateRecordNumber('LEGACY-001');

      final ready = await controller.ensureChargeItemsReady();
      expect(ready, isTrue);
      expect(fakeApiClient.getOrCreateRecordCalls, 1);

      await controller.addChargeItem(
        ChargeItem(
          recordUuid: 'ignored-by-controller',
          itemName: 'Ultrasound',
          itemPrice: 900,
        ),
      );
      await waitForBackgroundSync();

      expect(fakeApiClient.saveChargeItemCalls, 1);
      expect(
        fakeApiClient.lastSaveChargeItemRecordUuid,
        isNot('legacy-record-id-1'),
      );
      expect(fakeApiClient.lastSaveChargeItemRecordUuid, 'generated-record-1');
    },
  );

  test(
    'EVENT-DETAIL-UNIT-022: addChargeItem() syncs charge item to server when credentials are available',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      final controller = buildController();

      await controller.addChargeItem(
        ChargeItem(
          recordUuid: 'ignored-by-controller',
          itemName: 'MRI',
          itemPrice: 2600,
        ),
      );
      await waitForBackgroundSync();

      expect(fakeApiClient.saveChargeItemCalls, 1);
      expect(fakeApiClient.lastSaveChargeItemRecordUuid, 'record-a1');
      expect(fakeApiClient.lastSaveChargeItemData?['eventId'], 'event-a1');
      expect(fakeApiClient.lastSaveChargeItemData?['bookUuid'], 'book-a');
      expect(fakeApiClient.lastSaveChargeItemData?['itemName'], 'MRI');
      expect(fakeApiClient.lastSaveChargeItemData?['itemPrice'], 2600);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-023: addChargeItem() keeps a dirty local copy when server save fails',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      fakeApiClient.saveChargeItemError = ApiException(
        'server failed',
        statusCode: 500,
      );

      final controller = buildController();

      await controller.addChargeItem(
        ChargeItem(
          recordUuid: 'ignored-by-controller',
          itemName: 'ServerOnly',
          itemPrice: 1100,
        ),
      );

      final savedItems = await dbService.getChargeItemsByRecordUuid(
        'record-a1',
      );
      expect(savedItems, hasLength(1));
      expect(savedItems.single.itemName, 'ServerOnly');
      expect(savedItems.single.itemPrice, 1100);
      expect(savedItems.single.isDirty, isTrue);
      expect(controller.state.isOffline, isTrue);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-029: addChargeItem() returns after local state update before delayed server sync completes',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      fakeApiClient.saveChargeItemDelay = const Duration(milliseconds: 150);

      final controller = buildController();

      final stopwatch = Stopwatch()..start();
      await controller.addChargeItem(
        ChargeItem(
          recordUuid: 'ignored-by-controller',
          itemName: 'Fast MRI',
          itemPrice: 2600,
        ),
      );
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(120));
      expect(controller.state.chargeItems, hasLength(1));
      expect(controller.state.chargeItems.single.itemName, 'Fast MRI');
      expect(controller.state.chargeItems.single.isDirty, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 220));

      final savedItem = await dbService.getChargeItemById(
        controller.state.chargeItems.single.id,
      );
      expect(savedItem, isNotNull);
      expect(savedItem!.isDirty, isFalse);
      expect(controller.state.chargeItems.single.isDirty, isFalse);
      expect(fakeApiClient.saveChargeItemCalls, 1);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-011: addChargeItem() links new item to current event even when all-items filter is active',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
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

  test(
    'EVENT-DETAIL-UNIT-026: updateEventsHasChargeItemsFlag() does not recompute server-owned event flags',
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
          id: 'charge-flag-event-a1',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Scoped Item',
          itemPrice: 500,
        ),
      );
      await dbService.updateEventsHasChargeItemsFlag(recordUuid: 'record-a1');

      final eventA1 = await dbService.getEventById('event-a1');
      final eventA2 = await dbService.getEventById('event-a2');
      expect(eventA1, isNotNull);
      expect(eventA2, isNotNull);
      expect(eventA1!.hasChargeItems, isFalse);
      expect(eventA2!.hasChargeItems, isFalse);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-013: appendChargeItemPayment() accumulates paid items and marks the charge item paid when totals match',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      await dbService.saveChargeItem(
        ChargeItem(
          id: 'charge-edit-paid',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Medication',
          itemPrice: 800,
          receivedAmount: 0,
        ),
      );

      final controller = buildController();
      final existingItem = await dbService.getChargeItemById(
        'charge-edit-paid',
      );

      expect(existingItem, isNotNull);
      await controller.appendChargeItemPayment(
        existingItem!,
        ChargeItemPayment(
          id: 'payment-1',
          amount: 300,
          paidDate: DateTime(2026, 3, 20),
        ),
      );

      var savedItem = await dbService.getChargeItemById('charge-edit-paid');
      expect(savedItem, isNotNull);
      expect(savedItem!.receivedAmount, 300);
      expect(savedItem.paidItems, hasLength(1));
      expect(savedItem.isPaid, isFalse);

      await controller.appendChargeItemPayment(
        savedItem,
        ChargeItemPayment(
          id: 'payment-2',
          amount: 500,
          paidDate: DateTime(2026, 3, 21),
        ),
      );

      savedItem = await dbService.getChargeItemById('charge-edit-paid');
      expect(savedItem, isNotNull);
      expect(savedItem!.receivedAmount, 800);
      expect(savedItem.paidItems, hasLength(2));
      expect(savedItem.isPaid, isTrue);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-032: appendChargeItemPayment() syncs both existing and new paid items to server',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );

      await dbService.saveChargeItem(
        ChargeItem(
          id: 'charge-append-sync',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Medication',
          itemPrice: 900,
          receivedAmount: 400,
          paidItems: _singlePaidItem(400, DateTime(2026, 3, 20)),
        ),
      );

      final controller = buildController();
      final existingItem = await dbService.getChargeItemById(
        'charge-append-sync',
      );

      expect(existingItem, isNotNull);
      await controller.appendChargeItemPayment(
        existingItem!,
        ChargeItemPayment(
          id: 'payment-2',
          amount: 200,
          paidDate: DateTime(2026, 3, 21),
        ),
      );
      await waitForBackgroundSync();

      final paidItems =
          fakeApiClient.lastSaveChargeItemData?['paidItems'] as List<dynamic>?;
      expect(fakeApiClient.saveChargeItemCalls, 1);
      expect(paidItems, isNotNull);
      expect(paidItems, hasLength(2));
      expect((paidItems![0] as Map<String, dynamic>)['amount'], 400);
      expect((paidItems[1] as Map<String, dynamic>)['amount'], 200);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-031: applyServerChargeItemChange() ignores stale server versions so newer paid items are not overwritten',
    () async {
      final initial = await dbService.saveChargeItem(
        ChargeItem(
          id: 'charge-stale-sync',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Medication',
          itemPrice: 800,
          receivedAmount: 300,
          paidItems: _singlePaidItem(300, DateTime(2026, 3, 20)),
        ),
      );

      final newerLocal = await dbService.saveChargeItem(
        initial.appendPaidItem(
          ChargeItemPayment(
            id: 'payment-2',
            amount: 500,
            paidDate: DateTime(2026, 3, 21),
          ),
        ),
      );

      expect(newerLocal.version, greaterThan(1));
      expect(newerLocal.paidItems, hasLength(2));

      await dbService.applyServerChargeItemChange({
        'id': 'charge-stale-sync',
        'record_uuid': 'record-a1',
        'event_id': 'event-a1',
        'item_name': 'Medication',
        'item_price': 800,
        'received_amount': 300,
        'paidItems': [
          {'id': 'payment-1', 'amount': 300, 'paidDate': '2026-03-20'},
        ],
        'created_at': DateTime(2026, 3, 20).toUtc().toIso8601String(),
        'updated_at': DateTime(2026, 3, 20).toUtc().toIso8601String(),
        'version': 1,
        'is_deleted': false,
      });

      final savedItem = await dbService.getChargeItemById('charge-stale-sync');
      expect(savedItem, isNotNull);
      expect(savedItem!.paidItems, hasLength(2));
      expect(savedItem.receivedAmount, 800);
      expect(savedItem.version, newerLocal.version);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-027: editChargeItem() updates the local charge item when device credentials are unavailable',
    () async {
      await dbService.saveChargeItem(
        ChargeItem(
          id: 'charge-edit-local-only',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Medication',
          itemPrice: 800,
          receivedAmount: 100,
          paidItems: _singlePaidItem(100, DateTime(2026, 3, 20)),
        ),
      );

      final controller = buildController();

      await controller.editChargeItem(
        ChargeItem(
          id: 'charge-edit-local-only',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Medication',
          itemPrice: 800,
          receivedAmount: 350,
          paidItems: _singlePaidItem(350, DateTime(2026, 3, 21)),
        ),
      );

      final savedItem = await dbService.getChargeItemById(
        'charge-edit-local-only',
      );
      expect(savedItem, isNotNull);
      expect(savedItem!.receivedAmount, 350);
      expect(savedItem.isPaid, isFalse);
      expect(savedItem.isDirty, isTrue);
      expect(fakeApiClient.saveChargeItemCalls, 0);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-030: editChargeItem() returns after local state update before delayed server sync completes',
    () async {
      await dbService.saveDeviceCredentials(
        deviceId: 'device-001',
        deviceToken: 'token-001',
        deviceName: 'Test Device',
        serverUrl: 'https://server.local',
        platform: 'test',
      );
      await dbService.saveChargeItem(
        ChargeItem(
          id: 'charge-edit-fast',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Medication',
          itemPrice: 800,
          receivedAmount: 100,
          paidItems: _singlePaidItem(100, DateTime(2026, 3, 20)),
        ),
      );
      fakeApiClient.saveChargeItemDelay = const Duration(milliseconds: 150);

      final controller = buildController();
      await controller.loadChargeItems();

      final stopwatch = Stopwatch()..start();
      await controller.editChargeItem(
        ChargeItem(
          id: 'charge-edit-fast',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Medication',
          itemPrice: 800,
          receivedAmount: 500,
          paidItems: _singlePaidItem(500, DateTime(2026, 3, 21)),
        ),
      );
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(120));
      expect(controller.state.chargeItems, hasLength(1));
      expect(controller.state.chargeItems.single.receivedAmount, 500);
      expect(controller.state.chargeItems.single.isDirty, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 220));

      final savedItem = await dbService.getChargeItemById('charge-edit-fast');
      expect(savedItem, isNotNull);
      expect(savedItem!.receivedAmount, 500);
      expect(savedItem.isDirty, isFalse);
      expect(controller.state.chargeItems.single.isDirty, isFalse);
      expect(fakeApiClient.saveChargeItemCalls, 1);
    },
  );

  test(
    'EVENT-DETAIL-UNIT-028: appendChargeItemPayment() updates the local charge item when device credentials are unavailable',
    () async {
      await dbService.saveChargeItem(
        ChargeItem(
          id: 'charge-toggle-local-only',
          recordUuid: 'record-a1',
          eventId: 'event-a1',
          itemName: 'Therapy',
          itemPrice: 600,
          receivedAmount: 0,
        ),
      );

      final controller = buildController();
      final existingItem = await dbService.getChargeItemById(
        'charge-toggle-local-only',
      );

      expect(existingItem, isNotNull);
      await controller.appendChargeItemPayment(
        existingItem!,
        ChargeItemPayment(
          id: 'payment-local-only',
          amount: 600,
          paidDate: DateTime(2026, 3, 22),
        ),
      );

      final savedItem = await dbService.getChargeItemById(
        'charge-toggle-local-only',
      );
      expect(savedItem, isNotNull);
      expect(savedItem!.receivedAmount, 600);
      expect(savedItem.paidItems, hasLength(1));
      expect(savedItem.isPaid, isTrue);
      expect(savedItem.isDirty, isTrue);
      expect(fakeApiClient.saveChargeItemCalls, 0);
    },
  );
}
