@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/services/api_client.dart';

void main() {
  test(
    'API-CLIENT-EVENT-001: fetchEventsByDateRange sends required device headers and supports event model mapping',
    () async {
      final requests = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': true,
            'events': [
              {
                'id': 'event-1',
                'book_uuid': 'book-1',
                'record_uuid': 'record-1',
                'record_name': 'Alice',
                'record_number': '001',
                'event_types': '["consultation","followUp"]',
                'has_charge_items': true,
                'start_time': 1760058000,
                'end_time': 1760059800,
                'created_at': 1760057000,
                'updated_at': 1760057100,
                'is_removed': false,
                'is_checked': true,
                'has_note': true,
                'version': 3,
              },
            ],
          }),
        );
        await request.response.close();
      });

      final apiClient = ApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final startDate = DateTime.utc(2026, 2, 10);
      final endDate = DateTime.utc(2026, 2, 12);

      try {
        final events = await apiClient.fetchEventsByDateRange(
          bookUuid: 'book-1',
          startDate: startDate,
          endDate: endDate,
          deviceId: 'device-1',
          deviceToken: 'token-1',
        );

        expect(requests.length, 1);
        final request = requests.single;
        expect(request.method, 'GET');
        expect(request.uri.path, '/api/books/book-1/events');
        expect(request.headers.value('x-device-id'), 'device-1');
        expect(request.headers.value('x-device-token'), 'token-1');
        expect(request.uri.queryParameters, contains('startDate'));
        expect(request.uri.queryParameters, contains('endDate'));

        final mappedEvent = Event.fromServerResponse(events.single);
        expect(mappedEvent.title, 'Alice');
        expect(mappedEvent.recordUuid, 'record-1');
        expect(mappedEvent.recordNumber, '001');
        expect(mappedEvent.eventTypes, const [
          EventType.consultation,
          EventType.followUp,
        ]);
        expect(mappedEvent.hasChargeItems, isTrue);
        expect(mappedEvent.hasNote, isTrue);
        expect(mappedEvent.isChecked, isTrue);
        expect(mappedEvent.version, 3);
      } finally {
        apiClient.dispose();
        await server.close(force: true);
      }
    },
  );

  test(
    'API-CLIENT-EVENT-002: updateEvent surfaces 409 as ApiConflictException with parsed serverVersion',
    () async {
      final requests = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request);
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        expect(payload['version'], 2);

        request.response.statusCode = 409;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'message': 'Version conflict',
            'serverVersion': 7,
            'serverEvent': {'id': 'event-1', 'version': 7},
          }),
        );
        await request.response.close();
      });

      final apiClient = ApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );

      try {
        await expectLater(
          () => apiClient.updateEvent(
            bookUuid: 'book-1',
            eventId: 'event-1',
            eventData: {'title': 'Edited', 'version': 2},
            deviceId: 'device-1',
            deviceToken: 'token-1',
          ),
          throwsA(
            isA<ApiConflictException>().having(
              (e) => e.serverVersion,
              'serverVersion',
              7,
            ),
          ),
        );

        expect(requests.length, 1);
        final request = requests.single;
        expect(request.method, 'PATCH');
        expect(request.uri.path, '/api/books/book-1/events/event-1');
        expect(request.headers.value('x-device-id'), 'device-1');
        expect(request.headers.value('x-device-token'), 'token-1');
      } finally {
        apiClient.dispose();
        await server.close(force: true);
      }
    },
  );
}
