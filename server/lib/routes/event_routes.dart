import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/note_service.dart';

/// Event routes (record-based architecture)
class EventRoutes {
  final DatabaseConnection db;
  late final Router bookScopedRouter;
  final NoteService _noteService;

  EventRoutes(this.db) : _noteService = NoteService(db) {
    bookScopedRouter = Router()
      ..get('/<bookUuid>/events/<eventId>', _getEventDetail)
      ..get('/<bookUuid>/records/<recordUuid>', _getRecordDetails);
  }

  Future<Response> _getEventDetail(Request request, String bookUuid, String eventId) async {
    try {
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(401, body: jsonEncode({'success': false, 'message': 'Missing device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await _noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await _noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Unauthorized access to book'}),
            headers: {'Content-Type': 'application/json'});
      }

      final eventRow = await db.querySingle('''
        SELECT
          e.id, e.book_uuid, e.record_uuid, e.title, e.record_number, e.event_types,
          e.has_charge_items, e.start_time, e.end_time, e.created_at, e.updated_at,
          e.is_removed, e.removal_reason, e.original_event_id, e.new_event_id,
          e.is_checked, e.has_note, e.version,
          r.name as record_name, r.phone as record_phone
        FROM events e
        LEFT JOIN records r ON e.record_uuid = r.record_uuid
        WHERE e.id = @eventId AND e.book_uuid = @bookUuid AND e.is_deleted = false
        LIMIT 1
      ''', parameters: {'eventId': eventId, 'bookUuid': bookUuid});

      if (eventRow == null) {
        return Response.notFound(jsonEncode({'success': false, 'message': 'Event not found'}),
            headers: {'Content-Type': 'application/json'});
      }

      return Response.ok(jsonEncode({'success': true, 'event': _serializeEvent(eventRow)}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'message': 'Failed to load event: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> _getRecordDetails(Request request, String bookUuid, String recordUuid) async {
    try {
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (deviceId == null || deviceToken == null) {
        return Response(401, body: jsonEncode({'success': false, 'message': 'Missing device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await _noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
            headers: {'Content-Type': 'application/json'});
      }

      if (!await _noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(jsonEncode({'success': false, 'message': 'Unauthorized access to book'}),
            headers: {'Content-Type': 'application/json'});
      }

      final recordRow = await db.querySingle('''
        SELECT record_uuid, record_number, name, phone, created_at, updated_at, version
        FROM records
        WHERE record_uuid = @recordUuid AND is_deleted = false
      ''', parameters: {'recordUuid': recordUuid});

      if (recordRow == null) {
        return Response.notFound(jsonEncode({'success': false, 'message': 'Record not found'}),
            headers: {'Content-Type': 'application/json'});
      }

      // Get note for this record
      final noteRow = await db.querySingle('''
        SELECT id, record_uuid, pages_data, created_at, updated_at, version
        FROM notes
        WHERE record_uuid = @recordUuid AND is_deleted = false
      ''', parameters: {'recordUuid': recordUuid});

      return Response.ok(jsonEncode({
        'success': true,
        'record': {
          'record_uuid': recordRow['record_uuid'],
          'record_number': recordRow['record_number'],
          'name': recordRow['name'],
          'phone': recordRow['phone'],
          'version': recordRow['version'],
        },
        'note': noteRow != null ? {
          'id': noteRow['id'],
          'record_uuid': noteRow['record_uuid'],
          'pages_data': noteRow['pages_data'],
          'version': noteRow['version'],
        } : null,
      }), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'message': 'Failed to load record: $e'}),
          headers: {'Content-Type': 'application/json'});
    }
  }

  Map<String, dynamic> _serializeEvent(Map<String, dynamic> row) {
    DateTime? asDate(dynamic v) => v == null ? null : (v is DateTime ? v : DateTime.tryParse(v.toString()));
    int? asSeconds(DateTime? d) => d != null ? d.millisecondsSinceEpoch ~/ 1000 : null;

    return {
      'id': row['id'],
      'book_uuid': row['book_uuid'],
      'record_uuid': row['record_uuid'],
      'title': row['title'],
      'record_number': row['record_number'],
      'event_types': row['event_types'],
      'has_charge_items': row['has_charge_items'] == true || row['has_charge_items'] == 1,
      'start_time': asSeconds(asDate(row['start_time'])),
      'end_time': asSeconds(asDate(row['end_time'])),
      'created_at': asSeconds(asDate(row['created_at'])),
      'updated_at': asSeconds(asDate(row['updated_at'])),
      'is_removed': row['is_removed'] == true || row['is_removed'] == 1,
      'removal_reason': row['removal_reason'],
      'original_event_id': row['original_event_id'],
      'new_event_id': row['new_event_id'],
      'is_checked': row['is_checked'] == true || row['is_checked'] == 1,
      'has_note': row['has_note'] == true || row['has_note'] == 1,
      'version': row['version'],
      'record_name': row['record_name'],
      'record_phone': row['record_phone'],
    };
  }
}
