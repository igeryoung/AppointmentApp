import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../database/connection.dart';

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
  static const int _queryPageSize = 500;
  static const String _eventSelectColumns =
      'id, book_uuid, record_uuid, title, event_types, has_charge_items, '
      'start_time, end_time, created_at, updated_at, is_removed, '
      'removal_reason, original_event_id, new_event_id, is_checked, has_note, '
      'version';

  final DatabaseConnection db;
  late final Router bookScopedRouter;
  final _uuid = const Uuid();

  EventRoutes(this.db) {
    bookScopedRouter = Router()
      ..get('/<bookUuid>/query-options/names', _getNameSuggestions)
      ..get(
        '/<bookUuid>/query-options/record-numbers',
        _getRecordNumberSuggestions,
      )
      ..get('/<bookUuid>/query-search', _queryAppointments)
      ..get('/<bookUuid>/events', _getEventsByDateRange)
      ..post('/<bookUuid>/events', _createEvent)
      ..post('/<bookUuid>/heavy-test/events/bulk', _createEventsBulkHeavyTest)
      ..get('/<bookUuid>/event-details/<eventId>', _getEventDetailBundle)
      ..patch('/<bookUuid>/event-details/<eventId>', _updateEventDetailBundle)
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

  String _normalizeDeviceRole(dynamic value, {String fallback = 'write'}) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'read') return 'read';
    if (normalized == 'write') return 'write';
    return fallback;
  }

  Future<String?> _authorizeBookRequest(
    Request request,
    String bookUuid, {
    bool requireWrite = false,
  }) async {
    final deviceId = request.headers['x-device-id'];
    final deviceToken = request.headers['x-device-token'];

    if (deviceId == null || deviceToken == null) {
      return 'missing_credentials';
    }

    final deviceRows = await db.client
        .from('devices')
        .select('id, device_token, is_active, device_role')
        .eq('id', deviceId)
        .limit(1);
    final device = _first(deviceRows);
    if (device == null) {
      return 'invalid_credentials';
    }

    final isActive = device['is_active'] == true;
    final matchedToken =
        (device['device_token'] ?? '').toString() == deviceToken;
    if (!isActive || !matchedToken) {
      return 'invalid_credentials';
    }

    final deviceRole = _normalizeDeviceRole(device['device_role']);
    if (requireWrite && deviceRole != 'write') {
      return 'read_only_device';
    }

    final bookRows = await db.client
        .from('books')
        .select('book_uuid, device_id')
        .eq('book_uuid', bookUuid)
        .eq('is_deleted', false)
        .limit(1);
    final book = _first(bookRows);
    if (book == null) {
      return 'unauthorized';
    }

    if (deviceRole == 'write') {
      return null;
    }

    final ownsBook = book['device_id']?.toString() == deviceId;
    if (ownsBook) {
      return null;
    }

    final accessRows = await db.client
        .from('book_device_access')
        .select('book_uuid')
        .eq('book_uuid', bookUuid)
        .eq('device_id', deviceId)
        .limit(1);
    final access = _first(accessRows);
    if (access == null) {
      return 'unauthorized';
    }

    return null;
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

    final failureCode = await _authorizeBookRequest(
      request,
      bookUuid,
      requireWrite: requireWrite,
    );
    if (failureCode == 'invalid_credentials') {
      return Response.forbidden(
        jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (failureCode == 'read_only_device') {
      return Response.forbidden(
        jsonEncode({
          'success': false,
          'message': 'Read-only device cannot modify events',
          'error': 'READ_ONLY_DEVICE',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    if (failureCode == 'unauthorized') {
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
        .select(_eventSelectColumns)
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
    final eventRows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += _queryPageSize) {
      final batch = _rows(
        await db.client
            .from('events')
            .select(_eventSelectColumns)
            .eq('book_uuid', bookUuid)
            .eq('is_deleted', false)
            .gte('start_time', startDate.toUtc().toIso8601String())
            .lt('start_time', endDate.toUtc().toIso8601String())
            .order('start_time', ascending: true)
            .range(offset, offset + _queryPageSize - 1),
      );
      if (batch.isEmpty) {
        break;
      }
      eventRows.addAll(batch);
      if (batch.length < _queryPageSize) {
        break;
      }
    }

    final recordUuids = eventRows
        .map((row) => row['record_uuid']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final recordsById = <String, Map<String, dynamic>>{};
    if (recordUuids.isNotEmpty) {
      for (var i = 0; i < recordUuids.length; i += _queryPageSize) {
        final chunk = recordUuids.sublist(
          i,
          (i + _queryPageSize).clamp(0, recordUuids.length),
        );
        final recordRows = _rows(
          await db.client
              .from('records')
              .select('record_uuid, record_number, name, phone')
              .inFilter('record_uuid', chunk)
              .eq('is_deleted', false),
        );
        for (final row in recordRows) {
          recordsById[row['record_uuid'].toString()] = row;
        }
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

  Future<List<Map<String, dynamic>>> _bookEventsWithRecords(
    String bookUuid,
  ) async {
    final eventRows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += _queryPageSize) {
      final batch = _rows(
        await db.client
            .from('events')
            .select(
              'id, book_uuid, record_uuid, title, event_types, has_charge_items, start_time, end_time, '
              'created_at, updated_at, is_removed, removal_reason, original_event_id, new_event_id, '
              'is_checked, has_note, version',
            )
            .eq('book_uuid', bookUuid)
            .eq('is_deleted', false)
            .order('start_time', ascending: true)
            .range(offset, offset + _queryPageSize - 1),
      );
      if (batch.isEmpty) {
        break;
      }
      eventRows.addAll(batch);
      if (batch.length < _queryPageSize) {
        break;
      }
    }

    final recordUuids = eventRows
        .map((row) => row['record_uuid']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final recordsById = <String, Map<String, dynamic>>{};
    if (recordUuids.isNotEmpty) {
      for (var i = 0; i < recordUuids.length; i += _queryPageSize) {
        final chunk = recordUuids.sublist(
          i,
          (i + _queryPageSize).clamp(0, recordUuids.length),
        );
        final recordRows = _rows(
          await db.client
              .from('records')
              .select('record_uuid, record_number, name, phone')
              .inFilter('record_uuid', chunk)
              .eq('is_deleted', false),
        );
        for (final row in recordRows) {
          recordsById[row['record_uuid']?.toString() ?? ''] = row;
        }
      }
    }

    return eventRows.map((event) {
      final record = recordsById[event['record_uuid']?.toString() ?? ''];
      return {
        ...event,
        'record_name': _normalizedEventName(event, record),
        'record_phone': record?['phone'],
        'record_number': (record?['record_number'] ?? '').toString().trim(),
      };
    }).toList();
  }

  String _normalizedEventName(
    Map<String, dynamic> event,
    Map<String, dynamic>? record,
  ) {
    final recordName = (record?['name'] ?? '').toString().trim();
    if (recordName.isNotEmpty) {
      return recordName;
    }

    final title = (event['title'] ?? '').toString().trim();
    final suffixIndex = title.indexOf('(');
    if (suffixIndex > 0) {
      return title.substring(0, suffixIndex).trim();
    }
    return title;
  }

  Future<List<Map<String, dynamic>>> _bookEventRecordRows(
    String bookUuid,
  ) async {
    final eventRows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += _queryPageSize) {
      final batch = _rows(
        await db.client
            .from('events')
            .select('record_uuid, title')
            .eq('book_uuid', bookUuid)
            .eq('is_deleted', false)
            .order('id', ascending: true)
            .range(offset, offset + _queryPageSize - 1),
      );
      if (batch.isEmpty) {
        break;
      }
      eventRows.addAll(batch);
      if (batch.length < _queryPageSize) {
        break;
      }
    }

    final recordUuids = eventRows
        .map((row) => row['record_uuid']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final recordsById = <String, Map<String, dynamic>>{};
    if (recordUuids.isNotEmpty) {
      for (var i = 0; i < recordUuids.length; i += _queryPageSize) {
        final chunk = recordUuids.sublist(
          i,
          (i + _queryPageSize).clamp(0, recordUuids.length),
        );
        final recordRows = _rows(
          await db.client
              .from('records')
              .select('record_uuid, record_number, name')
              .inFilter('record_uuid', chunk)
              .eq('is_deleted', false),
        );
        for (final row in recordRows) {
          recordsById[row['record_uuid']?.toString() ?? ''] = row;
        }
      }
    }

    return eventRows.map((event) {
      final recordUuid = event['record_uuid']?.toString() ?? '';
      final record = recordsById[recordUuid];
      return {
        'name': _normalizedEventName(event, record),
        'record_number': (record?['record_number'] ?? '').toString().trim(),
      };
    }).toList();
  }

  Future<Response> _getNameSuggestions(Request request, String bookUuid) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) {
        return authError;
      }

      final prefix =
          request.url.queryParameters['prefix']?.trim().toLowerCase() ?? '';
      if (prefix.isEmpty) {
        return Response.ok(
          jsonEncode({'success': true, 'names': const <String>[]}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final rows = await _bookEventRecordRows(bookUuid);
      final names =
          rows
              .map((row) => row['name']?.toString().trim() ?? '')
              .where(
                (name) =>
                    name.isNotEmpty && name.toLowerCase().startsWith(prefix),
              )
              .toSet()
              .toList()
            ..sort();

      return Response.ok(
        jsonEncode({'success': true, 'names': names}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to load name suggestions: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getRecordNumberSuggestions(
    Request request,
    String bookUuid,
  ) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) {
        return authError;
      }

      final prefix =
          request.url.queryParameters['prefix']?.trim().toLowerCase() ?? '';
      final namePrefix =
          request.url.queryParameters['namePrefix']?.trim().toLowerCase() ?? '';
      if (prefix.isEmpty && namePrefix.isEmpty) {
        return Response.ok(
          jsonEncode({'success': true, 'pairs': const <Map<String, String>>[]}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final rows = await _bookEventRecordRows(bookUuid);
      final pairs = <Map<String, String>>[];
      final seen = <String>{};
      for (final row in rows) {
        final name = row['name']?.toString().trim() ?? '';
        final recordNumber = row['record_number']?.toString().trim() ?? '';
        if (name.isEmpty || recordNumber.isEmpty) {
          continue;
        }
        if (prefix.isNotEmpty &&
            !recordNumber.toLowerCase().startsWith(prefix)) {
          continue;
        }
        if (namePrefix.isNotEmpty &&
            !name.toLowerCase().startsWith(namePrefix)) {
          continue;
        }

        final key = '$name::$recordNumber';
        if (!seen.add(key)) {
          continue;
        }
        pairs.add({'name': name, 'record_number': recordNumber});
      }

      pairs.sort((a, b) {
        final numberCompare = a['record_number']!.compareTo(
          b['record_number']!,
        );
        if (numberCompare != 0) {
          return numberCompare;
        }
        return a['name']!.compareTo(b['name']!);
      });

      return Response.ok(
        jsonEncode({'success': true, 'pairs': pairs}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to load record number suggestions: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _queryAppointments(Request request, String bookUuid) async {
    try {
      final authError = await _authorizeBookAccess(request, bookUuid);
      if (authError != null) {
        return authError;
      }

      final name = request.url.queryParameters['name']?.trim() ?? '';
      final recordNumber =
          request.url.queryParameters['recordNumber']?.trim() ?? '';
      if (name.isEmpty || recordNumber.isEmpty) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'events': const <Map<String, dynamic>>[],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final normalizedName = name.toLowerCase();
      final matched =
          (await _bookEventsWithRecords(bookUuid))
              .where((event) {
                final eventName = (event['record_name'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                final eventRecordNumber = (event['record_number'] ?? '')
                    .toString()
                    .trim();
                return eventName.startsWith(normalizedName) &&
                    eventRecordNumber == recordNumber;
              })
              .map(_serializeEvent)
              .toList()
            ..sort((a, b) {
              final aStart = (a['start_time'] as int?) ?? 0;
              final bStart = (b['start_time'] as int?) ?? 0;
              return bStart.compareTo(aStart);
            });

      return Response.ok(
        jsonEncode({'success': true, 'events': matched}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to search appointments: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
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

  Map<String, dynamic> _serializeRecord(Map<String, dynamic> row) {
    int? asSeconds(dynamic v) {
      if (v == null) return null;
      return _asUtc(v).millisecondsSinceEpoch ~/ 1000;
    }

    return {
      'record_uuid': row['record_uuid'],
      'record_number': row['record_number'],
      'name': row['name'],
      'phone': row['phone'],
      'created_at': asSeconds(row['created_at']),
      'updated_at': asSeconds(row['updated_at']),
      'version': (row['version'] as num?)?.toInt() ?? 1,
    };
  }

  Map<String, dynamic> _serializeNote(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'record_uuid': row['record_uuid'],
      'pages_data': row['pages_data'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
      'version': (row['version'] as num?)?.toInt() ?? 1,
      'locked_by_device_id': row['locked_by_device_id'],
      'locked_at': row['locked_at'],
    };
  }

  Future<Map<String, dynamic>?> _recordByUuid(String recordUuid) async {
    final recordRows = await db.client
        .from('records')
        .select(
          'record_uuid, record_number, name, phone, created_at, updated_at, version',
        )
        .eq('record_uuid', recordUuid)
        .eq('is_deleted', false)
        .limit(1);
    return _first(recordRows);
  }

  Future<Map<String, dynamic>?> _noteByRecordUuid(String recordUuid) async {
    final noteRows = await db.client
        .from('notes')
        .select(
          'id, record_uuid, pages_data, created_at, updated_at, version, locked_by_device_id, locked_at',
        )
        .eq('record_uuid', recordUuid)
        .eq('is_deleted', false)
        .limit(1);
    return _first(noteRows);
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
      if (!endDate.toUtc().isAfter(startDate.toUtc())) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'endDate must be after startDate',
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

  Future<Response> _getEventDetailBundle(
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

      final recordUuid = eventRow['record_uuid']?.toString() ?? '';
      final recordRow = recordUuid.isEmpty
          ? null
          : await _recordByUuid(recordUuid);
      final noteRow = recordUuid.isEmpty
          ? null
          : await _noteByRecordUuid(recordUuid);

      return Response.ok(
        jsonEncode({
          'success': true,
          'event': _serializeEvent(eventRow),
          'record': recordRow == null ? null : _serializeRecord(recordRow),
          'note': noteRow == null ? null : _serializeNote(noteRow),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to load event detail bundle: $e',
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

      final recordRow = await _recordByUuid(recordUuid);

      if (recordRow == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Record not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final noteRow = await _noteByRecordUuid(recordUuid);

      return Response.ok(
        jsonEncode({
          'success': true,
          'record': _serializeRecord(recordRow),
          'note': noteRow != null ? _serializeNote(noteRow) : null,
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
      final eventPayload = Map<String, dynamic>.from(
        prepared.eventInsertPayload,
      )..['has_charge_items'] = false;

      await _ensureRecord(
        recordUuid: prepared.recordUuid,
        recordNumber: prepared.recordNumber,
        recordName: prepared.recordName,
        recordPhone: prepared.recordPhone,
      );
      await db.client.from('events').insert(eventPayload);

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
      if (json.containsKey('record_uuid') || json.containsKey('recordUuid')) {
        final recordUuid = (json['record_uuid'] ?? json['recordUuid'])
            ?.toString()
            .trim();
        if (recordUuid != null && recordUuid.isNotEmpty) {
          payload['record_uuid'] = recordUuid;
        }
      }
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

  Future<Response> _updateEventDetailBundle(
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
      final eventJson = json['event'] is Map<String, dynamic>
          ? json['event'] as Map<String, dynamic>
          : json;
      final recordJson = json['record'] is Map<String, dynamic>
          ? json['record'] as Map<String, dynamic>
          : const <String, dynamic>{};

      final existingRows = await db.client
          .from('events')
          .select('id, version, record_uuid')
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

      final eventPayload = <String, dynamic>{};
      if (eventJson.containsKey('title')) {
        eventPayload['title'] = (eventJson['title'] as String?)?.trim();
      }
      if (eventJson.containsKey('record_uuid') ||
          eventJson.containsKey('recordUuid')) {
        final nextRecordUuid =
            (eventJson['record_uuid'] ?? eventJson['recordUuid'])
                ?.toString()
                .trim();
        if (nextRecordUuid != null && nextRecordUuid.isNotEmpty) {
          eventPayload['record_uuid'] = nextRecordUuid;
        }
      }
      if (eventJson.containsKey('event_types') ||
          eventJson.containsKey('eventTypes')) {
        eventPayload['event_types'] = _eventTypesToJson(
          eventJson['event_types'] ?? eventJson['eventTypes'],
        );
      }
      if (eventJson.containsKey('has_charge_items') ||
          eventJson.containsKey('hasChargeItems')) {
        eventPayload['has_charge_items'] = _toBool(
          eventJson['has_charge_items'] ?? eventJson['hasChargeItems'],
        );
      }
      if (eventJson.containsKey('start_time') ||
          eventJson.containsKey('startTime')) {
        eventPayload['start_time'] = _parseTimestamp(
          eventJson['start_time'] ?? eventJson['startTime'],
        )?.toIso8601String();
      }
      if (eventJson.containsKey('end_time') ||
          eventJson.containsKey('endTime')) {
        eventPayload['end_time'] = _parseTimestamp(
          eventJson['end_time'] ?? eventJson['endTime'],
        )?.toIso8601String();
      }
      if (eventJson.containsKey('is_removed') ||
          eventJson.containsKey('isRemoved')) {
        eventPayload['is_removed'] = _toBool(
          eventJson['is_removed'] ?? eventJson['isRemoved'],
        );
      }
      if (eventJson.containsKey('removal_reason') ||
          eventJson.containsKey('removalReason')) {
        eventPayload['removal_reason'] =
            (eventJson['removal_reason'] ?? eventJson['removalReason'])
                ?.toString();
      }
      if (eventJson.containsKey('original_event_id') ||
          eventJson.containsKey('originalEventId')) {
        eventPayload['original_event_id'] =
            (eventJson['original_event_id'] ?? eventJson['originalEventId'])
                ?.toString();
      }
      if (eventJson.containsKey('new_event_id') ||
          eventJson.containsKey('newEventId')) {
        eventPayload['new_event_id'] =
            (eventJson['new_event_id'] ?? eventJson['newEventId'])?.toString();
      }
      if (eventJson.containsKey('is_checked') ||
          eventJson.containsKey('isChecked')) {
        eventPayload['is_checked'] = _toBool(
          eventJson['is_checked'] ?? eventJson['isChecked'],
        );
      }
      if (eventJson.containsKey('has_note') ||
          eventJson.containsKey('hasNote')) {
        eventPayload['has_note'] = _toBool(
          eventJson['has_note'] ?? eventJson['hasNote'],
        );
      }

      if (eventPayload.isNotEmpty) {
        eventPayload['updated_at'] = DateTime.now().toUtc().toIso8601String();
        eventPayload['synced_at'] = DateTime.now().toUtc().toIso8601String();
        eventPayload['version'] =
            ((existing['version'] as num?)?.toInt() ?? 1) + 1;

        await db.client
            .from('events')
            .update(eventPayload)
            .eq('id', eventId)
            .eq('book_uuid', bookUuid)
            .eq('is_deleted', false);
      }

      final targetRecordUuid =
          (eventPayload['record_uuid'] ?? existing['record_uuid'])
              ?.toString() ??
          '';
      if (targetRecordUuid.isNotEmpty && recordJson.isNotEmpty) {
        final recordPayload = <String, dynamic>{};
        if (recordJson.containsKey('record_number') ||
            recordJson.containsKey('recordNumber')) {
          recordPayload['record_number'] =
              (recordJson['record_number'] ?? recordJson['recordNumber'])
                  ?.toString();
        }
        if (recordJson.containsKey('name')) {
          recordPayload['name'] = recordJson['name']?.toString();
        }
        if (recordJson.containsKey('phone')) {
          recordPayload['phone'] = recordJson['phone']?.toString();
        }

        if (recordPayload.isNotEmpty) {
          recordPayload['updated_at'] = DateTime.now()
              .toUtc()
              .toIso8601String();
          recordPayload['synced_at'] = DateTime.now().toUtc().toIso8601String();

          await db.client
              .from('records')
              .update(recordPayload)
              .eq('record_uuid', targetRecordUuid)
              .eq('is_deleted', false);
        }
      }

      final eventRow = await _eventWithRecord(bookUuid, eventId);
      if (eventRow == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final recordRow = await _recordByUuid(eventRow['record_uuid'].toString());
      final noteRow = await _noteByRecordUuid(
        eventRow['record_uuid'].toString(),
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'event': _serializeEvent(eventRow),
          'record': recordRow == null ? null : _serializeRecord(recordRow),
          'note': noteRow == null ? null : _serializeNote(noteRow),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to update event detail bundle: $e',
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

      final result = await db.transaction(() async {
        final existingRows = await db.client
            .from('events')
            .select('*')
            .eq('id', eventId)
            .eq('book_uuid', bookUuid)
            .eq('is_deleted', false)
            .limit(1);
        final existing = _first(existingRows);
        if (existing == null) {
          return null;
        }

        final recordUuid = existing['record_uuid']?.toString() ?? '';
        final record = recordUuid.isEmpty
            ? null
            : await _recordByUuid(recordUuid);
        final generatedId = _uuid.v4();
        final now = DateTime.now().toUtc().toIso8601String();
        final serverVersion = (existing['version'] as num?)?.toInt() ?? 1;

        final oldEventRow = {
          ...existing,
          'is_removed': true,
          'removal_reason': reason,
          'new_event_id': generatedId,
          'updated_at': now,
          'synced_at': now,
          'version': serverVersion + 1,
          'record_name': record?['name'],
          'record_phone': record?['phone'],
          'record_number': record?['record_number'],
        };

        final newEventRow = {
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
          'record_name': record?['name'],
          'record_phone': record?['phone'],
          'record_number': record?['record_number'],
        };

        await db.client
            .from('events')
            .update({
              'is_removed': true,
              'removal_reason': reason,
              'new_event_id': generatedId,
              'updated_at': now,
              'synced_at': now,
              'version': serverVersion + 1,
            })
            .eq('id', eventId)
            .eq('book_uuid', bookUuid)
            .eq('is_deleted', false);

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

        return (oldEvent: oldEventRow, newEvent: newEventRow);
      });
      if (result == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
          'success': true,
          'oldEvent': _serializeEvent(result.oldEvent),
          'newEvent': _serializeEvent(result.newEvent),
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
