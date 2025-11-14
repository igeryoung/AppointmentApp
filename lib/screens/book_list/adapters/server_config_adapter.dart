import '../../../services/server_config_service.dart';
import '../../../services/database_service_interface.dart';
import '../../../services/database/prd_database_service.dart';
import '../../../services/service_locator.dart';

/// Adapter for server configuration operations
/// Wraps ServerConfigService
class ServerConfigAdapter {
  final ServerConfigService _configService;

  ServerConfigAdapter._(this._configService);

  /// Create from service locator
  factory ServerConfigAdapter.fromGetIt() {
    final dbService = getIt<IDatabaseService>();
    if (dbService is PRDDatabaseService) {
      return ServerConfigAdapter._(ServerConfigService(dbService));
    }
    throw Exception('ServerConfigService requires PRDDatabaseService');
  }

  /// Get server URL or default
  Future<String> getUrlOrDefault() async {
    return await _configService.getServerUrlOrDefault();
  }

  /// Set server URL
  Future<void> setUrl(String url) async {
    return await _configService.setServerUrl(url);
  }

  /// Get current server URL (may be null)
  Future<String?> getUrl() async {
    try {
      final url = await _configService.getServerUrlOrDefault();
      // Check if it's the default URL
      if (url == 'http://localhost:8080') {
        return null;
      }
      return url;
    } catch (e) {
      return null;
    }
  }
}
