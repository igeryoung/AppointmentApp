import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';

/// Router for dashboard monitoring endpoints
/// Read-only endpoints for monitoring application data
class DashboardRoutes {
  final DatabaseConnection db;
  final String adminUsername;
  final String adminPassword;

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
    router.get('/notes', _authMiddleware(_getNotes));
    router.get('/drawings', _authMiddleware(_getDrawings));
    router.get('/backups', _authMiddleware(_getBackups));
    router.get('/sync-logs', _authMiddleware(_getSyncLogs));

    return router;
  }

  /// Simple admin login
  Future<Response> _login(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final username = json['username'] as String?;
      final password = json['password'] as String?;

      if (username == adminUsername && password == adminPassword) {
        // In a real app, generate a JWT token
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
        jsonEncode({
          'success': false,
          'message': 'Invalid credentials',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
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
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': 'Failed to fetch stats: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Map<String, dynamic>> _getDeviceStats() async {
    final totalRow = await db.querySingle('SELECT COUNT(*) as count FROM devices');
    final activeRow = await db.querySingle(
      'SELECT COUNT(*) as count FROM devices WHERE is_active = true',
    );

    final total = totalRow?['count'] as int? ?? 0;
    final active = activeRow?['count'] as int? ?? 0;

    final deviceRows = await db.query(
      'SELECT id, device_name, platform, registered_at, last_sync_at, is_active '
      'FROM devices ORDER BY registered_at DESC LIMIT 100',
    );

    return {
      'total': total,
      'active': active,
      'inactive': total - active,
      'devices': deviceRows,
    };
  }

  Future<Map<String, dynamic>> _getBookStats() async {
    final totalRow = await db.querySingle(
      'SELECT COUNT(*) as count FROM books WHERE is_deleted = false',
    );
    final activeRow = await db.querySingle(
      'SELECT COUNT(*) as count FROM books WHERE is_deleted = false AND archived_at IS NULL',
    );
    final archivedRow = await db.querySingle(
      'SELECT COUNT(*) as count FROM books WHERE is_deleted = false AND archived_at IS NOT NULL',
    );

    final bookRows = await db.query(
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
      'total': totalRow?['count'] as int? ?? 0,
      'active': activeRow?['count'] as int? ?? 0,
      'archived': archivedRow?['count'] as int? ?? 0,
      'books': bookRows,
    };
  }

  Future<Map<String, dynamic>> _getEventStats() async {
    final totalRow = await db.querySingle(
      'SELECT COUNT(*) as count FROM events WHERE is_deleted = false',
    );
    final activeRow = await db.querySingle(
      'SELECT COUNT(*) as count FROM events WHERE is_deleted = false AND is_removed = false',
    );
    final removedRow = await db.querySingle(
      'SELECT COUNT(*) as count FROM events WHERE is_deleted = false AND is_removed = true',
    );

    final eventTypeRows = await db.query(
      'SELECT event_type, COUNT(*) as count FROM events WHERE is_deleted = false GROUP BY event_type',
    );

    final byType = <String, int>{};
    for (final row in eventTypeRows) {
      final eventType = row['event_type']?.toString() ?? 'unknown';
      final count = (row['count'] is int)
          ? row['count'] as int
          : int.tryParse(row['count']?.toString() ?? '0') ?? 0;
      byType[eventType] = count;
    }

    final recentEvents = await db.query(
      '''
      SELECT e.*, EXISTS(SELECT 1 FROM notes n WHERE n.event_id = e.id AND n.is_deleted = false) as has_note
      FROM events e
      WHERE e.is_deleted = false
      ORDER BY e.created_at DESC
      LIMIT 50
      ''',
    );

    return {
      'total': totalRow?['count'] as int? ?? 0,
      'active': activeRow?['count'] as int? ?? 0,
      'removed': removedRow?['count'] as int? ?? 0,
      'byType': byType,
      'recent': recentEvents,
    };
  }

  Future<Map<String, dynamic>> _getNoteStats() async {
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

    final total = totalRow?['count'] as int? ?? 0;
    final withNotes = eventsWithNotesRow?['count'] as int? ?? 0;
    final totalEvents = totalEventsRow?['count'] as int? ?? 0;

    final recentNotes = await db.query(
      'SELECT * FROM notes WHERE is_deleted = false ORDER BY updated_at DESC LIMIT 50',
    );

    return {
      'total': total,
      'eventsWithNotes': withNotes,
      'eventsWithoutNotes': totalEvents - withNotes,
      'recentlyUpdated': recentNotes,
    };
  }

  Future<Map<String, dynamic>> _getDrawingStats() async {
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

    final recent = await db.query(
      'SELECT * FROM schedule_drawings WHERE is_deleted = false ORDER BY updated_at DESC LIMIT 50',
    );

    return {
      'total': totalRow?['count'] as int? ?? 0,
      'byViewMode': {
        'day': dayRow?['count'] as int? ?? 0,
        'threeDay': threeDayRow?['count'] as int? ?? 0,
        'week': weekRow?['count'] as int? ?? 0,
      },
      'recent': recent,
    };
  }

  Future<Map<String, dynamic>> _getBackupStats() async {
    final totalRow = await db.querySingle(
      'SELECT COUNT(*) as count FROM book_backups WHERE is_deleted = false',
    );

    final sizeRow = await db.querySingle(
      'SELECT SUM(backup_size) as total_size FROM book_backups WHERE is_deleted = false',
    );

    final totalSize = sizeRow?['total_size'] as int? ?? 0;
    final totalSizeMB = (totalSize / (1024 * 1024)).toStringAsFixed(2);

    final recent = await db.query(
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
      'total': totalRow?['count'] as int? ?? 0,
      'totalSizeBytes': totalSize,
      'totalSizeMB': totalSizeMB,
      'recentBackups': recent,
      'restoredCount': restoredRow?['count'] as int? ?? 0,
    };
  }

  Future<Map<String, dynamic>> _getSyncStatsData() async {
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

    final total = totalRow?['count'] as int? ?? 0;
    final successful = successRow?['count'] as int? ?? 0;

    final recent = await db.query(
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
      'failedSyncs': failedRow?['count'] as int? ?? 0,
      'conflictCount': conflictRow?['count'] as int? ?? 0,
      'successRate': total > 0 ? (successful / total) * 100 : 0.0,
      'recentSyncs': recent,
    };
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
