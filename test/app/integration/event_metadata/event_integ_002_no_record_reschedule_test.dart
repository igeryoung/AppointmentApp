import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void registerEventInteg002({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-002: no-record-number note remains visible for old/new events after reschedule',
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
          name: 'IT no-rn reschedule $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final oldEventId = uuid.v4();
        final recordUuid = uuid.v4();
        final startTime = DateTime.now().toUtc().add(
          const Duration(minutes: 15),
        );
        final endTime = startTime.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': oldEventId,
            'record_uuid': recordUuid,
            'title': 'IT no-rn fixture $suffix',
            'record_number': '',
            'record_name': 'IT NoRN $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
            'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        // Save initial note on the original event.
        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: oldEventId,
          noteData: buildSingleStrokeNotePayload(
            eventId: oldEventId,
            version: 1,
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final beforeRescheduleOldNote = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: oldEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(beforeRescheduleOldNote, isNotNull);
        expect(beforeRescheduleOldNote!.recordUuid, recordUuid);
        expect(beforeRescheduleOldNote.isNotEmpty, isTrue);

        // Reschedule event and capture new event ID from server response.
        final rescheduled = await apiClient.rescheduleEvent(
          bookUuid: bookUuid,
          eventId: oldEventId,
          newStartTime: startTime.add(const Duration(hours: 2)),
          newEndTime: endTime.add(const Duration(hours: 2)),
          reason: 'integration reschedule',
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final oldEvent = rescheduled['oldEvent'] as Map<String, dynamic>;
        final newEvent = rescheduled['newEvent'] as Map<String, dynamic>;
        final newEventId = pickString(newEvent, keys: const ['id']);

        expect(pickString(oldEvent, keys: const ['id']), oldEventId);
        expect(oldEvent['is_removed'], isTrue);
        expect(oldEvent['new_event_id'], newEventId);
        expect(newEvent['original_event_id'], oldEventId);

        // Verify both old and new events can fetch the same note.
        final oldEventNote = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: oldEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final newEventNote = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: newEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        expect(oldEventNote, isNotNull);
        expect(newEventNote, isNotNull);
        expect(oldEventNote!.recordUuid, recordUuid);
        expect(newEventNote!.recordUuid, recordUuid);
        expect(oldEventNote.pages, isNotEmpty);
        expect(newEventNote.pages, isNotEmpty);
      } finally {
        // Always cleanup to avoid polluting shared integration environments.
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
