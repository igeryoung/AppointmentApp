import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/book_pull_service.dart';
import '../utils/logger.dart';

/// Router for book pull endpoints (Server → Local sync)
///
/// API Endpoints:
///   GET  /api/books/list?search={query}  - List all books for device with optional search
///   POST /api/books/pull/{bookUuid}      - Pull complete book data from server
///   GET  /api/books/{bookUuid}/info      - Get book metadata only
class BookPullRoutes {
  final DatabaseConnection db;
  late final BookPullService pullService;
  final _logger = Logger('BookPullRoutes');

  BookPullRoutes(this.db) {
    pullService = BookPullService(db);
  }

  /// Router for /api/books/... endpoints
  Router get router {
    final router = Router();

    router.get('/list', _listBooks);
    router.post('/pull/<bookUuid>', _pullBook);
    router.get('/<bookUuid>/info', _getBookInfo);

    return router;
  }

  /// List all books for authenticated device with optional search
  /// GET /api/books/list?search={query}
  Future<Response> _listBooks(Request request) async {
    final reqLog = _logger.request('GET', '/api/books/list');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('List books attempt without credentials', data: {
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
        _logger.warning('List books attempt with invalid credentials', data: {
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

      // Get search query parameter
      final searchQuery = request.url.queryParameters['search'];

      // List books
      final books = await pullService.listBooksForDevice(
        deviceId,
        searchQuery: searchQuery,
      );

      _logger.success('Books listed', data: {
        'deviceId': deviceId,
        'bookCount': books.length,
        'hasSearch': searchQuery != null,
      });

      reqLog.complete(200);

      return Response.ok(
        jsonEncode({
          'success': true,
          'books': books,
          'count': books.length,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('List books failed', error: e, stackTrace: stackTrace);
      reqLog.fail(e, stackTrace: stackTrace);

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to list books: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Pull complete book data from server (book + events + notes + drawings)
  /// POST /api/books/pull/{bookUuid}
  Future<Response> _pullBook(Request request, String bookUuid) async {
    final reqLog = _logger.request('POST', '/api/books/pull/$bookUuid');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('Pull book attempt without credentials', data: {
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

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        _logger.warning('Pull book attempt with invalid credentials', data: {
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

      // Get complete book data
      final bookData = await pullService.getCompleteBookData(
        bookUuid,
        deviceId,
      );

      _logger.success('Book pulled', data: {
        'bookUuid': bookUuid,
        'deviceId': deviceId,
        'eventCount': (bookData['events'] as List).length,
        'noteCount': (bookData['notes'] as List).length,
        'drawingCount': (bookData['drawings'] as List).length,
      });

      reqLog.complete(200);

      return Response.ok(
        jsonEncode({
          'success': true,
          'data': bookData,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('Pull book failed', error: e, stackTrace: stackTrace, data: {
        'bookUuid': bookUuid,
      });
      reqLog.fail(e, stackTrace: stackTrace);

      // Handle specific errors
      if (e.toString().contains('Book not found')) {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'error': 'BOOK_NOT_FOUND',
            'message': 'Book not found or does not belong to this device: $bookUuid',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to pull book: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Get book metadata only (without events/notes/drawings)
  /// GET /api/books/{bookUuid}/info
  Future<Response> _getBookInfo(Request request, String bookUuid) async {
    final reqLog = _logger.request('GET', '/api/books/$bookUuid/info');
    reqLog.start();

    try {
      // Extract auth headers
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        _logger.warning('Get book info attempt without credentials', data: {
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

      // Verify device
      if (!await _verifyDevice(deviceId, deviceToken)) {
        _logger.warning('Get book info attempt with invalid credentials', data: {
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

      // Get book metadata
      final bookInfo = await pullService.getBookMetadata(
        bookUuid,
        deviceId,
      );

      _logger.success('Book info retrieved', data: {
        'bookUuid': bookUuid,
        'deviceId': deviceId,
      });

      reqLog.complete(200);

      return Response.ok(
        jsonEncode({
          'success': true,
          'book': bookInfo,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('Get book info failed', error: e, stackTrace: stackTrace, data: {
        'bookUuid': bookUuid,
      });
      reqLog.fail(e, stackTrace: stackTrace);

      // Handle specific errors
      if (e.toString().contains('Book not found')) {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'error': 'BOOK_NOT_FOUND',
            'message': 'Book not found or does not belong to this device: $bookUuid',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to get book info: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

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
