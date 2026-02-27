import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/note_service.dart';
import '../utils/logger.dart';

/// Note routes (record-based architecture - notes are per record)
class NoteRoutes {
  final DatabaseConnection db;
  late final NoteService noteService;
  final _logger = Logger('NoteRoutes');

  NoteRoutes(this.db) {
    noteService = NoteService(db);
  }

  Router get router {
    final router = Router();
    router.post('/batch', _batchGetNotes);
    return router;
  }

  Router get bookScopedRouter {
    final router = Router();
    // Record-based routes (internal)
    router.get('/<bookUuid>/records/<recordUuid>/note', _getNote);
    router.post('/<bookUuid>/records/<recordUuid>/note', _createOrUpdateNote);
    router.delete('/<bookUuid>/records/<recordUuid>/note', _deleteNote);
    // Event-based routes (client-facing)
    router.get('/<bookUuid>/events/<eventId>/note', _getNoteByEvent);
    router.post(
      '/<bookUuid>/events/<eventId>/note',
      _createOrUpdateNoteByEvent,
    );
    router.delete('/<bookUuid>/events/<eventId>/note', _deleteNoteByEvent);
    return router;
  }

  Future<Response> _getNote(Request request) async {
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final recordUuid = request.params['recordUuid'] ?? '';

      if (bookUuid.isEmpty || recordUuid.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Invalid bookUuid or recordUuid',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await noteService.verifyBookAccess(deviceId, bookUuid)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'UNAUTHORIZED_BOOK',
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final note = await noteService.getNoteByRecordUuid(recordUuid);
      return Response.ok(
        jsonEncode({'success': true, 'note': note}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to get note: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _createOrUpdateNote(Request request) async {
    final reqLog = _logger.request(
      'POST',
      '/api/books/<bookUuid>/records/<recordUuid>/note',
    );
    reqLog.start();
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final recordUuid = request.params['recordUuid'] ?? '';

      if (bookUuid.isEmpty || recordUuid.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Invalid bookUuid or recordUuid',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final pagesData = json['pages_data'] as String?;
      final version = json['version'] as int?;

      if (pagesData == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Missing pages_data',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final hasWriteAccess = await noteService.verifyBookAccess(
        deviceId,
        bookUuid,
        requireWrite: true,
      );
      if (!hasWriteAccess) {
        if (!await noteService.canDeviceWrite(deviceId)) {
          return Response.forbidden(
            jsonEncode({
              'success': false,
              'error': 'READ_ONLY_DEVICE',
              'message': 'Read-only device cannot modify notes',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'UNAUTHORIZED_BOOK',
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = await noteService.createOrUpdateNoteForRecord(
        recordUuid: recordUuid,
        pagesData: pagesData,
        expectedVersion: version != null ? version - 1 : null,
      );

      if (result.success) {
        reqLog.complete(200);
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
        _logger.warning(
          'Note version conflict (record-based)',
          data: {
            'recordUuid': recordUuid,
            'clientVersion': version,
            'expectedVersion': version != null ? version - 1 : null,
            'serverVersion': result.serverVersion,
          },
        );
        reqLog.complete(
          409,
          data: {
            'error': 'VERSION_CONFLICT',
            'message':
                'Note version conflict. Please pull the latest note and retry.',
          },
        );
        return Response(
          409,
          body: jsonEncode({
            'success': false,
            'conflict': true,
            'error': 'VERSION_CONFLICT',
            'message':
                'Note version conflict. Please pull the latest note and retry.',
            'serverVersion': result.serverVersion,
            'serverNote': result.serverNote,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      reqLog.complete(404, data: {'error': 'NOTE_NOT_FOUND'});
      return Response.notFound(
        jsonEncode({
          'success': false,
          'error': 'NOTE_NOT_FOUND',
          'message': 'Note not found',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      reqLog.fail(e);
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to save note: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _deleteNote(Request request) async {
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final recordUuid = request.params['recordUuid'] ?? '';

      if (bookUuid.isEmpty || recordUuid.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Invalid bookUuid or recordUuid',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final hasWriteAccess = await noteService.verifyBookAccess(
        deviceId,
        bookUuid,
        requireWrite: true,
      );
      if (!hasWriteAccess) {
        if (!await noteService.canDeviceWrite(deviceId)) {
          return Response.forbidden(
            jsonEncode({
              'success': false,
              'error': 'READ_ONLY_DEVICE',
              'message': 'Read-only device cannot modify notes',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'UNAUTHORIZED_BOOK',
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deleted = await noteService.deleteNoteByRecordUuid(recordUuid);
      if (deleted) {
        return Response.ok(
          jsonEncode({'success': true, 'message': 'Note deleted'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return Response.notFound(
        jsonEncode({
          'success': false,
          'error': 'NOTE_NOT_FOUND',
          'message': 'Note not found',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to delete note: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // ============================================
  // Event-based note routes (client-facing)
  // ============================================

  /// Get note by event ID - looks up event to get record_uuid
  Future<Response> _getNoteByEvent(Request request) async {
    final reqLog = _logger.request(
      'GET',
      '/api/books/<bookUuid>/events/<eventId>/note',
    );
    reqLog.start();
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final eventId = request.params['eventId'] ?? '';

      if (bookUuid.isEmpty || eventId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Invalid bookUuid or eventId',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await noteService.verifyBookAccess(deviceId, bookUuid)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'UNAUTHORIZED_BOOK',
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Look up event to get record_uuid
      final recordUuid = await noteService.getRecordUuidByEvent(
        bookUuid: bookUuid,
        eventId: eventId,
      );

      if (recordUuid == null) {
        reqLog.complete(404, data: {'error': 'EVENT_NOT_FOUND'});
        return Response.notFound(
          jsonEncode({
            'success': false,
            'error': 'EVENT_NOT_FOUND',
            'message': 'Event not found',
            'eventId': eventId,
            'bookUuid': bookUuid,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final note = await noteService.getNoteByRecordUuid(recordUuid);
      if (note == null) {
        _logger.info(
          'Note not found for event',
          data: {'eventId': eventId, 'recordUuid': recordUuid},
        );
      } else {
        _logger.info(
          'Note fetched for event',
          data: {
            'eventId': eventId,
            'recordUuid': recordUuid,
            'version': note['version'],
          },
        );
      }
      reqLog.complete(200, data: {'noteFound': note != null});
      return Response.ok(
        jsonEncode({'success': true, 'note': note}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      reqLog.fail(e);
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to get note: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Create/update note by event ID - auto-creates event if eventData provided
  Future<Response> _createOrUpdateNoteByEvent(Request request) async {
    final reqLog = _logger.request(
      'POST',
      '/api/books/<bookUuid>/events/<eventId>/note',
    );
    reqLog.start();
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final eventId = request.params['eventId'] ?? '';

      if (bookUuid.isEmpty || eventId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Invalid bookUuid or eventId',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final pagesData = json['pagesData'] as String?;
      final version = json['version'] as int?;
      final eventData = json['eventData'] as Map<String, dynamic>?;

      if (pagesData == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Missing pagesData',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final hasWriteAccess = await noteService.verifyBookAccess(
        deviceId,
        bookUuid,
        requireWrite: true,
      );
      if (!hasWriteAccess) {
        if (!await noteService.canDeviceWrite(deviceId)) {
          return Response.forbidden(
            jsonEncode({
              'success': false,
              'error': 'READ_ONLY_DEVICE',
              'message': 'Read-only device cannot modify notes',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'UNAUTHORIZED_BOOK',
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Look up event to get record_uuid
      String? recordUuid = await noteService.getRecordUuidByEvent(
        bookUuid: bookUuid,
        eventId: eventId,
      );

      // If event not found, try to create it from eventData
      if (recordUuid == null && eventData != null) {
        final resolvedRecordUuid = await _getOrCreateRecord(eventData);
        if (resolvedRecordUuid == null) {
          return Response.badRequest(
            body: jsonEncode({
              'success': false,
              'error': 'INVALID_EVENT_DATA',
              'message':
                  'Cannot create event: missing record_uuid in eventData',
              'eventId': eventId,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Create the event
        await _createEvent(
          eventId: eventId,
          bookUuid: bookUuid,
          recordUuid: resolvedRecordUuid,
          eventData: eventData,
        );
        recordUuid = resolvedRecordUuid;
      }

      if (recordUuid == null) {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'error': 'EVENT_NOT_FOUND',
            'message': 'Event not found. Provide eventData to auto-create.',
            'eventId': eventId,
            'bookUuid': bookUuid,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = await noteService.createOrUpdateNoteForRecord(
        recordUuid: recordUuid,
        pagesData: pagesData,
        expectedVersion: version != null ? version - 1 : null,
      );

      if (result.success) {
        reqLog.complete(200);
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
        _logger.warning(
          'Note version conflict (event-based)',
          data: {
            'eventId': eventId,
            'recordUuid': recordUuid,
            'clientVersion': version,
            'expectedVersion': version != null ? version - 1 : null,
            'serverVersion': result.serverVersion,
          },
        );
        reqLog.complete(
          409,
          data: {
            'error': 'VERSION_CONFLICT',
            'message':
                'Note version conflict. Please pull the latest note and retry.',
          },
        );
        return Response(
          409,
          body: jsonEncode({
            'success': false,
            'conflict': true,
            'error': 'VERSION_CONFLICT',
            'message':
                'Note version conflict. Please pull the latest note and retry.',
            'serverVersion': result.serverVersion,
            'serverNote': result.serverNote,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      reqLog.complete(404, data: {'error': 'NOTE_NOT_FOUND'});
      return Response.notFound(
        jsonEncode({
          'success': false,
          'error': 'NOTE_NOT_FOUND',
          'message': 'Failed to save note',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      reqLog.fail(e);
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to save note: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Delete note by event ID
  Future<Response> _deleteNoteByEvent(Request request) async {
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final eventId = request.params['eventId'] ?? '';

      if (bookUuid.isEmpty || eventId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Invalid bookUuid or eventId',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final hasWriteAccess = await noteService.verifyBookAccess(
        deviceId,
        bookUuid,
        requireWrite: true,
      );
      if (!hasWriteAccess) {
        if (!await noteService.canDeviceWrite(deviceId)) {
          return Response.forbidden(
            jsonEncode({
              'success': false,
              'error': 'READ_ONLY_DEVICE',
              'message': 'Read-only device cannot modify notes',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'UNAUTHORIZED_BOOK',
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Look up event to get record_uuid
      final recordUuid = await noteService.getRecordUuidByEvent(
        bookUuid: bookUuid,
        eventId: eventId,
      );

      if (recordUuid == null) {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'error': 'EVENT_NOT_FOUND',
            'message': 'Event not found',
            'eventId': eventId,
            'bookUuid': bookUuid,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deleted = await noteService.deleteNoteByRecordUuid(recordUuid);
      if (deleted) {
        return Response.ok(
          jsonEncode({'success': true, 'message': 'Note deleted'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return Response.notFound(
        jsonEncode({
          'success': false,
          'error': 'NOTE_NOT_FOUND',
          'message': 'Note not found',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to delete note: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Helper: Get or create record from eventData
  Future<String?> _getOrCreateRecord(Map<String, dynamic> eventData) async {
    return noteService.getOrCreateRecordFromEventData(eventData);
  }

  /// Helper: Create event from eventData
  Future<void> _createEvent({
    required String eventId,
    required String bookUuid,
    required String recordUuid,
    required Map<String, dynamic> eventData,
  }) async {
    await noteService.createEventIfAbsent(
      eventId: eventId,
      bookUuid: bookUuid,
      recordUuid: recordUuid,
      eventData: eventData,
    );
  }

  Future<Response> _batchGetNotes(Request request) async {
    try {
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'MISSING_CREDENTIALS',
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final recordUuids = (json['record_uuids'] as List?)?.cast<String>() ?? [];

      if (recordUuids.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error': 'INVALID_REQUEST',
            'message': 'Missing record_uuids',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final canWrite = await noteService.canDeviceWrite(deviceId);
      if (!canWrite) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'error': 'READ_ONLY_DEVICE',
            'message': 'Read-only device cannot use notes batch endpoint',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final notes = await noteService.batchGetNotesByRecordUuids(
        recordUuids: recordUuids,
      );
      return Response.ok(
        jsonEncode({'success': true, 'notes': notes, 'count': notes.length}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'INTERNAL_ERROR',
          'message': 'Failed to batch get notes: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
