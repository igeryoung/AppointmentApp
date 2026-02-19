import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void registerEventInteg012({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-012: stale writer gets conflict and keeps newer server note',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
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
          name: 'IT multi-device note $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final eventId = uuid.v4();
        final recordUuid = uuid.v4();
        final startTime = DateTime.now().toUtc().add(
          const Duration(minutes: 25),
        );
        final endTime = startTime.add(const Duration(minutes: 30));
        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventId,
            'record_uuid': recordUuid,
            'title': 'IT note conflict $suffix',
            'record_number': 'NOTE-CF-$suffix',
            'record_name': 'IT Conflict $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: eventId,
          noteData: buildSingleStrokeNotePayload(eventId: eventId, version: 1),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final noteSeenByDeviceB = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: deviceB.deviceId,
          deviceToken: deviceB.deviceToken,
        );
        expect(noteSeenByDeviceB, isNotNull);
        expect(noteSeenByDeviceB!.version, greaterThanOrEqualTo(1));

        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: eventId,
          noteData: buildSingleStrokeNotePayload(
            eventId: '${eventId}_deviceA_v2',
            version: 2,
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await expectLater(
          () => apiClient.saveNote(
            bookUuid: bookUuid!,
            eventId: eventId,
            noteData: buildSingleStrokeNotePayload(
              eventId: '${eventId}_deviceB_stale',
              version: 2,
            ),
            deviceId: deviceB.deviceId,
            deviceToken: deviceB.deviceToken,
          ),
          throwsA(
            isA<ApiConflictException>().having(
              (e) => e.statusCode,
              'statusCode',
              409,
            ),
          ),
        );

        final afterConflict = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: deviceB.deviceId,
          deviceToken: deviceB.deviceToken,
        );
        expect(afterConflict, isNotNull);
        expect(afterConflict!.version, greaterThanOrEqualTo(2));

        final retryPayload = buildNotePayloadFromExisting(
          noteMap: afterConflict.toMap(),
          version: afterConflict.version + 1,
        );
        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: eventId,
          noteData: retryPayload,
          deviceId: deviceB.deviceId,
          deviceToken: deviceB.deviceToken,
        );

        final finalNote = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(finalNote, isNotNull);
        expect(
          finalNote!.version,
          greaterThanOrEqualTo(afterConflict.version + 1),
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
