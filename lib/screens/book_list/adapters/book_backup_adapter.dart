import '../../../services/book_backup_service.dart';
import '../../../services/database_service_interface.dart';
import '../../../services/database/prd_database_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/api_client.dart';
import '../../../services/server_config_service.dart';
import '../utils/platform_utils.dart';

/// Adapter for book backup operations
/// Handles platform checks and wraps BookBackupService
class BookBackupAdapter {
  final PRDDatabaseService? _dbService;
  BookBackupService? _backupService;
  ApiClient? _apiClient;

  BookBackupAdapter._(this._dbService);

  /// Create from service locator
  factory BookBackupAdapter.fromGetIt() {
    if (PlatformUtils.isWeb) {
      return BookBackupAdapter._(null);
    }

    final dbService = getIt<IDatabaseService>();
    if (dbService is PRDDatabaseService) {
      return BookBackupAdapter._(dbService);
    }

    return BookBackupAdapter._(null);
  }

  /// Lazily initialize BookBackupService with ApiClient
  Future<BookBackupService> _ensureInitialized() async {
    if (_backupService != null) {
      return _backupService!;
    }

    if (_dbService == null) {
      throw Exception('Book backup is not available on this platform');
    }

    // Create ApiClient with server URL
    final serverConfig = ServerConfigService(_dbService!);
    final serverUrl = await serverConfig.getServerUrlOrDefault();
    _apiClient = ApiClient(baseUrl: serverUrl);

    // Create BookBackupService
    _backupService = BookBackupService(
      dbService: _dbService!,
      apiClient: _apiClient!,
    );

    return _backupService!;
  }

  /// Check if backup service is available (false on web)
  bool get available => _dbService != null;

  /// Upload a book to server
  /// Returns the backup ID
  Future<int> upload(String bookUuid) async {
    final service = await _ensureInitialized();
    return await service.uploadBook(bookUuid);
  }

  /// List all backups from server
  Future<List<Map<String, dynamic>>> listBackups() async {
    final service = await _ensureInitialized();
    return await service.listBackups();
  }

  /// Restore a book from server backup
  /// Returns a success message
  Future<String> restore(int backupId) async {
    final service = await _ensureInitialized();
    return await service.restoreBook(backupId);
  }
}
