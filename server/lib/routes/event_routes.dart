import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../database/connection.dart';
import '../services/note_service.dart';

class _PreparedEventCreate {
  final String eventId;
  final String recordUuid;
  final String recordNumber;
  final String recordName;
  final String? recordPhone;
  final Map<String, dynamic> eventInsertPayload;

  const _PreparedEventCreate({
    required this.eventId,
    required this.recordUuid,
    required this.recordNumber,
    required this.recordName,
    required this.recordPhone,
    required this.eventInsertPayload,
  });
}

/// Event routes (record-based architecture)
class EventRoutes {
  final DatabaseConnection db;
  late final Router bookScopedRouter;
  final NoteService _noteService;
  final _uuid = const Uuid();

  EventRoutes(this.db) : _noteService = NoteService(db) {
    bookScopedRouter = Router()
      ..get('/<bookUuid>/events', _getEventsByDateRange)
      ..post('/<bookUuid>/events', _createEvent)
      ..post('/<bookUuid>/heavy-test/events/bulk', _createEventsBulkHeavyTest)
      ..get('/<bookUuid>/events/<eventId>', _getEventDetail)
      ..patch('/<bookUuid>/events/<eventId>', _updateEvent)
      ..post('/<bookUuid>/events/<eventId>/remove', _removeEvent)
      ..post('/<bookUuid>/events/<eventId>/reschedule', _rescheduleEvent)
      ..delete('/<bookUuid>/events/<eventId>', _deleteEvent)
      ..get('/<bookUuid>/records/<recordUuid>', _getRecordDetails);
  }

