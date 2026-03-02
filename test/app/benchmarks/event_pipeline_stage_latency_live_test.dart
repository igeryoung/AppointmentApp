@Tags(['benchmark', 'integration', 'event'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../integration/event_metadata/live_server_test_support.dart';
import '../support/db_seed.dart';
import '../support/test_db_path.dart';

Map<String, num> _stats(List<int> microseconds) {
  final sorted = List<int>.from(microseconds)..sort();
  final total = microseconds.fold<int>(0, (sum, value) => sum + value);

  int percentile(double p) {
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }

  double toMs(num micros) => micros / 1000.0;

  return {
    'count': microseconds.length,
    'avg_ms': toMs(total / microseconds.length),
    'p50_ms': toMs(percentile(0.50)),
    'p95_ms': toMs(percentile(0.95)),
    'min_ms': toMs(sorted.first),
    'max_ms': toMs(sorted.last),
  };
}

Future<T> _measureStage<T>(
  Map<String, List<int>> samples,
  String stage,
  Future<T> Function() action,
) async {
  final sw = Stopwatch()..start();
  final result = await action();
  sw.stop();
  samples.putIfAbsent(stage, () => <int>[]).add(sw.elapsedMicroseconds);
  return result;
}

Future<void> _cacheServerMetadataLocally({
  required PRDDatabaseService prdDb,
  required Event savedEvent,
  required String name,
  required String recordNumber,
  required String? phone,
}) async {
  final db = await prdDb.database;
  final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  final existingRecord = await prdDb.getRecordByUuid(savedEvent.recordUuid);
  if (existingRecord == null) {
    await db.insert('records', {
      'record_uuid': savedEvent.recordUuid,
      'record_number': recordNumber,
      'name': name,
      'phone': phone,
      'created_at': nowSeconds,
      'updated_at': nowSeconds,
      'version': 1,
      'is_dirty': 0,
      'is_deleted': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  } else {
    await db.update(
      'records',
      {
        'record_number': recordNumber,
        'name': name,
        'phone': phone,
        'updated_at': nowSeconds,
        'is_dirty': 0,
        'is_deleted': 0,
      },
      where: 'record_uuid = ?',
      whereArgs: [savedEvent.recordUuid],
    );
  }

  final eventMap = savedEvent.toMap();
  eventMap['is_dirty'] = 0;
  await db.insert(
    'events',
    eventMap,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Map<String, dynamic> _buildEventSyncPayload(
  Event eventData, {
  required String name,
  required String? phone,
}) {
  final payload = Map<String, dynamic>.from(eventData.toMap());
  payload.remove('has_note');
  payload.remove('hasNote');
  payload['name'] = name;
  payload['record_name'] = name;
  payload['recordName'] = name;
  payload['phone'] = phone;
  payload['eventTypes'] = eventData.eventTypes.map((t) => t.name).toList();
  return payload;
}

Map<String, Map<String, num>> _summarize(Map<String, List<int>> samples) {
  final summary = <String, Map<String, num>>{};
  for (final entry in samples.entries) {
    summary[entry.key] = _stats(entry.value);
  }
  return summary;
}

void main() {
  test(
    'live event pipeline stage latency benchmark',
    () async {
      final config = LiveServerConfig.fromEnv();
      if (config == null) {
        markTestSkipped(liveServerSkipReason);
      }

      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await setUniqueDatabasePath('event_pipeline_stage_latency_live');
      PRDDatabaseService.resetInstance();

      final prdDb = PRDDatabaseService();
      await prdDb.clearAllData();
      await prdDb.saveDeviceCredentials(
        deviceId: config!.deviceId,
        deviceToken: config.deviceToken,
        deviceName: 'Benchmark Device',
        serverUrl: config.baseUrl,
        platform: 'benchmark',
      );

      final apiClient = ApiClient(baseUrl: config.baseUrl);
      final uuid = const Uuid();

      String? bookUuid;
      String? eventId;
      String? recordUuid;
      const warmupIterations = 2;
      const measuredIterations = 6;

      final fetchSamples = <String, List<int>>{};
      final updateMetadataSamples = <String, List<int>>{};
      final updateWithNoteSamples = <String, List<int>>{};

      try {
        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: config,
          name: 'IT pipeline latency ${DateTime.now().millisecondsSinceEpoch}',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );
        await seedBook(
          await prdDb.database,
          bookUuid: bookUuid,
          name: 'Benchmark Book',
        );

        eventId = uuid.v4();
        recordUuid = uuid.v4();
        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final startTime = DateTime.now().toUtc().add(
          const Duration(minutes: 30),
        );
        final endTime = startTime.add(const Duration(minutes: 30));

        final createdEvent = await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventId,
            'record_uuid': recordUuid,
            'title': 'IT pipeline event $suffix',
            'record_number': 'PIPE-$suffix',
            'record_name': 'Pipeline User $suffix',
            'record_phone': '0900000000',
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: config.deviceId,
          deviceToken: config.deviceToken,
        );
        var currentEvent = Event.fromServerResponse(createdEvent);
        var currentName = 'Pipeline User $suffix';
        var currentRecordNumber = 'PIPE-$suffix';
        var currentPhone = '0900000000';

        final savedNote = await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: eventId,
          noteData: buildSingleStrokeNotePayload(eventId: eventId, version: 1),
          deviceId: config.deviceId,
          deviceToken: config.deviceToken,
        );
        var currentNoteVersion = (savedNote['version'] as num?)?.toInt() ?? 1;

        Future<void> runFetchIteration(Map<String, List<int>> target) async {
          final totalSw = Stopwatch()..start();
          final credentials = await _measureStage(
            target,
            'credentials_local',
            prdDb.getDeviceCredentials,
          );
          expect(credentials, isNotNull);
          final creds = credentials!;

          final bundle = await _measureStage(
            target,
            'fetch_bundle',
            () => apiClient.fetchEventDetailBundle(
              bookUuid: bookUuid!,
              eventId: eventId!,
              deviceId: creds.deviceId,
              deviceToken: creds.deviceToken,
            ),
          );
          expect(bundle, isNotNull);
          final eventPayload = bundle!['event'] as Map<String, dynamic>?;
          expect(eventPayload, isNotNull);
          final fetchedEvent = Event.fromServerResponse(eventPayload!);
          final recordPayload = bundle['record'] as Map<String, dynamic>?;

          await _measureStage(
            target,
            'cache_local_metadata',
            () => _cacheServerMetadataLocally(
              prdDb: prdDb,
              savedEvent: fetchedEvent,
              name: (recordPayload?['name'] ?? '').toString(),
              recordNumber:
                  (recordPayload?['record_number'] ?? fetchedEvent.recordNumber)
                      .toString(),
              phone: recordPayload?['phone']?.toString(),
            ),
          );

          totalSw.stop();
          target
              .putIfAbsent('total', () => <int>[])
              .add(totalSw.elapsedMicroseconds);
        }

        Future<void> runUpdateMetadataIteration(
          Map<String, List<int>> target,
          int iteration,
        ) async {
          final totalSw = Stopwatch()..start();
          final credentials = await _measureStage(
            target,
            'credentials_local',
            prdDb.getDeviceCredentials,
          );
          expect(credentials, isNotNull);
          final creds = credentials!;

          final nextEventTypes = iteration.isEven
              ? const [EventType.followUp]
              : const [EventType.surgery, EventType.followUp];
          final nextPhone =
              '09${(10000000 + iteration).toString().padLeft(8, '0')}';
          final payload = _buildEventSyncPayload(
            currentEvent.copyWith(eventTypes: nextEventTypes),
            name: currentName,
            phone: nextPhone,
          );

          final savedBundle = await _measureStage(
            target,
            'update_bundle',
            () => apiClient.updateEventDetailBundle(
              bookUuid: bookUuid!,
              eventId: currentEvent.id!,
              eventData: payload,
              recordData: {
                'name': currentName,
                'phone': nextPhone,
                'record_number': currentRecordNumber,
              },
              deviceId: creds.deviceId,
              deviceToken: creds.deviceToken,
            ),
          );
          final updatedPayload = savedBundle['event'] as Map<String, dynamic>?;
          expect(updatedPayload, isNotNull);
          currentEvent = Event.fromServerResponse(updatedPayload!);

          currentPhone = nextPhone;
          await _measureStage(
            target,
            'cache_local_metadata',
            () => _cacheServerMetadataLocally(
              prdDb: prdDb,
              savedEvent: currentEvent,
              name: currentName,
              recordNumber: currentRecordNumber,
              phone: currentPhone,
            ),
          );

          totalSw.stop();
          target
              .putIfAbsent('total', () => <int>[])
              .add(totalSw.elapsedMicroseconds);
        }

        Future<void> runUpdateWithNoteIteration(
          Map<String, List<int>> target,
          int iteration,
        ) async {
          final totalSw = Stopwatch()..start();
          final credentials = await _measureStage(
            target,
            'credentials_local',
            prdDb.getDeviceCredentials,
          );
          expect(credentials, isNotNull);
          final creds = credentials!;

          final nextEventTypes = iteration.isEven
              ? const [EventType.consultation]
              : const [EventType.emergency];
          final nextPhone =
              '09${(20000000 + iteration).toString().padLeft(8, '0')}';
          final payload = _buildEventSyncPayload(
            currentEvent.copyWith(eventTypes: nextEventTypes),
            name: currentName,
            phone: nextPhone,
          );

          final savedBundle = await _measureStage(
            target,
            'update_bundle',
            () => apiClient.updateEventDetailBundle(
              bookUuid: bookUuid!,
              eventId: currentEvent.id!,
              eventData: payload,
              recordData: {
                'name': currentName,
                'phone': nextPhone,
                'record_number': currentRecordNumber,
              },
              deviceId: creds.deviceId,
              deviceToken: creds.deviceToken,
            ),
          );
          final updatedPayload = savedBundle['event'] as Map<String, dynamic>?;
          expect(updatedPayload, isNotNull);
          currentEvent = Event.fromServerResponse(updatedPayload!);
          currentPhone = nextPhone;

          await _measureStage(
            target,
            'cache_local_metadata',
            () => _cacheServerMetadataLocally(
              prdDb: prdDb,
              savedEvent: currentEvent,
              name: currentName,
              recordNumber: currentRecordNumber,
              phone: currentPhone,
            ),
          );

          final savedNotePayload = await _measureStage(
            target,
            'save_note',
            () => apiClient.saveNote(
              bookUuid: bookUuid!,
              eventId: currentEvent.id!,
              noteData: buildSingleStrokeNotePayload(
                eventId: currentEvent.id!,
                version: currentNoteVersion + 1,
              ),
              deviceId: creds.deviceId,
              deviceToken: creds.deviceToken,
            ),
          );
          currentNoteVersion =
              (savedNotePayload['version'] as num?)?.toInt() ??
              (currentNoteVersion + 1);

          totalSw.stop();
          target
              .putIfAbsent('total', () => <int>[])
              .add(totalSw.elapsedMicroseconds);
        }

        for (var i = 0; i < warmupIterations; i++) {
          await runFetchIteration(fetchSamples);
          await runUpdateMetadataIteration(updateMetadataSamples, i);
          await runUpdateWithNoteIteration(updateWithNoteSamples, i);
        }

        fetchSamples.clear();
        updateMetadataSamples.clear();
        updateWithNoteSamples.clear();

        for (var i = 0; i < measuredIterations; i++) {
          await runFetchIteration(fetchSamples);
          await runUpdateMetadataIteration(updateMetadataSamples, i);
          await runUpdateWithNoteIteration(updateWithNoteSamples, i);
        }

        final result = {
          'benchmark': 'live_event_pipeline_stage_latency',
          'samples': measuredIterations,
          'fixture': {
            'book_uuid': bookUuid,
            'event_id': eventId,
            'record_uuid': recordUuid,
          },
          'fetch_pipeline': _summarize(fetchSamples),
          'update_metadata_pipeline': _summarize(updateMetadataSamples),
          'update_with_note_pipeline': _summarize(updateWithNoteSamples),
        };

        print(const JsonEncoder.withIndent('  ').convert(result));

        expect(
          (result['fetch_pipeline'] as Map<String, Map<String, num>>)
              .containsKey('total'),
          isTrue,
        );
      } finally {
        if (bookUuid != null) {
          try {
            await apiClient.deleteBook(
              bookUuid: bookUuid,
              deviceId: config.deviceId,
              deviceToken: config.deviceToken,
            );
          } catch (_) {}
        }
        apiClient.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
