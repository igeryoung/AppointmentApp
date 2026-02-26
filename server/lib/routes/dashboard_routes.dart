import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../database/connection.dart';
import '../utils/logger.dart';

/// Router for dashboard monitoring endpoints.
///
/// Supabase SDK-only implementation. Aggregations are performed in Dart so no
/// raw SQL or RPC SQL gateway is required.
class DashboardRoutes {
  final DatabaseConnection db;
  final String adminUsername;
  final String adminPassword;
  final Logger _logger = Logger('DashboardRoutes');

  DashboardRoutes(this.db, {String? adminUsername, String? adminPassword})
    : adminUsername = adminUsername ?? 'admin',
      adminPassword = adminPassword ?? 'admin123';

  Router get router {
    final router = Router();

    router.post('/auth/login', _login);

    router.get('/stats', _authMiddleware(_getStats));
    router.get('/devices', _authMiddleware(_getDevices));
    router.get('/books', _authMiddleware(_getBooks));
    router.get('/records', _authMiddleware(_getRecords));
    router.get('/records/<recordUuid>', (
      Request request,
      String recordUuid,
    ) async {
      return _authMiddleware(
        (Request req) => _getRecordDetail(req, recordUuid),
      )(request);
    });
    router.get('/events', _authMiddleware(_getEvents));
    router.get('/events/<eventId>', (Request request, String eventId) async {
      return _authMiddleware((Request req) => _getEventDetail(req, eventId))(
        request,
      );
    });
    router.get('/events/<eventId>/note', (
      Request request,
      String eventId,
    ) async {
      return _authMiddleware((Request req) => _getEventNote(req, eventId))(
        request,
      );
    });
    router.get('/notes', _authMiddleware(_getNotes));
    router.get('/drawings', _authMiddleware(_getDrawings));
    router.get('/backups', _authMiddleware(_getBackups));
    router.get('/sync-logs', _authMiddleware(_getSyncLogs));

    return router;
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

  int _safeInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  int? _parseLimit(Map<String, String> params, {int max = 200}) {
    final rawLimit = params['limit'];
    if (rawLimit == null || rawLimit.trim().isEmpty) {
      return null;
    }

    final parsed = int.tryParse(rawLimit);
    if (parsed == null || parsed <= 0) {
      return null;
    }

    return parsed > max ? max : parsed;
  }

  int _parseOffset(Map<String, String> params) {
    final rawOffset = params['offset'];
    if (rawOffset == null || rawOffset.trim().isEmpty) {
      return 0;
    }

    final parsed = int.tryParse(rawOffset);
    if (parsed == null || parsed < 0) {
      return 0;
    }

    return parsed;
  }

  String _snakeToCamel(String snakeCase) {
    final parts = snakeCase.split('_');
    if (parts.length == 1) return snakeCase;

    return parts[0] +
        parts
            .skip(1)
            .map(
              (part) =>
                  part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1),
            )
            .join('');
  }

