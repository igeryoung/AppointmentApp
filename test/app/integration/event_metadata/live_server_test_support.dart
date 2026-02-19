import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

const String liveServerSkipReason =
    'Set SN_TEST_BASE_URL, SN_TEST_DEVICE_ID, SN_TEST_DEVICE_TOKEN '
    '(env or .env.integration). '
    'Optionally set SN_TEST_BOOK_UUID, SN_TEST_EVENT_ID, SN_TEST_RECORD_UUID '
    'to use existing fixture; otherwise test auto-creates temporary data.';

class LiveServerConfig {
  final String baseUrl;
  final String deviceId;
  final String deviceToken;
  final String registrationPassword;
  final String? bookUuid;
  final String? eventId;
  final String? recordUuid;
  final bool autoCleanupFixture;

  const LiveServerConfig({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    required this.registrationPassword,
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

  static LiveServerConfig? fromEnv() {
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
    final registrationPassword = resolve('SN_TEST_REGISTRATION_PASSWORD');
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

    return LiveServerConfig(
      baseUrl: baseUrl,
      deviceId: deviceId,
      deviceToken: deviceToken,
      registrationPassword: registrationPassword.isEmpty
          ? 'password'
          : registrationPassword,
      bookUuid: bookUuid.isEmpty ? null : bookUuid,
      eventId: eventId.isEmpty ? null : eventId,
      recordUuid: recordUuid.isEmpty ? null : recordUuid,
      autoCleanupFixture: autoCleanupFixture,
    );
  }
}

class LiveDeviceCredentials {
  final String deviceId;
  final String deviceToken;

  const LiveDeviceCredentials({
    required this.deviceId,
    required this.deviceToken,
  });
}

class ResolvedFixture {
  final String bookUuid;
  final String eventId;
  final String recordUuid;
  final bool isTemporary;

  const ResolvedFixture({
    required this.bookUuid,
    required this.eventId,
    required this.recordUuid,
    required this.isTemporary,
  });
}

Object skipForMissingConfig(LiveServerConfig? config) {
  return config == null ? liveServerSkipReason : false;
}

Future<Map<String, dynamic>> fetchBookScopedRecord({
  required http.Client httpClient,
  required LiveServerConfig config,
  required ResolvedFixture fixture,
}) async {
  return fetchBookScopedRecordWithCredentials(
    httpClient: httpClient,
    baseUrl: config.baseUrl,
    bookUuid: fixture.bookUuid,
    recordUuid: fixture.recordUuid,
    deviceId: config.deviceId,
    deviceToken: config.deviceToken,
  );
}

Future<Map<String, dynamic>> fetchBookScopedRecordWithCredentials({
  required http.Client httpClient,
  required String baseUrl,
  required String bookUuid,
  required String recordUuid,
  required String deviceId,
  required String deviceToken,
}) async {
  final response = await httpClient.get(
    Uri.parse('$baseUrl/api/books/$bookUuid/records/$recordUuid'),
    headers: {
      'Content-Type': 'application/json',
      'X-Device-ID': deviceId,
      'X-Device-Token': deviceToken,
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

Future<LiveDeviceCredentials> registerTemporaryDevice({
  required ApiClient apiClient,
  required LiveServerConfig config,
  String deviceNamePrefix = 'IT second device',
}) async {
  final suffix = DateTime.now().millisecondsSinceEpoch.toString();
  final registration = await apiClient.registerDevice(
    deviceName: '$deviceNamePrefix $suffix',
    password: config.registrationPassword,
    platform: 'ios',
  );

  return LiveDeviceCredentials(
    deviceId: pickString(
      registration,
      keys: const ['deviceId', 'device_id', 'id'],
    ),
    deviceToken: pickString(
      registration,
      keys: const ['deviceToken', 'device_token', 'token'],
    ),
  );
}

String pickString(Map<String, dynamic> source, {required List<String> keys}) {
  for (final key in keys) {
    final value = source[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  throw StateError('Missing expected keys: ${keys.join(', ')}');
}

bool pickBool(Map<String, dynamic> source, {required List<String> keys}) {
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

Future<ResolvedFixture> resolveFixture({
  required ApiClient apiClient,
  required LiveServerConfig config,
}) async {
  if (config.bookUuid != null &&
      config.eventId != null &&
      config.recordUuid != null) {
    try {
      final existing = await apiClient.fetchEvent(
        bookUuid: config.bookUuid!,
        eventId: config.eventId!,
        deviceId: config.deviceId,
        deviceToken: config.deviceToken,
      );
      if (existing != null) {
        return ResolvedFixture(
          bookUuid: config.bookUuid!,
          eventId: config.eventId!,
          recordUuid: config.recordUuid!,
          isTemporary: false,
        );
      }
    } catch (_) {
      // If shared fixture is inaccessible in this environment, fallback to
      // temporary fixture so integration contracts remain executable.
    }
  }

  final suffix = DateTime.now().millisecondsSinceEpoch.toString();
  final uuid = const Uuid();

  final createdBook = await apiClient.createBook(
    name: 'IT metadata $suffix',
    deviceId: config.deviceId,
    deviceToken: config.deviceToken,
  );
  final bookUuid = pickString(
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

  return ResolvedFixture(
    bookUuid: bookUuid,
    eventId: eventId,
    recordUuid: recordUuid,
    isTemporary: true,
  );
}

List<String> parseEventTypes(dynamic value) {
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

Future<Map<String, dynamic>> createTemporaryBook({
  required ApiClient apiClient,
  required LiveServerConfig config,
  required String name,
}) async {
  final createdBook = await apiClient.createBook(
    name: name,
    deviceId: config.deviceId,
    deviceToken: config.deviceToken,
  );
  return createdBook;
}

Map<String, dynamic> buildSingleStrokeNotePayload({
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

Map<String, dynamic> buildNotePayloadFromExisting({
  required Map<String, dynamic> noteMap,
  required int version,
}) {
  return {'pagesData': noteMap['pages_data'], 'version': version};
}
