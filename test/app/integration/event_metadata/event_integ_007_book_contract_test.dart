import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void registerEventInteg007({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-007: book server contract covers create/list/update/archive/delete and bundle pull',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final uuid = const Uuid();
      String? bookUuid;

      try {
        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final created = await apiClient.createBook(
          name: 'IT book contract $suffix',
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        bookUuid = pickString(
          created,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );
        expect(bookUuid, isNotEmpty);

        final listedBefore = await apiClient.listServerBooks(
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(
          listedBefore.any(
            (book) =>
                pickString(
                  book,
                  keys: const ['bookUuid', 'book_uuid', 'uuid'],
                ) ==
                bookUuid,
          ),
          isTrue,
        );

        final renamed = await apiClient.updateBook(
          bookUuid: bookUuid,
          name: '  IT book renamed $suffix  ',
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(renamed['name']?.toString(), 'IT book renamed $suffix');

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
            'title': 'IT bundle event $suffix',
            'record_number': 'BOOK-$suffix',
            'record_name': 'IT Bundle $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final bundle = await apiClient.pullBook(
          bookUuid: bookUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final bundleEvents = (bundle['events'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          bundleEvents.any(
            (event) => pickString(event, keys: const ['id']) == eventId,
          ),
          isTrue,
        );

        await apiClient.archiveBook(
          bookUuid: bookUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final listedAfterArchive = await apiClient.listServerBooks(
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(
          listedAfterArchive.any(
            (book) =>
                pickString(
                  book,
                  keys: const ['bookUuid', 'book_uuid', 'uuid'],
                ) ==
                bookUuid,
          ),
          isFalse,
        );

        await apiClient.deleteBook(
          bookUuid: bookUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await expectLater(
          () => apiClient.getServerBookInfo(
            bookUuid: bookUuid!,
            deviceId: live.deviceId,
            deviceToken: live.deviceToken,
          ),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
          ),
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
        apiClient.dispose();
      }
    },
    skip: skipForMissingConfig(config),
  );
}
