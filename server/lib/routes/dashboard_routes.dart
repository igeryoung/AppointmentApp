import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../utils/logger.dart';

/// Router for dashboard monitoring endpoints
/// Read-only endpoints for monitoring application data
class DashboardRoutes {
  final DatabaseConnection db;
  final String adminUsername;
  final String adminPassword;
  final Logger _logger = Logger('DashboardRoutes');

  DashboardRoutes(
    this.db, {
    String? adminUsername,
    String? adminPassword,
  })  : adminUsername = adminUsername ?? 'admin',
        adminPassword = adminPassword ?? 'admin123';

  Router get router {
    final router = Router();

    // Auth
    router.post('/auth/login', _login);

    // Dashboard stats - all require auth
    router.get('/stats', _authMiddleware(_getStats));
    router.get('/devices', _authMiddleware(_getDevices));
    router.get('/books', _authMiddleware(_getBooks));
    router.get('/events', _authMiddleware(_getEvents));
    router.get('/events/<eventId>', (Request request, String eventId) async {
      return _authMiddleware((Request req) => _getEventDetail(req, eventId))(request);
    });
    router.get('/events/<eventId>/note', (Request request, String eventId) async {
      return _authMiddleware((Request req) => _getEventNote(req, eventId))(request);
    });
    router.get('/notes', _authMiddleware(_getNotes));
    router.get('/drawings', _authMiddleware(_getDrawings));
    router.get('/backups', _authMiddleware(_getBackups));
    router.get('/sync-logs', _authMiddleware(_getSyncLogs));

    return router;
  }

