import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/note_service.dart';

/// Note routes (record-based architecture - notes are per record)
class NoteRoutes {
  final DatabaseConnection db;
  late final NoteService noteService;

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
    router.post('/<bookUuid>/events/<eventId>/note', _createOrUpdateNoteByEvent);
    router.delete('/<bookUuid>/events/<eventId>/note', _deleteNoteByEvent);
    return router;
  }

  Future<Response> _getNote(Request request) async {
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final recordUuid = request.params['recordUuid'] ?? '';

      if (bookUuid.isEmpty || recordUuid.isEmpty) {
        return Response.badRequest(body: jsonEncode({'success': false, 'message': 'Invalid bookUuid or recordUuid'}),
            headers: {'Content-Type': 'application/json'});
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(401, body: jsonEncode({'success': false, 'message': 'Missing device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Unauthorized access to book'}),
            headers: {'Content-Type': 'application/json'});
      }

      final note = await noteService.getNoteByRecordUuid(recordUuid);
      return Response.ok(jsonEncode({'success': true, 'note': note}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'message': 'Failed to get note: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _createOrUpdateNote(Request request) async {
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final recordUuid = request.params['recordUuid'] ?? '';

      if (bookUuid.isEmpty || recordUuid.isEmpty) {
        return Response.badRequest(body: jsonEncode({'success': false, 'message': 'Invalid bookUuid or recordUuid'}),
            headers: {'Content-Type': 'application/json'});
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(401, body: jsonEncode({'success': false, 'message': 'Missing device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final pagesData = json['pages_data'] as String?;
      final version = json['version'] as int?;

      if (pagesData == null) {
        return Response.badRequest(body: jsonEncode({'success': false, 'message': 'Missing pages_data'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Unauthorized access to book'}),
            headers: {'Content-Type': 'application/json'});
      }

      final result = await noteService.createOrUpdateNoteForRecord(
        recordUuid: recordUuid,
        pagesData: pagesData,
        expectedVersion: version != null ? version - 1 : null,
      );

      if (result.success) {
        return Response.ok(jsonEncode({'success': true, 'note': result.note, 'version': result.note!['version']}),
            headers: {'Content-Type': 'application/json'});
      }

      if (result.hasConflict) {
        return Response(409, body: jsonEncode({
          'success': false, 'conflict': true,
          'serverVersion': result.serverVersion, 'serverNote': result.serverNote
        }), headers: {'Content-Type': 'application/json'});
      }

      return Response.notFound(jsonEncode({'success': false, 'message': 'Note not found'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'message': 'Failed to save note: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _deleteNote(Request request) async {
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final recordUuid = request.params['recordUuid'] ?? '';

      if (bookUuid.isEmpty || recordUuid.isEmpty) {
        return Response.badRequest(body: jsonEncode({'success': false, 'message': 'Invalid bookUuid or recordUuid'}),
            headers: {'Content-Type': 'application/json'});
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(401, body: jsonEncode({'success': false, 'message': 'Missing device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Unauthorized access to book'}),
            headers: {'Content-Type': 'application/json'});
      }

      final deleted = await noteService.deleteNoteByRecordUuid(recordUuid);
      if (deleted) {
        return Response.ok(jsonEncode({'success': true, 'message': 'Note deleted'}),
            headers: {'Content-Type': 'application/json'});
      }
      return Response.notFound(jsonEncode({'success': false, 'message': 'Note not found'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'message': 'Failed to delete note: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  // ============================================
  // Event-based note routes (client-facing)
  // ============================================

  /// Get note by event ID - looks up event to get record_uuid
  Future<Response> _getNoteByEvent(Request request) async {
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final eventId = request.params['eventId'] ?? '';

      if (bookUuid.isEmpty || eventId.isEmpty) {
        return Response.badRequest(body: jsonEncode({'success': false, 'message': 'Invalid bookUuid or eventId'}),
            headers: {'Content-Type': 'application/json'});
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(401, body: jsonEncode({'success': false, 'message': 'Missing device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Unauthorized access to book'}),
            headers: {'Content-Type': 'application/json'});
      }

      // Look up event to get record_uuid
      final event = await db.querySingle(
        'SELECT record_uuid FROM events WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false',
        parameters: {'eventId': eventId, 'bookUuid': bookUuid},
      );

      if (event == null) {
        return Response.notFound(jsonEncode({
          'success': false,
          'message': 'Event not found',
          'eventId': eventId,
          'bookUuid': bookUuid,
        }), headers: {'Content-Type': 'application/json'});
      }

      final recordUuid = event['record_uuid'] as String;
      final note = await noteService.getNoteByRecordUuid(recordUuid);
      return Response.ok(jsonEncode({'success': true, 'note': note}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'message': 'Failed to get note: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  /// Create/update note by event ID - auto-creates event if eventData provided
  Future<Response> _createOrUpdateNoteByEvent(Request request) async {
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final eventId = request.params['eventId'] ?? '';

      if (bookUuid.isEmpty || eventId.isEmpty) {
        return Response.badRequest(body: jsonEncode({'success': false, 'message': 'Invalid bookUuid or eventId'}),
            headers: {'Content-Type': 'application/json'});
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(401, body: jsonEncode({'success': false, 'message': 'Missing device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final pagesData = json['pagesData'] as String?;
      final version = json['version'] as int?;
      final eventData = json['eventData'] as Map<String, dynamic>?;

      if (pagesData == null) {
        return Response.badRequest(body: jsonEncode({'success': false, 'message': 'Missing pagesData'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Unauthorized access to book'}),
            headers: {'Content-Type': 'application/json'});
      }

      // Look up event to get record_uuid
      var event = await db.querySingle(
        'SELECT record_uuid FROM events WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false',
        parameters: {'eventId': eventId, 'bookUuid': bookUuid},
      );

      // If event not found, try to create it from eventData
      if (event == null && eventData != null) {
        final recordUuid = await _getOrCreateRecord(eventData);
        if (recordUuid == null) {
          return Response.badRequest(body: jsonEncode({
            'success': false,
            'message': 'Cannot create event: missing record_uuid in eventData',
            'eventId': eventId,
          }), headers: {'Content-Type': 'application/json'});
        }

        // Create the event
        await _createEvent(eventId: eventId, bookUuid: bookUuid, recordUuid: recordUuid, eventData: eventData);
        event = {'record_uuid': recordUuid};
      }

      if (event == null) {
        return Response.notFound(jsonEncode({
          'success': false,
          'message': 'Event not found. Provide eventData to auto-create.',
          'eventId': eventId,
          'bookUuid': bookUuid,
        }), headers: {'Content-Type': 'application/json'});
      }

      final recordUuid = event['record_uuid'] as String;

      final result = await noteService.createOrUpdateNoteForRecord(
        recordUuid: recordUuid,
        pagesData: pagesData,
        expectedVersion: version != null ? version - 1 : null,
      );

      if (result.success) {
        return Response.ok(jsonEncode({'success': true, 'note': result.note, 'version': result.note!['version']}),
            headers: {'Content-Type': 'application/json'});
      }

      if (result.hasConflict) {
        return Response(409, body: jsonEncode({
          'success': false, 'conflict': true,
          'serverVersion': result.serverVersion, 'serverNote': result.serverNote
        }), headers: {'Content-Type': 'application/json'});
      }

      return Response.notFound(jsonEncode({'success': false, 'message': 'Failed to save note'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'message': 'Failed to save note: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  /// Delete note by event ID
  Future<Response> _deleteNoteByEvent(Request request) async {
    try {
      final bookUuid = request.params['bookUuid'] ?? '';
      final eventId = request.params['eventId'] ?? '';

      if (bookUuid.isEmpty || eventId.isEmpty) {
        return Response.badRequest(body: jsonEncode({'success': false, 'message': 'Invalid bookUuid or eventId'}),
            headers: {'Content-Type': 'application/json'});
      }

      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(401, body: jsonEncode({'success': false, 'message': 'Missing device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Unauthorized access to book'}),
            headers: {'Content-Type': 'application/json'});
      }

      // Look up event to get record_uuid
      final event = await db.querySingle(
        'SELECT record_uuid FROM events WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false',
        parameters: {'eventId': eventId, 'bookUuid': bookUuid},
      );

      if (event == null) {
        return Response.notFound(jsonEncode({
          'success': false,
          'message': 'Event not found',
          'eventId': eventId,
          'bookUuid': bookUuid,
        }), headers: {'Content-Type': 'application/json'});
      }

      final recordUuid = event['record_uuid'] as String;
      final deleted = await noteService.deleteNoteByRecordUuid(recordUuid);
      if (deleted) {
        return Response.ok(jsonEncode({'success': true, 'message': 'Note deleted'}),
            headers: {'Content-Type': 'application/json'});
      }
      return Response.notFound(jsonEncode({'success': false, 'message': 'Note not found'}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'message': 'Failed to delete note: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  /// Helper: Get or create record from eventData
  Future<String?> _getOrCreateRecord(Map<String, dynamic> eventData) async {
    // If record_uuid is provided directly, use it
    final recordUuid = eventData['record_uuid'] as String?;
    if (recordUuid != null && recordUuid.isNotEmpty) {
      // Check if record exists, if not create it
      final existing = await db.querySingle(
        'SELECT record_uuid FROM records WHERE record_uuid = @recordUuid',
        parameters: {'recordUuid': recordUuid},
      );
      if (existing != null) {
        return recordUuid;
      }
      // Create record with provided uuid
      final recordNumber = eventData['record_number'] as String? ?? '';
      final title = eventData['title'] as String? ?? '';
      await db.query(
        '''INSERT INTO records (record_uuid, record_number, name)
           VALUES (@recordUuid, @recordNumber, @name)
           ON CONFLICT (record_uuid) DO NOTHING''',
        parameters: {'recordUuid': recordUuid, 'recordNumber': recordNumber, 'name': title},
      );
      return recordUuid;
    }
    return null;
  }

  /// Helper: Create event from eventData
  Future<void> _createEvent({
    required String eventId,
    required String bookUuid,
    required String recordUuid,
    required Map<String, dynamic> eventData,
  }) async {
    final title = eventData['title'] as String? ?? '';
    final eventTypes = eventData['event_types'] as String? ?? '["other"]';
    final hasChargeItems = eventData['has_charge_items'] == 1 || eventData['has_charge_items'] == true;

    // Parse timestamps (client sends seconds since epoch)
    final startTimeSeconds = eventData['start_time'] as int?;
    final endTimeSeconds = eventData['end_time'] as int?;
    final startTime = startTimeSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(startTimeSeconds * 1000, isUtc: true)
        : DateTime.now().toUtc();
    final endTime = endTimeSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(endTimeSeconds * 1000, isUtc: true)
        : null;

    await db.query(
      '''INSERT INTO events (id, book_uuid, record_uuid, title, event_types, has_charge_items, start_time, end_time)
         VALUES (@id, @bookUuid, @recordUuid, @title, @eventTypes, @hasChargeItems, @startTime, @endTime)
         ON CONFLICT (id) DO NOTHING''',
      parameters: {
        'id': eventId,
        'bookUuid': bookUuid,
        'recordUuid': recordUuid,
        'title': title,
        'eventTypes': eventTypes,
        'hasChargeItems': hasChargeItems,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
      },
    );
  }

  Future<Response> _batchGetNotes(Request request) async {
    try {
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(401, body: jsonEncode({'success': false, 'message': 'Missing device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final recordUuids = (json['record_uuids'] as List?)?.cast<String>() ?? [];

      if (recordUuids.isEmpty) {
        return Response.badRequest(body: jsonEncode({'success': false, 'message': 'Missing record_uuids'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      final notes = await noteService.batchGetNotesByRecordUuids(recordUuids: recordUuids);
      return Response.ok(jsonEncode({'success': true, 'notes': notes, 'count': notes.length}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'message': 'Failed to batch get notes: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }
}
