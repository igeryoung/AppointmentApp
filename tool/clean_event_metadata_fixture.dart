import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

Map<String, String> _loadEnvFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return const {};

  final map = <String, String>{};
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final idx = line.indexOf('=');
    if (idx <= 0) continue;
    map[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
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

http.Client _buildClient(String baseUrl) {
  if (!baseUrl.startsWith('https://')) return http.Client();

  final allowBadCert =
      (Platform.environment['SN_TEST_ALLOW_BAD_CERT'] ?? '1') != '0';
  final ioClient = HttpClient();
  if (allowBadCert) {
    ioClient.badCertificateCallback = (_, __, ___) => true;
  }
  return IOClient(ioClient);
}

Future<void> main() async {
  final envFilePath =
      Platform.environment['SN_TEST_ENV_FILE']?.trim().isNotEmpty == true
      ? Platform.environment['SN_TEST_ENV_FILE']!.trim()
      : '.env.integration';
  final fileEnv = _loadEnvFile(envFilePath);

  final baseUrl = _resolveValue(key: 'SN_TEST_BASE_URL', fileEnv: fileEnv);
  final registrationPassword = _resolveValue(
    key: 'SN_TEST_REGISTRATION_PASSWORD',
    fileEnv: fileEnv,
  );

  if (baseUrl.isEmpty) {
    stderr.writeln(
      'Missing required config. Set SN_TEST_BASE_URL (env or $envFilePath).',
    );
    exitCode = 64;
    return;
  }

  final client = _buildClient(baseUrl);
  try {
    final response = await client
        .post(
          Uri.parse('$baseUrl/api/test-fixtures/live-event-metadata/cleanup'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'password': registrationPassword.isEmpty
                ? 'password'
                : registrationPassword,
            'fixture': {
              'bookUuid': _resolveValue(
                key: 'SN_TEST_BOOK_UUID',
                fileEnv: fileEnv,
              ),
              'eventId': _resolveValue(
                key: 'SN_TEST_EVENT_ID',
                fileEnv: fileEnv,
              ),
              'recordUuid': _resolveValue(
                key: 'SN_TEST_RECORD_UUID',
                fileEnv: fileEnv,
              ),
            },
            'devices': {
              'writeDeviceId':
                  _resolveValue(
                    key: 'SN_TEST_WRITE_DEVICE_ID',
                    fileEnv: fileEnv,
                  ).isEmpty
                  ? _resolveValue(key: 'SN_TEST_DEVICE_ID', fileEnv: fileEnv)
                  : _resolveValue(
                      key: 'SN_TEST_WRITE_DEVICE_ID',
                      fileEnv: fileEnv,
                    ),
              'readDeviceId': _resolveValue(
                key: 'SN_TEST_READ_DEVICE_ID',
                fileEnv: fileEnv,
              ),
            },
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      stderr.writeln(
        'Fixture cleanup API failed: ${response.statusCode} ${response.body}',
      );
      exitCode = 1;
      return;
    }

    stdout.writeln('Deleted integration fixture data and devices.');
  } catch (e) {
    stderr.writeln('Failed to clean integration fixture data: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}
