import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:uuid/uuid.dart';

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
}) {
  final fromProcess = Platform.environment[key]?.trim();
  if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
  final fromFile = fileEnv[key]?.trim();
  if (fromFile != null && fromFile.isNotEmpty) return fromFile;
  return '';
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

Map<String, dynamic> _buildNotePayload500({
  required String eventId,
  required int seed,
}) {
  final random = Random(seed);
  final strokes = <Map<String, dynamic>>[];

  for (var i = 0; i < 500; i++) {
    final points = <Map<String, double>>[];
    var dx = 20 + random.nextInt(320);
    var dy = 20 + random.nextInt(520);

    for (var p = 0; p < 4; p++) {
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

    strokes.add(<String, dynamic>{
      'id': 's-$seed-$i',
      'event_uuid': eventId,
      'points': points,
      'stroke_width': 1.6,
      'color': 0xFF111827,
      'stroke_type': 0,
    });
  }

  return <String, dynamic>{
    'formatVersion': 2,
    'pages': <List<Map<String, dynamic>>>[strokes],
    'erasedStrokesByEvent': <String, List<String>>{},
  };
}

Map<String, num> _stats(List<int> values) {
  if (values.isEmpty) return const {};
  final sorted = List<int>.from(values)..sort();
  final sum = values.fold<int>(0, (a, b) => a + b);
  int percentile(double p) {
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }

  return <String, num>{
    'count': values.length,
    'avg_ms': sum / values.length,
    'min_ms': sorted.first,
    'p50_ms': percentile(0.50),
    'p90_ms': percentile(0.90),
    'p95_ms': percentile(0.95),
    'max_ms': sorted.last,
  };
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
  final samples = _resolveInt(
    key: 'SN_BENCH_SAMPLES',
    fileEnv: fileEnv,
    fallback: 20,
  );

  if (baseUrl.isEmpty || deviceId.isEmpty || deviceToken.isEmpty) {
    stderr.writeln(
      'Missing required config: SN_TEST_BASE_URL, SN_TEST_DEVICE_ID, SN_TEST_DEVICE_TOKEN',
    );
    exitCode = 64;
    return;
  }

  final client = _buildClient(baseUrl);
  final uuid = const Uuid();
  String? bookUuid;

  try {
    final createBookResponse = await client.post(
      Uri.parse('$baseUrl/api/books'),
      headers: _headers(deviceId: deviceId, deviceToken: deviceToken),
      body: jsonEncode(<String, dynamic>{
        'name': 'heavy-test benchmark ${DateTime.now().toUtc().toIso8601String()}',
      }),
    );

    if (createBookResponse.statusCode != 200) {
      throw StateError(
        'Create book failed: ${createBookResponse.statusCode} ${createBookResponse.body}',
      );
    }

    final created = jsonDecode(createBookResponse.body) as Map<String, dynamic>;
    final book = created['book'] as Map<String, dynamic>;
    bookUuid = (book['bookUuid'] ?? book['book_uuid']).toString();

    final eventMs = <int>[];
    final noteMs = <int>[];
    final totalMs = <int>[];

    for (var i = 0; i < samples; i++) {
      final eventId = uuid.v4();
      final recordUuid = uuid.v4();
      final start = DateTime.now().toUtc().add(Duration(minutes: i + 1));
      final end = start.add(const Duration(minutes: 30));

      final swEvent = Stopwatch()..start();
      final createEventResponse = await client.post(
        Uri.parse('$baseUrl/api/books/$bookUuid/events'),
        headers: _headers(deviceId: deviceId, deviceToken: deviceToken),
        body: jsonEncode(<String, dynamic>{
          'id': eventId,
          'record_uuid': recordUuid,
          'title': 'heavy-test bench',
          'record_number': 'BENCH-${i + 1}',
          'record_name': 'Bench ${(i + 1)}',
          'record_phone': null,
          'event_types': const <String>['consultation'],
          'start_time': start.millisecondsSinceEpoch ~/ 1000,
          'end_time': end.millisecondsSinceEpoch ~/ 1000,
        }),
      );
      swEvent.stop();

      if (createEventResponse.statusCode != 200) {
        throw StateError(
          'Create event failed at sample ${i + 1}: '
          '${createEventResponse.statusCode} ${createEventResponse.body}',
        );
      }

      final notePayload = _buildNotePayload500(eventId: eventId, seed: i + 1);
      final swNote = Stopwatch()..start();
      final saveNoteResponse = await client.post(
        Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId/note'),
        headers: _headers(deviceId: deviceId, deviceToken: deviceToken),
        body: jsonEncode(<String, dynamic>{
          'pagesData': jsonEncode(notePayload),
          'version': 1,
        }),
      );
      swNote.stop();

      if (saveNoteResponse.statusCode != 200) {
        throw StateError(
          'Save note failed at sample ${i + 1}: '
          '${saveNoteResponse.statusCode} ${saveNoteResponse.body}',
        );
      }

      final e = swEvent.elapsedMilliseconds;
      final n = swNote.elapsedMilliseconds;
      eventMs.add(e);
      noteMs.add(n);
      totalMs.add(e + n);
    }

    final result = <String, dynamic>{
      'samples': samples,
      'event_create': _stats(eventMs),
      'save_note_500_strokes': _stats(noteMs),
      'combined_event_plus_note': _stats(totalMs),
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  } catch (e) {
    stderr.writeln('Benchmark failed: $e');
    exitCode = 1;
  } finally {
    if (bookUuid != null) {
      try {
        await client.delete(
          Uri.parse('$baseUrl/api/books/$bookUuid'),
          headers: _headers(deviceId: deviceId, deviceToken: deviceToken),
        );
      } catch (_) {
        // best effort cleanup
      }
    }
    client.close();
  }
}
