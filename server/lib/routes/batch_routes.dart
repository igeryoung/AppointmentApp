import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/batch_service.dart';

/// Router for batch operation endpoints
///
/// Provides atomic batch operations for notes and drawings:
/// - POST /api/batch/save - Save multiple notes and drawings in one transaction
///
/// As Linus says: "Batch operations aren't premature optimization.
/// They're the difference between usable and unusable."
class BatchRoutes {
  final DatabaseConnection db;
  late final BatchService batchService;

  BatchRoutes(this.db) {
    batchService = BatchService(db);
  }

  Router get router {
    final router = Router();

    router.post('/save', _batchSave);

    return router;
  }

  /// POST /api/batch/save
  ///
  /// Save multiple notes and drawings in a single atomic transaction.
  ///
  /// Strategy: All-or-nothing
  /// - All operations succeed → COMMIT, return success
  /// - Any operation fails → ROLLBACK, return error
  ///
  /// Headers:
  ///   X-Device-ID: UUID of the device
  ///   X-Device-Token: Authentication token
  ///
  /// Request Body:
  /// {
  ///   "notes": [
  ///     {
  ///       "eventId": 1,
  ///       "bookId": 1,
  ///       "strokesData": "...",
  ///       "version": 2  // Optional: for updates with optimistic locking
  ///     }
  ///   ],
  ///   "drawings": [
  ///     {
  ///       "bookId": 1,
  ///       "date": "2025-10-23T00:00:00Z",
  ///       "viewMode": 0,
  ///       "strokesData": "...",
  ///       "version": 1  // Optional: for updates with optimistic locking
  ///     }
  ///   ]
  /// }
  ///
  /// Response 200:
  /// {
  ///   "success": true,
  ///   "results": {
  ///     "notes": { "succeeded": 10, "failed": 0 },
  ///     "drawings": { "succeeded": 5, "failed": 0 }
  ///   }
  /// }
  ///
  /// Response 400/409/500:
  /// {
  ///   "success": false,
  ///   "message": "Error description",
  ///   "results": {
  ///     "notes": { "succeeded": 0, "failed": 0 },
  ///     "drawings": { "succeeded": 0, "failed": 0 }
  ///   }
  /// }
  Future<Response> _batchSave(Request request) async {
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
      final bodyString = await request.readAsString();
      final body = jsonDecode(bodyString) as Map<String, dynamic>;

      final notes = (body['notes'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];

      final drawings = (body['drawings'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];

      // Validate payload size (prevent DoS)
      final totalItems = notes.length + drawings.length;
      if (totalItems > 1000) {
        return Response(
          413,
          body: jsonEncode({
            'success': false,
            'message': 'Payload too large: maximum 1000 items allowed (got $totalItems)',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Execute batch save
      final result = await batchService.batchSave(
        deviceId: deviceId,
        deviceToken: deviceToken,
        notes: notes,
        drawings: drawings,
      );

      if (result.success) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'results': result.results,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        // Determine appropriate status code from error message
        int statusCode = 400;
        if (result.errorMessage?.contains('Invalid device credentials') == true) {
          statusCode = 403;
        } else if (result.errorMessage?.contains('Unauthorized') == true) {
          statusCode = 403;
        } else if (result.errorMessage?.contains('Version conflict') == true) {
          statusCode = 409;
        }

        return Response(
          statusCode,
          body: jsonEncode({
            'success': false,
            'message': result.errorMessage,
            'results': result.results,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      print('❌ Batch save endpoint error: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Internal server error: ${e.toString()}',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
