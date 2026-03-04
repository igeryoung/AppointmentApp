import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/cubits/schedule_cubit.dart';
import 'package:schedule_note_app/cubits/schedule_state.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/repositories/device_repository.dart';
import 'package:schedule_note_app/repositories/device_repository_impl.dart';
import 'package:schedule_note_app/repositories/event_repository.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/database/mixins/event_operations_mixin.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:schedule_note_app/services/drawing_content_service.dart';
import 'package:schedule_note_app/services/time_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../support/test_db_path.dart';
import 'live_server_test_support.dart';

class _StageProbe {
  final Map<String, List<int>> _samples = <String, List<int>>{};
  final List<String> order = <String>[];

  Future<T> measure<T>(String stage, Future<T> Function() action) async {
    final sw = Stopwatch()..start();
    try {
      return await action();
    } finally {
      sw.stop();
      order.add(stage);
      _samples.putIfAbsent(stage, () => <int>[]).add(sw.elapsedMicroseconds);
    }
  }

  void reset() {
    _samples.clear();
    order.clear();
  }

  Map<String, double> singleRunMs() {
    return _samples.map((key, value) => MapEntry(key, value.last / 1000.0));
  }

  int totalMeasuredMicroseconds() {
    return _samples.values.fold<int>(
      0,
      (sum, values) => sum + values.fold<int>(0, (s, value) => s + value),
    );
  }
}

class _TrackingDeviceRepository implements IDeviceRepository {
  _TrackingDeviceRepository(this._inner, this._probe);

  final DeviceRepositoryImpl _inner;
  final _StageProbe _probe;
  int _getCredentialsCalls = 0;

  void resetMeasuredRun() {
    _getCredentialsCalls = 0;
  }

  @override
  Future<DeviceCredentials?> getCredentials() {
    _getCredentialsCalls += 1;
    final stage = switch (_getCredentialsCalls) {
      1 => 'credentials_local_before_reschedule',
      2 => 'credentials_local_before_reload',
      _ => 'credentials_local_extra_$_getCredentialsCalls',
    };
    return _probe.measure(stage, _inner.getCredentials);
  }

