@Tags(['integration', 'event'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/http_client_factory.dart';
import 'package:uuid/uuid.dart';

class _LiveServerConfig {
  final String baseUrl;
  final String deviceId;
  final String deviceToken;
  final String? bookUuid;
  final String? eventId;
  final String? recordUuid;
  final bool autoCleanupFixture;

  const _LiveServerConfig({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    this.bookUuid,
    this.eventId,
    this.recordUuid,
    required this.autoCleanupFixture,
  });

  static Map<String, String> _loadEnvFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return const {};

    final map = <String, String>{};
    final lines = file.readAsLinesSync();
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isEmpty) continue;
      map[key] = value;
    }
    return map;
  }

  static _LiveServerConfig? fromEnv() {
    final envFilePath =
        Platform.environment['SN_TEST_ENV_FILE']?.trim().isNotEmpty == true
        ? Platform.environment['SN_TEST_ENV_FILE']!.trim()
        : '.env.integration';
    final fileEnv = _loadEnvFile(envFilePath);

    String resolve(String key) {
      final fromProcess = Platform.environment[key]?.trim();
      if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
      final fromFile = fileEnv[key]?.trim();
      if (fromFile != null && fromFile.isNotEmpty) return fromFile;
      return '';
    }

    final baseUrl = resolve('SN_TEST_BASE_URL');
    final deviceId = resolve('SN_TEST_DEVICE_ID');
    final deviceToken = resolve('SN_TEST_DEVICE_TOKEN');
    final bookUuid = resolve('SN_TEST_BOOK_UUID');
    final eventId = resolve('SN_TEST_EVENT_ID');
    final recordUuid = resolve('SN_TEST_RECORD_UUID');
    final autoCleanupRaw = resolve(
      'SN_TEST_FIXTURE_AUTO_CLEANUP',
    ).toLowerCase();
    final autoCleanupFixture =
        autoCleanupRaw == '1' ||
        autoCleanupRaw == 'true' ||
        autoCleanupRaw == 'yes' ||
        autoCleanupRaw == 'on';

    if (baseUrl.isEmpty || deviceId.isEmpty || deviceToken.isEmpty) {
      return null;
    }

    final hasAnyFixtureIds =
        bookUuid.isNotEmpty || eventId.isNotEmpty || recordUuid.isNotEmpty;
    final hasAllFixtureIds =
        bookUuid.isNotEmpty && eventId.isNotEmpty && recordUuid.isNotEmpty;
    if (hasAnyFixtureIds && !hasAllFixtureIds) {
      throw StateError(
        'If any of SN_TEST_BOOK_UUID / SN_TEST_EVENT_ID / SN_TEST_RECORD_UUID '
        'is set, all three must be set.',
      );
    }

    return _LiveServerConfig(
      baseUrl: baseUrl,
      deviceId: deviceId,
      deviceToken: deviceToken,
      bookUuid: bookUuid.isEmpty ? null : bookUuid,
      eventId: eventId.isEmpty ? null : eventId,
      recordUuid: recordUuid.isEmpty ? null : recordUuid,
      autoCleanupFixture: autoCleanupFixture,
    );
  }
}

class _ResolvedFixture {
  final String bookUuid;
  final String eventId;
  final String recordUuid;
  final bool isTemporary;

  const _ResolvedFixture({
    required this.bookUuid,
    required this.eventId,
    required this.recordUuid,
    required this.isTemporary,
  });
}

Future<Map<String, dynamic>> _fetchBookScopedRecord({
  required http.Client httpClient,
  required _LiveServerConfig config,
  required _ResolvedFixture fixture,
}) async {
  final response = await httpClient.get(
    Uri.parse(
      '${config.baseUrl}/api/books/${fixture.bookUuid}/records/${fixture.recordUuid}',
    ),
    headers: {
      'Content-Type': 'application/json',
      'X-Device-ID': config.deviceId,
      'X-Device-Token': config.deviceToken,
    },
  );

  if (response.statusCode != 200) {
    throw Exception(
      'Failed to fetch record details: ${response.statusCode} ${response.body}',
    );
  }

  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final record = body['record'] as Map<String, dynamic>?;
  if (record == null) {
    throw Exception('Record details response missing "record" payload');
  }

  return record;
}

