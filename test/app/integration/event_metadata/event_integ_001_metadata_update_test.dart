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
      final deviceRole = await resolveLiveDeviceRole(
        apiClient: apiClient,
        config: live,
      );

      ResolvedFixture? fixture;
      List<String> originalEventTypes = const [];
      String? originalPhone;

      try {
        fixture = await resolveFixture(
          apiClient: apiClient,
          config: live,
          deviceRole: deviceRole,
        );
        final resolvedFixture = fixture!;

        final originalEvent = await apiClient.fetchEvent(
          bookUuid: resolvedFixture.bookUuid,
          eventId: resolvedFixture.eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(originalEvent, isNotNull);

        originalEventTypes = parseEventTypes(
          originalEvent!['event_types'] ?? originalEvent['eventTypes'],
        );
        final originalRecord = await fetchBookScopedRecord(
          httpClient: httpClient,
          config: live,
          fixture: resolvedFixture,
        );
        originalPhone = originalRecord['phone']?.toString();

        if (isReadOnlyDeviceRole(deviceRole)) {
          await expectReadOnlyDeviceFailure(
            () => apiClient.updateEvent(
              bookUuid: resolvedFixture.bookUuid,
              eventId: resolvedFixture.eventId,
              eventData: {
                'eventTypes': const ['surgery', 'followUp'],
              },
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            ),
          );

          final unchangedEvent = await apiClient.fetchEvent(
            bookUuid: resolvedFixture.bookUuid,
            eventId: resolvedFixture.eventId,
            deviceId: live.deviceId,
            deviceToken: live.deviceToken,
          );
          expect(unchangedEvent, isNotNull);
          expect(
            parseEventTypes(
              unchangedEvent!['event_types'] ?? unchangedEvent['eventTypes'],
            ).toSet(),
            equals(originalEventTypes.toSet()),
          );

          final unchangedRecord = await fetchBookScopedRecord(
            httpClient: httpClient,
            config: live,
            fixture: resolvedFixture,
          );
          expect(unchangedRecord['phone']?.toString(), originalPhone);
          return;
        }

        if (!resolvedFixture.isTemporary && !live.autoCleanupFixture) {
          // Persist original shared-fixture state so the test can restore it.
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
          bookUuid: resolvedFixture.bookUuid,
          eventId: resolvedFixture.eventId,
          eventData: {'eventTypes': targetEventTypes},
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        await apiClient.updateRecord(
          recordUuid: resolvedFixture.recordUuid,
          recordData: {'phone': targetPhone},
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final refreshedEvent = await apiClient.fetchEvent(
          bookUuid: resolvedFixture.bookUuid,
          eventId: resolvedFixture.eventId,
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
          fixture: resolvedFixture,
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
