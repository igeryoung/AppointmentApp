import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:schedule_note_app/services/http_client_factory.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void registerEventInteg011({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-011: multi-device metadata updates keep last writer value',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final httpClient = HttpClientFactory.createClient();
      final uuid = const Uuid();
      String? bookUuid;

      try {
        final deviceB = await registerTemporaryDevice(
          apiClient: apiClient,
          config: live,
        );
        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT multi-device metadata $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final eventId = uuid.v4();
        final recordUuid = uuid.v4();
        final startTime = DateTime.now().toUtc().add(
          const Duration(minutes: 20),
        );
        final endTime = startTime.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventId,
            'record_uuid': recordUuid,
            'title': 'IT metadata LWW $suffix',
            'record_number': 'LWW-$suffix',
            'record_name': 'IT LWW $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final phoneFromDeviceA =
            '09${(DateTime.now().millisecondsSinceEpoch % 100000000).toString().padLeft(8, '0')}';
        final phoneFromDeviceB =
            '09${((DateTime.now().millisecondsSinceEpoch + 7) % 100000000).toString().padLeft(8, '0')}';

        await apiClient.updateRecord(
          recordUuid: recordUuid,
          recordData: {'phone': phoneFromDeviceA},
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.updateRecord(
          recordUuid: recordUuid,
          recordData: {'phone': phoneFromDeviceB},
          deviceId: deviceB.deviceId,
          deviceToken: deviceB.deviceToken,
        );

        final refreshedRecord = await fetchBookScopedRecordWithCredentials(
          httpClient: httpClient,
          baseUrl: live.baseUrl,
          bookUuid: bookUuid,
          recordUuid: recordUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(refreshedRecord['phone'], phoneFromDeviceB);
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
        httpClient.close();
        apiClient.dispose();
      }
    },
    skip: skipForMissingConfig(config),
  );
}
