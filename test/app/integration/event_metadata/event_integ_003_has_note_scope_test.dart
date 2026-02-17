import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void registerEventInteg003({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-003: has_note stays false for new event that only shares an existing record note',
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
          name: 'IT has-note scope $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final recordUuid = uuid.v4();
        final eventWithNoteId = uuid.v4();
        final eventWithoutNoteId = uuid.v4();
        final startA = DateTime.now().toUtc().add(const Duration(minutes: 20));
        final endA = startA.add(const Duration(minutes: 30));
        final startB = startA.add(const Duration(hours: 1));
        final endB = startB.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventWithNoteId,
            'record_uuid': recordUuid,
            'title': 'IT noted event $suffix',
            'record_number': 'HASNOTE-$suffix',
            'record_name': 'IT HasNote $suffix',
            'record_phone': null,
            'event_types': const ['consultation'],
            'start_time': startA.millisecondsSinceEpoch ~/ 1000,
            'end_time': endA.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: eventWithNoteId,
          noteData: buildSingleStrokeNotePayload(
            eventId: eventWithNoteId,
            version: 1,
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': eventWithoutNoteId,
            'record_uuid': recordUuid,
            'title': 'IT plain event $suffix',
            'record_number': 'HASNOTE-$suffix',
            'record_name': 'IT HasNote $suffix',
            'record_phone': null,
            'event_types': const ['followUp'],
            'start_time': startB.millisecondsSinceEpoch ~/ 1000,
            'end_time': endB.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final notedEvent = await apiClient.fetchEvent(
          bookUuid: bookUuid,
          eventId: eventWithNoteId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final plainEvent = await apiClient.fetchEvent(
          bookUuid: bookUuid,
          eventId: eventWithoutNoteId,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(notedEvent, isNotNull);
        expect(plainEvent, isNotNull);
        expect(
          pickBool(notedEvent!, keys: const ['has_note', 'hasNote']),
          isTrue,
        );
        expect(
          pickBool(plainEvent!, keys: const ['has_note', 'hasNote']),
          isFalse,
        );

        final listedEvents = await apiClient.fetchEventsByDateRange(
          bookUuid: bookUuid,
          startDate: startA.subtract(const Duration(hours: 1)),
          endDate: endB.add(const Duration(hours: 1)),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final listedNoted = listedEvents.firstWhere(
          (event) => pickString(event, keys: const ['id']) == eventWithNoteId,
        );
        final listedPlain = listedEvents.firstWhere(
          (event) =>
              pickString(event, keys: const ['id']) == eventWithoutNoteId,
        );

        expect(
          pickBool(listedNoted, keys: const ['has_note', 'hasNote']),
          isTrue,
        );
        expect(
          pickBool(listedPlain, keys: const ['has_note', 'hasNote']),
          isFalse,
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
