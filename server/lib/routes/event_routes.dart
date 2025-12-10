import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../services/note_service.dart';

/// Routes for event operations (device-authenticated)
class EventRoutes {
  final DatabaseConnection db;
  late final Router bookScopedRouter;
  final NoteService _noteService;

  EventRoutes(this.db) : _noteService = NoteService(db) {
    bookScopedRouter = Router()
      ..get('/<bookUuid>/events/<eventId>', _getEventDetail)
      ..get('/<bookUuid>/persons/<recordNumber>', _getPersonByRecordNumber);
  }

  Future<Response> _getEventDetail(Request request, String bookUuid, String eventId) async {
    try {
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

      // Verify device and book ownership
      if (!await _noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await _noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final eventRow = await db.querySingle(
        '''
        SELECT
          id,
          book_uuid,
          name,
          record_number,
          phone,
          event_type,
          event_types,
          has_charge_items,
          start_time,
          end_time,
          created_at,
          updated_at,
          is_removed,
          removal_reason,
          original_event_id,
          new_event_id,
          is_checked,
          has_note,
          version
        FROM events
        WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false
        LIMIT 1
        ''',
        parameters: {
          'eventId': eventId,
          'bookUuid': bookUuid,
        },
      );

      if (eventRow == null) {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'message': 'Event not found',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final eventJson = _serializeEvent(eventRow);
      return Response.ok(
        jsonEncode({
          'success': true,
          'event': eventJson,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ GET event failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to load event: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Get person data by record number (name and latest note)
  Future<Response> _getPersonByRecordNumber(Request request, String bookUuid, String recordNumber) async {
    try {
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

      // Verify device and book ownership
      if (!await _noteService.verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!await _noteService.verifyBookOwnership(deviceId, bookUuid)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized access to book',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Decode record number (may be URL encoded)
      final decodedRecordNumber = Uri.decodeComponent(recordNumber);

      // Get the latest event with this record number to get the name
      final eventRow = await db.querySingle(
        '''
        SELECT name, record_number
        FROM events
        WHERE book_uuid = @bookUuid
          AND LOWER(TRIM(record_number)) = LOWER(TRIM(@recordNumber))
          AND is_deleted = false
          AND is_removed = false
        ORDER BY updated_at DESC
        LIMIT 1
        ''',
        parameters: {
          'bookUuid': bookUuid,
          'recordNumber': decodedRecordNumber,
        },
      );

      if (eventRow == null) {
        return Response.notFound(
          jsonEncode({
            'success': false,
            'message': 'Person not found with this record number',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final name = eventRow['name'] as String;
      final nameNormalized = name.trim().toLowerCase();
      final recordNumberNormalized = decodedRecordNumber.trim().toLowerCase();

      // Get the latest note for this person (using normalized person key)
      final noteRow = await db.querySingle(
        '''
        SELECT
          n.id,
          n.event_id,
          -- Use pages_data when available (multi-page notes) and fallback to strokes_data for legacy rows.
          COALESCE(n.pages_data, n.strokes_data) AS strokes_data,
          n.created_at,
          n.updated_at,
          n.version
        FROM notes n
        WHERE n.person_name_normalized = @nameNormalized
          AND n.record_number_normalized = @recordNumberNormalized
          AND n.is_deleted = false
        ORDER BY n.updated_at DESC
        LIMIT 1
        ''',
        parameters: {
          'nameNormalized': nameNormalized,
          'recordNumberNormalized': recordNumberNormalized,
        },
      );

      Map<String, dynamic>? noteJson;
      if (noteRow != null) {
        noteJson = {
          'id': noteRow['id'],
          'event_id': noteRow['event_id'],
          'strokes_data': noteRow['strokes_data'],
          'created_at': noteRow['created_at']?.toString(),
          'updated_at': noteRow['updated_at']?.toString(),
          'version': noteRow['version'],
        };
      }

      return Response.ok(
        jsonEncode({
          'success': true,
          'person': {
            'name': name,
            'recordNumber': eventRow['record_number'],
            'latestNote': noteJson,
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ GET person by record number failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to load person data: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Map<String, dynamic> _serializeEvent(Map<String, dynamic> row) {
    DateTime? _asDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      return DateTime.tryParse(value.toString());
    }

    final startTime = _asDate(row['start_time']);
    final endTime = _asDate(row['end_time']);
    final createdAt = _asDate(row['created_at']);
    final updatedAt = _asDate(row['updated_at']);

    return {
      'id': row['id'],
      'book_uuid': row['book_uuid'],
      'name': row['name'],
      'record_number': row['record_number'],
      'phone': row['phone'],
      'event_type': row['event_type'],
      'event_types': row['event_types'],
      'has_charge_items': row['has_charge_items'] == true || row['has_charge_items'] == 1,
      'start_time': startTime != null ? startTime.millisecondsSinceEpoch ~/ 1000 : null,
      'end_time': endTime != null ? endTime.millisecondsSinceEpoch ~/ 1000 : null,
      'created_at': createdAt != null ? createdAt.millisecondsSinceEpoch ~/ 1000 : null,
      'updated_at': updatedAt != null ? updatedAt.millisecondsSinceEpoch ~/ 1000 : null,
      'is_removed': row['is_removed'] == true || row['is_removed'] == 1,
      'removal_reason': row['removal_reason'],
      'original_event_id': row['original_event_id'],
      'new_event_id': row['new_event_id'],
      'is_checked': row['is_checked'] == true || row['is_checked'] == 1,
      'has_note': row['has_note'] == true || row['has_note'] == 1,
      'version': row['version'],
      'is_dirty': 0,
    };
  }
}
