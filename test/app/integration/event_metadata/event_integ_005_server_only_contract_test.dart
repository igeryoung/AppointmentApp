import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/http_client_factory.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void registerEventInteg005({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-005: events endpoint rejects requests without required device headers',
    () async {
      final live = config!;
      final httpClient = HttpClientFactory.createClient();
      final now = DateTime.now().toUtc();
      final startDate = now.subtract(const Duration(days: 1)).toIso8601String();
      final endDate = now.add(const Duration(days: 1)).toIso8601String();
      final uri = Uri.parse(
        '${live.baseUrl}/api/books/header-contract-book/events?startDate=$startDate&endDate=$endDate',
      );

      try {
        final response = await httpClient.get(
          uri,
          headers: const {'Content-Type': 'application/json'},
        );
        expect(response.statusCode, 401);

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['message'], contains('Missing device credentials'));
      } finally {
        httpClient.close();
      }
    },
    skip: skipForMissingConfig(config),
  );

  test(
    'EVENT-INTEG-006: repeated fetch after server update returns latest event metadata',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final uuid = const Uuid();
      String? bookUuid;

      try {
        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT server-only refresh $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final eventId = uuid.v4();
        final recordUuid = uuid.v4();
        final startTime = DateTime.now().toUtc().add(
          const Duration(minutes: 15),
        );
        final endTime = startTime.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventId,
            'record_uuid': recordUuid,
            'title': 'IT refresh fixture $suffix',
            'record_number': 'REFRESH-$suffix',
            'record_name': 'IT Refresh $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final firstFetch = await apiClient.fetchEventsByDateRange(
          bookUuid: bookUuid,
          startDate: startTime.subtract(const Duration(hours: 1)),
          endDate: endTime.add(const Duration(hours: 1)),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final firstEvent = firstFetch.firstWhere(
          (event) => pickString(event, keys: const ['id']) == eventId,
        );
        final firstTypes = parseEventTypes(
          firstEvent['event_types'] ?? firstEvent['eventTypes'],
        );
        expect(firstTypes, contains('consultation'));

        const updatedTypes = ['followUp', 'surgery'];
        await apiClient.updateEvent(
          bookUuid: bookUuid,
          eventId: eventId,
          eventData: {'eventTypes': updatedTypes},
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final secondFetch = await apiClient.fetchEventsByDateRange(
          bookUuid: bookUuid,
          startDate: startTime.subtract(const Duration(hours: 1)),
          endDate: endTime.add(const Duration(hours: 1)),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final secondEvent = secondFetch.firstWhere(
          (event) => pickString(event, keys: const ['id']) == eventId,
        );
        final secondTypes = parseEventTypes(
          secondEvent['event_types'] ?? secondEvent['eventTypes'],
        );
        expect(secondTypes.toSet(), updatedTypes.toSet());
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
    skip: skipForMissingConfig(config),
  );
}
