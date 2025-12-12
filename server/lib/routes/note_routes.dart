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
    router.get('/<bookUuid>/records/<recordUuid>/note', _getNote);
    router.post('/<bookUuid>/records/<recordUuid>/note', _createOrUpdateNote);
    router.delete('/<bookUuid>/records/<recordUuid>/note', _deleteNote);
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
