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

  const _LiveServerConfig({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    this.bookUuid,
    this.eventId,
    this.recordUuid,
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

        if (!fixture.isTemporary) {
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
          if (fixture != null && fixture.isTemporary) {
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
}
