import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/note_service.dart';

/// Router for note endpoints following Server-Store pattern
///
/// Provides on-demand access to notes rather than full sync:
/// - GET individual note
/// - POST create/update note with optimistic locking
/// - DELETE note
/// - POST batch get notes
class NoteRoutes {
  final DatabaseConnection db;
  late final NoteService noteService;

  NoteRoutes(this.db) {
    noteService = NoteService(db);
  }

  Router get router {
    final router = Router();

    // Note: The batch endpoint is mounted under /batch, not /api/notes/batch
    // because it will be mounted at /api/notes/ in main.dart
    router.post('/batch', _batchGetNotes);

    return router;
  }

  /// Router for book-scoped note endpoints
  /// These are mounted under /api/books/ in main.dart
  Router get bookScopedRouter {
    final router = Router();

    router.get('/<bookId>/events/<eventId>/note', _getNote);
    router.post('/<bookId>/events/<eventId>/note', _createOrUpdateNote);
    router.delete('/<bookId>/events/<eventId>/note', _deleteNote);

    return router;
  }

  /// GET /api/books/{bookId}/events/{eventId}/note
  ///
  /// Get a single note for an event
  ///
  /// Headers:
  ///   X-Device-ID: UUID of the device
  ///   X-Device-Token: Authentication token
  ///
  /// Response:
  ///   200: { success: true, note: {...} } or { success: true, note: null } if not exists
  ///   403: { success: false, message: "Unauthorized" }
  Future<Response> _getNote(Request request) async {
    try {
      // Extract path parameters - bookId is now a UUID string, not an integer
      final bookUuid = request.params['bookId'] ?? '';
      final eventIdStr = request.params['eventId'] ?? '';
      final eventId = int.tryParse(eventIdStr);

      if (bookUuid.isEmpty || eventId == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Invalid bookId or eventId. bookId must be a UUID string, eventId must be an integer.',
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
      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        print('❌ [403] GET /api/books/$bookUuid/events/$eventId/note - Invalid device credentials: deviceId=$deviceId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify book ownership
      if (!await noteService.verifyBookOwnership(deviceId, bookUuid)) {
        print('❌ [403] GET /api/books/$bookUuid/events/$eventId/note - Unauthorized access to book: deviceId=$deviceId, bookUuid=$bookUuid');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify event belongs to book
      if (!await noteService.verifyEventInBook(eventId, bookUuid)) {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'message': 'Event not found in book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get the note
      final note = await noteService.getNote(eventId);

      // Return 200 with null if note doesn't exist (not an error)
      return Response.ok(
        jsonEncode({
          'success': true,
          'note': note,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Get note failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to get note: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/books/{bookId}/events/{eventId}/note
  ///
  /// Create or update a note with optimistic locking
  ///
  /// Headers:
  ///   X-Device-ID: UUID of the device
  ///   X-Device-Token: Authentication token
  ///
  /// Body:
  ///   {
  ///     "strokesData": "JSON string of strokes",
  ///     "version": 1,  // Optional: for updates, omit for creates
  ///     "eventData": {  // Optional: event data for auto-creation if event doesn't exist
  ///       "id": 123,
  ///       "book_uuid": "ca44a444-...",
  ///       "name": "Event name",
  ///       "record_number": "REC001",
  ///       "event_type": "appointment",
  ///       "start_time": 1234567890,  // Unix seconds
  ///       "end_time": 1234567890,    // Unix seconds, optional
  ///       "created_at": 1234567890,  // Unix seconds
  ///       "updated_at": 1234567890,  // Unix seconds
  ///       "is_removed": false,
  ///       "removal_reason": null,
  ///       "original_event_id": null,
  ///       "new_event_id": null
  ///     }
  ///   }
  ///
  /// Response:
  ///   200: { success: true, note: {...}, version: 2 }
  ///   409: { success: false, conflict: true, serverVersion: 3, serverNote: {...} }
  ///   403: { success: false, message: "Unauthorized" }
  Future<Response> _createOrUpdateNote(Request request) async {
    try {
      // Extract path parameters - bookId is now a UUID string, not an integer
      final bookUuid = request.params['bookId'] ?? '';
      final eventIdStr = request.params['eventId'] ?? '';
      final eventId = int.tryParse(eventIdStr);

      print('📝 POST /api/books/$bookUuid/events/$eventIdStr/note');
      print('   bookUuid: $bookUuid (length: ${bookUuid.length})');
      print('   eventId: $eventId (parsed from "$eventIdStr")');

      if (bookUuid.isEmpty || eventId == null) {
        print('❌ [400] Invalid parameters - bookUuid: "$bookUuid", eventId: $eventId');
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Invalid bookId or eventId. bookId must be a UUID string, eventId must be an integer.',
            'received': {
              'bookId': bookUuid,
              'eventId': eventIdStr,
            },
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
      print('   Request body length: ${body.length} bytes');
      final json = jsonDecode(body) as Map<String, dynamic>;
      print('   Request JSON keys: ${json.keys.join(", ")}');

      // Debug: Print raw values and types
      print('   RAW strokesData type: ${json['strokesData']?.runtimeType}');
      print('   RAW strokesData value: ${json['strokesData']}');
      print('   RAW pagesData type: ${json['pagesData']?.runtimeType}');

      // Support both new pagesData and legacy strokesData
      final pagesData = json['pagesData'] as String?;
      final strokesData = json['strokesData'] as String?;
      final version = json['version'] as int?;
      final eventData = json['eventData'] as Map<String, dynamic>?;

      print('   pagesData: ${pagesData != null ? "present (${pagesData.length} chars)" : "null"}');
      print('   strokesData: ${strokesData != null ? "present (${strokesData.length} chars)" : "null"}');
      print('   version: $version');
      print('   eventData: ${eventData != null ? "present" : "null"}');

      // Prefer pagesData, fall back to strokesData for backward compatibility
      final notesDataString = pagesData ?? strokesData;

      if (notesDataString == null) {
        print('❌ [400] Missing both pagesData and strokesData in request');
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Missing pagesData or strokesData',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify device credentials
      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        print('❌ [403] POST /api/books/$bookUuid/events/$eventId/note - Invalid device credentials: deviceId=$deviceId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify book ownership
      if (!await noteService.verifyBookOwnership(deviceId, bookUuid)) {
        print('❌ [403] POST /api/books/$bookUuid/events/$eventId/note - Unauthorized access to book: deviceId=$deviceId, bookUuid=$bookUuid');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify event belongs to book, or create it if eventData is provided
      if (!await noteService.verifyEventInBook(eventId, bookUuid)) {
        // Event doesn't exist - try to create it if eventData was provided
        if (eventData != null) {
          try {
            print('📝 Event not found, attempting auto-creation: event=$eventId, bookUuid=$bookUuid');
            await noteService.createEventIfMissing(
              eventData: eventData,
              deviceId: deviceId,
            );

            // Verify again after creation
            if (!await noteService.verifyEventInBook(eventId, bookUuid)) {
              return Response.notFound(
                jsonEncode({
                  'success': false,
                  'message': 'Event creation succeeded but verification failed',
                }),
                headers: {'Content-Type': 'application/json'},
              );
            }
          } catch (e) {
            print('❌ Auto-create event failed: $e');
            return Response.internalServerError(
              body: jsonEncode({
                'success': false,
                'message': 'Failed to create event: $e',
              }),
              headers: {'Content-Type': 'application/json'},
            );
          }
        } else {
          // Event doesn't exist and no eventData provided
          return Response.notFound(
            jsonEncode({
              'success': false,
              'message': 'Event not found in book',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // Create or update the note
      // Client sends its current version (after increment), but we need the version it's based on
      // So expectedVersion = client version - 1 (or null for first sync)
      final expectedVersion = version != null ? version - 1 : null;
      final result = await noteService.createOrUpdateNote(
        eventId: eventId,
        deviceId: deviceId,
        pagesData: pagesData,
        strokesData: strokesData,
        expectedVersion: expectedVersion,
      );

      if (result.success) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'note': result.note,
            'version': result.note!['version'],
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
            'serverNote': result.serverNote,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Note not found or deleted
      return Response.notFound(
        jsonEncode({
          'success': false,
          'message': 'Note not found or deleted',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Create/update note failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to create/update note: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// DELETE /api/books/{bookId}/events/{eventId}/note
  ///
  /// Delete a note (soft delete)
  ///
  /// Headers:
  ///   X-Device-ID: UUID of the device
  ///   X-Device-Token: Authentication token
  ///
  /// Response:
  ///   200: { success: true, message: "Note deleted" }
  ///   404: { success: false, message: "Note not found" }
  ///   403: { success: false, message: "Unauthorized" }
  Future<Response> _deleteNote(Request request) async {
    try {
      // Extract path parameters - bookId is now a UUID string, not an integer
      final bookUuid = request.params['bookId'] ?? '';
      final eventIdStr = request.params['eventId'] ?? '';
      final eventId = int.tryParse(eventIdStr);

      if (bookUuid.isEmpty || eventId == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Invalid bookId or eventId. bookId must be a UUID string, eventId must be an integer.',
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
      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        print('❌ [403] DELETE /api/books/$bookUuid/events/$eventId/note - Invalid device credentials: deviceId=$deviceId');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify book ownership
      if (!await noteService.verifyBookOwnership(deviceId, bookUuid)) {
        print('❌ [403] DELETE /api/books/$bookUuid/events/$eventId/note - Unauthorized access to book: deviceId=$deviceId, bookUuid=$bookUuid');
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify event belongs to book
      if (!await noteService.verifyEventInBook(eventId, bookUuid)) {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'message': 'Event not found in book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Delete the note
      final deleted = await noteService.deleteNote(eventId);

      if (deleted) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'message': 'Note deleted',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'message': 'Note not found',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      print('❌ Delete note failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to delete note: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/notes/batch
  ///
  /// Batch get notes for multiple events
  ///
  /// Headers:
  ///   X-Device-ID: UUID of the device
  ///   X-Device-Token: Authentication token
  ///
  /// Body:
  ///   {
  ///     "eventIds": [1, 2, 3, 4, 5]
  ///   }
  ///
  /// Response:
  ///   200: {
  ///     success: true,
  ///     notes: [...]  // Only notes from events in books owned by device
  ///   }
  ///
  /// Note: Authorization is built into the query - only returns notes
  /// from events in books owned by the authenticated device
  Future<Response> _batchGetNotes(Request request) async {
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
      final eventIdsJson = json['eventIds'] as List?;

      if (eventIdsJson == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Missing eventIds',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final eventIds = eventIdsJson.map((id) => id as int).toList();

      // Verify device credentials
      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Batch get notes (authorization handled in query)
      final notes = await noteService.batchGetNotes(
        deviceId: deviceId,
        eventIds: eventIds,
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'notes': notes,
          'count': notes.length,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Batch get notes failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to batch get notes: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
