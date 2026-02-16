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
      ..get('/<bookUuid>/events', _getEventsByDateRange)
      ..post('/<bookUuid>/events', _createEvent)
      ..get('/<bookUuid>/events/<eventId>', _getEventDetail)
      ..patch('/<bookUuid>/events/<eventId>', _updateEvent)
      ..post('/<bookUuid>/events/<eventId>/remove', _removeEvent)
      ..post('/<bookUuid>/events/<eventId>/reschedule', _rescheduleEvent)
      ..delete('/<bookUuid>/events/<eventId>', _deleteEvent)
      ..get('/<bookUuid>/records/<recordUuid>', _getRecordDetails);
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.isUtc ? value : value.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt() * 1000,
        isUtc: true,
      );
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final asInt = int.tryParse(text);
    if (asInt != null) {
      return DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return parsed.isUtc ? parsed : parsed.toUtc();
  }

  bool _toBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  String _eventTypesToJson(dynamic value) {
    if (value == null) return '["other"]';
    if (value is List) return jsonEncode(value);
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return '["other"]';
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) return jsonEncode(decoded);
      } catch (_) {
        return jsonEncode([trimmed]);
      }
      return jsonEncode([trimmed]);
    }
    return jsonEncode([value.toString()]);
  }

  Future<Response?> _authorizeBookAccess(
    Request request,
    String bookUuid,
  ) async {
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

    if (!await _noteService.verifyDeviceAccess(deviceId, deviceToken)) {
      return Response.forbidden(
        jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
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

    return null;
  }

  /// Get events by date range
  /// GET /api/books/<bookUuid>/events?startDate=<ISO8601>&endDate=<ISO8601>
  Future<Response> _getEventsByDateRange(
    Request request,
    String bookUuid,
  ) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) {
        return authError;
      }

      // Parse date range parameters
      final params = request.url.queryParameters;
      final startDateStr = params['startDate'];
      final endDateStr = params['endDate'];

      if (startDateStr == null || endDateStr == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Missing startDate or endDate parameters',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final startDate = DateTime.tryParse(startDateStr);
      final endDate = DateTime.tryParse(endDateStr);

      if (startDate == null || endDate == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Invalid date format. Use ISO8601 format.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final eventRows = await db.queryRows(
        '''
        SELECT
          e.id, e.book_uuid, e.record_uuid, e.title, e.event_types,
          e.has_charge_items, e.start_time, e.end_time, e.created_at, e.updated_at,
          e.is_removed, e.removal_reason, e.original_event_id, e.new_event_id,
          e.is_checked, e.version,
          r.name as record_name, r.phone as record_phone, r.record_number,
          e.has_note
        FROM events e
        LEFT JOIN records r ON e.record_uuid = r.record_uuid
        WHERE e.book_uuid = @bookUuid
          AND e.is_deleted = false
          AND e.start_time >= @startDate
          AND e.start_time < @endDate
        ORDER BY e.start_time ASC
      ''',
        parameters: {
          'bookUuid': bookUuid,
          'startDate': startDate.toUtc(),
          'endDate': endDate.toUtc(),
        },
      );

      final events = eventRows.map((row) => _serializeEvent(row)).toList();

      return Response.ok(
        jsonEncode({'success': true, 'events': events}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to load events: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getEventDetail(
    Request request,
    String bookUuid,
    String eventId,
  ) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) {
        return authError;
      }

      final eventRow = await db.querySingle(
        '''
        SELECT
          e.id, e.book_uuid, e.record_uuid, e.title, e.event_types,
          e.has_charge_items, e.start_time, e.end_time, e.created_at, e.updated_at,
          e.is_removed, e.removal_reason, e.original_event_id, e.new_event_id,
          e.is_checked, e.version,
          r.name as record_name, r.phone as record_phone, r.record_number,
          e.has_note
        FROM events e
        LEFT JOIN records r ON e.record_uuid = r.record_uuid
        WHERE e.id = @eventId AND e.book_uuid = @bookUuid AND e.is_deleted = false
        LIMIT 1
      ''',
        parameters: {'eventId': eventId, 'bookUuid': bookUuid},
      );

      if (eventRow == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'success': true, 'event': _serializeEvent(eventRow)}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to load event: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getRecordDetails(
    Request request,
    String bookUuid,
    String recordUuid,
  ) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) {
        return authError;
      }

      final recordRow = await db.querySingle(
        '''
        SELECT record_uuid, record_number, name, phone, created_at, updated_at, version
        FROM records
        WHERE record_uuid = @recordUuid AND is_deleted = false
      ''',
        parameters: {'recordUuid': recordUuid},
      );

      if (recordRow == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Record not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get note for this record
      final noteRow = await db.querySingle(
        '''
        SELECT id, record_uuid, pages_data, created_at, updated_at, version
        FROM notes
        WHERE record_uuid = @recordUuid AND is_deleted = false
      ''',
        parameters: {'recordUuid': recordUuid},
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'record': {
            'record_uuid': recordRow['record_uuid'],
            'record_number': recordRow['record_number'],
            'name': recordRow['name'],
            'phone': recordRow['phone'],
            'version': recordRow['version'],
          },
          'note': noteRow != null
              ? {
                  'id': noteRow['id'],
                  'record_uuid': noteRow['record_uuid'],
                  'pages_data': noteRow['pages_data'],
                  'version': noteRow['version'],
                }
              : null,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to load record: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Map<String, dynamic> _serializeEvent(Map<String, dynamic> row) {
    DateTime? asDate(dynamic v) => v == null
        ? null
        : (v is DateTime ? v : DateTime.tryParse(v.toString()));
    int? asSeconds(DateTime? d) =>
        d != null ? d.millisecondsSinceEpoch ~/ 1000 : null;

    return {
      'id': row['id'],
      'book_uuid': row['book_uuid'],
      'record_uuid': row['record_uuid'],
      'title': row['title'],
      'record_number': row['record_number'],
      'event_types': row['event_types'],
      'has_charge_items':
          row['has_charge_items'] == true || row['has_charge_items'] == 1,
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

  Future<Response> _createEvent(Request request, String bookUuid) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) return authError;

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final recordUuid = (json['record_uuid'] ?? json['recordUuid'])
          ?.toString();
      final title = (json['title'] as String?)?.trim() ?? '';
      final startTime = _parseTimestamp(
        json['start_time'] ?? json['startTime'],
      );
      final endTime = _parseTimestamp(json['end_time'] ?? json['endTime']);
      if (recordUuid == null ||
          recordUuid.isEmpty ||
          title.isEmpty ||
          startTime == null) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'recordUuid, title and startTime are required',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final recordNumber = (json['record_number'] ?? json['recordNumber'] ?? '')
          .toString();
      final recordName = (json['record_name'] ?? json['recordName'] ?? title)
          .toString();
      final recordPhone = (json['record_phone'] ?? json['recordPhone'])
          ?.toString();

      await db.query(
        '''
        INSERT INTO records (record_uuid, record_number, name, phone, created_at, updated_at, synced_at, version, is_deleted)
        VALUES (@recordUuid, @recordNumber, @recordName, @recordPhone, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false)
        ON CONFLICT (record_uuid) DO UPDATE
        SET
          record_number = COALESCE(NULLIF(@recordNumber, ''), records.record_number),
          name = COALESCE(@recordName, records.name),
          phone = COALESCE(@recordPhone, records.phone),
          updated_at = CURRENT_TIMESTAMP,
          synced_at = CURRENT_TIMESTAMP
        ''',
        parameters: {
          'recordUuid': recordUuid,
          'recordNumber': recordNumber,
          'recordName': recordName,
          'recordPhone': recordPhone,
        },
      );

      final eventId = (json['id'] as String?)?.trim();
      final row = await db.querySingle(
        '''
        INSERT INTO events (
          id, book_uuid, record_uuid, title, event_types, has_charge_items,
          start_time, end_time, created_at, updated_at, synced_at, version,
          is_deleted, is_removed, removal_reason, original_event_id, new_event_id, is_checked, has_note
        )
        VALUES (
          COALESCE(NULLIF(@eventId, '')::uuid, uuid_generate_v4()),
          @bookUuid, @recordUuid, @title, @eventTypes, @hasChargeItems,
          @startTime, @endTime, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1,
          false, @isRemoved, @removalReason, @originalEventId, @newEventId, @isChecked, @hasNote
        )
        RETURNING *
        ''',
        parameters: {
          'eventId': eventId,
          'bookUuid': bookUuid,
          'recordUuid': recordUuid,
          'title': title,
          'eventTypes': _eventTypesToJson(
            json['event_types'] ?? json['eventTypes'],
          ),
          'hasChargeItems': _toBool(
            json['has_charge_items'] ?? json['hasChargeItems'],
          ),
          'startTime': startTime,
          'endTime': endTime,
          'isRemoved': _toBool(json['is_removed'] ?? json['isRemoved']),
          'removalReason': (json['removal_reason'] ?? json['removalReason'])
              ?.toString(),
          'originalEventId':
              (json['original_event_id'] ?? json['originalEventId'])
                  ?.toString(),
          'newEventId': (json['new_event_id'] ?? json['newEventId'])
              ?.toString(),
          'isChecked': _toBool(json['is_checked'] ?? json['isChecked']),
          'hasNote': _toBool(json['has_note'] ?? json['hasNote']),
        },
      );

      return Response.ok(
        jsonEncode({'success': true, 'event': _serializeEvent(row!)}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to create event: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _updateEvent(
    Request request,
    String bookUuid,
    String eventId,
  ) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) return authError;

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final updates = <String>[];
      final params = <String, dynamic>{
        'bookUuid': bookUuid,
        'eventId': eventId,
      };

      void addSet(String key, String column, dynamic value) {
        if (value == null) return;
        updates.add('$column = @$key');
        params[key] = value;
      }

      addSet('title', 'title', (json['title'] as String?)?.trim());
      if (json.containsKey('event_types') || json.containsKey('eventTypes')) {
        addSet(
          'eventTypes',
          'event_types',
          _eventTypesToJson(json['event_types'] ?? json['eventTypes']),
        );
      }
      if (json.containsKey('has_charge_items') ||
          json.containsKey('hasChargeItems')) {
        addSet(
          'hasChargeItems',
          'has_charge_items',
          _toBool(json['has_charge_items'] ?? json['hasChargeItems']),
        );
      }
      if (json.containsKey('start_time') || json.containsKey('startTime')) {
        addSet(
          'startTime',
          'start_time',
          _parseTimestamp(json['start_time'] ?? json['startTime']),
        );
      }
      if (json.containsKey('end_time') || json.containsKey('endTime')) {
        addSet(
          'endTime',
          'end_time',
          _parseTimestamp(json['end_time'] ?? json['endTime']),
        );
      }
      if (json.containsKey('is_removed') || json.containsKey('isRemoved')) {
        addSet(
          'isRemoved',
          'is_removed',
          _toBool(json['is_removed'] ?? json['isRemoved']),
        );
      }
      if (json.containsKey('removal_reason') ||
          json.containsKey('removalReason')) {
        addSet(
          'removalReason',
          'removal_reason',
          (json['removal_reason'] ?? json['removalReason'])?.toString(),
        );
      }
      if (json.containsKey('original_event_id') ||
          json.containsKey('originalEventId')) {
        addSet(
          'originalEventId',
          'original_event_id',
          (json['original_event_id'] ?? json['originalEventId'])?.toString(),
        );
      }
      if (json.containsKey('new_event_id') || json.containsKey('newEventId')) {
        addSet(
          'newEventId',
          'new_event_id',
          (json['new_event_id'] ?? json['newEventId'])?.toString(),
        );
      }
      if (json.containsKey('is_checked') || json.containsKey('isChecked')) {
        addSet(
          'isChecked',
          'is_checked',
          _toBool(json['is_checked'] ?? json['isChecked']),
        );
      }
      if (json.containsKey('has_note') || json.containsKey('hasNote')) {
        addSet(
          'hasNote',
          'has_note',
          _toBool(json['has_note'] ?? json['hasNote']),
        );
      }

      if (updates.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'No fields to update',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      updates.add('updated_at = CURRENT_TIMESTAMP');
      updates.add('synced_at = CURRENT_TIMESTAMP');
      updates.add('version = version + 1');

      final row = await db.querySingle('''
        UPDATE events
        SET ${updates.join(', ')}
        WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false
        RETURNING *
        ''', parameters: params);

      if (row == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'success': true, 'event': _serializeEvent(row)}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to update event: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _removeEvent(
    Request request,
    String bookUuid,
    String eventId,
  ) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) return authError;

      final body = await request.readAsString();
      final json = body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      final reason = (json['reason'] as String?)?.trim() ?? 'Removed by user';

      final row = await db.querySingle(
        '''
        UPDATE events
        SET
          is_removed = true,
          removal_reason = @reason,
          updated_at = CURRENT_TIMESTAMP,
          synced_at = CURRENT_TIMESTAMP,
          version = version + 1
        WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false
        RETURNING *
        ''',
        parameters: {
          'reason': reason,
          'bookUuid': bookUuid,
          'eventId': eventId,
        },
      );

      if (row == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'success': true, 'event': _serializeEvent(row)}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to remove event: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _deleteEvent(
    Request request,
    String bookUuid,
    String eventId,
  ) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) return authError;

      final row = await db.querySingle(
        '''
        UPDATE events
        SET
          is_deleted = true,
          updated_at = CURRENT_TIMESTAMP,
          synced_at = CURRENT_TIMESTAMP,
          version = version + 1
        WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false
        RETURNING *
        ''',
        parameters: {'bookUuid': bookUuid, 'eventId': eventId},
      );

      if (row == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to delete event: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _rescheduleEvent(
    Request request,
    String bookUuid,
    String eventId,
  ) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) return authError;

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final newStart = _parseTimestamp(
        json['newStartTime'] ?? json['new_start_time'],
      );
      final newEnd = _parseTimestamp(
        json['newEndTime'] ?? json['new_end_time'],
      );
      final reason = (json['reason'] as String?)?.trim() ?? '';
      if (newStart == null || reason.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'newStartTime and reason are required',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final existing = await db.querySingle(
        'SELECT * FROM events WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false',
        parameters: {'eventId': eventId, 'bookUuid': bookUuid},
      );
      if (existing == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final newEventId = await db.querySingle(
        'SELECT uuid_generate_v4() AS id',
      );
      final generatedId = newEventId!['id'].toString();

      final oldUpdated = await db.querySingle(
        '''
        UPDATE events
        SET
          is_removed = true,
          removal_reason = @reason,
          new_event_id = @newEventId,
          updated_at = CURRENT_TIMESTAMP,
          synced_at = CURRENT_TIMESTAMP,
          version = version + 1
        WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false
        RETURNING *
        ''',
        parameters: {
          'reason': reason,
          'newEventId': generatedId,
          'eventId': eventId,
          'bookUuid': bookUuid,
        },
      );

      final created = await db.querySingle(
        '''
        INSERT INTO events (
          id, book_uuid, record_uuid, title, event_types, has_charge_items,
          start_time, end_time, created_at, updated_at, synced_at, version,
          is_deleted, is_removed, removal_reason, original_event_id, new_event_id, is_checked, has_note
        )
        VALUES (
          @newEventId, @bookUuid, @recordUuid, @title, @eventTypes, @hasChargeItems,
          @startTime, @endTime, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1,
          false, false, NULL, @originalEventId, NULL, @isChecked, @hasNote
        )
        RETURNING *
        ''',
        parameters: {
          'newEventId': generatedId,
          'bookUuid': bookUuid,
          'recordUuid': existing['record_uuid'],
          'title': existing['title'],
          'eventTypes': existing['event_types'],
          'hasChargeItems': existing['has_charge_items'],
          'startTime': newStart,
          'endTime': newEnd,
          'originalEventId': eventId,
          'isChecked': existing['is_checked'],
          'hasNote': existing['has_note'],
        },
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'oldEvent': _serializeEvent(oldUpdated!),
          'newEvent': _serializeEvent(created!),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to reschedule event: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
