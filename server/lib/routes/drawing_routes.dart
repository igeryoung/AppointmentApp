import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/drawing_service.dart';

/// Router for schedule drawing endpoints following Server-Store pattern
///
/// Provides on-demand access to schedule drawings using composite key:
/// (book_id, date, view_mode)
///
/// - GET individual drawing
/// - POST create/update drawing with optimistic locking
/// - DELETE drawing
/// - POST batch get drawings by date range
class DrawingRoutes {
  final DatabaseConnection db;
  late final DrawingService drawingService;

  DrawingRoutes(this.db) {
    drawingService = DrawingService(db);
  }

  Router get router {
    final router = Router();

    // Batch endpoint mounted under /api/drawings/
    router.post('/batch', _batchGetDrawings);

    return router;
  }

  /// Router for book-scoped drawing endpoints
  /// These are mounted under /api/books/ in main.dart
  Router get bookScopedRouter {
    final router = Router();

    router.get('/<bookId>/drawings', _getDrawing);
    router.post('/<bookId>/drawings', _createOrUpdateDrawing);
    router.delete('/<bookId>/drawings', _deleteDrawing);

    return router;
  }

  /// GET /api/books/{bookId}/drawings?date=2025-10-23&viewMode=1
  ///
  /// Get a single drawing for a specific date and view mode
  ///
  /// Headers:
  ///   X-Device-ID: UUID of the device
  ///   X-Device-Token: Authentication token
  ///
  /// Query Parameters:
  ///   date: ISO date string (e.g., "2025-10-23")
  ///   viewMode: Integer (0: Day, 1: 3-Day, 2: Week)
  ///
  /// Response:
  ///   200: { success: true, drawing: {...} } or { success: true, drawing: null } if not exists
  ///   403: { success: false, message: "Unauthorized" }
  Future<Response> _getDrawing(Request request) async {
    try {
      // Extract path parameters
      final bookId = int.tryParse(request.params['bookId'] ?? '');

      // Extract query parameters
      final date = request.url.queryParameters['date'];
      final viewModeStr = request.url.queryParameters['viewMode'];
      final viewMode = int.tryParse(viewModeStr ?? '');

      if (bookId == null || date == null || viewMode == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Invalid bookId, date, or viewMode',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

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

      // Verify device credentials
      if (!await drawingService.verifyDeviceAccess(deviceId, deviceToken)) {
        print('❌ [403] GET /api/books/$bookId/drawings?date=$date&viewMode=$viewMode - Invalid device credentials: deviceId=$deviceId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify book ownership
      if (!await drawingService.verifyBookOwnership(deviceId, bookId)) {
        print('❌ [403] GET /api/books/$bookId/drawings?date=$date&viewMode=$viewMode - Unauthorized access to book: deviceId=$deviceId, bookId=$bookId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get the drawing
      final drawing = await drawingService.getDrawing(bookId, date, viewMode);

      // Return 200 with null if drawing doesn't exist (not an error)
      return Response.ok(
        jsonEncode({
          'success': true,
          'drawing': drawing,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Get drawing failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to get drawing: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/books/{bookId}/drawings
  ///
  /// Create or update a drawing with optimistic locking
  ///
  /// Headers:
  ///   X-Device-ID: UUID of the device
  ///   X-Device-Token: Authentication token
  ///
  /// Body:
  ///   {
  ///     "date": "2025-10-23",
  ///     "viewMode": 1,
  ///     "strokesData": "JSON string of strokes",
  ///     "version": 1  // Optional: for updates, omit for creates
  ///   }
  ///
  /// Response:
  ///   200: { success: true, drawing: {...}, version: 2 }
  ///   409: { success: false, conflict: true, serverVersion: 3, serverDrawing: {...} }
  ///   403: { success: false, message: "Unauthorized" }
  Future<Response> _createOrUpdateDrawing(Request request) async {
    try {
      // Extract path parameters
      final bookId = int.tryParse(request.params['bookId'] ?? '');

      if (bookId == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Invalid bookId',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

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
      final date = json['date'] as String?;
      final viewMode = json['viewMode'] as int?;
      final strokesData = json['strokesData'] as String?;
      final version = json['version'] as int?;

      if (date == null || viewMode == null || strokesData == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Missing date, viewMode, or strokesData',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device credentials
      if (!await drawingService.verifyDeviceAccess(deviceId, deviceToken)) {
        print('❌ [403] POST /api/books/$bookId/drawings - Invalid device credentials: deviceId=$deviceId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify book ownership
      if (!await drawingService.verifyBookOwnership(deviceId, bookId)) {
        print('❌ [403] POST /api/books/$bookId/drawings - Unauthorized access to book: deviceId=$deviceId, bookId=$bookId, date=$date, viewMode=$viewMode');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Create or update the drawing
      final result = await drawingService.createOrUpdateDrawing(
        bookId: bookId,
        deviceId: deviceId,
        date: date,
        viewMode: viewMode,
        strokesData: strokesData,
        expectedVersion: version,
      );

      if (result.success) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'drawing': result.drawing,
            'version': result.drawing!['version'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (result.hasConflict) {
        return Response(
          409,
          body: jsonEncode({
            'success': false,
            'conflict': true,
            'serverVersion': result.serverVersion,
            'serverDrawing': result.serverDrawing,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Drawing not found or deleted
      return Response.notFound(
        jsonEncode({
          'success': false,
          'message': 'Drawing not found or deleted',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Create/update drawing failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to create/update drawing: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// DELETE /api/books/{bookId}/drawings?date=2025-10-23&viewMode=1
  ///
  /// Delete a drawing (soft delete)
  ///
  /// Headers:
  ///   X-Device-ID: UUID of the device
  ///   X-Device-Token: Authentication token
  ///
  /// Query Parameters:
  ///   date: ISO date string (e.g., "2025-10-23")
  ///   viewMode: Integer (0: Day, 1: 3-Day, 2: Week)
  ///
  /// Response:
  ///   200: { success: true, message: "Drawing deleted" }
  ///   404: { success: false, message: "Drawing not found" }
  ///   403: { success: false, message: "Unauthorized" }
  Future<Response> _deleteDrawing(Request request) async {
    try {
      // Extract path parameters
      final bookId = int.tryParse(request.params['bookId'] ?? '');

      // Extract query parameters
      final date = request.url.queryParameters['date'];
      final viewModeStr = request.url.queryParameters['viewMode'];
      final viewMode = int.tryParse(viewModeStr ?? '');

      if (bookId == null || date == null || viewMode == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Invalid bookId, date, or viewMode',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

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

      // Verify device credentials
      if (!await drawingService.verifyDeviceAccess(deviceId, deviceToken)) {
        print('❌ [403] DELETE /api/books/$bookId/drawings?date=$date&viewMode=$viewMode - Invalid device credentials: deviceId=$deviceId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify book ownership
      if (!await drawingService.verifyBookOwnership(deviceId, bookId)) {
        print('❌ [403] DELETE /api/books/$bookId/drawings?date=$date&viewMode=$viewMode - Unauthorized access to book: deviceId=$deviceId, bookId=$bookId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Delete the drawing
      final deleted = await drawingService.deleteDrawing(bookId, date, viewMode);

      if (deleted) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'message': 'Drawing deleted',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'message': 'Drawing not found',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      print('❌ Delete drawing failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to delete drawing: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/drawings/batch
  ///
  /// Batch get drawings for a date range and view mode
  ///
  /// Headers:
  ///   X-Device-ID: UUID of the device
  ///   X-Device-Token: Authentication token
  ///
  /// Body:
  ///   {
  ///     "bookId": 1,
  ///     "dateRange": {
  ///       "start": "2025-10-23",
  ///       "end": "2025-10-30"
  ///     },
  ///     "viewMode": 1
  ///   }
  ///
  /// Response:
  ///   200: {
  ///     success: true,
  ///     drawings: [...]  // Only drawings from books owned by device
  ///   }
  ///
  /// Note: Authorization is built into the query - only returns drawings
  /// from books owned by the authenticated device
  Future<Response> _batchGetDrawings(Request request) async {
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
      final bookId = json['bookId'] as int?;
      final dateRange = json['dateRange'] as Map<String, dynamic>?;
      final viewMode = json['viewMode'] as int?;

      if (bookId == null || dateRange == null || viewMode == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Missing bookId, dateRange, or viewMode',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final startDate = dateRange['start'] as String?;
      final endDate = dateRange['end'] as String?;

      if (startDate == null || endDate == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Missing start or end date in dateRange',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device credentials
      if (!await drawingService.verifyDeviceAccess(deviceId, deviceToken)) {
        print('❌ [403] POST /api/drawings/batch - Invalid device credentials: deviceId=$deviceId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify book ownership
      if (!await drawingService.verifyBookOwnership(deviceId, bookId)) {
        print('❌ [403] POST /api/drawings/batch - Unauthorized access to book: deviceId=$deviceId, bookId=$bookId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Batch get drawings (authorization handled in query)
      final drawings = await drawingService.batchGetDrawings(
        deviceId: deviceId,
        bookId: bookId,
        startDate: startDate,
        endDate: endDate,
        viewMode: viewMode,
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'drawings': drawings,
          'count': drawings.length,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Batch get drawings failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to batch get drawings: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
