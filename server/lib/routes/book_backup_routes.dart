import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/book_backup_service.dart';

/// Router for book backup/restore endpoints
///
/// New API (file-based):
///   POST   /api/books/{bookId}/backup
///   GET    /api/books/{bookId}/backups
///   GET    /api/backups/{backupId}/download
///   POST   /api/backups/{backupId}/restore
///   DELETE /api/backups/{backupId}
///
/// Legacy API (JSON-based, deprecated):
///   POST   /api/books/upload
///   GET    /api/books/list
class BookBackupRoutes {
  final DatabaseConnection db;
  late final BookBackupService backupService;

  BookBackupRoutes(this.db, {String? backupDir}) {
    backupService = BookBackupService(db, backupDir: backupDir);
  }

  // ============================================================================
  // NEW API (File-based backups)
  // ============================================================================

  /// Router for /api/books/{bookId}/... endpoints
  Router get bookScopedRouter {
    final router = Router();

    router.post('/<bookId>/backup', _createBackup);
    router.get('/<bookId>/backups', _listBookBackups);

    return router;
  }

  /// Router for /api/backups/{backupId}/... endpoints
  Router get backupScopedRouter {
    final router = Router();

    router.get('/<backupId>/download', _downloadBackup);
    router.post('/<backupId>/restore', _restoreBackup);
    router.delete('/<backupId>', _deleteBackup);

    return router;
  }

  /// Create a file-based backup for a book
  /// POST /api/books/{bookId}/backup
  Future<Response> _createBackup(Request request, String bookId) async {
    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Parse request body
      final body = await request.readAsString();
      final json = body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : <String, dynamic>{};
      final backupName = json['backupName'] as String?;

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Create file-based backup
      final backupId = await backupService.createFileBackup(
        bookId: int.parse(bookId),
        deviceId: deviceId,
        backupName: backupName,
      );

      print('✅ Book backup created: ID $backupId, Book #$bookId');

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Backup created successfully',
          'backupId': backupId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Book backup creation failed: $e');
      print('   Stack trace: $stackTrace');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to create backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// List all backups for a specific book
  /// GET /api/books/{bookId}/backups
  Future<Response> _listBookBackups(Request request, String bookId) async {
    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get backups for this book
      final backups = await backupService.listBookBackups(int.parse(bookId), deviceId);

      return Response.ok(
        jsonEncode({
          'success': true,
          'backups': backups,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ List book backups failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to list backups: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Download a backup file (streaming)
  /// GET /api/backups/{backupId}/download
  Future<Response> _downloadBackup(Request request, String backupId) async {
    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get backup file path
      final filePath = await backupService.getBackupFilePath(int.parse(backupId), deviceId);

      if (filePath == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Backup file not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Stream the file
      final file = File(filePath);
      final fileName = file.path.split('/').last;

      print('📥 Streaming backup file: $fileName (${file.lengthSync()} bytes)');

      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': 'application/gzip',
          'Content-Disposition': 'attachment; filename="$fileName"',
          'Content-Length': file.lengthSync().toString(),
        },
      );
    } catch (e) {
      print('❌ Download backup failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to download backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Restore a book from a backup
  /// POST /api/backups/{backupId}/restore
  Future<Response> _restoreBackup(Request request, String backupId) async {
    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Try file-based restore first, fall back to JSON if needed
      try {
        await backupService.restoreFromFileBackup(
          backupId: int.parse(backupId),
          deviceId: deviceId,
        );
        print('✅ Book restored from file-based backup: ID $backupId');
      } catch (e) {
        // Fall back to JSON-based restore for backward compatibility
        if (e.toString().contains('not a file-based backup')) {
          print('ℹ️  Falling back to JSON-based restore...');
          await backupService.restoreBookBackup(
            backupId: int.parse(backupId),
            deviceId: deviceId,
          );
          print('✅ Book restored from JSON backup: ID $backupId');
        } else {
          rethrow;
        }
      }

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Book restored successfully',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Book restore failed: $e');
      print('   Stack trace: $stackTrace');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to restore backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Delete a backup
  /// DELETE /api/backups/{backupId}
  Future<Response> _deleteBackup(Request request, String backupId) async {
    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Delete backup
      await backupService.deleteBackup(int.parse(backupId), deviceId);

      print('✅ Backup deleted: ID $backupId');

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Backup deleted successfully',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Delete backup failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to delete backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // ============================================================================
  // LEGACY API (JSON-based backups - deprecated but kept for compatibility)
  // ============================================================================

  /// Router for legacy /api/books/... endpoints
  Router get legacyRouter {
    final router = Router();

    router.post('/upload', _uploadBackupLegacy);
    router.get('/list', _listBackupsLegacy);
    router.get('/download/<backupId>', _downloadBackupLegacy);
    router.post('/restore/<backupId>', _restoreBackupLegacy);
    router.delete('/<backupId>', _deleteBackup);

    return router;
  }

  /// Upload a complete book backup (JSON format - DEPRECATED)
  /// POST /api/books/upload
  Future<Response> _uploadBackupLegacy(Request request) async {
    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Parse request body
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final bookId = json['bookId'] as int;
      final backupName = json['backupName'] as String;
      final backupData = json['backupData'] as Map<String, dynamic>;

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Upload backup (legacy JSON format)
      final backupId = await backupService.uploadBookBackup(
        deviceId: deviceId,
        bookId: bookId,
        backupName: backupName,
        backupData: backupData,
      );

      print('✅ Book backup uploaded (JSON): ID $backupId, Book #$bookId, "$backupName"');

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Backup uploaded successfully (legacy format)',
          'backupId': backupId,
        }),
        headers: {
          'Content-Type': 'application/json',
          'X-Deprecated': 'Use POST /api/books/{bookId}/backup instead',
        },
      );
    } catch (e) {
      print('❌ Book backup upload failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to upload backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// List all backups for a device (DEPRECATED)
  /// GET /api/books/list
  Future<Response> _listBackupsLegacy(Request request) async {
    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get backups (legacy list - returns newest backup per book_uuid)
      final backups = await backupService.listBackups(deviceId);

      return Response.ok(
        jsonEncode({
          'success': true,
          'backups': backups,
        }),
        headers: {
          'Content-Type': 'application/json',
          'X-Deprecated': 'Use GET /api/books/{bookId}/backups instead',
        },
      );
    } catch (e) {
      print('❌ List backups failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to list backups: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Download backup data directly (for client-side restore) - DEPRECATED
  /// GET /api/books/download/{backupId}
  Future<Response> _downloadBackupLegacy(Request request, String backupId) async {
    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get backup data (JSON format)
      final backupData = await backupService.getBackup(int.parse(backupId), deviceId);

      if (backupData == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Backup not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      print('✅ Backup data downloaded (JSON): ID $backupId');

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Backup data retrieved successfully',
          'backupData': backupData,
        }),
        headers: {
          'Content-Type': 'application/json',
          'X-Deprecated': 'Use GET /api/backups/{backupId}/download instead',
        },
      );
    } catch (e) {
      print('❌ Download backup failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to download backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Restore a book from backup (DEPRECATED - use new endpoint)
  /// POST /api/books/restore/{backupId}
  Future<Response> _restoreBackupLegacy(Request request, String backupId) async {
    // Just redirect to new restore endpoint
    return _restoreBackup(request, backupId);
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Verify device credentials
  Future<bool> _verifyDevice(String deviceId, String token) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM devices WHERE id = @id AND device_token = @token AND is_active = true',
        parameters: {'id': deviceId, 'token': token},
      );
      return row != null;
    } catch (e) {
      print('❌ Device verification failed: $e');
      return false;
    }
  }
}
