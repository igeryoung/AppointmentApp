import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void main() {}

void registerEventInteg013({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-013: existing record number lookup returns canonical record data and shared note for autofill',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final uuid = const Uuid();
      final deviceRole = await resolveLiveDeviceRole(
        apiClient: apiClient,
        config: live,
      );
      String? bookUuid;

      try {
        if (isReadOnlyDeviceRole(deviceRole)) {
          final fixture = await resolveFixture(
            apiClient: apiClient,
            config: live,
            deviceRole: deviceRole,
          );
          await expectReadOnlyDeviceFailure(
            () => apiClient.updateEvent(
              bookUuid: fixture.bookUuid,
              eventId: fixture.eventId,
              eventData: {'title': 'IT read-only lookup'},
              deviceId: live.deviceId,
              deviceToken: live.deviceToken,
            ),
          );
          return;
        }

        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT record lookup $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final existingEventId = uuid.v4();
        final existingRecordUuid = uuid.v4();
        final existingRecordNumber = 'LOOKUP-$suffix';
        final existingName = 'Lookup Person $suffix';
        final existingPhone = '0900${suffix.substring(suffix.length - 6)}';
        final start = DateTime.now().toUtc().add(const Duration(minutes: 35));
        final end = start.add(const Duration(minutes: 30));

        await apiClient.createEvent(
          bookUuid: bookUuid,
          eventData: {
            'id': existingEventId,
            'record_uuid': existingRecordUuid,
            'title': existingName,
            'record_number': existingRecordNumber,
            'record_name': existingName,
            'record_phone': existingPhone,
            'event_types': const ['consultation'],
            'start_time': start.millisecondsSinceEpoch ~/ 1000,
            'end_time': end.millisecondsSinceEpoch ~/ 1000,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.saveNote(
          bookUuid: bookUuid,
          eventId: existingEventId,
          noteData: buildSingleStrokeNotePayload(
            eventId: existingEventId,
            version: 1,
          ),
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final resolvedRecord = await apiClient.fetchRecordByNumber(
          recordNumber: existingRecordNumber,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        expect(resolvedRecord, isNotNull);
        expect(
          pickString(
            resolvedRecord!,
            keys: const ['record_uuid', 'recordUuid'],
          ),
          existingRecordUuid,
        );
        expect(
          pickString(
            resolvedRecord,
            keys: const ['record_number', 'recordNumber'],
          ),
          existingRecordNumber,
        );
        expect(pickString(resolvedRecord, keys: const ['name']), existingName);
        expect(
          pickString(resolvedRecord, keys: const ['phone']),
          existingPhone,
        );

        final scopedRecord = await apiClient.fetchRecordDetails(
          bookUuid: bookUuid,
          recordUuid: existingRecordUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(scopedRecord, isNotNull);
        expect(
          pickString(
            scopedRecord!,
            keys: const ['record_number', 'recordNumber'],
          ),
          existingRecordNumber,
        );
        expect(pickString(scopedRecord, keys: const ['name']), existingName);

        final resolvedNote = await apiClient.fetchNoteByRecordUuid(
          bookUuid: bookUuid,
          recordUuid: existingRecordUuid,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(resolvedNote, isNotNull);
        expect(resolvedNote!.isNotEmpty, isTrue);
        final strokeIds = resolvedNote.pages
            .expand((page) => page)
            .map((stroke) => stroke.id)
            .whereType<String>()
            .toSet();
        expect(strokeIds, contains('stroke-$existingEventId'));
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
    timeout: liveServerTestTimeout,
    skip: skipForMissingConfig(config),
  );
}
