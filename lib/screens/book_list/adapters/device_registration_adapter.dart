import '../../../services/api_client.dart';
import '../../../services/database_service_interface.dart';
import '../../../services/prd_database_service.dart';
import '../../../services/service_locator.dart';
import '../utils/platform_utils.dart';

/// Adapter for device registration operations
/// Wraps ApiClient and handles credential storage
class DeviceRegistrationAdapter {
  final PRDDatabaseService _dbService;

  DeviceRegistrationAdapter._(this._dbService);

  /// Create from service locator
  factory DeviceRegistrationAdapter.fromGetIt() {
    final dbService = getIt<IDatabaseService>();
    if (dbService is PRDDatabaseService) {
      return DeviceRegistrationAdapter._(dbService);
    }
    throw Exception('DeviceRegistrationAdapter requires PRDDatabaseService');
  }

  /// Check if device is registered
  Future<bool> isRegistered() async {
    final credentials = await _dbService.getDeviceCredentials();
    return credentials != null;
  }

  /// Register device with server
  Future<void> register({
    required String baseUrl,
    required String password,
    String? deviceName,
    String? platform,
  }) async {
    final actualDeviceName = deviceName ?? PlatformUtils.deviceDisplayName;
    final actualPlatform = platform ?? PlatformUtils.platformName;

    final apiClient = ApiClient(baseUrl: baseUrl);
    try {
      final response = await apiClient.registerDevice(
        deviceName: actualDeviceName,
        password: password,
        platform: actualPlatform,
      );

      // Save device credentials
      final deviceId = response['deviceId'] as String;
      final deviceToken = response['deviceToken'] as String;

      await _dbService.saveDeviceCredentials(
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: actualDeviceName,
        platform: actualPlatform,
      );
    } finally {
      apiClient.dispose();
    }
  }

  /// Get device credentials
  Future<Map<String, dynamic>?> getCredentials() async {
    final credentials = await _dbService.getDeviceCredentials();
    if (credentials == null) return null;

    return {
      'deviceId': credentials.deviceId,
      'deviceToken': credentials.deviceToken,
    };
  }
}