  Map<String, dynamic>? _first(dynamic data) {
    if (data is List && data.isNotEmpty) {
      final row = data.first;
      if (row is Map<String, dynamic>) return row;
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  DateTime _asUtc(dynamic value) {
    if (value is DateTime) return value.isUtc ? value : value.toUtc();
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null)
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return parsed.isUtc ? parsed : parsed.toUtc();
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
    String bookUuid, {
    bool requireWrite = false,
  }) async {
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

    final hasAccess = await _noteService.verifyBookAccess(
      deviceId,
      bookUuid,
      requireWrite: requireWrite,
    );
    if (!hasAccess) {
      if (requireWrite && !await _noteService.canDeviceWrite(deviceId)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Read-only device cannot modify events',
            'error': 'READ_ONLY_DEVICE',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
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

  Future<Map<String, dynamic>?> _eventWithRecord(
    String bookUuid,
    String eventId,
  ) async {
    final eventRows = await db.client
        .from('events')
        .select(
          'id, book_uuid, record_uuid, title, event_types, has_charge_items, start_time, end_time, '
          'created_at, updated_at, is_removed, removal_reason, original_event_id, new_event_id, '
          'is_checked, has_note, version',
        )
        .eq('id', eventId)
        .eq('book_uuid', bookUuid)
        .eq('is_deleted', false)
        .limit(1);
    final event = _first(eventRows);
    if (event == null) return null;

    final recordRows = await db.client
        .from('records')
        .select('record_uuid, record_number, name, phone')
        .eq('record_uuid', event['record_uuid'])
        .eq('is_deleted', false)
        .limit(1);
    final record = _first(recordRows);

    return {
      ...event,
      'record_name': record?['name'],
      'record_phone': record?['phone'],
      'record_number': record?['record_number'],
    };
  }

  Future<List<Map<String, dynamic>>> _eventsWithRecordsByRange({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final eventRows = _rows(
      await db.client
          .from('events')
          .select(
            'id, book_uuid, record_uuid, title, event_types, has_charge_items, start_time, end_time, '
            'created_at, updated_at, is_removed, removal_reason, original_event_id, new_event_id, '
            'is_checked, has_note, version',
          )
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .gte('start_time', startDate.toUtc().toIso8601String())
          .lt('start_time', endDate.toUtc().toIso8601String())
          .order('start_time', ascending: true),
    );

    final recordUuids = eventRows
        .map((row) => row['record_uuid']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final recordsById = <String, Map<String, dynamic>>{};
    if (recordUuids.isNotEmpty) {
      final recordRows = _rows(
        await db.client
            .from('records')
            .select('record_uuid, record_number, name, phone')
            .inFilter('record_uuid', recordUuids)
            .eq('is_deleted', false),
      );
      for (final row in recordRows) {
        recordsById[row['record_uuid'].toString()] = row;
      }
    }

    return eventRows.map((event) {
      final record = recordsById[event['record_uuid']?.toString() ?? ''];
      return {
        ...event,
        'record_name': record?['name'],
        'record_phone': record?['phone'],
        'record_number': record?['record_number'],
      };
    }).toList();
  }

  Map<String, dynamic> _serializeEvent(Map<String, dynamic> row) {
    int? asSeconds(dynamic v) {
      if (v == null) return null;
      return _asUtc(v).millisecondsSinceEpoch ~/ 1000;
    }

    return {
      'id': row['id'],
      'book_uuid': row['book_uuid'],
      'record_uuid': row['record_uuid'],
      'title': row['title'],
      'record_number': row['record_number'],
      'event_types': row['event_types'],
      'has_charge_items': _toBool(row['has_charge_items']),
      'start_time': asSeconds(row['start_time']),
      'end_time': asSeconds(row['end_time']),
      'created_at': asSeconds(row['created_at']),
      'updated_at': asSeconds(row['updated_at']),
      'is_removed': _toBool(row['is_removed']),
      'removal_reason': row['removal_reason'],
      'original_event_id': row['original_event_id'],
      'new_event_id': row['new_event_id'],
      'is_checked': _toBool(row['is_checked']),
      'has_note': _toBool(row['has_note']),
      'version': (row['version'] as num?)?.toInt() ?? 1,
      'record_name': row['record_name'],
      'record_phone': row['record_phone'],
    };
  }

  Future<Response> _getEventsByDateRange(
    Request request,
    String bookUuid,
  ) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) {
        return authError;
      }

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

      final eventRows = await _eventsWithRecordsByRange(
        bookUuid: bookUuid,
        startDate: startDate,
        endDate: endDate,
      );

      final events = eventRows.map(_serializeEvent).toList();
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

      final eventRow = await _eventWithRecord(bookUuid, eventId);
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

      final recordRows = await db.client
          .from('records')
          .select(
            'record_uuid, record_number, name, phone, created_at, updated_at, version',
          )
          .eq('record_uuid', recordUuid)
          .eq('is_deleted', false)
          .limit(1);
      final recordRow = _first(recordRows);

      if (recordRow == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Record not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final noteRows = await db.client
          .from('notes')
          .select(
            'id, record_uuid, pages_data, created_at, updated_at, version',
          )
          .eq('record_uuid', recordUuid)
          .eq('is_deleted', false)
          .limit(1);
      final noteRow = _first(noteRows);

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

  Future<void> _ensureRecord({
    required String recordUuid,
    required String recordNumber,
    required String recordName,
    String? recordPhone,
  }) async {
    final rows = await db.client
        .from('records')
        .select('record_uuid, record_number, name, phone')
        .eq('record_uuid', recordUuid)
        .limit(1);
    final existing = _first(rows);

    if (existing == null) {
      await db.client.from('records').insert({
        'record_uuid': recordUuid,
        'record_number': recordNumber,
        'name': recordName,
        'phone': recordPhone,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'synced_at': DateTime.now().toUtc().toIso8601String(),
        'version': 1,
        'is_deleted': false,
      });
      return;
    }

    final mergedNumber = recordNumber.trim().isNotEmpty
        ? recordNumber
        : (existing['record_number'] ?? '').toString();
    final mergedName = recordName.trim().isNotEmpty
        ? recordName
        : (existing['name'] ?? '').toString();
    final mergedPhone =
        recordPhone ??
        (existing['phone']?.toString().isEmpty == true
            ? null
            : existing['phone']);

    await db.client
        .from('records')
        .update({
          'record_number': mergedNumber,
          'name': mergedName,
          'phone': mergedPhone,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'synced_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('record_uuid', recordUuid);
  }

  _PreparedEventCreate _prepareEventCreateInput({
    required Map<String, dynamic> json,
    required String bookUuid,
  }) {
    final recordUuid = (json['record_uuid'] ?? json['recordUuid'])?.toString();
    final title = (json['title'] as String?)?.trim() ?? '';
    final startTime = _parseTimestamp(json['start_time'] ?? json['startTime']);
    final endTime = _parseTimestamp(json['end_time'] ?? json['endTime']);
    if (recordUuid == null ||
        recordUuid.isEmpty ||
        title.isEmpty ||
        startTime == null) {
      throw const FormatException(
        'recordUuid, title and startTime are required',
      );
    }

    final recordNumber = (json['record_number'] ?? json['recordNumber'] ?? '')
        .toString();
    final recordName = (json['record_name'] ?? json['recordName'] ?? title)
        .toString();
    final recordPhone = (json['record_phone'] ?? json['recordPhone'])
        ?.toString();
    final eventId = (json['id'] as String?)?.trim();
    final insertId = (eventId == null || eventId.isEmpty)
        ? _uuid.v4()
        : eventId;
    final now = DateTime.now().toUtc().toIso8601String();

    return _PreparedEventCreate(
      eventId: insertId,
      recordUuid: recordUuid,
      recordNumber: recordNumber,
      recordName: recordName,
      recordPhone: recordPhone,
      eventInsertPayload: {
        'id': insertId,
        'book_uuid': bookUuid,
        'record_uuid': recordUuid,
        'title': title,
        'event_types': _eventTypesToJson(
          json['event_types'] ?? json['eventTypes'],
        ),
        'has_charge_items': _toBool(
          json['has_charge_items'] ?? json['hasChargeItems'],
        ),
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'created_at': now,
        'updated_at': now,
        'synced_at': now,
        'version': 1,
        'is_deleted': false,
        'is_removed': _toBool(json['is_removed'] ?? json['isRemoved']),
        'removal_reason': (json['removal_reason'] ?? json['removalReason'])
            ?.toString(),
        'original_event_id':
            (json['original_event_id'] ?? json['originalEventId'])?.toString(),
        'new_event_id': (json['new_event_id'] ?? json['newEventId'])
            ?.toString(),
        'is_checked': _toBool(json['is_checked'] ?? json['isChecked']),
        'has_note': _toBool(json['has_note'] ?? json['hasNote']),
      },
    );
  }

  Future<void> _upsertRecordsForBulkEvents(
    List<_PreparedEventCreate> events,
  ) async {
    final recordByUuid = <String, _PreparedEventCreate>{};
    for (final event in events) {
      final existing = recordByUuid[event.recordUuid];
      if (existing == null) {
        recordByUuid[event.recordUuid] = event;
        continue;
      }

      final mergedNumber = event.recordNumber.trim().isNotEmpty
          ? event.recordNumber
          : existing.recordNumber;
      final mergedName = event.recordName.trim().isNotEmpty
          ? event.recordName
          : existing.recordName;
      final mergedPhone = (event.recordPhone ?? '').trim().isNotEmpty
          ? event.recordPhone
          : existing.recordPhone;

      recordByUuid[event.recordUuid] = _PreparedEventCreate(
        eventId: existing.eventId,
        recordUuid: existing.recordUuid,
        recordNumber: mergedNumber,
        recordName: mergedName,
        recordPhone: mergedPhone,
        eventInsertPayload: existing.eventInsertPayload,
      );
    }

    if (recordByUuid.isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final recordRows = recordByUuid.values.map((entry) {
      return <String, dynamic>{
        'record_uuid': entry.recordUuid,
        'record_number': entry.recordNumber,
        'name': entry.recordName,
        'phone': entry.recordPhone,
        'updated_at': now,
        'synced_at': now,
        'is_deleted': false,
      };
    }).toList();

    const chunkSize = 500;
    for (var i = 0; i < recordRows.length; i += chunkSize) {
      final end = (i + chunkSize > recordRows.length)
          ? recordRows.length
          : i + chunkSize;
      await db.client
          .from('records')
          .upsert(recordRows.sublist(i, end), onConflict: 'record_uuid');
    }
  }

  Future<Response> _createEventsBulkHeavyTest(
    Request request,
    String bookUuid,
  ) async {
    try {
      final authError = await _authorizeBookAccess(
        request,
        bookUuid,
        requireWrite: true,
      );
      if (authError != null) return authError;

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final eventsRaw = json['events'];
      if (eventsRaw is! List) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'events list is required',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (eventsRaw.isEmpty) {
        return Response.ok(
          jsonEncode({'success': true, 'count': 0, 'event_ids': <String>[]}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (eventsRaw.length > 500) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'events list too large; maximum 500 per request',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final prepared = <_PreparedEventCreate>[];
      for (final raw in eventsRaw) {
        if (raw is! Map) {
          return Response.badRequest(
            body: jsonEncode({
              'success': false,
              'message': 'each event must be a JSON object',
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
        prepared.add(
          _prepareEventCreateInput(
            json: Map<String, dynamic>.from(raw),
            bookUuid: bookUuid,
          ),
        );
      }

      await _upsertRecordsForBulkEvents(prepared);

      final rows = prepared.map((entry) => entry.eventInsertPayload).toList();
      await db.client.from('events').insert(rows);

      return Response.ok(
        jsonEncode({
          'success': true,
          'count': prepared.length,
          'event_ids': prepared.map((entry) => entry.eventId).toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on FormatException catch (e) {
      return Response.badRequest(
        body: jsonEncode({'success': false, 'message': e.message}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to bulk create heavy-test events: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _createEvent(Request request, String bookUuid) async {
    try {
      final authError = await _authorizeBookAccess(
        request,
        bookUuid,
        requireWrite: true,
      );
      if (authError != null) return authError;

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final prepared = _prepareEventCreateInput(json: json, bookUuid: bookUuid);

      await _ensureRecord(
        recordUuid: prepared.recordUuid,
        recordNumber: prepared.recordNumber,
        recordName: prepared.recordName,
        recordPhone: prepared.recordPhone,
      );
      await db.client.from('events').insert(prepared.eventInsertPayload);

      final row = await _eventWithRecord(bookUuid, prepared.eventId);
      return Response.ok(
        jsonEncode({'success': true, 'event': _serializeEvent(row!)}),
        headers: {'Content-Type': 'application/json'},
      );
    } on FormatException catch (e) {
      return Response.badRequest(
        body: jsonEncode({'success': false, 'message': e.message}),
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
      final authError = await _authorizeBookAccess(
        request,
        bookUuid,
        requireWrite: true,
      );
      if (authError != null) return authError;

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final existingRows = await db.client
          .from('events')
          .select('id, version')
          .eq('id', eventId)
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .limit(1);
      final existing = _first(existingRows);
      if (existing == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final payload = <String, dynamic>{};
      if (json.containsKey('title'))
        payload['title'] = (json['title'] as String?)?.trim();
      if (json.containsKey('event_types') || json.containsKey('eventTypes')) {
        payload['event_types'] = _eventTypesToJson(
          json['event_types'] ?? json['eventTypes'],
        );
      }
      if (json.containsKey('has_charge_items') ||
          json.containsKey('hasChargeItems')) {
        payload['has_charge_items'] = _toBool(
          json['has_charge_items'] ?? json['hasChargeItems'],
        );
      }
      if (json.containsKey('start_time') || json.containsKey('startTime')) {
        payload['start_time'] = _parseTimestamp(
          json['start_time'] ?? json['startTime'],
        )?.toIso8601String();
      }
      if (json.containsKey('end_time') || json.containsKey('endTime')) {
        payload['end_time'] = _parseTimestamp(
          json['end_time'] ?? json['endTime'],
        )?.toIso8601String();
      }
      if (json.containsKey('is_removed') || json.containsKey('isRemoved')) {
        payload['is_removed'] = _toBool(
          json['is_removed'] ?? json['isRemoved'],
        );
      }
      if (json.containsKey('removal_reason') ||
          json.containsKey('removalReason')) {
        payload['removal_reason'] =
            (json['removal_reason'] ?? json['removalReason'])?.toString();
      }
      if (json.containsKey('original_event_id') ||
          json.containsKey('originalEventId')) {
        payload['original_event_id'] =
            (json['original_event_id'] ?? json['originalEventId'])?.toString();
      }
      if (json.containsKey('new_event_id') || json.containsKey('newEventId')) {
        payload['new_event_id'] = (json['new_event_id'] ?? json['newEventId'])
            ?.toString();
      }
      if (json.containsKey('is_checked') || json.containsKey('isChecked')) {
        payload['is_checked'] = _toBool(
          json['is_checked'] ?? json['isChecked'],
        );
      }
      if (json.containsKey('has_note') || json.containsKey('hasNote')) {
        payload['has_note'] = _toBool(json['has_note'] ?? json['hasNote']);
      }

      if (payload.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'No fields to update',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      payload['updated_at'] = DateTime.now().toUtc().toIso8601String();
      payload['synced_at'] = DateTime.now().toUtc().toIso8601String();
      payload['version'] = ((existing['version'] as num?)?.toInt() ?? 1) + 1;

      await db.client
          .from('events')
          .update(payload)
          .eq('id', eventId)
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false);

      final row = await _eventWithRecord(bookUuid, eventId);
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
      final authError = await _authorizeBookAccess(
        request,
        bookUuid,
        requireWrite: true,
      );
      if (authError != null) return authError;

      final body = await request.readAsString();
      final json = body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      final reason = (json['reason'] as String?)?.trim() ?? 'Removed by user';

      final existingRows = await db.client
          .from('events')
          .select('version')
          .eq('id', eventId)
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .limit(1);
      final existing = _first(existingRows);
      if (existing == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await db.client
          .from('events')
          .update({
            'is_removed': true,
            'removal_reason': reason,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'version': ((existing['version'] as num?)?.toInt() ?? 1) + 1,
          })
          .eq('id', eventId)
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false);

      final row = await _eventWithRecord(bookUuid, eventId);
      return Response.ok(
        jsonEncode({'success': true, 'event': _serializeEvent(row!)}),
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
      final authError = await _authorizeBookAccess(
        request,
        bookUuid,
        requireWrite: true,
      );
      if (authError != null) return authError;

      final existingRows = await db.client
          .from('events')
          .select('version')
          .eq('id', eventId)
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .limit(1);
      final existing = _first(existingRows);
      if (existing == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await db.client
          .from('events')
          .update({
            'is_deleted': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'version': ((existing['version'] as num?)?.toInt() ?? 1) + 1,
          })
          .eq('id', eventId)
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false);

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
      final authError = await _authorizeBookAccess(
        request,
        bookUuid,
        requireWrite: true,
      );
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

      final existingRows = await db.client
          .from('events')
          .select('*')
          .eq('id', eventId)
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .limit(1);
      final existing = _first(existingRows);
      if (existing == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final generatedId = _uuid.v4();
      final serverVersion = (existing['version'] as num?)?.toInt() ?? 1;

      await db.client
          .from('events')
          .update({
            'is_removed': true,
            'removal_reason': reason,
            'new_event_id': generatedId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'version': serverVersion + 1,
          })
          .eq('id', eventId)
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false);

      final now = DateTime.now().toUtc().toIso8601String();
      await db.client.from('events').insert({
        'id': generatedId,
        'book_uuid': bookUuid,
        'record_uuid': existing['record_uuid'],
        'title': existing['title'],
        'event_types': existing['event_types'],
        'has_charge_items': _toBool(existing['has_charge_items']),
        'start_time': newStart.toIso8601String(),
        'end_time': newEnd?.toIso8601String(),
        'created_at': now,
        'updated_at': now,
        'synced_at': now,
        'version': 1,
        'is_deleted': false,
        'is_removed': false,
        'removal_reason': null,
        'original_event_id': eventId,
        'new_event_id': null,
        'is_checked': _toBool(existing['is_checked']),
        'has_note': _toBool(existing['has_note']),
      });

      final oldEvent = await _eventWithRecord(bookUuid, eventId);
      final newEvent = await _eventWithRecord(bookUuid, generatedId);

      return Response.ok(
        jsonEncode({
          'success': true,
          'oldEvent': _serializeEvent(oldEvent!),
          'newEvent': _serializeEvent(newEvent!),
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