  dynamic _serializeValue(String column, dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (column.endsWith('_at')) {
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed.toUtc().toIso8601String();
    }
    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(k.toString(), _serializeValue(k.toString(), v)),
      );
    }
    if (value is List) {
      return value.map((v) => _serializeValue(column, v)).toList();
    }
    return value;
  }

  Map<String, dynamic> _serializeRow(Map<String, dynamic> row) {
    final result = <String, dynamic>{};
    for (final entry in row.entries) {
      result[_snakeToCamel(entry.key)] = _serializeValue(
        entry.key,
        entry.value,
      );
    }
    return result;
  }

  List<Map<String, dynamic>> _serializeRows(List<Map<String, dynamic>> rows) {
    return rows.map(_serializeRow).toList();
  }

  List<Map<String, dynamic>> _paginate(
    List<Map<String, dynamic>> rows, {
    required int offset,
    required int? limit,
  }) {
    if (rows.isEmpty || offset >= rows.length) return const [];
    final end = limit == null
        ? rows.length
        : (offset + limit).clamp(0, rows.length);
    return rows.sublist(offset, end);
  }

  int _compareDateDesc(dynamic a, dynamic b) {
    final da = _asUtc(a);
    final dbv = _asUtc(b);
    return dbv.compareTo(da);
  }

  List<String> _normalizeEventTypes(dynamic raw) {
    if (raw == null) return const ['other'];
    if (raw is List) {
      final values = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty);
      return values.isEmpty ? const ['other'] : values.toList();
    }

    final text = raw.toString().trim();
    if (text.isEmpty) return const ['other'];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        final values = decoded
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return values.isEmpty ? const ['other'] : values;
      }
    } catch (_) {
      // Fall through and treat as scalar string.
    }

    return [text];
  }

  Map<String, dynamic> _indexByStringKey(
    List<Map<String, dynamic>> rows,
    String key,
  ) {
    final result = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final value = row[key]?.toString();
      if (value != null && value.isNotEmpty) {
        result[value] = row;
      }
    }
    return result;
  }

  Future<Response> _login(Request request) async {
    try {
      final body = await request.readAsString();
      if (body.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'message': 'Empty request body'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final username = json['username'] as String?;
      final password = json['password'] as String?;

      if (username == adminUsername && password == adminPassword) {
        final token = base64Encode(utf8.encode('$username:$password'));
        return Response.ok(
          jsonEncode({
            'success': true,
            'token': token,
            'message': 'Login successful',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.forbidden(
        jsonEncode({'success': false, 'message': 'Invalid credentials'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('Dashboard login failed', error: e, stackTrace: stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': 'Login failed: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Handler _authMiddleware(Handler handler) {
    return (Request request) async {
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(
          401,
          body: jsonEncode({'success': false, 'message': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return handler(request);
    };
  }

  Future<Response> _getStats(Request request) async {
    try {
      final devices = await _getDeviceStats();
      final books = await _getBookStats();
      final events = await _getEventStats();
      final notes = await _getNoteStats();
      final drawings = await _getDrawingStats();
      final backups = await _getBackupStats();
      final sync = await _getSyncStatsData();

      return Response.ok(
        jsonEncode({
          'devices': devices,
          'books': books,
          'events': events,
          'notes': notes,
          'drawings': drawings,
          'backups': backups,
          'sync': sync,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to fetch dashboard stats',
        error: e,
        stackTrace: stackTrace,
      );
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to fetch stats',
          'error': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Map<String, dynamic>> _getDeviceStats() async {
    final allRows = _rows(await db.client.from('devices').select('*'));
    final listedRows = _rows(
      await db.client
          .from('devices')
          .select(
            'id, device_name, platform, registered_at, last_sync_at, is_active',
          )
          .order('registered_at', ascending: false)
          .limit(100),
    );

    final total = allRows.length;
    final active = allRows.where((row) => row['is_active'] == true).length;

    return {
      'total': total,
      'active': active,
      'inactive': total - active,
      'devices': _serializeRows(listedRows),
    };
  }

  Future<Map<String, dynamic>> _getBookStats() async {
    final allBooks = _rows(await db.client.from('books').select('*'));
    final activeBooks = allBooks
        .where((row) => row['is_deleted'] != true)
        .toList();

    final eventRows = _rows(
      await db.client
          .from('events')
          .select('id, book_uuid, record_uuid, is_deleted')
          .eq('is_deleted', false),
    );
    final noteRows = _rows(
      await db.client
          .from('notes')
          .select('record_uuid, is_deleted')
          .eq('is_deleted', false),
    );
    final drawingRows = _rows(
      await db.client
          .from('schedule_drawings')
          .select('id, book_uuid, is_deleted')
          .eq('is_deleted', false),
    );

    final eventCountByBook = <String, int>{};
    final notedRecords = <String>{};
    final notedRecordSetByBook = <String, Set<String>>{};
    final drawingCountByBook = <String, int>{};

    for (final row in noteRows) {
      final recordUuid = row['record_uuid']?.toString();
      if (recordUuid != null && recordUuid.isNotEmpty) {
        notedRecords.add(recordUuid);
      }
    }

    for (final event in eventRows) {
      final bookUuid = event['book_uuid']?.toString();
      final recordUuid = event['record_uuid']?.toString();
      if (bookUuid == null || bookUuid.isEmpty) continue;

      eventCountByBook[bookUuid] = (eventCountByBook[bookUuid] ?? 0) + 1;

      if (recordUuid != null && notedRecords.contains(recordUuid)) {
        notedRecordSetByBook
            .putIfAbsent(bookUuid, () => <String>{})
            .add(recordUuid);
      }
    }

    for (final drawing in drawingRows) {
      final bookUuid = drawing['book_uuid']?.toString();
      if (bookUuid == null || bookUuid.isEmpty) continue;
      drawingCountByBook[bookUuid] = (drawingCountByBook[bookUuid] ?? 0) + 1;
    }

    activeBooks.sort(
      (a, b) => _compareDateDesc(a['created_at'], b['created_at']),
    );

    final listedBooks = activeBooks.take(100).map((book) {
      final bookUuid = book['book_uuid']?.toString() ?? '';
      return {
        ...book,
        'event_count': eventCountByBook[bookUuid] ?? 0,
        'note_count': notedRecordSetByBook[bookUuid]?.length ?? 0,
        'drawing_count': drawingCountByBook[bookUuid] ?? 0,
      };
    }).toList();

    final archived = activeBooks
        .where((row) => row['archived_at'] != null)
        .length;

    return {
      'total': activeBooks.length,
      'active': activeBooks.length - archived,
      'archived': archived,
      'books': _serializeRows(listedBooks),
    };
  }

  Future<Map<String, dynamic>> _getEventStats() async {
    final allEvents = _rows(await db.client.from('events').select('*'));
    final activeEvents = allEvents
        .where((row) => row['is_deleted'] != true)
        .toList();

    final byType = <String, int>{};
    for (final event in activeEvents) {
      for (final type in _normalizeEventTypes(event['event_types'])) {
        byType[type] = (byType[type] ?? 0) + 1;
      }
    }

    activeEvents.sort(
      (a, b) => _compareDateDesc(a['created_at'], b['created_at']),
    );
    final recent = activeEvents.take(50).toList();

    final recordUuids = recent
        .map((row) => row['record_uuid']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();

    Map<String, dynamic> recordMap = {};
    if (recordUuids.isNotEmpty) {
      final records = _rows(
        await db.client
            .from('records')
            .select('record_uuid, name, phone, record_number')
            .inFilter('record_uuid', recordUuids.toList()),
      );
      recordMap = _indexByStringKey(records, 'record_uuid');
    }

    final recentWithRecord = recent.map((event) {
      final recordUuid = event['record_uuid']?.toString();
      final record = recordUuid == null ? null : recordMap[recordUuid];
      return {
        ...event,
        'name': record?['name'],
        'phone': record?['phone'],
        'record_number': record?['record_number'],
        'has_note': event['has_note'] == true,
      };
    }).toList();

    final removed = activeEvents
        .where((row) => row['is_removed'] == true)
        .length;

    return {
      'total': activeEvents.length,
      'active': activeEvents.length - removed,
      'removed': removed,
      'byType': byType,
      'recent': _serializeRows(recentWithRecord),
    };
  }

  Future<Map<String, dynamic>> _getNoteStats() async {
    final notes = _rows(
      await db.client.from('notes').select('*'),
    ).where((row) => row['is_deleted'] != true).toList();
    final events = _rows(
      await db.client.from('events').select('id, record_uuid, is_deleted'),
    ).where((row) => row['is_deleted'] != true).toList();

    final notedRecordUuids = notes
        .map((row) => row['record_uuid']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();

    final eventsWithNotes = events
        .where(
          (row) => notedRecordUuids.contains(row['record_uuid']?.toString()),
        )
        .length;

    notes.sort((a, b) => _compareDateDesc(a['updated_at'], b['updated_at']));

    return {
      'total': notes.length,
      'eventsWithNotes': eventsWithNotes,
      'eventsWithoutNotes': events.length - eventsWithNotes,
      'recentlyUpdated': _serializeRows(notes.take(50).toList()),
    };
  }

  Future<Map<String, dynamic>> _getDrawingStats() async {
    final drawings = _rows(
      await db.client.from('schedule_drawings').select('*'),
    ).where((row) => row['is_deleted'] != true).toList();

    final day = drawings.where((row) => _safeInt(row['view_mode']) == 0).length;
    final threeDay = drawings
        .where((row) => _safeInt(row['view_mode']) == 1)
        .length;
    final week = drawings
        .where((row) => _safeInt(row['view_mode']) == 2)
        .length;

    drawings.sort((a, b) => _compareDateDesc(a['updated_at'], b['updated_at']));

    return {
      'total': drawings.length,
      'byViewMode': {'day': day, 'threeDay': threeDay, 'week': week},
      'recent': _serializeRows(drawings.take(50).toList()),
    };
  }

  Future<Map<String, dynamic>> _getBackupStats() async {
    try {
      final rawRows = _rows(await db.client.from('book_backups').select('*'));
      final backups = rawRows
          .where((row) => row['is_deleted'] != true)
          .toList();

      final bookUuids = backups
          .map((row) => row['book_uuid']?.toString())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet();

      Map<String, dynamic> bookMap = {};
      if (bookUuids.isNotEmpty) {
        final books = _rows(
          await db.client
              .from('books')
              .select('book_uuid, name')
              .inFilter('book_uuid', bookUuids.toList()),
        );
        bookMap = _indexByStringKey(books, 'book_uuid');
      }

      final totalSize = backups.fold<int>(
        0,
        (sum, row) => sum + _safeInt(row['backup_size']),
      );

      backups.sort(
        (a, b) => _compareDateDesc(a['created_at'], b['created_at']),
      );
      final recentBackups = backups.take(50).map((row) {
        final bookUuid = row['book_uuid']?.toString();
        final book = bookUuid == null ? null : bookMap[bookUuid];
        return {...row, 'book_name': book?['name']};
      }).toList();

      final restoredCount = backups
          .where((row) => row['restored_at'] != null)
          .length;

      return {
        'total': backups.length,
        'totalSizeBytes': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'recentBackups': _serializeRows(recentBackups),
        'restoredCount': restoredCount,
      };
    } catch (_) {
      return {
        'total': 0,
        'totalSizeBytes': 0,
        'totalSizeMB': '0.00',
        'recentBackups': const [],
        'restoredCount': 0,
      };
    }
  }

  Future<Map<String, dynamic>> _getSyncStatsData() async {
    try {
      final logs = _rows(await db.client.from('sync_log').select('*'));
      logs.sort((a, b) => _compareDateDesc(a['synced_at'], b['synced_at']));

      final deviceIds = logs
          .map((row) => row['device_id']?.toString())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet();

      Map<String, dynamic> deviceMap = {};
      if (deviceIds.isNotEmpty) {
        final devices = _rows(
          await db.client
              .from('devices')
              .select('id, device_name')
              .inFilter('id', deviceIds.toList()),
        );
        deviceMap = _indexByStringKey(devices, 'id');
      }

      final successful = logs
          .where((row) => row['status']?.toString() == 'success')
          .length;
      final failed = logs
          .where((row) => row['status']?.toString() == 'failed')
          .length;
      final conflicts = logs
          .where((row) => row['status']?.toString() == 'conflict')
          .length;

      final recent = logs.take(100).map((row) {
        final deviceId = row['device_id']?.toString();
        final device = deviceId == null ? null : deviceMap[deviceId];
        return {...row, 'device_name': device?['device_name']};
      }).toList();

      return {
        'totalOperations': logs.length,
        'successfulSyncs': successful,
        'failedSyncs': failed,
        'conflictCount': conflicts,
        'successRate': logs.isEmpty ? 0.0 : (successful / logs.length) * 100,
        'recentSyncs': _serializeRows(recent),
      };
    } catch (_) {
      return {
        'totalOperations': 0,
        'successfulSyncs': 0,
        'failedSyncs': 0,
        'conflictCount': 0,
        'successRate': 0.0,
        'recentSyncs': const [],
      };
    }
  }

  Future<Response> _getRecords(Request request) async {
    try {
      final params = request.url.queryParameters;
      final name = params['name']?.trim().toLowerCase();
      final recordNumber = params['recordNumber']?.trim().toLowerCase();
      final phone = params['phone']?.trim().toLowerCase();
      final searchQuery = params['searchQuery']?.trim().toLowerCase();
      final limit = _parseLimit(params);
      final offset = _parseOffset(params);

      final records = _rows(
        await db.client.from('records').select('*'),
      ).where((row) => row['is_deleted'] != true).toList();

      final events = _rows(
        await db.client.from('events').select('id, record_uuid, is_deleted'),
      ).where((row) => row['is_deleted'] != true).toList();
      final noteRows = _rows(
        await db.client.from('notes').select('record_uuid, is_deleted'),
      ).where((row) => row['is_deleted'] != true).toList();

      final noteRecords = noteRows
          .map((row) => row['record_uuid']?.toString())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet();

      final eventCountByRecord = <String, int>{};
      for (final event in events) {
        final recordUuid = event['record_uuid']?.toString();
        if (recordUuid == null || recordUuid.isEmpty) continue;
        eventCountByRecord[recordUuid] =
            (eventCountByRecord[recordUuid] ?? 0) + 1;
      }

      final filtered = records.where((record) {
        final rName = (record['name'] ?? '').toString().toLowerCase();
        final rNumber = (record['record_number'] ?? '')
            .toString()
            .toLowerCase();
        final rPhone = (record['phone'] ?? '').toString().toLowerCase();
        final uuid = (record['record_uuid'] ?? '').toString().toLowerCase();

        final matchesName = name == null || rName.contains(name);
        final matchesNumber =
            recordNumber == null || rNumber.contains(recordNumber);
        final matchesPhone = phone == null || rPhone.contains(phone);

        final matchesSearch =
            searchQuery == null ||
            rName.contains(searchQuery) ||
            rNumber.contains(searchQuery) ||
            rPhone.contains(searchQuery) ||
            uuid.contains(searchQuery);

        return matchesName && matchesNumber && matchesPhone && matchesSearch;
      }).toList();

      filtered.sort(
        (a, b) => _compareDateDesc(a['updated_at'], b['updated_at']),
      );

      final total = filtered.length;
      final paged = _paginate(filtered, offset: offset, limit: limit);
      final rows = paged.map((record) {
        final recordUuid = record['record_uuid']?.toString() ?? '';
        return {
          ...record,
          'event_count': eventCountByRecord[recordUuid] ?? 0,
          'has_note': noteRecords.contains(recordUuid),
        };
      }).toList();

      return Response.ok(
        jsonEncode({
          'records': _serializeRows(rows),
          'total': total,
          'limit': limit ?? rows.length,
          'offset': limit != null ? offset : 0,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to fetch records',
        error: e,
        stackTrace: stackTrace,
      );
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getRecordDetail(Request request, String recordUuid) async {
    try {
      final id = recordUuid.trim();
      if (id.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid record ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final recordRows = _rows(
        await db.client
            .from('records')
            .select('*')
            .eq('record_uuid', id)
            .eq('is_deleted', false)
            .limit(1),
      );
      final recordRow = _first(recordRows);
      if (recordRow == null) {
        return Response.notFound(
          jsonEncode({'error': 'Record not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final eventRows = _rows(
        await db.client
            .from('events')
            .select('*')
            .eq('record_uuid', id)
            .eq('is_deleted', false),
      );
      eventRows.sort(
        (a, b) => _compareDateDesc(a['created_at'], b['created_at']),
      );

      final bookUuids = eventRows
          .map((row) => row['book_uuid']?.toString())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet();

      Map<String, dynamic> bookMap = {};
      if (bookUuids.isNotEmpty) {
        final books = _rows(
          await db.client
              .from('books')
              .select('book_uuid, name')
              .inFilter('book_uuid', bookUuids.toList()),
        );
        bookMap = _indexByStringKey(books, 'book_uuid');
      }

      final events = eventRows.map((event) {
        final bookUuid = event['book_uuid']?.toString();
        final book = bookUuid == null ? null : bookMap[bookUuid];
        return {
          ...event,
          'book_name': book?['name'],
          'name': recordRow['name'],
          'phone': recordRow['phone'],
          'record_number': recordRow['record_number'],
          'has_note': event['has_note'] == true,
        };
      }).toList();

      final noteRows = _rows(
        await db.client
            .from('notes')
            .select('*')
            .eq('record_uuid', id)
            .eq('is_deleted', false)
            .limit(1),
      );
      final noteRow = _first(noteRows);

      final record = _serializeRow(recordRow);
      record['eventCount'] = events.length;
      record['hasNote'] = noteRow != null;

      return Response.ok(
        jsonEncode({
          'record': record,
          'events': _serializeRows(events),
          'note': noteRow == null ? null : _serializeRow(noteRow),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to fetch record detail',
        error: e,
        stackTrace: stackTrace,
      );
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Map<String, dynamic>> _getFilteredEvents(
    String? bookUuid,
    String? name,
    String? recordNumber, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int offset = 0,
  }) async {
    final events = _rows(
      await db.client.from('events').select('*'),
    ).where((row) => row['is_deleted'] != true).toList();

    Map<String, dynamic> recordsMap = {};
    if (events.isNotEmpty) {
      final recordUuids = events
          .map((row) => row['record_uuid']?.toString())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet();
      if (recordUuids.isNotEmpty) {
        final records = _rows(
          await db.client
              .from('records')
              .select('record_uuid, name, phone, record_number')
              .inFilter('record_uuid', recordUuids.toList()),
        );
        recordsMap = _indexByStringKey(records, 'record_uuid');
      }
    }

    Map<String, dynamic> booksMap = {};
    if (events.isNotEmpty) {
      final bookUuids = events
          .map((row) => row['book_uuid']?.toString())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet();
      if (bookUuids.isNotEmpty) {
        final books = _rows(
          await db.client
              .from('books')
              .select('book_uuid, name')
              .inFilter('book_uuid', bookUuids.toList()),
        );
        booksMap = _indexByStringKey(books, 'book_uuid');
      }
    }

    final normalizedName = name?.trim().toLowerCase();
    final normalizedRecordNumber = recordNumber?.trim().toLowerCase();

    final filtered = events.where((event) {
      if (bookUuid != null && bookUuid.isNotEmpty) {
        if (event['book_uuid']?.toString() != bookUuid) return false;
      }

      final eventStart = _asUtc(event['start_time']);
      if (startDate != null && eventStart.isBefore(startDate.toUtc())) {
        return false;
      }
      if (endDate != null && !eventStart.isBefore(endDate.toUtc())) {
        return false;
      }

      final recordUuid = event['record_uuid']?.toString();
      final record = recordUuid == null ? null : recordsMap[recordUuid];

      if (normalizedName != null && normalizedName.isNotEmpty) {
        final recordName = (record?['name'] ?? '').toString().toLowerCase();
        if (!recordName.contains(normalizedName)) return false;
      }

      if (normalizedRecordNumber != null && normalizedRecordNumber.isNotEmpty) {
        final value = (record?['record_number'] ?? '').toString().toLowerCase();
        if (!value.contains(normalizedRecordNumber)) return false;
      }

      return true;
    }).toList();

    final sortByStart = startDate != null || endDate != null;
    filtered.sort((a, b) {
      if (sortByStart) {
        return _asUtc(a['start_time']).compareTo(_asUtc(b['start_time']));
      }
      return _compareDateDesc(a['created_at'], b['created_at']);
    });

    final total = filtered.length;
    final paged = _paginate(filtered, offset: offset, limit: limit);

    final enriched = paged.map((event) {
      final book = booksMap[event['book_uuid']?.toString() ?? ''];
      final record = recordsMap[event['record_uuid']?.toString() ?? ''];
      return {
        ...event,
        'book_name': book?['name'],
        'name': record?['name'],
        'phone': record?['phone'],
        'record_number': record?['record_number'],
        'has_note': event['has_note'] == true,
      };
    }).toList();

    return {
      'events': _serializeRows(enriched),
      'total': total,
      'limit': limit ?? enriched.length,
      'offset': limit != null ? offset : 0,
    };
  }

  Future<Response> _getEventDetail(Request request, String eventId) async {
    try {
      final id = eventId.trim();
      if (id.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid event ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final rows = _rows(
        await db.client
            .from('events')
            .select('*')
            .eq('id', id)
            .eq('is_deleted', false)
            .limit(1),
      );
      final event = _first(rows);
      if (event == null) {
        return Response.notFound(
          jsonEncode({'error': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      Map<String, dynamic>? book;
      final bookUuid = event['book_uuid']?.toString();
      if (bookUuid != null && bookUuid.isNotEmpty) {
        final bookRows = _rows(
          await db.client
              .from('books')
              .select('book_uuid, name')
              .eq('book_uuid', bookUuid)
              .limit(1),
        );
        book = _first(bookRows);
      }

      Map<String, dynamic>? record;
      final recordUuid = event['record_uuid']?.toString();
      if (recordUuid != null && recordUuid.isNotEmpty) {
        final recordRows = _rows(
          await db.client
              .from('records')
              .select('record_uuid, name, phone, record_number')
              .eq('record_uuid', recordUuid)
              .limit(1),
        );
        record = _first(recordRows);
      }

      return Response.ok(
        jsonEncode(
          _serializeRow({
            ...event,
            'book_name': book?['name'],
            'name': record?['name'],
            'phone': record?['phone'],
            'record_number': record?['record_number'],
            'has_note': event['has_note'] == true,
          }),
        ),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to fetch event detail',
        error: e,
        stackTrace: stackTrace,
      );
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getEventNote(Request request, String eventId) async {
    try {
      final id = eventId.trim();
      if (id.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid event ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final eventRows = _rows(
        await db.client
            .from('events')
            .select('record_uuid')
            .eq('id', id)
            .eq('is_deleted', false)
            .limit(1),
      );
      final event = _first(eventRows);
      final recordUuid = event?['record_uuid']?.toString();
      if (recordUuid == null || recordUuid.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Note not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final noteRows = _rows(
        await db.client
            .from('notes')
            .select('*')
            .eq('record_uuid', recordUuid)
            .eq('is_deleted', false)
            .limit(1),
      );
      final note = _first(noteRows);

      if (note == null) {
        return Response.notFound(
          jsonEncode({'error': 'Note not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(_serializeRow(note)),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to fetch event note',
        error: e,
        stackTrace: stackTrace,
      );
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getDevices(Request request) async {
    try {
      final stats = await _getDeviceStats();
      return Response.ok(
        jsonEncode(stats),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getBooks(Request request) async {
    try {
      final stats = await _getBookStats();
      return Response.ok(
        jsonEncode(stats),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getEvents(Request request) async {
    try {
      final params = request.url.queryParameters;
      final bookUuid = params['bookUuid'];
      final name = params['name'];
      final recordNumber = params['recordNumber'];
      final startDateStr = params['startDate'];
      final endDateStr = params['endDate'];
      final limit = _parseLimit(params);
      final offset = _parseOffset(params);

      DateTime? startDate;
      DateTime? endDate;
      if (startDateStr != null) {
        startDate = DateTime.tryParse(startDateStr);
      }
      if (endDateStr != null) {
        endDate = DateTime.tryParse(endDateStr);
      }

      final wantsList =
          params.containsKey('bookUuid') ||
          params.containsKey('name') ||
          params.containsKey('recordNumber') ||
          params.containsKey('startDate') ||
          params.containsKey('endDate') ||
          params.containsKey('list');

      if (wantsList) {
        final eventsResponse = await _getFilteredEvents(
          bookUuid,
          name,
          recordNumber,
          startDate: startDate,
          endDate: endDate,
          limit: limit,
          offset: offset,
        );
        return Response.ok(
          jsonEncode(eventsResponse),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final stats = await _getEventStats();
      return Response.ok(
        jsonEncode(stats),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getNotes(Request request) async {
    try {
      final stats = await _getNoteStats();
      return Response.ok(
        jsonEncode(stats),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getDrawings(Request request) async {
    try {
      final stats = await _getDrawingStats();
      return Response.ok(
        jsonEncode(stats),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getBackups(Request request) async {
    try {
      final stats = await _getBackupStats();
      return Response.ok(
        jsonEncode(stats),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getSyncLogs(Request request) async {
    try {
      final stats = await _getSyncStatsData();
      return Response.ok(
        jsonEncode(stats),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