  /// Simple admin login
  Future<Response> _login(Request request) async {
    try {
      print('🔐 Dashboard login attempt...');
      final body = await request.readAsString();
      print('   Request body: $body');

      if (body.isEmpty) {
        print('   ❌ Empty request body');
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Empty request body',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final json = jsonDecode(body) as Map<String, dynamic>;

      final username = json['username'] as String?;
      final password = json['password'] as String?;

      print('   Username: $username');
      print('   Expected: $adminUsername');

      if (username == adminUsername && password == adminPassword) {
        // In a real app, generate a JWT token
        final token = base64Encode(utf8.encode('$username:$password'));

        print('   ✅ Login successful');
        return Response.ok(
          jsonEncode({
            'success': true,
            'token': token,
            'message': 'Login successful',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      print('   ❌ Invalid credentials');
      return Response.forbidden(
        jsonEncode({
          'success': false,
          'message': 'Invalid credentials',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Dashboard login error: $e');
      print('   Stack trace: $stackTrace');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Login failed: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Auth middleware
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

      // In a real app, verify JWT token
      // For simplicity, we're just checking if the header exists
      return handler(request);
    };
  }

  /// Safely convert PostgreSQL count results to int
  /// PostgreSQL COUNT(*) returns bigint, which may be int or BigInt in Dart
  int _safeInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is BigInt) return value.toInt();
    // Fallback: try parsing as string
    return int.tryParse(value.toString()) ?? 0;
  }

  /// Convert database rows to JSON-serializable format
  /// Handles DateTime, UUID, and other PostgreSQL-specific types
  List<Map<String, dynamic>> _serializeRows(List<Map<String, dynamic>> rows) {
    return rows.map((row) => _serializeRow(row)).toList();
  }

  /// Convert a single database row to JSON-serializable format
  /// Also converts snake_case column names to camelCase for frontend compatibility
  Map<String, dynamic> _serializeRow(Map<String, dynamic> row) {
    final result = <String, dynamic>{};
    for (final entry in row.entries) {
      final camelKey = _snakeToCamel(entry.key);
      result[camelKey] = _serializeValue(entry.value);
    }
    return result;
  }

  /// Convert snake_case to camelCase
  String _snakeToCamel(String snakeCase) {
    final parts = snakeCase.split('_');
    if (parts.length == 1) return snakeCase;

    return parts[0] +
           parts.skip(1).map((part) =>
             part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1)
           ).join('');
  }

  /// Convert a value to JSON-serializable format
  dynamic _serializeValue(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _serializeValue(v)));
    }
    if (value is List) {
      return value.map(_serializeValue).toList();
    }
    // For primitive types and already serializable types
    return value;
  }

  /// Get overall dashboard statistics
  Future<Response> _getStats(Request request) async {
    try {
      final devices = await _getDeviceStats();
      final books = await _getBookStats();
      final events = await _getEventStats();
      final notes = await _getNoteStats();
      final drawings = await _getDrawingStats();
      final backups = await _getBackupStats();
      final sync = await _getSyncStatsData();

      final response = {
        'devices': devices,
        'books': books,
        'events': events,
        'notes': notes,
        'drawings': drawings,
        'backups': backups,
        'sync': sync,
      };

      return Response.ok(
        jsonEncode(response),
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
    try {
      final totalRow = await db.querySingle('SELECT COUNT(*) as count FROM devices');
      final activeRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM devices WHERE is_active = true',
      );

      final total = _safeInt(totalRow?['count']);
      final active = _safeInt(activeRow?['count']);

      final deviceRows = await db.queryRows(
        'SELECT id, device_name, platform, registered_at, last_sync_at, is_active '
        'FROM devices ORDER BY registered_at DESC LIMIT 100',
      );

      return {
        'total': total,
        'active': active,
        'inactive': total - active,
        'devices': _serializeRows(deviceRows),
      };
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch device stats', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getBookStats() async {
    try {
      final totalRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM books WHERE is_deleted = false',
      );
      final activeRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM books WHERE is_deleted = false AND archived_at IS NULL',
      );
      final archivedRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM books WHERE is_deleted = false AND archived_at IS NOT NULL',
      );

      final bookRows = await db.queryRows(
        '''
        SELECT
          b.id, b.device_id, b.name, b.created_at, b.updated_at, b.archived_at,
          COUNT(DISTINCT e.id) as event_count,
          COUNT(DISTINCT n.id) as note_count,
          COUNT(DISTINCT sd.id) as drawing_count
        FROM books b
        LEFT JOIN events e ON b.id = e.book_id AND e.is_deleted = false
        LEFT JOIN notes n ON e.id = n.event_id AND n.is_deleted = false
        LEFT JOIN schedule_drawings sd ON b.id = sd.book_id AND sd.is_deleted = false
        WHERE b.is_deleted = false
        GROUP BY b.id
        ORDER BY b.created_at DESC
        LIMIT 100
        ''',
      );

      return {
        'total': _safeInt(totalRow?['count']),
        'active': _safeInt(activeRow?['count']),
        'archived': _safeInt(archivedRow?['count']),
        'books': _serializeRows(bookRows),
      };
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch book stats', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getEventStats() async {
    try {
      final totalRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM events WHERE is_deleted = false',
      );
      final activeRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM events WHERE is_deleted = false AND is_removed = false',
      );
      final removedRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM events WHERE is_deleted = false AND is_removed = true',
      );

      final eventTypeRows = await db.queryRows(
        'SELECT event_type, COUNT(*) as count FROM events WHERE is_deleted = false GROUP BY event_type',
      );

      final byType = <String, int>{};
      for (final row in eventTypeRows) {
        final eventType = row['event_type']?.toString() ?? 'unknown';
        final count = _safeInt(row['count']);
        byType[eventType] = count;
      }

      final recentEvents = await db.queryRows(
        '''
        SELECT e.*, EXISTS(SELECT 1 FROM notes n WHERE n.event_id = e.id AND n.is_deleted = false) as has_note
        FROM events e
        WHERE e.is_deleted = false
        ORDER BY e.created_at DESC
        LIMIT 50
        ''',
      );

      return {
        'total': _safeInt(totalRow?['count']),
        'active': _safeInt(activeRow?['count']),
        'removed': _safeInt(removedRow?['count']),
        'byType': byType,
        'recent': _serializeRows(recentEvents),
      };
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch event stats', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getNoteStats() async {
    try {
      final totalRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM notes WHERE is_deleted = false',
      );

      final eventsWithNotesRow = await db.querySingle(
        '''
        SELECT COUNT(DISTINCT e.id) as count
        FROM events e
        INNER JOIN notes n ON e.id = n.event_id
        WHERE e.is_deleted = false AND n.is_deleted = false
        ''',
      );

      final totalEventsRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM events WHERE is_deleted = false',
      );

