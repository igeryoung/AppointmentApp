import '../services/database/prd_database_service.dart'; // For DeviceCredentials class

/// Repository interface for Device credentials operations
abstract class IDeviceRepository {
  /// Get stored device credentials
  Future<DeviceCredentials?> getCredentials();

  /// Save device credentials
  Future<void> saveCredentials({
    String? accountId,
    String? username,
    required String deviceId,
    required String deviceToken,
    required String deviceName,
    String? platform,
    String deviceRole = 'read',
  });
}
