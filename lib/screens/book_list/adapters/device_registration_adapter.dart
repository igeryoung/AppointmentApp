import '../../../services/api_client.dart';
import '../../../services/database_service_interface.dart';
import '../../../services/database/prd_database_service.dart';
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

  /// Remove local account session and cached book data from this device.
  Future<void> logout() async {
    await _dbService.clearAllData();
    await _dbService.clearDeviceCredentials();
  }

  String _normalizeRole(String? role, {String fallback = 'read'}) {
    final normalized = role?.trim().toLowerCase() ?? '';
    if (normalized == 'read' || normalized == 'write') {
      return normalized;
    }
    return fallback;
  }

  /// Login or register an account and store the returned device session.
  Future<void> authenticateAccount({
    required String baseUrl,
    required String username,
    required String password,
    String? registrationPassword,
    bool createAccount = false,
    String? deviceName,
    String? platform,
  }) async {
    final actualDeviceName = deviceName ?? PlatformUtils.deviceDisplayName;
    final actualPlatform = platform ?? PlatformUtils.platformName;

    final apiClient = ApiClient(baseUrl: baseUrl);
    try {
      final response = createAccount
          ? await apiClient.registerAccount(
              username: username,
              password: password,
              registrationPassword: registrationPassword ?? '',
              deviceName: actualDeviceName,
              platform: actualPlatform,
            )
          : await apiClient.loginAccount(
              username: username,
              password: password,
              deviceName: actualDeviceName,
              platform: actualPlatform,
            );

      // Save device credentials with server URL
      final accountId = response['accountId'] as String?;
      final accountUsername = response['username'] as String? ?? username;
      final deviceId = response['deviceId'] as String;
      final deviceToken = response['deviceToken'] as String;
      final deviceRole = _normalizeRole(
        response['deviceRole']?.toString(),
        fallback: 'read',
      );

      await _dbService.saveDeviceCredentials(
        accountId: accountId,
        username: accountUsername,
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: actualDeviceName,
        serverUrl: baseUrl,
        platform: actualPlatform,
        deviceRole: deviceRole,
      );
    } finally {
      apiClient.dispose();
    }
  }

  /// Refresh device role from server and persist locally.
  Future<void> refreshDeviceRoleFromServer() async {
    final credentials = await _dbService.getDeviceCredentials();
    if (credentials == null) return;

    final db = await _dbService.database;
    final rows = await db.query('device_info', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return;
    final row = rows.first;
    final serverUrl = row['server_url'] as String?;
    if (serverUrl == null || serverUrl.trim().isEmpty) return;

    final apiClient = ApiClient(baseUrl: serverUrl);
    try {
      final account = await apiClient.fetchCurrentAccount(
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
      final accountRole = account['accountRole']?.toString();
      await db.update('device_info', {
        'account_id': account['accountId']?.toString() ?? credentials.accountId,
        'username': account['username']?.toString() ?? credentials.username,
        'device_role': _normalizeRole(
          accountRole,
          fallback: credentials.deviceRole,
        ),
      }, where: 'id = 1');
    } on ApiException {
      return;
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
      'accountId': credentials.accountId,
      'username': credentials.username,
      'deviceRole': credentials.deviceRole,
      'isReadOnly': credentials.isReadOnly,
    };
  }
}