      final total = _safeInt(totalRow?['count']);
      final withNotes = _safeInt(eventsWithNotesRow?['count']);
      final totalEvents = _safeInt(totalEventsRow?['count']);

      final recentNotes = await db.queryRows(
        'SELECT * FROM notes WHERE is_deleted = false ORDER BY updated_at DESC LIMIT 50',
      );

      return {
        'total': total,
        'eventsWithNotes': withNotes,
        'eventsWithoutNotes': totalEvents - withNotes,
        'recentlyUpdated': _serializeRows(recentNotes),
      };
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch note stats', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getDrawingStats() async {
    try {
      final totalRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM schedule_drawings WHERE is_deleted = false',
      );

      final dayRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM schedule_drawings WHERE is_deleted = false AND view_mode = 0',
      );
      final threeDayRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM schedule_drawings WHERE is_deleted = false AND view_mode = 1',
      );
      final weekRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM schedule_drawings WHERE is_deleted = false AND view_mode = 2',
      );

      final recent = await db.queryRows(
        'SELECT * FROM schedule_drawings WHERE is_deleted = false ORDER BY updated_at DESC LIMIT 50',
      );

      return {
        'total': _safeInt(totalRow?['count']),
        'byViewMode': {
          'day': _safeInt(dayRow?['count']),
          'threeDay': _safeInt(threeDayRow?['count']),
          'week': _safeInt(weekRow?['count']),
        },
        'recent': _serializeRows(recent),
      };
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch drawing stats', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getBackupStats() async {
    try {
      final totalRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM book_backups WHERE is_deleted = false',
      );

      final sizeRow = await db.querySingle(
        'SELECT SUM(backup_size) as total_size FROM book_backups WHERE is_deleted = false',
      );

      final totalSize = _safeInt(sizeRow?['total_size']);
      final totalSizeMB = (totalSize / (1024 * 1024)).toStringAsFixed(2);

      final recent = await db.queryRows(
        '''
        SELECT bb.*, b.name as book_name
        FROM book_backups bb
        LEFT JOIN books b ON bb.book_id = b.id
        WHERE bb.is_deleted = false
        ORDER BY bb.created_at DESC
        LIMIT 50
        ''',
      );

      final restoredRow = await db.querySingle(
        'SELECT COUNT(*) as count FROM book_backups WHERE is_deleted = false AND restored_at IS NOT NULL',
      );

      return {
        'total': _safeInt(totalRow?['count']),
        'totalSizeBytes': totalSize,
        'totalSizeMB': totalSizeMB,
        'recentBackups': _serializeRows(recent),
        'restoredCount': _safeInt(restoredRow?['count']),
      };
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch backup stats', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getSyncStatsData() async {
    try {
      final totalRow = await db.querySingle('SELECT COUNT(*) as count FROM sync_log');
      final successRow = await db.querySingle(
        "SELECT COUNT(*) as count FROM sync_log WHERE status = 'success'",
      );
      final failedRow = await db.querySingle(
        "SELECT COUNT(*) as count FROM sync_log WHERE status = 'failed'",
      );
      final conflictRow = await db.querySingle(
        "SELECT COUNT(*) as count FROM sync_log WHERE status = 'conflict'",
      );

      final total = _safeInt(totalRow?['count']);
      final successful = _safeInt(successRow?['count']);

      final recent = await db.queryRows(
        '''
        SELECT sl.*, d.device_name
        FROM sync_log sl
        LEFT JOIN devices d ON sl.device_id = d.id
        ORDER BY sl.synced_at DESC
        LIMIT 100
        ''',
      );

      return {
        'totalOperations': total,
        'successfulSyncs': successful,
        'failedSyncs': _safeInt(failedRow?['count']),
        'conflictCount': _safeInt(conflictRow?['count']),
        'successRate': total > 0 ? (successful / total) * 100 : 0.0,
        'recentSyncs': _serializeRows(recent),
      };
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch sync stats', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get filtered list of events with optional book, name, and record number filters
  /// Returns all events sorted by created_at DESC (newest first)
  Future<List<Map<String, dynamic>>> _getFilteredEvents(
    int? bookId,
    String? name,
    String? recordNumber,
  ) async {
    try {
      final conditions = <String>['e.is_deleted = false'];
      final params = <String, dynamic>{};

      if (bookId != null) {
        conditions.add('e.book_id = @bookId');
        params['bookId'] = bookId;
      }

      if (name != null && name.isNotEmpty) {
        conditions.add('LOWER(e.name) LIKE @name');
        params['name'] = '%${name.toLowerCase()}%';
      }

      if (recordNumber != null && recordNumber.isNotEmpty) {
        conditions.add('LOWER(e.record_number) LIKE @recordNumber');
        params['recordNumber'] = '%${recordNumber.toLowerCase()}%';
      }

      final whereClause = conditions.join(' AND ');

      final query = '''
        SELECT
          e.*,
          b.name as book_name,
          EXISTS(SELECT 1 FROM notes n WHERE n.event_id = e.id AND n.is_deleted = false) as has_note
        FROM events e
        LEFT JOIN books b ON e.book_id = b.id
        WHERE $whereClause
        ORDER BY e.created_at DESC
      ''';

      final rows = await db.queryRows(query, parameters: params);
      return _serializeRows(rows);
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch filtered events', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get single event detail by ID
  Future<Response> _getEventDetail(Request request, String eventId) async {
    try {
      final id = int.tryParse(eventId);
      if (id == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid event ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final row = await db.querySingle(
        '''
        SELECT
          e.*,
          b.name as book_name,
          EXISTS(SELECT 1 FROM notes n WHERE n.event_id = e.id AND n.is_deleted = false) as has_note
        FROM events e
        LEFT JOIN books b ON e.book_id = b.id
        WHERE e.id = @id AND e.is_deleted = false
        ''',
        parameters: {'id': id},
      );

      if (row == null) {
        return Response.notFound(
          jsonEncode({'error': 'Event not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(_serializeRow(row)),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch event detail', error: e, stackTrace: stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Get note for a specific event
  Future<Response> _getEventNote(Request request, String eventId) async {
    try {
      final id = int.tryParse(eventId);
      if (id == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid event ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final row = await db.querySingle(
        '''
        SELECT
          n.*
        FROM notes n
        WHERE n.event_id = @eventId AND n.is_deleted = false
        ''',
        parameters: {'eventId': id},
      );

      if (row == null) {
        return Response.notFound(
          jsonEncode({'error': 'Note not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(_serializeRow(row)),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch event note', error: e, stackTrace: stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // Delegate methods for individual endpoints
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
      // Get query parameters for filtering
      final params = request.url.queryParameters;
      final bookId = params['bookId'] != null ? int.tryParse(params['bookId']!) : null;
      final name = params['name'];
      final recordNumber = params['recordNumber'];

      // Check if this is a request for the events list (not stats)
      final wantsList = params.containsKey('bookId') ||
                        params.containsKey('name') ||
                        params.containsKey('recordNumber') ||
                        params.containsKey('list');

      // If requesting list or any filters are provided, return filtered list
      if (wantsList) {
        final events = await _getFilteredEvents(bookId, name, recordNumber);
        return Response.ok(
          jsonEncode({'events': events}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Otherwise return stats (backward compatibility)
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
