import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void registerEventInteg004({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-004: no-record event note persists after reenter fill record number update',
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
          name: 'IT refill rn note $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final sharedName = 'IT Refill $suffix';
        final targetRecordNumber = 'REFILL-$suffix';

        // Create event without record number and write note (simulates first session autosave).
        final refillEventId = uuid.v4();
        final refillRecordUuid = uuid.v4();
        final refillStart = DateTime.now().toUtc().add(
          const Duration(minutes: 40),
        );
        final refillEnd = refillStart.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': refillEventId,
            'record_uuid': refillRecordUuid,
            'title': sharedName,
            'record_number': '',
            'record_name': sharedName,
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': refillStart.millisecondsSinceEpoch ~/ 1000,
            'end_time': refillEnd.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: refillEventId,
          noteData: buildSingleStrokeNotePayload(
            eventId: refillEventId,
            version: 1,
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final beforeFillNote = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: refillEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(beforeFillNote, isNotNull);
        expect(beforeFillNote!.isNotEmpty, isTrue);

        // Reenter + fill record number.
        await apiClient.updateEvent(
          bookUuid: bookUuid,
          eventId: refillEventId,
          eventData: {'title': sharedName},
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final refreshedEvent = await apiClient.fetchEvent(
          bookUuid: bookUuid,
          eventId: refillEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(refreshedEvent, isNotNull);

        final resolvedRecordUuid = pickString(
          refreshedEvent!,
          keys: const ['record_uuid', 'recordUuid'],
        );

        // Simulate controller metadata sync record update on resolved uuid.
        await apiClient.updateRecord(
          recordUuid: resolvedRecordUuid,
          recordData: {
            'name': sharedName,
            'phone': null,
            'record_number': targetRecordNumber,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final updatedEvent = await apiClient.fetchEvent(
          bookUuid: bookUuid,
          eventId: refillEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(updatedEvent, isNotNull);
        expect(
          updatedEvent!['record_number']?.toString() ?? '',
          targetRecordNumber,
        );

        // Note should still be reachable from event after refill.
        final afterFillNote = await apiClient.fetchNote(
          bookUuid: bookUuid,
          eventId: refillEventId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(afterFillNote, isNotNull);
        expect(afterFillNote!.isNotEmpty, isTrue);
        final strokeIds = afterFillNote.pages
            .expand((page) => page)
            .map((stroke) => stroke.id)
            .whereType<String>()
            .toSet();
        expect(strokeIds, contains('stroke-$refillEventId'));
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
