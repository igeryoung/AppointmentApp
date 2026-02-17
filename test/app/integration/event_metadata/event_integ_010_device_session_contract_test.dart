import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void registerEventInteg010({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-010: device session contract validates registration check and credential gating',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final randomDeviceId = const Uuid().v4();

      try {
        final registered = await apiClient.checkDeviceRegistration(
          deviceId: live.deviceId,
        );
        expect(registered, isTrue);

        final missing = await apiClient.checkDeviceRegistration(
          deviceId: randomDeviceId,
        );
        expect(missing, isFalse);

        await expectLater(
          () => apiClient.listServerBooks(
            deviceId: live.deviceId,
            deviceToken: 'invalid-token',
          ),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
          ),
        );

        final books = await apiClient.listServerBooks(
          deviceId: live.deviceId,
          deviceToken: live.deviceToken,
        );
        expect(books, isA<List<Map<String, dynamic>>>());
      } finally {
        apiClient.dispose();
      }
    },
    skip: skipForMissingConfig(config),
  );
}
