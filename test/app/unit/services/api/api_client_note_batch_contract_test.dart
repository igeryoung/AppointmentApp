@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';

void main() {
  test(
    'API-CLIENT-NOTE-BATCH-001: batchFetchNotes() posts record_uuids payload with device headers',
    () async {
      final requests = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request);
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        expect(payload['record_uuids'], ['record-1', 'record-2']);
        expect(payload.containsKey('eventIds'), isFalse);

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': true,
            'notes': [
              {'id': 'note-1', 'record_uuid': 'record-1', 'version': 2},
            ],
          }),
        );
        await request.response.close();
      });

      final apiClient = ApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );

      try {
        final notes = await apiClient.batchFetchNotes(
          recordUuids: const ['record-1', 'record-2'],
          deviceId: 'device-1',
          deviceToken: 'token-1',
        );

        expect(notes, hasLength(1));
        expect(notes.single['record_uuid'], 'record-1');
        expect(requests, hasLength(1));
        expect(requests.single.method, 'POST');
        expect(requests.single.uri.path, '/api/notes/batch');
        expect(requests.single.headers.value('x-device-id'), 'device-1');
        expect(requests.single.headers.value('x-device-token'), 'token-1');
      } finally {
        apiClient.dispose();
        await server.close(force: true);
      }
    },
  );

  test(
    'API-CLIENT-NOTE-BATCH-002: batchFetchNotes() surfaces non-200 response as ApiException',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 400;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'success': false, 'message': 'Missing record_uuids'}),
        );
        await request.response.close();
      });

      final apiClient = ApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );

      try {
        await expectLater(
          () => apiClient.batchFetchNotes(
            recordUuids: const ['record-1'],
            deviceId: 'device-1',
            deviceToken: 'token-1',
          ),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
          ),
        );
      } finally {
        apiClient.dispose();
        await server.close(force: true);
      }
    },
  );
}
