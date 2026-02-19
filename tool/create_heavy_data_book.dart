import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:uuid/uuid.dart';

const int _defaultDaysBefore = 45;
const int _defaultDaysAfter = 45;
const int _defaultStartHour = 9;
const int _defaultEndHour = 21; // exclusive
const int _defaultEventsPerSlot = 3;
const double _defaultRecordRatio = 0.5;
const int _defaultTimezoneOffsetHours = 8;
const double _defaultOpenEndRate = 0.35;

// Requirement: 80% notes are heavy (300~500 strokes per page), 20% empty.
const double _defaultRichNoteRatio = 0.8;
const int _defaultMinStrokesPerPage = 300;
const int _defaultMaxStrokesPerPage = 500;

// Best-effort charge-item seeding ratio. Uses API if endpoint exists.
const double _defaultChargeRecordRatio = 0.3;

// Use app-supported non-"other" types only.
const List<String> _eventTypePool = <String>[
  'consultation',
  'surgery',
  'followUp',
  'emergency',
  'checkUp',
  'treatment',
];

const List<String> _namePrefixPool = <String>[
  'Alex',
  'Blake',
  'Casey',
  'Drew',
  'Evan',
  'Flynn',
  'Gray',
  'Hayden',
  'Jordan',
  'Kai',
  'Lane',
  'Morgan',
  'Noel',
  'Parker',
  'Quinn',
  'Reese',
  'Sage',
  'Taylor',
];

const List<String> _chargeItemNamePool = <String>[
  'Consult Fee',
  'Lab Fee',
  'Procedure Fee',
  'Medication',
  'Injection Fee',
  'Supply Fee',
  'Follow-up Fee',
];

const List<int> _colorPool = <int>[
  0xFF111827,
  0xFF1D4ED8,
  0xFF0F766E,
  0xFF7C3AED,
  0xFFBE123C,
  0xFFB45309,
];

class _RecordPlan {
  final String recordUuid;
  final String recordNumber;
  final String recordName;
  final String recordPhone;
  final bool richNote;
  final bool hasChargeItems;

  const _RecordPlan({
    required this.recordUuid,
    required this.recordNumber,
    required this.recordName,
    required this.recordPhone,
    required this.richNote,
    required this.hasChargeItems,
  });
}

class _EventPlan {
  final String eventId;
  final DateTime startTimeUtc;
  final DateTime? endTimeUtc;
  final String recordUuid;
  final String recordNumber;
  final String recordName;
  final String recordPhone;
  final String title;
  final List<String> eventTypes;
  final bool hasChargeItems;

  const _EventPlan({
    required this.eventId,
    required this.startTimeUtc,
    required this.endTimeUtc,
    required this.recordUuid,
    required this.recordNumber,
    required this.recordName,
    required this.recordPhone,
    required this.title,
    required this.eventTypes,
    required this.hasChargeItems,
  });
}

class _NoteBuildResult {
  final Map<String, dynamic> payload;
  final int pageCount;
  final int strokeCount;

  const _NoteBuildResult({
    required this.payload,
    required this.pageCount,
    required this.strokeCount,
  });
}

