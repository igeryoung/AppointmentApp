import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';
import 'package:schedule_note_app/services/api_client.dart';

import 'live_server_test_support.dart';

void registerEventInteg009({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-009: drawing server contract covers fetch/save/update/delete',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      String? bookUuid;

      try {
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
    skip: skipForMissingConfig(config),
  );

  test(
    'EVENT-INTEG-009B: pulled device can fetch drawings from shared book',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      String? bookUuid;

      try {
        final deviceB = await registerTemporaryDevice(
          apiClient: apiClient,
          config: live,
          deviceNamePrefix: 'IT drawing reader',
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
          deviceId: deviceB.deviceId,
          deviceToken: deviceB.deviceToken,
        );

        final fetchedByDeviceB = await apiClient.fetchDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: deviceB.deviceId,
          deviceToken: deviceB.deviceToken,
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
    skip: skipForMissingConfig(config),
  );
}
