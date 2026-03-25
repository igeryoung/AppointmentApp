import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void main() {}

int? _pickIntOrNull(Map<String, dynamic> source, {required List<String> keys}) {
  for (final key in keys) {
    if (!source.containsKey(key)) {
      continue;
    }

    final value = source[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }

    final parsed = int.tryParse(value?.toString().trim() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }

  return null;
}

int _nextVersion(Map<String, dynamic> source) {
  return (_pickIntOrNull(source, keys: const ['version']) ?? 1) + 1;
}

List<Map<String, dynamic>> _findChargeItemsById(
  List<Map<String, dynamic>> items,
  String chargeItemId,
) {
  return items
      .where((item) => (item['id'] ?? '').toString() == chargeItemId)
      .toList();
}

List<Map<String, dynamic>> _buildPaidItems(List<int> amounts) {
  final paidItems = <Map<String, dynamic>>[];
  for (var index = 0; index < amounts.length; index++) {
    paidItems.add({
      'id': 'payment-${index + 1}',
      'amount': amounts[index],
      'paidDate': '2026-03-${(20 + index).toString().padLeft(2, '0')}',
    });
  }
  return paidItems;
}

Map<String, dynamic> _buildChargeItemPayload({
  required String id,
  required String eventId,
  required String itemName,
  required int itemPrice,
  required List<Map<String, dynamic>> paidItems,
  required String bookUuid,
  int? version,
}) {
  final receivedAmount = paidItems.fold<int>(
    0,
    (sum, item) => sum + ((item['amount'] as num?)?.toInt() ?? 0),
  );
  return {
    'id': id,
    'eventId': eventId,
    'itemName': itemName,
    'itemPrice': itemPrice,
    'receivedAmount': receivedAmount,
    'paidItems': paidItems,
    'bookUuid': bookUuid,
    if (version != null) 'version': version,
  };
}

void registerEventInteg016({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-016: updating charge item paid amount persists partial and full payment on live server',
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
                'id': const Uuid().v4(),
                'eventId': fixture.eventId,
                'itemName': 'IT read-only paid update block',
                'itemPrice': 400,
                'receivedAmount': 200,
                'paidItems': _buildPaidItems(const [200]),
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
        final eventId = uuid.v4();
        final recordUuid = uuid.v4();
        final chargeItemId = uuid.v4();

        final createdBook = await apiClient.createBook(
          name: 'IT charge-paid $suffix',
          bookPassword: live.bookPassword,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final start = DateTime.now().toUtc().add(const Duration(minutes: 40));
        final end = start.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventId,
            'record_uuid': recordUuid,
            'title': 'IT charge paid event',
            'record_number': 'IT-CIP-$suffix',
            'record_name': 'IT Charge Paid',
            'event_types': const ['consultation'],
            'start_time': start.millisecondsSinceEpoch ~/ 1000,
            'end_time': end.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final createdChargeItem = await apiClient.saveChargeItem(
          recordUuid: recordUuid,
          chargeItemData: _buildChargeItemPayload(
            id: chargeItemId,
            eventId: eventId,
            itemName: 'Progress Payment',
            itemPrice: 900,
            paidItems: const [],
            bookUuid: bookUuid,
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(pickString(createdChargeItem, keys: const ['id']), chargeItemId);

        final partialUpdate = await apiClient.saveChargeItem(
          recordUuid: recordUuid,
          chargeItemData: _buildChargeItemPayload(
            id: chargeItemId,
            eventId: eventId,
            itemName: 'Progress Payment',
            itemPrice: 900,
            paidItems: _buildPaidItems(const [400]),
            bookUuid: bookUuid,
            version: _nextVersion(createdChargeItem),
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final chargeItemsAfterPartial = await apiClient.fetchChargeItems(
          recordUuid: recordUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final partialMatches = _findChargeItemsById(
          chargeItemsAfterPartial,
          chargeItemId,
        );
        expect(partialMatches, hasLength(1));
        expect(
          _pickIntOrNull(
            partialMatches.single,
            keys: const ['receivedAmount', 'received_amount'],
          ),
          400,
        );
        expect(
          _pickIntOrNull(
            partialMatches.single,
            keys: const ['itemPrice', 'item_price'],
          ),
          900,
        );
        expect(partialMatches.single['paidItems'], hasLength(1));

        final finalUpdate = await apiClient.saveChargeItem(
          recordUuid: recordUuid,
          chargeItemData: _buildChargeItemPayload(
            id: chargeItemId,
            eventId: eventId,
            itemName: 'Progress Payment',
            itemPrice: 900,
            paidItems: _buildPaidItems(const [400, 500]),
            bookUuid: bookUuid,
            version: _nextVersion(partialUpdate),
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final chargeItemsAfterFull = await apiClient.fetchChargeItems(
          recordUuid: recordUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final fullMatches = _findChargeItemsById(
          chargeItemsAfterFull,
          chargeItemId,
        );
        expect(fullMatches, hasLength(1));

        final fullReceivedAmount = _pickIntOrNull(
          fullMatches.single,
          keys: const ['receivedAmount', 'received_amount'],
        );
        final fullItemPrice = _pickIntOrNull(
          fullMatches.single,
          keys: const ['itemPrice', 'item_price'],
        );

        expect(fullReceivedAmount, 900);
        expect(fullItemPrice, 900);
        expect(fullMatches.single['paidItems'], hasLength(2));
        expect(
          fullReceivedAmount,
          fullItemPrice,
          reason:
              'Server should persist the full paid amount so the app computes '
              'the item as paid after refresh.',
        );
        expect(
          _pickIntOrNull(finalUpdate, keys: const ['version']),
          greaterThanOrEqualTo(
            _pickIntOrNull(partialUpdate, keys: const ['version']) ?? 1,
          ),
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
