import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/http_client_factory.dart';

import 'live_server_test_support.dart';

void registerEventInteg001({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-001: event metadata update persists on live server',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final httpClient = HttpClientFactory.createClient();

      ResolvedFixture? fixture;
      List<String> originalEventTypes = const [];
      String? originalPhone;

      try {
        fixture = await resolveFixture(apiClient: apiClient, config: live);

        final originalEvent = await apiClient.fetchEvent(
          bookUuid: fixture.bookUuid,
          eventId: fixture.eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(originalEvent, isNotNull);

        if (!fixture.isTemporary && !live.autoCleanupFixture) {
          originalEventTypes = parseEventTypes(
            originalEvent!['event_types'] ?? originalEvent['eventTypes'],
          );
          final originalRecord = await fetchBookScopedRecord(
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

        final refreshedEventTypes = parseEventTypes(
          refreshedEvent!['event_types'] ?? refreshedEvent['eventTypes'],
        );
        expect(refreshedEventTypes.toSet(), equals(targetEventTypes.toSet()));

        final refreshedRecord = await fetchBookScopedRecord(
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
    skip: skipForMissingConfig(config),
  );
}
