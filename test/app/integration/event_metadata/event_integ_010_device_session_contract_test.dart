import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';
import 'package:uuid/uuid.dart';

import 'live_server_test_support.dart';

void main() {}

void registerEventInteg010({required LiveServerConfig? config}) {
  test(
    'EVENT-INTEG-010: device session contract validates registration check and credential gating',
    () async {
      final live = config!;
      final apiClient = ApiClient(baseUrl: live.baseUrl);
      final randomDeviceId = const Uuid().v4();
      LiveDeviceCredentials? testDevice;
      String? deletedDeviceId;

      try {
        final writeRole = await apiClient.fetchDeviceRole(
          deviceId: live.deviceId,
        );
        final readRole = await apiClient.fetchDeviceRole(
          deviceId: live.readDeviceId,
        );
        expect(writeRole, liveDeviceRoleWrite);
        expect(readRole, liveDeviceRoleRead);

        testDevice = await registerTemporaryDevice(
          apiClient: apiClient,
          config: live,
          deviceNamePrefix: 'IT session contract',
        );
        final registeredDevice = testDevice;

        final registered = await apiClient.checkDeviceRegistration(
          deviceId: registeredDevice.deviceId,
        );
        expect(registered, isTrue);

        final role =
            await apiClient.fetchDeviceRole(
              deviceId: registeredDevice.deviceId,
            ) ??
            liveDeviceRoleRead;
        expect(role, liveDeviceRoleRead);

        final missing = await apiClient.checkDeviceRegistration(
          deviceId: randomDeviceId,
        );
        expect(missing, isFalse);

        await expectLater(
          () => apiClient.listServerBooks(
            deviceId: registeredDevice.deviceId,
            deviceToken: 'invalid-token',
          ),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
          ),
        );

        final books = await apiClient.listServerBooks(
          deviceId: registeredDevice.deviceId,
          deviceToken: registeredDevice.deviceToken,
        );
        expect(books, isA<List<Map<String, dynamic>>>());

        deletedDeviceId = registeredDevice.deviceId;
        await cleanupTemporaryDevice(
          apiClient: apiClient,
          credentials: registeredDevice,
        );
        testDevice = null;

        final deleted = await apiClient.checkDeviceRegistration(
          deviceId: deletedDeviceId,
        );
        expect(deleted, isFalse);
      } finally {
        try {
          await cleanupTemporaryDevice(
            apiClient: apiClient,
            credentials: testDevice,
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
