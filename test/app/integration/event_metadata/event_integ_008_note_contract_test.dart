import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void registerEventInteg008({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-008: note server contract covers fetch/save/update/delete by event and record',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final uuid = const Uuid();
      String? bookUuid;
      String? eventId;
      String? recordUuid;

      try {
        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT note contract $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        eventId = uuid.v4();
        recordUuid = uuid.v4();
        final startTime = DateTime.now().toUtc().add(
          const Duration(minutes: 30),
        );
        final endTime = startTime.add(const Duration(minutes: 30));
        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventId,
            'record_uuid': recordUuid,
            'title': 'IT note event $suffix',
            'record_number': 'NOTE-$suffix',
            'record_name': 'IT Note $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final before = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(before, isNull);

        final saved = await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: eventId,
          noteData: buildSingleStrokeNotePayload(eventId: eventId, version: 1),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(saved, isNotEmpty);

        final afterFirstSave = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(afterFirstSave, isNotNull);
        expect(afterFirstSave!.recordUuid, recordUuid);
        expect(afterFirstSave.isNotEmpty, isTrue);

        final byRecord = await apiClient.fetchNoteByRecordUuid(
          bookUuid: bookUuid,
          recordUuid: recordUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(byRecord, isNotNull);
        expect(byRecord!.recordUuid, recordUuid);

        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: eventId,
          noteData: buildSingleStrokeNotePayload(
            eventId: '${eventId}_v2',
            version: 2,
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final afterSecondSave = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(afterSecondSave, isNotNull);
        expect(afterSecondSave!.version, greaterThanOrEqualTo(2));

        await apiClient.deleteNote(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final afterDeleteByEvent = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: eventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(afterDeleteByEvent, isNull);

        final afterDeleteByRecord = await apiClient.fetchNoteByRecordUuid(
          bookUuid: bookUuid,
          recordUuid: recordUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(afterDeleteByRecord, isNull);
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
