import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../utils/logger.dart';

/// Router for book creation endpoint
///
/// Book Creation API:
///   POST   /api/create-books
class BookBackupRoutes {
  final DatabaseConnection db;
  final _logger = Logger('BookBackupRoutes');

  BookBackupRoutes(this.db, {String? backupDir});

  // ============================================================================
  // BOOK CREATION API
  // ============================================================================

  /// Router for /api/create-books endpoint
  Router get createBookRouter {
    final router = Router();

    router.post('/', _createBook);

    return router;
  }

  /// Create a new book and return its UUID
  /// POST /api/create-books
  Future<Response> _createBook(Request request) async {
    final reqLog = _logger.request('POST', '/api/create-books');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('Create book attempt without credentials', data: {
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

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        _logger.warning('Create book attempt with invalid credentials', data: {
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

      // Parse request body
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final name = json['name'] as String?;
      final createdAtStr = json['created_at'] as String?;

      if (name == null || name.trim().isEmpty) {
        _logger.warning('Create book attempt with missing or empty name', data: {
          'deviceId': deviceId,
        });

        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Book name is required and cannot be empty.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final createdAt = createdAtStr != null
          ? DateTime.parse(createdAtStr)
          : DateTime.now();

      // Create book in database with UUID as primary key
      final bookUuid = await db.querySingle(
        '''
        INSERT INTO books (book_uuid, device_id, name, created_at, updated_at, synced_at, version, is_deleted)
        VALUES (uuid_generate_v4(), @deviceId, @name, @createdAt, @updatedAt, @syncedAt, 1, false)
        RETURNING book_uuid
        ''',
        parameters: {
          'deviceId': deviceId,
          'name': name.trim(),
          'createdAt': createdAt.toUtc(),
          'updatedAt': createdAt.toUtc(),
          'syncedAt': DateTime.now().toUtc(),
        },
      );

      final uuid = bookUuid!['book_uuid'] as String;

      _logger.success('Book created', data: {
        'uuid': uuid,
        'name': name,
        'deviceId': deviceId,
      });

      reqLog.complete(200);

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Book created successfully',
          'uuid': uuid,
          'name': name.trim(),
          'device_id': deviceId,
          'created_at': createdAt.toUtc().toIso8601String(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('Book creation failed', error: e, stackTrace: stackTrace);
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to create book: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
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
