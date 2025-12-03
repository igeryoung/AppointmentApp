import '../../../services/content_service.dart';

/// Wrapper for server health check operations

class ServerHealthChecker {
  final ContentService _contentService;

  ServerHealthChecker(this._contentService);

  /// Check if server is reachable via health check
  /// Returns true if server is reachable, false otherwise
  Future<bool> checkServerConnectivity() async {
    try {
      final isHealthy = await _contentService.healthCheck();
      return isHealthy;
    } catch (e) {
      return false;
    }
  }
}