  @override
  Future<void> saveCredentials({
    required String deviceId,
    required String deviceToken,
    required String deviceName,
    String? platform,
    String deviceRole = 'read',
  }) {
    return _inner.saveCredentials(
      deviceId: deviceId,
      deviceToken: deviceToken,
      deviceName: deviceName,
      platform: platform,
      deviceRole: deviceRole,
    );
  }
}

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({required super.baseUrl, required this.probe});

  final _StageProbe probe;
  int _fetchEventsCalls = 0;

  void resetMeasuredRun() {
    _fetchEventsCalls = 0;
  }

  @override
  Future<Map<String, dynamic>> rescheduleEvent({
    required String bookUuid,
    required String eventId,
    required DateTime newStartTime,
    DateTime? newEndTime,
    required String reason,
    required String deviceId,
    required String deviceToken,
  }) {
    return probe.measure(
      'reschedule_server_roundtrip',
      () => super.rescheduleEvent(
        bookUuid: bookUuid,
        eventId: eventId,
        newStartTime: newStartTime,
        newEndTime: newEndTime,
        reason: reason,
        deviceId: deviceId,
        deviceToken: deviceToken,
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEventsByDateRange({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
    required String deviceId,
    required String deviceToken,
  }) {
    _fetchEventsCalls += 1;
    final stage = switch (_fetchEventsCalls) {
      1 => 'fetch_events_window',
      _ => 'fetch_events_window_extra_$_fetchEventsCalls',
    };
    return probe.measure(
      stage,
      () => super.fetchEventsByDateRange(
        bookUuid: bookUuid,
        startDate: startDate,
        endDate: endDate,
        deviceId: deviceId,
        deviceToken: deviceToken,
      ),
    );
  }
}

class _TrackingEventRepository implements IEventRepository {
  final List<String> calls = <String>[];

  Never _unexpected(String method) {
    calls.add(method);
    throw UnsupportedError(
      'Schedule reschedule pipeline should not call event repository: $method',
    );
  }

  @override
  Future<void> applyServerChange(Map<String, dynamic> changeData) async =>
      _unexpected('applyServerChange');

  @override
  Future<ChangeEventTimeResult> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  ) async => _unexpected('changeEventTime');

  @override
  Future<Event> create(Event event) async => _unexpected('create');

  @override
  Future<void> delete(String id) async => _unexpected('delete');

  @override
  Future<List<Event>> getAll() async => _unexpected('getAll');

  @override
  Future<List<String>> getAllNames(String bookUuid) async =>
      _unexpected('getAllNames');

  @override
  Future<List<NameRecordPair>> getAllNameRecordPairs(String bookUuid) async =>
      _unexpected('getAllNameRecordPairs');

  @override
  Future<List<String>> getAllRecordNumbers(String bookUuid) async =>
      _unexpected('getAllRecordNumbers');

  @override
  Future<List<Event>> getByBookId(String bookUuid) async =>
      _unexpected('getByBookId');

  @override
  Future<List<Event>> getByDateRange(
    String bookUuid,
    DateTime startDate,
    DateTime endDate,
  ) async => _unexpected('getByDateRange');

  @override
  Future<Event?> getById(String id) async => _unexpected('getById');

  @override
  Future<Event?> getByServerId(String serverId) async =>
      _unexpected('getByServerId');

  @override
  Future<List<String>> getRecordNumbersByName(
    String bookUuid,
    String name,
  ) async => _unexpected('getRecordNumbersByName');

  @override
  Future<List<String>> fetchNameSuggestions(
    String bookUuid,
    String prefix,
  ) async => _unexpected('fetchNameSuggestions');

  @override
  Future<List<NameRecordPair>> fetchRecordNumberSuggestions(
    String bookUuid,
    String prefix, {
    String? namePrefix,
  }) async => _unexpected('fetchRecordNumberSuggestions');

  @override
  Future<Event> removeEvent(String eventId, String reason) async =>
      _unexpected('removeEvent');

  @override
  Future<List<Event>> searchByNameAndRecordNumber(
    String bookUuid,
    String name,
    String recordNumber,
  ) async => _unexpected('searchByNameAndRecordNumber');

  @override
  Future<Event> update(Event event) async => _unexpected('update');
}

DateTime _atUtcHour(DateTime baseUtc, int hour, int minute) {
  return DateTime.utc(baseUtc.year, baseUtc.month, baseUtc.day, hour, minute);
}

void registerEventInteg014({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-014: schedule time change request follows current reschedule pipeline and reports stage latency',
    () async {
      final live = config!;
      final probe = _StageProbe();
      final apiClient = _TrackingApiClient(baseUrl: live.baseUrl, probe: probe);
      final eventRepository = _TrackingEventRepository();
      final timeService = TimeService.instance;
      final uuid = const Uuid();

      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await setUniqueDatabasePath('event_integ_014_schedule_reschedule');
      PRDDatabaseService.resetInstance();
      final prdDb = PRDDatabaseService();
      await prdDb.clearAllData();

      final baseDeviceRepository = DeviceRepositoryImpl(() => prdDb.database);
      final deviceRepository = _TrackingDeviceRepository(
        baseDeviceRepository,
        probe,
      );
      final drawingContentService = DrawingContentService(
        apiClient,
        deviceRepository,
      );

      String? bookUuid;
      ScheduleCubit? cubit;

      try {
        await deviceRepository.saveCredentials(
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
          deviceName: 'Integration Schedule Device',
          platform: 'integration',
          deviceRole: 'write',
        );

        final baseUtc = DateTime.now().toUtc().add(const Duration(days: 1));
        final startTime = _atUtcHour(baseUtc, 10, 0);
        final endTime = _atUtcHour(baseUtc, 10, 30);
        final newStartTime = _atUtcHour(baseUtc, 12, 0);
        final newEndTime = _atUtcHour(baseUtc, 12, 30);
        final suffix = DateTime.now().millisecondsSinceEpoch.toString();

        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT schedule reschedule pipeline $suffix',
        );
        final createdBookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );
        bookUuid = createdBookUuid;

        final eventPayload = await apiClient.createEvent(
          bookUuid: createdBookUuid,
          eventData: {
            'id': uuid.v4(),
            'record_uuid': uuid.v4(),
            'title': 'IT schedule reschedule $suffix',
            'record_number': 'RESCH-$suffix',
            'record_name': 'Schedule Pipeline $suffix',
            'record_phone': '0900000000',
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final originalEvent = Event.fromServerResponse(eventPayload);

        timeService.setTestTime(startTime);

        cubit = ScheduleCubit(
          eventRepository,
          drawingContentService,
          timeService,
          apiClient: apiClient,
          deviceRepository: deviceRepository,
        );

        await cubit.initialize(createdBookUuid);
        expect(cubit.state, isA<ScheduleLoaded>());
        final initialState = cubit.state as ScheduleLoaded;
        expect(
          initialState.events.any((event) => event.id == originalEvent.id),
          isTrue,
        );

        probe.reset();
        deviceRepository.resetMeasuredRun();
        apiClient.resetMeasuredRun();

        final totalSw = Stopwatch()..start();
        final result = await cubit.changeEventTime(
          originalEvent,
          newStartTime,
          newEndTime,
          'integration pipeline timing',
        );
        totalSw.stop();

        expect(result, isNotNull);
        final changeResult = result!;
        expect(eventRepository.calls, isEmpty);
        expect(
          probe.order,
          equals(const [
            'credentials_local_before_reschedule',
            'reschedule_server_roundtrip',
            'credentials_local_before_reload',
            'fetch_events_window',
          ]),
        );

        final state = cubit.state;
        expect(state, isA<ScheduleLoaded>());
        final loaded = state as ScheduleLoaded;

        final oldEvent = loaded.events.firstWhere(
          (event) => event.id == changeResult.oldEvent.id,
        );
        final newEvent = loaded.events.firstWhere(
          (event) => event.id == changeResult.newEvent.id,
        );

        expect(oldEvent.isRemoved, isTrue);
        expect(oldEvent.newEventId, changeResult.newEvent.id);
        expect(newEvent.originalEventId, changeResult.oldEvent.id);
        expect(newEvent.startTime.toUtc(), newStartTime);
        expect(newEvent.endTime?.toUtc(), newEndTime);

        final measuredMicros = probe.totalMeasuredMicroseconds();
        final totalMicros = totalSw.elapsedMicroseconds;
        final clientOverheadMicros = totalMicros - measuredMicros;

        final report = <String, dynamic>{
          'test': 'EVENT-INTEG-014',
          'pipeline':
              'schedule_change_time_request_to_refetched_schedule_state',
          'stage_order': probe.order,
          'stages_ms': probe.singleRunMs(),
          'total_ms': totalMicros / 1000.0,
          'client_overhead_ms': clientOverheadMicros / 1000.0,
          'local_event_repository_calls': eventRepository.calls,
          'result': {
            'old_event_id': changeResult.oldEvent.id,
            'new_event_id': changeResult.newEvent.id,
            'old_event_removed': oldEvent.isRemoved,
            'new_event_start_utc': newEvent.startTime.toUtc().toIso8601String(),
            'new_event_end_utc': newEvent.endTime?.toUtc().toIso8601String(),
          },
        };

        debugPrint(const JsonEncoder.withIndent('  ').convert(report));
      } finally {
        timeService.resetToRealTime();
        await cubit?.close();
        if (bookUuid != null) {
          try {
            await apiClient.deleteBook(
              bookUuid: bookUuid,
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            );
          } catch (_) {}
        }
        await prdDb.close();
        PRDDatabaseService.resetInstance();
        apiClient.dispose();
      }
    },
    timeout: liveServerTestTimeout,
    skip: skipForMissingConfig(config),
  );
}