String _pickString(Map<String, dynamic> source, {required List<String> keys}) {
  for (final key in keys) {
    final value = source[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  throw StateError('Missing expected keys: ${keys.join(', ')}');
}

bool _pickBool(Map<String, dynamic> source, {required List<String> keys}) {
  for (final key in keys) {
    if (!source.containsKey(key)) continue;
    final value = source[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  throw StateError('Missing expected bool keys: ${keys.join(', ')}');
}

Future<_ResolvedFixture> _resolveFixture({
  required ApiClient apiClient,
  required _LiveServerConfig config,
}) async {
  if (config.bookUuid != null &&
      config.eventId != null &&
      config.recordUuid != null) {
    return _ResolvedFixture(
      bookUuid: config.bookUuid!,
      eventId: config.eventId!,
      recordUuid: config.recordUuid!,
      isTemporary: false,
    );
  }

  final suffix = DateTime.now().millisecondsSinceEpoch.toString();
  final uuid = const Uuid();

  final createdBook = await apiClient.createBook(
    name: 'IT metadata $suffix',
    deviceId: config.deviceId,
    deviceToken: config.deviceToken,
  );
  final bookUuid = _pickString(
    createdBook,
    keys: const ['bookUuid', 'book_uuid', 'uuid'],
  );

  final eventId = uuid.v4();
  final recordUuid = uuid.v4();
  final startTime = DateTime.now().toUtc().add(const Duration(minutes: 30));
  final endTime = startTime.add(const Duration(minutes: 30));

  await apiClient.createEvent(
    bookUuid: bookUuid,
    eventData: {
      'id': eventId,
      'record_uuid': recordUuid,
      'title': 'IT metadata fixture $suffix',
      'record_number': 'IT-$suffix',
      'record_name': 'IT Fixture $suffix',
      'record_phone': null,
      'event_types': const ['consultation'],
      'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
      'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
    },
    deviceId: config.deviceId,
    deviceToken: config.deviceToken,
  );

  return _ResolvedFixture(
    bookUuid: bookUuid,
    eventId: eventId,
    recordUuid: recordUuid,
    isTemporary: true,
  );
}

List<String> _parseEventTypes(dynamic value) {
  if (value == null) return const [];
  if (value is List) return value.map((e) => e.toString()).toList();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return [trimmed];
    }
    return [trimmed];
  }
  return [value.toString()];
}

Future<Map<String, dynamic>> _createTemporaryBook({
  required ApiClient apiClient,
  required _LiveServerConfig config,
  required String name,
}) async {
  final createdBook = await apiClient.createBook(
    name: name,
    deviceId: config.deviceId,
    deviceToken: config.deviceToken,
  );
  return createdBook;
}

Map<String, dynamic> _buildSingleStrokeNotePayload({
  required String eventId,
  required int version,
}) {
  final pagesData = jsonEncode({
    'formatVersion': 2,
    'pages': [
      [
        {
          'id': 'stroke-$eventId',
          'event_uuid': eventId,
          'points': [
            {'x': 10.0, 'y': 10.0},
            {'x': 20.0, 'y': 20.0},
          ],
          'stroke_width': 2.0,
          'color': 4278190080,
          'stroke_type': 'pen',
        },
      ],
    ],
    'erasedStrokesByEvent': <String, List<String>>{},
  });

  return {'pagesData': pagesData, 'version': version};
}

void main() {
  final config = _LiveServerConfig.fromEnv();
  final shouldSkip = config == null;
  final skipReason =
      'Set SN_TEST_BASE_URL, SN_TEST_DEVICE_ID, SN_TEST_DEVICE_TOKEN '
      '(env or .env.integration). '
      'Optionally set SN_TEST_BOOK_UUID, SN_TEST_EVENT_ID, SN_TEST_RECORD_UUID '
      'to use existing fixture; otherwise test auto-creates temporary data.';

  test(
    'EVENT-INTEG-001: event metadata update persists on live server',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final httpClient = HttpClientFactory.createClient();

      _ResolvedFixture? fixture;
      List<String> originalEventTypes = const [];
      String? originalPhone;

      try {
        fixture = await _resolveFixture(apiClient: apiClient, config: live);

        final originalEvent = await apiClient.fetchEvent(
          bookUuid: fixture.bookUuid,
          eventId: fixture.eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(originalEvent, isNotNull);

        if (!fixture.isTemporary && !live.autoCleanupFixture) {
          originalEventTypes = _parseEventTypes(
            originalEvent!['event_types'] ?? originalEvent['eventTypes'],
          );
          final originalRecord = await _fetchBookScopedRecord(
            httpClient: httpClient,
            config: live,
            fixture: fixture,
          );
          originalPhone = originalRecord['phone']?.toString();
        }

        final targetEventTypes =
            originalEventTypes.length == 2 &&
                originalEventTypes.contains('surgery') &&
                originalEventTypes.contains('followUp')
            ? const ['consultation']
            : const ['surgery', 'followUp'];
        final targetPhone =
            '09${(DateTime.now().millisecondsSinceEpoch % 100000000).toString().padLeft(8, '0')}';

        await apiClient.updateEvent(
          bookUuid: fixture.bookUuid,
          eventId: fixture.eventId,
          eventData: {'eventTypes': targetEventTypes},
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        await apiClient.updateRecord(
          recordUuid: fixture.recordUuid,
          recordData: {'phone': targetPhone},
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final refreshedEvent = await apiClient.fetchEvent(
          bookUuid: fixture.bookUuid,
          eventId: fixture.eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(refreshedEvent, isNotNull);

        final refreshedEventTypes = _parseEventTypes(
          refreshedEvent!['event_types'] ?? refreshedEvent['eventTypes'],
        );
        expect(refreshedEventTypes.toSet(), equals(targetEventTypes.toSet()));

        final refreshedRecord = await _fetchBookScopedRecord(
          httpClient: httpClient,
          config: live,
          fixture: fixture,
        );
        expect(refreshedRecord['phone'], targetPhone);
      } finally {
        try {
          if (fixture != null &&
              (fixture.isTemporary || live.autoCleanupFixture)) {
            await apiClient.deleteBook(
              bookUuid: fixture.bookUuid,
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            );
          } else if (fixture != null) {
            if (originalEventTypes.isNotEmpty) {
              await apiClient.updateEvent(
                bookUuid: fixture.bookUuid,
                eventId: fixture.eventId,
                eventData: {'eventTypes': originalEventTypes},
                deviceId: live.deviceId,
                deviceToken: live.deviceToken,
              );
            }
            await apiClient.updateRecord(
              recordUuid: fixture.recordUuid,
              recordData: {'phone': originalPhone},
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            );
          }
        } catch (_) {
          // Best-effort cleanup only for shared test environments.
        }
        apiClient.dispose();
        httpClient.close();
      }
    },
    skip: shouldSkip ? skipReason : false,
  );

  test(
    'EVENT-INTEG-002: no-record-number note remains visible for old/new events after reschedule',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final uuid = const Uuid();
      String? bookUuid;

      try {
        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await _createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT no-rn reschedule $suffix',
        );
        bookUuid = _pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final oldEventId = uuid.v4();
        final recordUuid = uuid.v4();
        final startTime = DateTime.now().toUtc().add(
          const Duration(minutes: 15),
        );
        final endTime = startTime.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': oldEventId,
            'record_uuid': recordUuid,
            'title': 'IT no-rn fixture $suffix',
            'record_number': '',
            'record_name': 'IT NoRN $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        // Save initial note on the original event.
        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: oldEventId,
          noteData: _buildSingleStrokeNotePayload(
            eventId: oldEventId,
            version: 1,
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final beforeRescheduleOldNote = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: oldEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(beforeRescheduleOldNote, isNotNull);
        expect(beforeRescheduleOldNote!.recordUuid, recordUuid);
        expect(beforeRescheduleOldNote.isNotEmpty, isTrue);

        // Reschedule event and capture new event ID from server response.
        final rescheduled = await apiClient.rescheduleEvent(
          bookUuid: bookUuid,
          eventId: oldEventId,
          newStartTime: startTime.add(const Duration(hours: 2)),
          newEndTime: endTime.add(const Duration(hours: 2)),
          reason: 'integration reschedule',
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final oldEvent = rescheduled['oldEvent'] as Map<String, dynamic>;
        final newEvent = rescheduled['newEvent'] as Map<String, dynamic>;
        final newEventId = _pickString(newEvent, keys: const ['id']);

        expect(_pickString(oldEvent, keys: const ['id']), oldEventId);
        expect(oldEvent['is_removed'], isTrue);
        expect(oldEvent['new_event_id'], newEventId);
        expect(newEvent['original_event_id'], oldEventId);

        // Verify both old and new events can fetch the same note.
        final oldEventNote = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: oldEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final newEventNote = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: newEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        expect(oldEventNote, isNotNull);
        expect(newEventNote, isNotNull);
        expect(oldEventNote!.recordUuid, recordUuid);
        expect(newEventNote!.recordUuid, recordUuid);
        expect(oldEventNote.pages, isNotEmpty);
        expect(newEventNote.pages, isNotEmpty);
      } finally {
        // Always cleanup to avoid polluting shared integration environments.
        if (bookUuid != null) {
          try {
            await apiClient.deleteBook(
              bookUuid: bookUuid,
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            );
          } catch (_) {
            // Best-effort cleanup.
          }
        }
        apiClient.dispose();
      }
    },
    skip: shouldSkip ? skipReason : false,
  );

  test(
    'EVENT-INTEG-003: has_note stays false for new event that only shares an existing record note',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final uuid = const Uuid();
      String? bookUuid;

      try {
        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await _createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT has-note scope $suffix',
        );
        bookUuid = _pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final recordUuid = uuid.v4();
        final eventWithNoteId = uuid.v4();
        final eventWithoutNoteId = uuid.v4();
        final startA = DateTime.now().toUtc().add(const Duration(minutes: 20));
        final endA = startA.add(const Duration(minutes: 30));
        final startB = startA.add(const Duration(hours: 1));
        final endB = startB.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventWithNoteId,
            'record_uuid': recordUuid,
            'title': 'IT noted event $suffix',
            'record_number': 'HASNOTE-$suffix',
            'record_name': 'IT HasNote $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startA.millisecondsSinceEpoch ~/ 1000,
            'end_time': endA.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: eventWithNoteId,
          noteData: _buildSingleStrokeNotePayload(
            eventId: eventWithNoteId,
            version: 1,
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventWithoutNoteId,
            'record_uuid': recordUuid,
            'title': 'IT plain event $suffix',
            'record_number': 'HASNOTE-$suffix',
            'record_name': 'IT HasNote $suffix',
            'record_phone': null,
            'event_types': const ['followUp'],
            'start_time': startB.millisecondsSinceEpoch ~/ 1000,
            'end_time': endB.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final notedEvent = await apiClient.fetchEvent(
          bookUuid: bookUuid,
          eventId: eventWithNoteId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final plainEvent = await apiClient.fetchEvent(
          bookUuid: bookUuid,
          eventId: eventWithoutNoteId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(notedEvent, isNotNull);
        expect(plainEvent, isNotNull);
        expect(
          _pickBool(notedEvent!, keys: const ['has_note', 'hasNote']),
          isTrue,
        );
        expect(
          _pickBool(plainEvent!, keys: const ['has_note', 'hasNote']),
          isFalse,
        );

        final listedEvents = await apiClient.fetchEventsByDateRange(
          bookUuid: bookUuid,
          startDate: startA.subtract(const Duration(hours: 1)),
          endDate: endB.add(const Duration(hours: 1)),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final listedNoted = listedEvents.firstWhere(
          (event) => _pickString(event, keys: const ['id']) == eventWithNoteId,
        );
        final listedPlain = listedEvents.firstWhere(
          (event) =>
              _pickString(event, keys: const ['id']) == eventWithoutNoteId,
        );

        expect(
          _pickBool(listedNoted, keys: const ['has_note', 'hasNote']),
          isTrue,
        );
        expect(
          _pickBool(listedPlain, keys: const ['has_note', 'hasNote']),
          isFalse,
        );
      } finally {
        if (bookUuid != null) {
          try {
            await apiClient.deleteBook(
              bookUuid: bookUuid,
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            );
          } catch (_) {
            // Best-effort cleanup.
          }
        }
        apiClient.dispose();
      }
    },
    skip: shouldSkip ? skipReason : false,
  );
}
