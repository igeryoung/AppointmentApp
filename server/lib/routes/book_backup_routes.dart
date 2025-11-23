import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/book_backup_service.dart';
import '../utils/logger.dart';

/// Router for book backup/restore endpoints
///
/// New API (file-based):
///   POST   /api/books/{bookUuid}/backup
///   GET    /api/books/{bookUuid}/backups
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
  final _logger = Logger('BookBackupRoutes');

  BookBackupRoutes(this.db, {String? backupDir}) {
    backupService = BookBackupService(db, backupDir: backupDir);
  }

  // ============================================================================
  // NEW API (File-based backups)
  // ============================================================================

  /// Router for /api/books/{bookUuid}/... endpoints
  Router get bookScopedRouter {
    final router = Router();

    router.post('/<bookUuid>/backup', _createBackup);
    router.get('/<bookUuid>/backups', _listBookBackups);

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
  /// POST /api/books/{bookUuid}/backup
  Future<Response> _createBackup(Request request, String bookUuid) async {
    final reqLog = _logger.request('POST', '/api/books/$bookUuid/backup');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('Backup creation attempt without credentials', data: {
          'bookUuid': bookUuid,
          'hasDeviceId': deviceId != null,
          'hasDeviceToken': deviceToken != null,
        });

        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Authentication required. Please provide device credentials via X-Device-ID and X-Device-Token headers.',
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
        _logger.warning('Backup creation attempt with invalid credentials', data: {
          'deviceId': deviceId,
          'bookUuid': bookUuid,
        });

        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials. Please check your X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Create file-based backup
      final backupId = await backupService.createFileBackup(
        bookUuid: bookUuid,
        deviceId: deviceId,
        backupName: backupName,
      );

      _logger.success('Book backup created', data: {
        'backupId': backupId,
        'bookUuid': bookUuid,
        'deviceId': deviceId,
      });

      reqLog.complete(200);

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Backup created successfully',
          'backupId': backupId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('Book backup creation failed', error: e, stackTrace: stackTrace, data: {
        'bookUuid': bookUuid,
      });
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to create backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// List all backups for a specific book
  /// GET /api/books/{bookUuid}/backups
  Future<Response> _listBookBackups(Request request, String bookUuid) async {
    final reqLog = _logger.request('GET', '/api/books/$bookUuid/backups');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('List backups attempt without credentials', data: {
          'bookUuid': bookUuid,
        });

        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Authentication required. Please provide device credentials via X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        _logger.warning('List backups attempt with invalid credentials', data: {
          'deviceId': deviceId,
          'bookUuid': bookUuid,
        });

        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials. Please check your X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get backups for this book
      final backups = await backupService.listBookBackups(bookUuid, deviceId);

      reqLog.complete(200);

      return Response.ok(
        jsonEncode({
          'success': true,
          'backups': backups,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('List book backups failed', error: e, stackTrace: stackTrace, data: {
        'bookUuid': bookUuid,
      });
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to list backups: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Download a backup file (streaming)
  /// GET /api/backups/{backupId}/download
  Future<Response> _downloadBackup(Request request, String backupId) async {
    final reqLog = _logger.request('GET', '/api/backups/$backupId/download');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('Download backup attempt without credentials', data: {
          'backupId': backupId,
        });

        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Authentication required. Please provide device credentials via X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        _logger.warning('Download backup attempt with invalid credentials', data: {
          'deviceId': deviceId,
          'backupId': backupId,
        });

        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials. Please check your X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get backup file path
      final filePath = await backupService.getBackupFilePath(int.parse(backupId), deviceId);

      if (filePath == null) {
        _logger.warning('Backup file not found', data: {
          'backupId': backupId,
          'deviceId': deviceId,
        });

        return Response.notFound(
          jsonEncode({
            'success': false,
            'error': 'NOT_FOUND',
            'message': 'Backup file not found',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Stream the file
      final file = File(filePath);
      final fileName = file.path.split('/').last;

      _logger.info('Streaming backup file', data: {
        'fileName': fileName,
        'size': file.lengthSync(),
        'backupId': backupId,
      });

      reqLog.complete(200);

      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': 'application/gzip',
          'Content-Disposition': 'attachment; filename="$fileName"',
          'Content-Length': file.lengthSync().toString(),
        },
      );
    } catch (e, stackTrace) {
      _logger.error('Download backup failed', error: e, stackTrace: stackTrace, data: {
        'backupId': backupId,
      });
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to download backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Restore a book from a backup
  /// POST /api/backups/{backupId}/restore
  Future<Response> _restoreBackup(Request request, String backupId) async {
    final reqLog = _logger.request('POST', '/api/backups/$backupId/restore');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('Restore backup attempt without credentials', data: {
          'backupId': backupId,
        });

        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Authentication required. Please provide device credentials via X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        _logger.warning('Restore backup attempt with invalid credentials', data: {
          'deviceId': deviceId,
          'backupId': backupId,
        });

        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials. Please check your X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Try file-based restore first, fall back to JSON if needed
      try {
        await backupService.restoreFromFileBackup(
          backupId: int.parse(backupId),
          deviceId: deviceId,
        );
        _logger.success('Book restored from file-based backup', data: {
          'backupId': backupId,
          'deviceId': deviceId,
        });
      } catch (e) {
        // Fall back to JSON-based restore for backward compatibility
        if (e.toString().contains('not a file-based backup')) {
          _logger.info('Falling back to JSON-based restore', data: {
            'backupId': backupId,
          });
          await backupService.restoreBookBackup(
            backupId: int.parse(backupId),
            deviceId: deviceId,
          );
          _logger.success('Book restored from JSON backup', data: {
            'backupId': backupId,
            'deviceId': deviceId,
          });
        } else {
          rethrow;
        }
      }

      reqLog.complete(200);

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Book restored successfully',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('Book restore failed', error: e, stackTrace: stackTrace, data: {
        'backupId': backupId,
      });
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to restore backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Delete a backup
  /// DELETE /api/backups/{backupId}
  Future<Response> _deleteBackup(Request request, String backupId) async {
    final reqLog = _logger.request('DELETE', '/api/backups/$backupId');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('Delete backup attempt without credentials', data: {
          'backupId': backupId,
        });

        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Authentication required. Please provide device credentials via X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        _logger.warning('Delete backup attempt with invalid credentials', data: {
          'deviceId': deviceId,
          'backupId': backupId,
        });

        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials. Please check your X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Delete backup
      await backupService.deleteBackup(int.parse(backupId), deviceId);

      _logger.success('Backup deleted', data: {
        'backupId': backupId,
        'deviceId': deviceId,
      });

      reqLog.complete(200);

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Backup deleted successfully',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('Delete backup failed', error: e, stackTrace: stackTrace, data: {
        'backupId': backupId,
      });
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
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
    final reqLog = _logger.request('POST', '/api/books/upload');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('Upload attempt without credentials', data: {
          'hasDeviceId': deviceId != null,
          'hasDeviceToken': deviceToken != null,
        });

        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Authentication required. Please provide device credentials via X-Device-ID and X-Device-Token headers.',
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
        _logger.warning('Upload attempt with invalid credentials', data: {
          'deviceId': deviceId,
        });

        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials. Please check your X-Device-ID and X-Device-Token headers.',
          }),
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

      _logger.success('Book backup uploaded (legacy JSON)', data: {
        'backupId': backupId,
        'bookId': bookId,
        'backupName': backupName,
        'deviceId': deviceId,
      });

      reqLog.complete(200);

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
    } catch (e, stackTrace) {
      _logger.error('Book backup upload failed', error: e, stackTrace: stackTrace);
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to upload backup: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// List all backups for a device (DEPRECATED)
  /// GET /api/books/list
  Future<Response> _listBackupsLegacy(Request request) async {
    final reqLog = _logger.request('GET', '/api/books/list');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('List backups (legacy) attempt without credentials');

        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Authentication required. Please provide device credentials via X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        _logger.warning('List backups (legacy) attempt with invalid credentials', data: {
          'deviceId': deviceId,
        });

        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials. Please check your X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get backups (legacy list - returns newest backup per book_uuid)
      final backups = await backupService.listBackups(deviceId);

      reqLog.complete(200);

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
    } catch (e, stackTrace) {
      _logger.error('List backups (legacy) failed', error: e, stackTrace: stackTrace);
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to list backups: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Download backup data directly (for client-side restore) - DEPRECATED
  /// GET /api/books/download/{backupId}
  Future<Response> _downloadBackupLegacy(Request request, String backupId) async {
    final reqLog = _logger.request('GET', '/api/books/download/$backupId');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('Download backup (legacy) attempt without credentials', data: {
          'backupId': backupId,
        });

        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Authentication required. Please provide device credentials via X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        _logger.warning('Download backup (legacy) attempt with invalid credentials', data: {
          'deviceId': deviceId,
          'backupId': backupId,
        });

        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials. Please check your X-Device-ID and X-Device-Token headers.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get backup data (JSON format)
      final backupData = await backupService.getBackup(int.parse(backupId), deviceId);

      if (backupData == null) {
        _logger.warning('Backup (legacy) not found', data: {
          'backupId': backupId,
          'deviceId': deviceId,
        });

        return Response.notFound(
          jsonEncode({
            'success': false,
            'error': 'NOT_FOUND',
            'message': 'Backup not found',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      _logger.success('Backup data downloaded (legacy JSON)', data: {
        'backupId': backupId,
        'deviceId': deviceId,
      });

      reqLog.complete(200);

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
    } catch (e, stackTrace) {
      _logger.error('Download backup (legacy) failed', error: e, stackTrace: stackTrace, data: {
        'backupId': backupId,
      });
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
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
      _logger.error('Device verification failed', error: e, data: {
        'deviceId': deviceId,
      });
      return false;
    }
  }
}
