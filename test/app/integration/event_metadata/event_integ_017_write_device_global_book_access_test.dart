import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void main() {}

void registerEventInteg017({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-017: write devices can fetch and create events across books without explicit membership grants',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final uuid = const Uuid();
      String? bookUuid;
      LiveDeviceCredentials? deviceB;

      try {
        deviceB = await provisionTemporaryDevice(
          apiClient: apiClient,
          config: live,
          deviceRole: liveDeviceRoleWrite,
          deviceNamePrefix: 'IT global writer',
        );

        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT global access $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final seededEventId = uuid.v4();
        final seededRecordUuid = uuid.v4();
        final startTime = DateTime.now().toUtc().add(
          const Duration(minutes: 20),
        );
        final endTime = startTime.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': seededEventId,
            'record_uuid': seededRecordUuid,
            'title': 'IT seeded global access $suffix',
            'record_number': 'GA-$suffix',
            'record_name': 'IT Global Access $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final fetched = await apiClient.fetchEventsByDateRange(
          bookUuid: bookUuid,
          startDate: startTime.subtract(const Duration(days: 1)),
          endDate: endTime.add(const Duration(days: 1)),
          deviceId: deviceB.deviceId,
          deviceToken: deviceB.deviceToken,
        );
        expect(
          fetched.any(
            (event) => pickString(event, keys: const ['id']) == seededEventId,
          ),
          isTrue,
        );

        final createdByDeviceB = await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': uuid.v4(),
            'record_uuid': uuid.v4(),
            'title': 'IT created by global writer $suffix',
            'record_number': 'GB-$suffix',
            'record_name': 'IT Global Writer $suffix',
            'record_phone': null,
            'event_types': const ['follow_up'],
            'start_time':
                endTime.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                1000,
            'end_time':
                endTime.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
                1000,
          },
          deviceId: deviceB.deviceId,
          deviceToken: deviceB.deviceToken,
        );

        expect(
          pickString(createdByDeviceB, keys: const ['bookUuid', 'book_uuid']),
          bookUuid,
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
            // Best-effort cleanup.
          }
        }
        try {
          await cleanupTemporaryDevice(
            apiClient: apiClient,
            credentials: deviceB,
          );
        } catch (_) {
          // Best-effort cleanup.
        }
        apiClient.dispose();
      }
    },
    timeout: liveServerTestTimeout,
    skip: skipForMissingConfig(config),
  );
}
