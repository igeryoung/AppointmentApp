import '../../../services/book_backup_service.dart';
import '../../../services/database_service_interface.dart';
import '../../../services/database/prd_database_service.dart';
import '../../../services/service_locator.dart';
import '../utils/platform_utils.dart';

/// Adapter for book backup operations
/// Handles platform checks and wraps BookBackupService
class BookBackupAdapter {
  final BookBackupService? _backupService;

  BookBackupAdapter._(this._backupService);

  /// Create from service locator
  factory BookBackupAdapter.fromGetIt() {
    if (PlatformUtils.isWeb) {
      return BookBackupAdapter._(null);
    }

    final dbService = getIt<IDatabaseService>();
    if (dbService is PRDDatabaseService) {
      return BookBackupAdapter._(BookBackupService(dbService: dbService));
    }

    return BookBackupAdapter._(null);
  }

  /// Check if backup service is available (false on web)
  bool get available => _backupService != null;

  /// Upload a book to server
  /// Returns the backup ID
  Future<int> upload(String bookUuid) async {
    if (_backupService == null) {
      throw Exception('Book backup is not available on this platform');
    }
    return await _backupService!.uploadBook(bookUuid);
  }

  /// List all backups from server
  Future<List<Map<String, dynamic>>> listBackups() async {
    if (_backupService == null) {
      throw Exception('Book backup is not available on this platform');
    }
    return await _backupService!.listBackups();
  }

  /// Restore a book from server backup
  /// Returns a success message
  Future<String> restore(int backupId) async {
    if (_backupService == null) {
      throw Exception('Book backup is not available on this platform');
    }
    return await _backupService!.restoreBook(backupId);
  }
}
