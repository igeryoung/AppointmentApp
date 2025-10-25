import 'package:flutter/foundation.dart';
import 'prd_database_service.dart';

/// Service for managing server URL configuration
class ServerConfigService {
  final PRDDatabaseService dbService;

  ServerConfigService(this.dbService);

  /// Get the configured server URL
  /// Returns null if not configured
  Future<String?> getServerUrl() async {
    final db = await dbService.database;
    final rows = await db.query('device_info', limit: 1);

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['server_url'] as String?;
  }

  /// Set the server URL
  /// Only updates server_url if device is already registered
  /// Otherwise stores URL for later use during registration
  Future<void> setServerUrl(String url) async {
    final db = await dbService.database;

    // Check if device_info row exists (device is registered)
    final rows = await db.query('device_info', limit: 1);

    if (rows.isNotEmpty) {
      // Device is registered - update the server URL
      await db.update(
        'device_info',
        {'server_url': url},
        where: 'id = 1',
      );
      debugPrint('✅ Server URL updated in registered device: $url');
    } else {
      // Device not registered yet - URL will be saved during registration
      debugPrint('ℹ️  Server URL will be saved during device registration: $url');
    }
  }

  /// Get server URL with fallback to default
  /// Automatically upgrades HTTP to HTTPS for security (all environments)
  Future<String> getServerUrlOrDefault({String defaultUrl = 'https://localhost:8080'}) async {
    final url = await getServerUrl();
    final finalUrl = url ?? defaultUrl;

    // Auto-upgrade HTTP to HTTPS for security
    return _upgradeToHttps(finalUrl);
  }

  /// Automatically upgrade HTTP URLs to HTTPS
  /// All environments: upgrade to HTTPS for security
  /// Debug mode: accepts self-signed certificates (configured in ApiClient)
  String _upgradeToHttps(String url) {
    if (url.startsWith('http://')) {
      final httpsUrl = url.replaceFirst('http://', 'https://');
      if (kDebugMode) {
        debugPrint('🔒 Auto-upgraded HTTP to HTTPS (debug mode): $httpsUrl');
        debugPrint('   Self-signed certificates are accepted in debug mode');
      } else {
        debugPrint('🔒 Auto-upgraded HTTP to HTTPS: $httpsUrl');
      }
      return httpsUrl;
    }
    return url;
  }
}
