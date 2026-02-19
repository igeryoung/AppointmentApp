import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

Map<String, String> _loadEnvFile(String path) {
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

void _printUsage() {
  stdout.writeln('Usage:');
  stdout.writeln(
    '  dart run tool/clean_heavy_data_book.dart [book-uuid] [--dry-run]',
  );
  stdout.writeln('');
  stdout.writeln('Resolve order for book UUID:');
  stdout.writeln('  1) CLI positional arg');
  stdout.writeln('  2) SN_HEAVY_BOOK_UUID');
  stdout.writeln('  3) SN_TEST_BOOK_UUID');
  stdout.writeln('');
  stdout.writeln('Required env (or SN_TEST_ENV_FILE/.env.integration):');
  stdout.writeln('  SN_TEST_BASE_URL');
  stdout.writeln('  SN_TEST_DEVICE_ID');
  stdout.writeln('  SN_TEST_DEVICE_TOKEN');
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

Future<void> main(List<String> args) async {
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

  final dryRun = args.contains('--dry-run');
  final wantsHelp = args.contains('--help') || args.contains('-h');
  final positionalArgs = args
      .where((a) => !a.startsWith('--'))
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .toList();

  if (wantsHelp) {
    _printUsage();
    return;
  }

  final cliBookUuid = positionalArgs.isNotEmpty ? positionalArgs.first : '';
  final envBookUuid = _resolveValue(
    key: 'SN_HEAVY_BOOK_UUID',
    fileEnv: fileEnv,
  );
  final fallbackBookUuid = _resolveValue(
    key: 'SN_TEST_BOOK_UUID',
    fileEnv: fileEnv,
  );
  final bookUuid = cliBookUuid.isNotEmpty
      ? cliBookUuid
      : (envBookUuid.isNotEmpty ? envBookUuid : fallbackBookUuid);

  if (baseUrl.isEmpty || deviceId.isEmpty || deviceToken.isEmpty) {
    stderr.writeln(
      'Missing required config. Set SN_TEST_BASE_URL, SN_TEST_DEVICE_ID, '
      'SN_TEST_DEVICE_TOKEN (env or $envFilePath).',
    );
    exitCode = 64;
    return;
  }
  if (bookUuid.isEmpty) {
    stderr.writeln(
      'Missing target book UUID. Provide CLI arg or set '
      'SN_HEAVY_BOOK_UUID/SN_TEST_BOOK_UUID.',
    );
    _printUsage();
    exitCode = 64;
    return;
  }

  final client = _buildClient(baseUrl);
  try {
    final getUri = Uri.parse('$baseUrl/api/books/$bookUuid');
    final preflight = await client
        .get(
          getUri,
          headers: _headers(deviceId: deviceId, deviceToken: deviceToken),
        )
        .timeout(const Duration(seconds: 20));

    if (preflight.statusCode == 404) {
      stdout.writeln('Book already missing/deleted: $bookUuid');
      return;
    }
    if (preflight.statusCode != 200) {
      throw StateError(
        'Preflight GET failed: ${preflight.statusCode} ${preflight.body}',
      );
    }

    if (dryRun) {
      final decoded = jsonDecode(preflight.body) as Map<String, dynamic>;
      final book = decoded['book'];
      final name = book is Map<String, dynamic>
          ? (book['name'] ?? '').toString()
          : '';
      stdout.writeln('Dry run only. Book is deletable:');
      stdout.writeln('bookUuid=$bookUuid');
      stdout.writeln('name=$name');
      return;
    }

    final deleteUri = Uri.parse('$baseUrl/api/books/$bookUuid');
    final deleted = await client
        .delete(
          deleteUri,
          headers: _headers(deviceId: deviceId, deviceToken: deviceToken),
        )
        .timeout(const Duration(seconds: 20));

    if (deleted.statusCode == 200) {
      stdout.writeln('Deleted heavy test book: $bookUuid');
      return;
    }
    if (deleted.statusCode == 404) {
      stdout.writeln('Book already missing/deleted: $bookUuid');
      return;
    }

    throw StateError('Delete failed: ${deleted.statusCode} ${deleted.body}');
  } catch (e) {
    stderr.writeln('Failed to clean heavy fixture book: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}
