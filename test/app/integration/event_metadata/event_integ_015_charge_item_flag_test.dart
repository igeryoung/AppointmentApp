import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void main() {}

void registerEventInteg015({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-015A: create event after charge-item creation keeps charge item and sets has_charge_items',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final role = await resolveLiveDeviceRole(
        apiClient: apiClient,
        config: live,
      );
      String? bookUuid;

      try {
        if (isReadOnlyDeviceRole(role)) {
          final fixture = await resolveFixture(
            apiClient: apiClient,
            config: live,
            deviceRole: role,
            requireWrite: false,
          );

          await expectReadOnlyDeviceFailure(
            () => apiClient.saveChargeItem(
              recordUuid: fixture.recordUuid,
              chargeItemData: {
                'itemName': 'IT read-only block',
                'itemPrice': 100,
                'receivedAmount': 0,
                'bookUuid': fixture.bookUuid,
              },
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            ),
          );
          return;
        }

        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await apiClient.createBook(
          name: 'IT charge-flag A $suffix',
          bookPassword: live.bookPassword,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final record = await apiClient.getOrCreateRecord(
          recordNumber: 'IT-CI-$suffix',
          name: 'IT Charge Flag A',
          phone: null,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final recordUuid = pickString(
          record,
          keys: const ['record_uuid', 'recordUuid'],
        );

        final savedChargeItem = await apiClient.saveChargeItem(
          recordUuid: recordUuid,
          chargeItemData: {
            'itemName': 'Pre Event Charge Item',
            'itemPrice': 1300,
            'receivedAmount': 0,
            'bookUuid': bookUuid,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(pickString(savedChargeItem, keys: const ['id']), isNotEmpty);

        final start = DateTime.now().toUtc().add(const Duration(minutes: 20));
        final end = start.add(const Duration(minutes: 30));
        final createdEvent = await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': const Uuid().v4(),
            'record_uuid': recordUuid,
            'title': 'IT charge-flag A event',
            'record_number': 'IT-CI-$suffix',
            'record_name': 'IT Charge Flag A',
            'event_types': const ['consultation'],
            'start_time': start.millisecondsSinceEpoch ~/ 1000,
            'end_time': end.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        expect(
          pickBool(
            createdEvent,
            keys: const ['has_charge_items', 'hasChargeItems'],
          ),
          isTrue,
        );

        final eventId = pickString(createdEvent, keys: const ['id']);
        final refreshedEvent = await apiClient.fetchEvent(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(refreshedEvent, isNotNull);
        expect(
          pickBool(
            refreshedEvent!,
            keys: const ['has_charge_items', 'hasChargeItems'],
          ),
          isTrue,
        );

        final chargeItems = await apiClient.fetchChargeItems(
          recordUuid: recordUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(
          chargeItems.any(
            (item) =>
                (item['itemName'] ?? item['item_name'])?.toString() ==
                'Pre Event Charge Item',
          ),
          isTrue,
        );
      } finally {
        if (bookUuid != null) {
          try {
            await apiClient.deleteBook(
              bookUuid: bookUuid,
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            );
          } catch (_) {
            // Best-effort cleanup only.
          }
        }
        apiClient.dispose();
      }
    },
    timeout: liveServerTestTimeout,
    skip: skipForMissingConfig(config),
  );

  test(
    'EVENT-INTEG-015B: add charge item to existing event flips has_charge_items true',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final role = await resolveLiveDeviceRole(
        apiClient: apiClient,
        config: live,
      );
      String? bookUuid;

      try {
        if (isReadOnlyDeviceRole(role)) {
          final fixture = await resolveFixture(
            apiClient: apiClient,
            config: live,
            deviceRole: role,
            requireWrite: false,
          );

          await expectReadOnlyDeviceFailure(
            () => apiClient.saveChargeItem(
              recordUuid: fixture.recordUuid,
              chargeItemData: {
                'eventId': fixture.eventId,
                'itemName': 'IT read-only block existing',
                'itemPrice': 150,
                'receivedAmount': 0,
                'bookUuid': fixture.bookUuid,
              },
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            ),
          );
          return;
        }

        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final uuid = const Uuid();

        final createdBook = await apiClient.createBook(
          name: 'IT charge-flag B $suffix',
          bookPassword: live.bookPassword,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final eventId = uuid.v4();
        final recordUuid = uuid.v4();
        final start = DateTime.now().toUtc().add(const Duration(minutes: 30));
        final end = start.add(const Duration(minutes: 30));

        final createdEvent = await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventId,
            'record_uuid': recordUuid,
            'title': 'IT charge-flag B event',
            'record_number': 'IT-CIB-$suffix',
            'record_name': 'IT Charge Flag B',
            'event_types': const ['consultation'],
            'start_time': start.millisecondsSinceEpoch ~/ 1000,
            'end_time': end.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(
          pickBool(
            createdEvent,
            keys: const ['has_charge_items', 'hasChargeItems'],
          ),
          isFalse,
        );

        final savedChargeItem = await apiClient.saveChargeItem(
          recordUuid: recordUuid,
          chargeItemData: {
            'eventId': eventId,
            'itemName': 'Existing Event Charge Item',
            'itemPrice': 2200,
            'receivedAmount': 0,
            'bookUuid': bookUuid,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(pickString(savedChargeItem, keys: const ['id']), isNotEmpty);
        expect(
          (savedChargeItem['eventId'] ?? savedChargeItem['event_id'])
              ?.toString(),
          eventId,
        );

        final refreshedEvent = await apiClient.fetchEvent(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(refreshedEvent, isNotNull);
        expect(
          pickBool(
            refreshedEvent!,
            keys: const ['has_charge_items', 'hasChargeItems'],
          ),
          isTrue,
        );

        final chargeItems = await apiClient.fetchChargeItems(
          recordUuid: recordUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(
          chargeItems.any(
            (item) =>
                (item['itemName'] ?? item['item_name'])?.toString() ==
                    'Existing Event Charge Item' &&
                (item['eventId'] ?? item['event_id'])?.toString() == eventId,
          ),
          isTrue,
        );
      } finally {
        if (bookUuid != null) {
          try {
            await apiClient.deleteBook(
              bookUuid: bookUuid,
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            );
          } catch (_) {
            // Best-effort cleanup only.
          }
        }
        apiClient.dispose();
      }
    },
    timeout: liveServerTestTimeout,
    skip: skipForMissingConfig(config),
  );
}
