import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';
import 'package:schedule_note_app/services/api_client.dart';

import 'live_server_test_support.dart';

void main() {}

void registerEventInteg009({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-009: drawing server contract covers fetch/save/update/delete',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final readDevice = live.readCredentials;
      String? bookUuid;

      try {
        final fixture = await resolveFixture(
          apiClient: apiClient,
          config: live,
          requireWrite: false,
        );
        final fixtureDate = DateTime.now().toUtc();
        const fixtureViewMode = ScheduleDrawing.VIEW_MODE_3DAY;

        await expectReadOnlyDeviceFailure(
          () => apiClient.saveDrawing(
            bookUuid: fixture.bookUuid,
            drawingData: {
              'date': fixtureDate.toIso8601String().split('T')[0],
              'viewMode': fixtureViewMode,
              'strokesData': jsonEncode(const []),
              'version': 1,
            },
            deviceId: readDevice.deviceId,
            deviceToken: readDevice.deviceToken,
          ),
        );
        await expectReadOnlyDeviceFailure(
          () => apiClient.deleteDrawing(
            bookUuid: fixture.bookUuid,
            date: fixtureDate,
            viewMode: fixtureViewMode,
            deviceId: readDevice.deviceId,
            deviceToken: readDevice.deviceToken,
          ),
        );

        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT drawing contract $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final date = DateTime.now().toUtc();
        const viewMode = ScheduleDrawing.VIEW_MODE_3DAY;

        final before = await apiClient.fetchDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(before, isNull);

        final firstStrokes = jsonEncode([
          {
            'id': 'stroke-a',
            'points': [
              {'x': 10.0, 'y': 10.0},
              {'x': 20.0, 'y': 20.0},
            ],
            'strokeType': 'pen',
            'strokeWidth': 2.0,
            'color': 4278190080,
          },
        ]);
        final savedV1 = await apiClient.saveDrawing(
          bookUuid: bookUuid,
          drawingData: {
            'date': date.toIso8601String().split('T')[0],
            'viewMode': viewMode,
            'strokesData': firstStrokes,
            'version': 1,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(savedV1['id'], isNotNull);

        final fetchedV1 = await apiClient.fetchDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(fetchedV1, isNotNull);
        final v1 = fetchedV1!['version'] as int? ?? 1;
        expect(v1, greaterThanOrEqualTo(1));

        final secondStrokes = jsonEncode([
          {
            'id': 'stroke-b',
            'points': [
              {'x': 30.0, 'y': 30.0},
              {'x': 40.0, 'y': 40.0},
            ],
            'strokeType': 'pen',
            'strokeWidth': 2.0,
            'color': 4278190080,
          },
        ]);
        await apiClient.saveDrawing(
          bookUuid: bookUuid,
          drawingData: {
            'date': date.toIso8601String().split('T')[0],
            'viewMode': viewMode,
            'strokesData': secondStrokes,
            'version': v1 + 1,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        final fetchedV2 = await apiClient.fetchDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(fetchedV2, isNotNull);
        final v2 = fetchedV2!['version'] as int? ?? 1;
        final strokesData =
            (fetchedV2['strokesData'] ?? fetchedV2['strokes_data'])
                ?.toString() ??
            '';
        expect(v2, greaterThanOrEqualTo(v1 + 1));
        expect(strokesData, contains('stroke-b'));

        await apiClient.deleteDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        final afterDelete = await apiClient.fetchDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(afterDelete, isNull);
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

  test(
    'EVENT-INTEG-009B: pulled device can fetch drawings from shared book',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      String? bookUuid;

      try {
        final readerDevice = live.readCredentials;
        final fixture = await resolveFixture(
          apiClient: apiClient,
          config: live,
          requireWrite: false,
        );
        final fixtureDate = DateTime.now().toUtc();
        final fixtureViewMode = ScheduleDrawing.VIEW_MODE_2DAY;

        await apiClient.saveDrawing(
          bookUuid: fixture.bookUuid,
          drawingData: {
            'date': fixtureDate.toIso8601String().split('T')[0],
            'viewMode': fixtureViewMode,
            'strokesData': jsonEncode(const [
              {
                'id': 'fixture-stroke',
                'points': [
                  {'x': 12.0, 'y': 12.0},
                  {'x': 36.0, 'y': 36.0},
                ],
                'strokeType': 'pen',
                'strokeWidth': 2.0,
                'color': 4278190080,
              },
            ]),
            'version': 1,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.pullBook(
          bookUuid: fixture.bookUuid,
          bookPassword: live.bookPassword,
          deviceId: readerDevice.deviceId,
          deviceToken: readerDevice.deviceToken,
        );

        final fetchedEvent = await apiClient.fetchEvent(
          bookUuid: fixture.bookUuid,
          eventId: fixture.eventId,
          deviceId: readerDevice.deviceId,
          deviceToken: readerDevice.deviceToken,
        );
        expect(fetchedEvent, isNotNull);

        final fetchedSharedDrawing = await apiClient.fetchDrawing(
          bookUuid: fixture.bookUuid,
          date: fixtureDate,
          viewMode: fixtureViewMode,
          deviceId: readerDevice.deviceId,
          deviceToken: readerDevice.deviceToken,
        );
        expect(fetchedSharedDrawing, isNotNull);
        final fixtureStrokesData =
            (fetchedSharedDrawing!['strokesData'] ??
                    fetchedSharedDrawing['strokes_data'])
                ?.toString() ??
            '';
        expect(fixtureStrokesData, contains('fixture-stroke'));

        await expectReadOnlyDeviceFailure(
          () => apiClient.saveDrawing(
            bookUuid: fixture.bookUuid,
            drawingData: {
              'date': fixtureDate.toIso8601String().split('T')[0],
              'viewMode': fixtureViewMode,
              'strokesData': jsonEncode(const []),
              'version': 2,
            },
            deviceId: readerDevice.deviceId,
            deviceToken: readerDevice.deviceToken,
          ),
        );

        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT drawing pull auth $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final date = DateTime.now().toUtc();
        final viewMode = ScheduleDrawing.VIEW_MODE_2DAY;
        final strokes = jsonEncode([
          {
            'id': 'stroke-shared',
            'points': [
              {'x': 11.0, 'y': 11.0},
              {'x': 33.0, 'y': 33.0},
            ],
            'strokeType': 'pen',
            'strokeWidth': 2.0,
            'color': 4278190080,
          },
        ]);

        await apiClient.saveDrawing(
          bookUuid: bookUuid,
          drawingData: {
            'date': date.toIso8601String().split('T')[0],
            'viewMode': viewMode,
            'strokesData': strokes,
            'version': 1,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        // Pull once so device B is in the same book access model used by app.
        await apiClient.pullBook(
          bookUuid: bookUuid,
          bookPassword: live.bookPassword,
          deviceId: readerDevice.deviceId,
          deviceToken: readerDevice.deviceToken,
        );

        final fetchedByDeviceB = await apiClient.fetchDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: readerDevice.deviceId,
          deviceToken: readerDevice.deviceToken,
        );

        expect(fetchedByDeviceB, isNotNull);
        final strokesData =
            (fetchedByDeviceB!['strokesData'] ??
                    fetchedByDeviceB['strokes_data'])
                ?.toString() ??
            '';
        expect(strokesData, contains('stroke-shared'));
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

  test(
    'EVENT-INTEG-009C: write-role device can update drawings after pulling a shared book',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      LiveDeviceCredentials? pulledWriteDevice;
      String? bookUuid;

      try {
        pulledWriteDevice = await provisionTemporaryDevice(
          apiClient: apiClient,
          config: live,
          deviceRole: liveDeviceRoleWrite,
          deviceNamePrefix: 'IT pulled write drawing device',
        );

        final suffix = DateTime.now().millisecondsSinceEpoch.toString();
        final createdBook = await createTemporaryBook(
          apiClient: apiClient,
          config: live,
          name: 'IT drawing write pull $suffix',
        );
        bookUuid = pickString(
          createdBook,
          keys: const ['bookUuid', 'book_uuid', 'uuid'],
        );

        final date = DateTime.now().toUtc();
        const viewMode = ScheduleDrawing.VIEW_MODE_2DAY;
        final ownerStrokes = jsonEncode([
          {
            'id': 'owner-stroke',
            'points': [
              {'x': 10.0, 'y': 10.0},
              {'x': 20.0, 'y': 20.0},
            ],
            'strokeType': 'pen',
            'strokeWidth': 2.0,
            'color': 4278190080,
          },
        ]);

        await apiClient.saveDrawing(
          bookUuid: bookUuid,
          drawingData: {
            'date': date.toIso8601String().split('T')[0],
            'viewMode': viewMode,
            'strokesData': ownerStrokes,
            'version': 1,
          },
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );

        await apiClient.pullBook(
          bookUuid: bookUuid,
          bookPassword: live.bookPassword,
          deviceId: pulledWriteDevice.deviceId,
          deviceToken: pulledWriteDevice.deviceToken,
        );

        final fetchedByPulledDevice = await apiClient.fetchDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: pulledWriteDevice.deviceId,
          deviceToken: pulledWriteDevice.deviceToken,
        );
        expect(fetchedByPulledDevice, isNotNull);

        final pulledVersion = fetchedByPulledDevice!['version'] as int? ?? 1;
        final updatedStrokes = jsonEncode([
          {
            'id': 'pulled-write-stroke',
            'points': [
              {'x': 30.0, 'y': 30.0},
              {'x': 40.0, 'y': 40.0},
            ],
            'strokeType': 'pen',
            'strokeWidth': 2.0,
            'color': 4278190080,
          },
        ]);

        await apiClient.saveDrawing(
          bookUuid: bookUuid,
          drawingData: {
            'date': date.toIso8601String().split('T')[0],
            'viewMode': viewMode,
            'strokesData': updatedStrokes,
            'version': pulledVersion + 1,
          },
          deviceId: pulledWriteDevice.deviceId,
          deviceToken: pulledWriteDevice.deviceToken,
        );

        final fetchedAfterUpdate = await apiClient.fetchDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(fetchedAfterUpdate, isNotNull);
        final updatedStrokesData =
            (fetchedAfterUpdate!['strokesData'] ??
                    fetchedAfterUpdate['strokes_data'])
                ?.toString() ??
            '';
        expect(updatedStrokesData, contains('pulled-write-stroke'));
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
            credentials: pulledWriteDevice,
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