Map<String, String> _loadEnvFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return const {};

  final map = <String, String>{};
  for (final rawLine in file.readAsLinesSync()) {
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

String _resolveValue({
  required String key,
  required Map<String, String> fileEnv,
  String fallback = '',
}) {
  final fromProcess = Platform.environment[key]?.trim();
  if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
  final fromFile = fileEnv[key]?.trim();
  if (fromFile != null && fromFile.isNotEmpty) return fromFile;
  return fallback;
}

int _resolveInt({
  required String key,
  required Map<String, String> fileEnv,
  required int fallback,
}) {
  final raw = _resolveValue(key: key, fileEnv: fileEnv);
  if (raw.isEmpty) return fallback;
  return int.tryParse(raw) ?? fallback;
}

double _resolveDouble({
  required String key,
  required Map<String, String> fileEnv,
  required double fallback,
}) {
  final raw = _resolveValue(key: key, fileEnv: fileEnv);
  if (raw.isEmpty) return fallback;
  return double.tryParse(raw) ?? fallback;
}

http.Client _buildClient(String baseUrl) {
  if (!baseUrl.startsWith('https://')) {
    return http.Client();
  }

  final ioClient = HttpClient();
  final allowBadCert =
      (Platform.environment['SN_TEST_ALLOW_BAD_CERT'] ?? '1') != '0';
  if (allowBadCert) {
    ioClient.badCertificateCallback = (_, __, ___) => true;
  }
  return IOClient(ioClient);
}

Map<String, String> _headers({
  required String deviceId,
  required String deviceToken,
}) {
  return <String, String>{
    'Content-Type': 'application/json',
    'X-Device-ID': deviceId,
    'X-Device-Token': deviceToken,
  };
}

Future<http.Response> _postJsonRaw({
  required http.Client client,
  required Uri uri,
  required Map<String, dynamic> body,
  required String deviceId,
  required String deviceToken,
  Duration timeout = const Duration(seconds: 30),
}) {
  return client
      .post(
        uri,
        headers: _headers(deviceId: deviceId, deviceToken: deviceToken),
        body: jsonEncode(body),
      )
      .timeout(timeout);
}

Future<Map<String, dynamic>> _postJson200({
  required http.Client client,
  required Uri uri,
  required Map<String, dynamic> body,
  required String deviceId,
  required String deviceToken,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final response = await _postJsonRaw(
    client: client,
    uri: uri,
    body: body,
    deviceId: deviceId,
    deviceToken: deviceToken,
    timeout: timeout,
  );

  if (response.statusCode != 200) {
    throw StateError(
      'POST ${uri.path} failed: ${response.statusCode} ${response.body}',
    );
  }

  final decoded = jsonDecode(response.body);
  if (decoded is Map<String, dynamic>) return decoded;
  throw StateError('Unexpected response payload for ${uri.path}');
}

String _pickString(Map<String, dynamic> map, {required List<String> keys}) {
  for (final key in keys) {
    final value = map[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  throw StateError('Missing expected keys: ${keys.join(', ')}');
}

List<DateTime> _buildSlotStartTimesUtc({
  required DateTime baseDateLocal,
  required int daysBefore,
  required int daysAfter,
  required int startHour,
  required int endHour,
  required int eventsPerSlot,
  required int timezoneOffsetHours,
}) {
  final starts = <DateTime>[];

  for (var dayOffset = -daysBefore; dayOffset <= daysAfter; dayOffset++) {
    final dayLocal = baseDateLocal.add(Duration(days: dayOffset));
    for (var hour = startHour; hour < endHour; hour++) {
      for (var i = 0; i < eventsPerSlot; i++) {
        final minute = (60 / eventsPerSlot * i).floor();
        final localWallClock = DateTime.utc(
          dayLocal.year,
          dayLocal.month,
          dayLocal.day,
          hour,
          minute,
        );
        starts.add(
          localWallClock.subtract(Duration(hours: timezoneOffsetHours)),
        );
      }
    }
  }

  return starts;
}

List<int> _assignRecordIndexes({
  required int totalEvents,
  required int totalRecords,
  required Random random,
}) {
  final indexes = <int>[];
  for (var i = 0; i < totalRecords; i++) {
    indexes.add(i);
  }
  while (indexes.length < totalEvents) {
    indexes.add(random.nextInt(totalRecords));
  }
  for (var i = indexes.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = indexes[i];
    indexes[i] = indexes[j];
    indexes[j] = tmp;
  }
  return indexes;
}

List<bool> _buildFlagList({
  required int total,
  required int trueCount,
  required Random random,
}) {
  final cappedTrue = trueCount.clamp(0, total);
  final flags = List<bool>.filled(total, false);
  for (var i = 0; i < cappedTrue; i++) {
    flags[i] = true;
  }
  flags.shuffle(random);
  return flags;
}

String _randomRecordName(Random random, int index) {
  final prefix = _namePrefixPool[random.nextInt(_namePrefixPool.length)];
  final suffix = (index + 1).toString().padLeft(4, '0');
  return '$prefix Heavy $suffix';
}

String _randomRecordPhone(Random random) {
  final area = 200 + random.nextInt(800);
  final mid = 100 + random.nextInt(900);
  final end = 1000 + random.nextInt(9000);
  return '+1-$area-$mid-$end';
}

String _randomEventTitle(Random random) {
  final t = _eventTypePool[random.nextInt(_eventTypePool.length)];
  return 'Heavy ${t.toLowerCase()}';
}

List<String> _randomEventTypes(Random random) {
  final copied = List<String>.from(_eventTypePool)..shuffle(random);
  final count = 1 + random.nextInt(2); // 1..2
  return copied.take(count).toList();
}

String _randomChargeItemName(Random random) {
  return _chargeItemNamePool[random.nextInt(_chargeItemNamePool.length)];
}

Map<String, dynamic> _randomStroke({
  required Random random,
  required String strokeId,
  required String eventId,
}) {
  final pointCount = 2 + random.nextInt(4); // 2..5
  final points = <Map<String, double>>[];

  var dx = 20 + random.nextInt(320);
  var dy = 20 + random.nextInt(520);

  for (var i = 0; i < pointCount; i++) {
    dx += random.nextInt(41) - 20;
    dy += random.nextInt(41) - 20;
    if (dx < 0) dx = 0;
    if (dy < 0) dy = 0;
    points.add(<String, double>{
      'dx': dx.toDouble(),
      'dy': dy.toDouble(),
      'pressure': 1.0,
    });
  }

  return <String, dynamic>{
    'id': strokeId,
    'event_uuid': eventId,
    'points': points,
    'stroke_width': 1.2 + (random.nextInt(25) / 10.0),
    'color': _colorPool[random.nextInt(_colorPool.length)],
    // App parser reads numeric index; 0=pen, 1=highlighter.
    'stroke_type': random.nextBool() ? 0 : 1,
  };
}

_NoteBuildResult _buildNotePayload({
  required Random random,
  required List<String> eventIds,
  required Uuid uuid,
  required bool richNote,
  required int minStrokesPerPage,
  required int maxStrokesPerPage,
}) {
  final pageCount = 1 + random.nextInt(5); // 1..5
  final pages = List<List<Map<String, dynamic>>>.generate(
    pageCount,
    (_) => <Map<String, dynamic>>[],
  );

  if (!richNote) {
    return _NoteBuildResult(
      payload: <String, dynamic>{
        'formatVersion': 2,
        'pages': pages,
        'erasedStrokesByEvent': <String, List<String>>{},
      },
      pageCount: pageCount,
      strokeCount: 0,
    );
  }

  // Ensure every event has at least one visible stroke in this shared note.
  for (final eventId in eventIds) {
    final pageIndex = random.nextInt(pageCount);
    pages[pageIndex].add(
      _randomStroke(
        random: random,
        strokeId: 'anchor-${uuid.v4()}',
        eventId: eventId,
      ),
    );
  }

  var totalStrokes = eventIds.length;
  final span = maxStrokesPerPage - minStrokesPerPage + 1;

  for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
    final target = minStrokesPerPage + random.nextInt(span);
    while (pages[pageIndex].length < target) {
      final eventId = eventIds[random.nextInt(eventIds.length)];
      pages[pageIndex].add(
        _randomStroke(
          random: random,
          strokeId: 'rich-${uuid.v4()}',
          eventId: eventId,
        ),
      );
      totalStrokes++;
    }
  }

  return _NoteBuildResult(
    payload: <String, dynamic>{
      'formatVersion': 2,
      'pages': pages,
      'erasedStrokesByEvent': <String, List<String>>{},
    },
    pageCount: pageCount,
    strokeCount: totalStrokes,
  );
}

Future<int> _seedChargeItemsBestEffort({
  required http.Client client,
  required String baseUrl,
  required String deviceId,
  required String deviceToken,
  required String recordUuid,
  required List<String> eventIds,
  required Random random,
  required Uuid uuid,
  required bool endpointAvailable,
}) async {
  if (!endpointAvailable) return 0;

  final itemCount = 1 + random.nextInt(3); // 1..3 per seeded record
  var created = 0;

  for (var i = 0; i < itemCount; i++) {
    final itemPrice = 300 + random.nextInt(3701); // 300..4000
    final received = random.nextBool() ? 0 : random.nextInt(itemPrice + 1);
    final eventId = eventIds[random.nextInt(eventIds.length)];
    final itemName = _randomChargeItemName(random);
    final now = DateTime.now().toUtc();
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

    final body = <String, dynamic>{
      // snake_case
      'id': uuid.v4(),
      'record_uuid': recordUuid,
      'event_id': eventId,
      'item_name': itemName,
      'item_price': itemPrice,
      'received_amount': received,
      'version': 1,
      'is_deleted': false,
      'created_at': nowSeconds,
      'updated_at': nowSeconds,
      // camelCase fallback
      'recordUuid': recordUuid,
      'eventId': eventId,
      'itemName': itemName,
      'itemPrice': itemPrice,
      'receivedAmount': received,
      'isDeleted': false,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };

    final response = await _postJsonRaw(
      client: client,
      uri: Uri.parse('$baseUrl/api/records/$recordUuid/charge-items'),
      body: body,
      deviceId: deviceId,
      deviceToken: deviceToken,
    );

    if (response.statusCode == 200) {
      created++;
      continue;
    }

    if (response.statusCode == 404) {
      return -1; // endpoint not available in this server build
    }

    // Keep best-effort behavior for heavy generation.
  }

  return created;
}

Future<void> main() async {
  final envFilePath =
      Platform.environment['SN_TEST_ENV_FILE']?.trim().isNotEmpty == true
      ? Platform.environment['SN_TEST_ENV_FILE']!.trim()
      : '.env.integration';
  final fileEnv = _loadEnvFile(envFilePath);

  final baseUrl = _resolveValue(key: 'SN_TEST_BASE_URL', fileEnv: fileEnv);
  final deviceId = _resolveValue(key: 'SN_TEST_DEVICE_ID', fileEnv: fileEnv);
  final deviceToken = _resolveValue(
    key: 'SN_TEST_DEVICE_TOKEN',
    fileEnv: fileEnv,
  );
  final daysBefore = _resolveInt(
    key: 'SN_HEAVY_DAYS_BEFORE',
    fileEnv: fileEnv,
    fallback: _defaultDaysBefore,
  );
  final daysAfter = _resolveInt(
    key: 'SN_HEAVY_DAYS_AFTER',
    fileEnv: fileEnv,
    fallback: _defaultDaysAfter,
  );
  final startHour = _resolveInt(
    key: 'SN_HEAVY_SLOT_START_HOUR',
    fileEnv: fileEnv,
    fallback: _defaultStartHour,
  );
  final endHour = _resolveInt(
    key: 'SN_HEAVY_SLOT_END_HOUR',
    fileEnv: fileEnv,
    fallback: _defaultEndHour,
  );
  final eventsPerSlot = _resolveInt(
    key: 'SN_HEAVY_EVENTS_PER_SLOT',
    fileEnv: fileEnv,
    fallback: _defaultEventsPerSlot,
  );
  final recordRatio = _resolveDouble(
    key: 'SN_HEAVY_RECORD_RATIO',
    fileEnv: fileEnv,
    fallback: _defaultRecordRatio,
  ).clamp(0.01, 1.0);
  final timezoneOffsetHours = _resolveInt(
    key: 'SN_HEAVY_TIMEZONE_OFFSET_HOURS',
    fileEnv: fileEnv,
    fallback: _defaultTimezoneOffsetHours,
  );
  final openEndRate = _resolveDouble(
    key: 'SN_HEAVY_OPEN_END_RATE',
    fileEnv: fileEnv,
    fallback: _defaultOpenEndRate,
  ).clamp(0.0, 1.0);
  final richNoteRatio = _resolveDouble(
    key: 'SN_HEAVY_RICH_NOTE_RATIO',
    fileEnv: fileEnv,
    fallback: _defaultRichNoteRatio,
  ).clamp(0.0, 1.0);
  final minStrokesPerPage = _resolveInt(
    key: 'SN_HEAVY_NOTE_STROKES_MIN',
    fileEnv: fileEnv,
    fallback: _defaultMinStrokesPerPage,
  );
  final maxStrokesPerPage = _resolveInt(
    key: 'SN_HEAVY_NOTE_STROKES_MAX',
    fileEnv: fileEnv,
    fallback: _defaultMaxStrokesPerPage,
  );
  final chargeRecordRatio = _resolveDouble(
    key: 'SN_HEAVY_CHARGE_RECORD_RATIO',
    fileEnv: fileEnv,
    fallback: _defaultChargeRecordRatio,
  ).clamp(0.0, 1.0);
  final seedRaw = _resolveValue(key: 'SN_HEAVY_RANDOM_SEED', fileEnv: fileEnv);
  final randomSeed = seedRaw.isEmpty
      ? DateTime.now().millisecondsSinceEpoch
      : (int.tryParse(seedRaw) ?? DateTime.now().millisecondsSinceEpoch);

  if (baseUrl.isEmpty || deviceId.isEmpty || deviceToken.isEmpty) {
    stderr.writeln(
      'Missing required config. Set SN_TEST_BASE_URL, SN_TEST_DEVICE_ID, '
      'SN_TEST_DEVICE_TOKEN (env or $envFilePath).',
    );
    exitCode = 64;
    return;
  }

  if (daysBefore < 0 || daysAfter < 0) {
    stderr.writeln('SN_HEAVY_DAYS_BEFORE / SN_HEAVY_DAYS_AFTER must be >= 0.');
    exitCode = 64;
    return;
  }
  if (startHour < 0 ||
      startHour > 23 ||
      endHour < 1 ||
      endHour > 24 ||
      endHour <= startHour) {
    stderr.writeln(
      'Invalid slot hours. Expect 0 <= start < end <= 24. '
      'Current: start=$startHour, end=$endHour',
    );
    exitCode = 64;
    return;
  }
  if (eventsPerSlot <= 0 || eventsPerSlot > 12) {
    stderr.writeln('SN_HEAVY_EVENTS_PER_SLOT must be between 1 and 12.');
    exitCode = 64;
    return;
  }
  if (timezoneOffsetHours < -12 || timezoneOffsetHours > 14) {
    stderr.writeln(
      'SN_HEAVY_TIMEZONE_OFFSET_HOURS must be between -12 and +14.',
    );
    exitCode = 64;
    return;
  }
  if (minStrokesPerPage < 0 || maxStrokesPerPage < minStrokesPerPage) {
    stderr.writeln(
      'Invalid note stroke bounds: min=$minStrokesPerPage max=$maxStrokesPerPage',
    );
    exitCode = 64;
    return;
  }

  final random = Random(randomSeed);
  final uuid = const Uuid();
  final client = _buildClient(baseUrl);

  final nowLocalPseudo = DateTime.now().toUtc().add(
    Duration(hours: timezoneOffsetHours),
  );
  final todayLocal = DateTime.utc(
    nowLocalPseudo.year,
    nowLocalPseudo.month,
    nowLocalPseudo.day,
  );

  final slotStarts = _buildSlotStartTimesUtc(
    baseDateLocal: todayLocal,
    daysBefore: daysBefore,
    daysAfter: daysAfter,
    startHour: startHour,
    endHour: endHour,
    eventsPerSlot: eventsPerSlot,
    timezoneOffsetHours: timezoneOffsetHours,
  );

  final totalEvents = slotStarts.length;
  final totalRecords = max(1, (totalEvents * recordRatio).floor());
  final recordIndexes = _assignRecordIndexes(
    totalEvents: totalEvents,
    totalRecords: totalRecords,
    random: random,
  );
  final recordNumberRunPrefix =
      'H${(randomSeed % 1000000).toString().padLeft(6, '0')}';

  final richRecordCount = (totalRecords * richNoteRatio).round();
  final chargeRecordCount = (totalRecords * chargeRecordRatio).round();
  final richFlags = _buildFlagList(
    total: totalRecords,
    trueCount: richRecordCount,
    random: random,
  );
  final chargeFlags = _buildFlagList(
    total: totalRecords,
    trueCount: chargeRecordCount,
    random: random,
  );

  final records = List<_RecordPlan>.generate(totalRecords, (i) {
    return _RecordPlan(
      recordUuid: uuid.v4(),
      recordNumber:
          '$recordNumberRunPrefix-${(i + 1).toString().padLeft(5, '0')}',
      recordName: _randomRecordName(random, i),
      recordPhone: _randomRecordPhone(random),
      richNote: richFlags[i],
      hasChargeItems: chargeFlags[i],
    );
  });

  try {
    stdout.writeln('Creating heavy test book...');
    final bookName =
        _resolveValue(key: 'SN_HEAVY_BOOK_NAME', fileEnv: fileEnv).isNotEmpty
        ? _resolveValue(key: 'SN_HEAVY_BOOK_NAME', fileEnv: fileEnv)
        : 'Heavy Test Book ${DateTime.now().toUtc().toIso8601String()}';

    final createdBook = await _postJson200(
      client: client,
      uri: Uri.parse('$baseUrl/api/books'),
      body: <String, dynamic>{'name': bookName},
      deviceId: deviceId,
      deviceToken: deviceToken,
    );

    final bookPayload = createdBook['book'] is Map<String, dynamic>
        ? createdBook['book'] as Map<String, dynamic>
        : createdBook;
    final bookUuid = _pickString(
      bookPayload,
      keys: const <String>['bookUuid', 'book_uuid', 'uuid'],
    );

    final eventPlans = <_EventPlan>[];
    final eventIdsByRecord = <String, List<String>>{};
    final totalSlots = (endHour - startHour) * (daysBefore + daysAfter + 1);

    stdout.writeln(
      'Generating $totalEvents events '
      '($totalSlots slots, $eventsPerSlot events/slot) '
      'with $totalRecords record_uuid values (seed=$randomSeed)...',
    );

    for (var i = 0; i < totalEvents; i++) {
      final record = records[recordIndexes[i]];
      final start = slotStarts[i];
      final isOpenEnded = random.nextDouble() < openEndRate;
      final end = isOpenEnded
          ? null
          : start.add(
              Duration(minutes: 20 + random.nextInt(11) * 10),
            ); // 20..120

      final eventId = uuid.v4();
      final event = _EventPlan(
        eventId: eventId,
        startTimeUtc: start,
        endTimeUtc: end,
        recordUuid: record.recordUuid,
        recordNumber: record.recordNumber,
        recordName: record.recordName,
        recordPhone: record.recordPhone,
        title: _randomEventTitle(random),
        eventTypes: _randomEventTypes(random),
        hasChargeItems: record.hasChargeItems,
      );
      eventPlans.add(event);
      eventIdsByRecord
          .putIfAbsent(event.recordUuid, () => <String>[])
          .add(eventId);
    }

    for (var i = 0; i < eventPlans.length; i++) {
      final event = eventPlans[i];
      await _postJson200(
        client: client,
        uri: Uri.parse('$baseUrl/api/books/$bookUuid/events'),
        body: <String, dynamic>{
          'id': event.eventId,
          'record_uuid': event.recordUuid,
          'title': event.title,
          'record_number': event.recordNumber,
          'record_name': event.recordName,
          'record_phone': event.recordPhone,
          'event_types': event.eventTypes,
          // Keep false on creation; charge-item API updates this flag
          // consistently once real charge rows are inserted.
          'has_charge_items': false,
          'start_time': event.startTimeUtc.millisecondsSinceEpoch ~/ 1000,
          'end_time': event.endTimeUtc?.millisecondsSinceEpoch == null
              ? null
              : event.endTimeUtc!.millisecondsSinceEpoch ~/ 1000,
        },
        deviceId: deviceId,
        deviceToken: deviceToken,
      );

      if ((i + 1) % 200 == 0 || i + 1 == eventPlans.length) {
        stdout.writeln('  events created: ${i + 1}/${eventPlans.length}');
      }
    }

    var noteCount = 0;
    var richNoteCount = 0;
    var emptyNoteCount = 0;
    var totalPages = 0;
    var totalStrokes = 0;

    final recordByUuid = <String, _RecordPlan>{
      for (final r in records) r.recordUuid: r,
    };

    final recordUuids = eventIdsByRecord.keys.toList();
    stdout.writeln('Creating record-shared notes (80% rich, 20% empty)...');

    for (var i = 0; i < recordUuids.length; i++) {
      final recordUuid = recordUuids[i];
      final recordPlan = recordByUuid[recordUuid]!;
      final eventIds = eventIdsByRecord[recordUuid]!;
      final noteBuild = _buildNotePayload(
        random: random,
        eventIds: eventIds,
        uuid: uuid,
        richNote: recordPlan.richNote,
        minStrokesPerPage: minStrokesPerPage,
        maxStrokesPerPage: maxStrokesPerPage,
      );
      final anchorEventId = eventIds.first;

      await _postJson200(
        client: client,
        uri: Uri.parse(
          '$baseUrl/api/books/$bookUuid/events/$anchorEventId/note',
        ),
        body: <String, dynamic>{
          'pagesData': jsonEncode(noteBuild.payload),
          'version': 1,
        },
        deviceId: deviceId,
        deviceToken: deviceToken,
      );
      noteCount++;
      totalPages += noteBuild.pageCount;
      totalStrokes += noteBuild.strokeCount;
      if (recordPlan.richNote) {
        richNoteCount++;
      } else {
        emptyNoteCount++;
      }

      if ((i + 1) % 100 == 0 || i + 1 == recordUuids.length) {
        stdout.writeln('  notes created: ${i + 1}/${recordUuids.length}');
      }
    }

    var chargeEndpointAvailable = true;
    var chargeSeededRecords = 0;
    var chargeSeededItems = 0;

    stdout.writeln('Seeding charge items (best effort)...');
    for (var i = 0; i < recordUuids.length; i++) {
      if (!chargeEndpointAvailable) break;

      final recordUuid = recordUuids[i];
      final recordPlan = recordByUuid[recordUuid]!;
      if (!recordPlan.hasChargeItems) continue;

      final result = await _seedChargeItemsBestEffort(
        client: client,
        baseUrl: baseUrl,
        deviceId: deviceId,
        deviceToken: deviceToken,
        recordUuid: recordUuid,
        eventIds: eventIdsByRecord[recordUuid]!,
        random: random,
        uuid: uuid,
        endpointAvailable: chargeEndpointAvailable,
      );

      if (result == -1) {
        chargeEndpointAvailable = false;
        stdout.writeln(
          '  charge endpoint unavailable (/api/records/{recordUuid}/charge-items).',
        );
        break;
      }

      if (result > 0) {
        chargeSeededRecords++;
        chargeSeededItems += result;
      }
    }

    stdout.writeln('');
    stdout.writeln('Heavy fixture created successfully.');
    stdout.writeln('Book UUID: $bookUuid');
    stdout.writeln('Events: ${eventPlans.length}');
    stdout.writeln('Record UUIDs: $totalRecords');
    stdout.writeln('Notes: $noteCount');
    stdout.writeln('Rich notes: $richNoteCount');
    stdout.writeln('Empty notes: $emptyNoteCount');
    stdout.writeln('Total note pages: $totalPages');
    stdout.writeln('Total note strokes: $totalStrokes');
    stdout.writeln('Charge seeded records: $chargeSeededRecords');
    stdout.writeln('Charge seeded items: $chargeSeededItems');
    stdout.writeln('');
    stdout.writeln('Range: ${-daysBefore}d to +$daysAfter d (inclusive)');
    stdout.writeln(
      'Timezone offset for slot generation: UTC$timezoneOffsetHours',
    );
    stdout.writeln(
      'Slots: ${startHour.toString().padLeft(2, '0')}:00'
      ' to ${endHour.toString().padLeft(2, '0')}:00 (hourly), '
      '$eventsPerSlot events/slot',
    );
    stdout.writeln('');
    stdout.writeln('Optional export for reuse:');
    stdout.writeln('SN_HEAVY_BOOK_UUID=$bookUuid');
    stdout.writeln('SN_HEAVY_RANDOM_SEED=$randomSeed');
  } catch (e) {
    stderr.writeln('Failed to create heavy fixture: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}
