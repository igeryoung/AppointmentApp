import 'package:flutter/foundation.dart';
import '../../../services/content_service.dart';

/// Wrapper for server health check operations
class ServerHealthChecker {
  final ContentService _contentService;

  ServerHealthChecker(this._contentService);

  /// Check if server is reachable via health check
  /// Returns true if server is reachable, false otherwise
  Future<bool> checkServerConnectivity() async {
    try {
      debugPrint('🔍 ServerHealthChecker: Checking server connectivity via health check...');
      final isHealthy = await _contentService.healthCheck();
      debugPrint(isHealthy
        ? '✅ ServerHealthChecker: Server is reachable'
        : '❌ ServerHealthChecker: Server health check returned false');
      return isHealthy;
    } catch (e) {
      debugPrint('❌ ServerHealthChecker: Server health check failed: $e');
      return false;
    }
  }
}
