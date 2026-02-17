@Tags(['schedule', 'unit'])
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/cubits/schedule_cubit.dart';
import 'package:schedule_note_app/cubits/schedule_state.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/repositories/device_repository.dart';
import 'package:schedule_note_app/repositories/event_repository.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/database/mixins/event_operations_mixin.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:schedule_note_app/services/drawing_content_service.dart';
import 'package:schedule_note_app/services/time_service.dart';

class _FakeEventRepository implements IEventRepository {
  bool getByDateRangeCalled = false;

  @override
  Future<List<Event>> getByDateRange(
    String bookUuid,
    DateTime startDate,
    DateTime endDate,
  ) async {
    getByDateRangeCalled = true;
    return [];
  }

  @override
  Future<void> applyServerChange(Map<String, dynamic> changeData) {
    throw UnimplementedError();
  }

  @override
  Future<ChangeEventTimeResult> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Event> create(Event event) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> getAllNames(String bookUuid) {
    throw UnimplementedError();
  }

  @override
  Future<List<NameRecordPair>> getAllNameRecordPairs(String bookUuid) {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> getAllRecordNumbers(String bookUuid) {
    throw UnimplementedError();
  }

  @override
  Future<List<Event>> getAll() {
    throw UnimplementedError();
  }

  @override
  Future<List<Event>> getByBookId(String bookUuid) {
    throw UnimplementedError();
  }

  @override
  Future<Event?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Event?> getByServerId(String serverId) {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> getRecordNumbersByName(String bookUuid, String name) {
    throw UnimplementedError();
  }

  @override
  Future<Event> removeEvent(String eventId, String reason) {
    throw UnimplementedError();
  }

  @override
  Future<List<Event>> searchByNameAndRecordNumber(
    String bookUuid,
    String name,
    String recordNumber,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Event> update(Event event) {
    throw UnimplementedError();
  }
}

class _FakeDeviceRepository implements IDeviceRepository {
  DeviceCredentials? credentials;

  @override
  Future<DeviceCredentials?> getCredentials() async => credentials;

  @override
  Future<void> saveCredentials({
    required String deviceId,
    required String deviceToken,
    required String deviceName,
    String? platform,
  }) async {
    credentials = DeviceCredentials(
      deviceId: deviceId,
      deviceToken: deviceToken,
    );
  }
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost:8080');

  final List<List<Map<String, dynamic>>> queuedResponses = [];
  final List<Object> queuedUpdateResults = [];
  final List<int?> updateRequestVersions = [];
  Object? fetchError;
  int fetchCount = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchEventsByDateRange({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
    required String deviceId,
    required String deviceToken,
    bool includeRemoved = true,
    bool includeTimeChanged = true,
  }) async {
    fetchCount++;
    if (fetchError != null) {
      throw fetchError!;
    }
    if (queuedResponses.isNotEmpty) {
      return queuedResponses.removeAt(0);
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> updateEvent({
    required String bookUuid,
    required String eventId,
    required Map<String, dynamic> eventData,
    required String deviceId,
    required String deviceToken,
  }) async {
    updateRequestVersions.add(eventData['version'] as int?);
    if (queuedUpdateResults.isNotEmpty) {
      final next = queuedUpdateResults.removeAt(0);
      if (next is Exception) {
        throw next;
      }
      if (next is Error) {
        throw next;
      }
      return next as Map<String, dynamic>;
    }
    throw UnimplementedError('No queued update result configured');
  }
}

void main() {
  late _FakeEventRepository eventRepository;
  late _FakeApiClient apiClient;
  late _FakeDeviceRepository deviceRepository;
  late DrawingContentService drawingContentService;
  late DateTime fixedNow;

  Map<String, dynamic> serverEventMap({
    required String eventId,
    required DateTime startTime,
  }) {
    final startSeconds = startTime.toUtc().millisecondsSinceEpoch ~/ 1000;
    return {
      'id': eventId,
      'book_uuid': 'book-1',
      'record_uuid': 'record-1',
      'record_name': 'Alice',
      'record_number': '001',
      'event_types': '["consultation"]',
      'start_time': startSeconds,
      'end_time': startSeconds + 1800,
      'created_at': startSeconds,
      'updated_at': startSeconds,
      'is_removed': false,
      'is_checked': false,
      'has_note': false,
      'version': 1,
    };
  }

  setUp(() {
    eventRepository = _FakeEventRepository();
    apiClient = _FakeApiClient();
    deviceRepository = _FakeDeviceRepository();
    drawingContentService = DrawingContentService(apiClient, deviceRepository);
    fixedNow = DateTime.utc(2026, 2, 10, 3, 0, 0);
    TimeService.instance.setTestTime(fixedNow);
  });

  tearDown(() {
    TimeService.instance.resetToRealTime();
    apiClient.dispose();
  });

  ScheduleCubit buildCubit() {
    return ScheduleCubit(
      eventRepository,
      drawingContentService,
      TimeService.instance,
      apiClient: apiClient,
      deviceRepository: deviceRepository,
    );
  }

  blocTest<ScheduleCubit, ScheduleState>(
    'SCHEDULE-CUBIT-001: initialize() fetches schedule events from server',
    build: () {
      deviceRepository.credentials = const DeviceCredentials(
        deviceId: 'd1',
        deviceToken: 't1',
      );
      apiClient.queuedResponses.add([
        serverEventMap(eventId: 'event-1', startTime: fixedNow),
      ]);
      return buildCubit();
    },
    act: (cubit) async => cubit.initialize('book-1'),
    expect: () => [
      isA<ScheduleLoading>(),
      isA<ScheduleLoaded>()
          .having((s) => s.events.length, 'events length', 1)
          .having((s) => s.events.first.id, 'event id', 'event-1'),
    ],
  );

  blocTest<ScheduleCubit, ScheduleState>(
    'SCHEDULE-CUBIT-002: refreshFromServer() keeps stale data visible with refreshing state',
    build: () {
      deviceRepository.credentials = const DeviceCredentials(
        deviceId: 'd1',
        deviceToken: 't1',
      );
      apiClient.queuedResponses.add([
        serverEventMap(eventId: 'event-1', startTime: fixedNow),
      ]);
      apiClient.queuedResponses.add([
        serverEventMap(
          eventId: 'event-2',
          startTime: fixedNow.add(const Duration(hours: 1)),
        ),
      ]);
      return buildCubit();
    },
    act: (cubit) async {
      await cubit.initialize('book-1');
      await cubit.refreshFromServer();
    },
    expect: () => [
      isA<ScheduleLoading>(),
      isA<ScheduleLoaded>().having(
        (s) => s.events.first.id,
        'first load id',
        'event-1',
      ),
      isA<ScheduleRefreshing>().having(
        (s) => s.events.first.id,
        'refreshing shows stale id',
        'event-1',
      ),
      isA<ScheduleLoaded>().having(
        (s) => s.events.first.id,
        'refreshed id',
        'event-2',
      ),
    ],
  );

  blocTest<ScheduleCubit, ScheduleState>(
    'SCHEDULE-CUBIT-003: missing credentials emits error and does not fall back to local repository',
    build: buildCubit,
    act: (cubit) async => cubit.initialize('book-1'),
    expect: () => [
      isA<ScheduleLoading>(),
      isA<ScheduleError>().having(
        (s) => s.message.contains('Device not registered'),
        'error message',
        true,
      ),
    ],
    verify: (_) {
      expect(eventRepository.getByDateRangeCalled, isFalse);
    },
  );

  blocTest<ScheduleCubit, ScheduleState>(
    'SCHEDULE-CUBIT-004: server fetch failure emits error and does not fall back to local repository',
    build: () {
      deviceRepository.credentials = const DeviceCredentials(
        deviceId: 'd1',
        deviceToken: 't1',
      );
      apiClient.fetchError = Exception('server down');
      return buildCubit();
    },
    act: (cubit) async => cubit.initialize('book-1'),
    expect: () => [
      isA<ScheduleLoading>(),
      isA<ScheduleError>().having(
        (s) => s.message.contains('server down'),
        'error includes server cause',
        true,
      ),
    ],
    verify: (_) {
      expect(eventRepository.getByDateRangeCalled, isFalse);
    },
  );

  blocTest<ScheduleCubit, ScheduleState>(
    'SCHEDULE-CUBIT-005: updateEvent() applies last-write-wins retry on conflict',
    build: () {
      deviceRepository.credentials = const DeviceCredentials(
        deviceId: 'd1',
        deviceToken: 't1',
      );
      apiClient.queuedResponses.add([
        serverEventMap(eventId: 'event-1', startTime: fixedNow),
      ]);
      apiClient.queuedUpdateResults.add(
        ApiConflictException(
          'conflict',
          statusCode: 409,
          responseBody: '{"serverVersion":3}',
        ),
      );
      apiClient.queuedUpdateResults.add(
        serverEventMap(eventId: 'event-1', startTime: fixedNow)
          ..['record_name'] = 'Alice updated'
          ..['version'] = 4,
      );
      return buildCubit();
    },
    act: (cubit) async {
      await cubit.initialize('book-1');
      final initial = cubit.state as ScheduleLoaded;
      final edited = initial.events.first.copyWith(title: 'Alice updated');
      await cubit.updateEvent(edited);
    },
    expect: () => [
      isA<ScheduleLoading>(),
      isA<ScheduleLoaded>().having(
        (s) => s.events.first.title,
        'initial title',
        'Alice',
      ),
      isA<ScheduleLoaded>().having(
        (s) => s.events.first.title,
        'optimistic title',
        'Alice updated',
      ),
      isA<ScheduleLoaded>().having(
        (s) => s.events.first.version,
        'server version after retry',
        4,
      ),
    ],
    verify: (_) {
      expect(apiClient.updateRequestVersions, equals([1, 4]));
    },
  );
}
