import '../database/connection.dart';

/// Result of drawing operation that may have version conflict
class DrawingOperationResult {
  final bool success;
  final Map<String, dynamic>? drawing;
  final bool hasConflict;
  final int? serverVersion;
  final Map<String, dynamic>? serverDrawing;

  const DrawingOperationResult({
    required this.success,
    this.drawing,
    this.hasConflict = false,
    this.serverVersion,
    this.serverDrawing,
  });

  DrawingOperationResult.success(Map<String, dynamic> drawing)
    : success = true,
      drawing = drawing,
      hasConflict = false,
      serverVersion = null,
      serverDrawing = null;

  DrawingOperationResult.conflict({
    required int serverVersion,
    required Map<String, dynamic> serverDrawing,
  }) : success = false,
       drawing = null,
       hasConflict = true,
       serverVersion = serverVersion,
       serverDrawing = serverDrawing;

  DrawingOperationResult.notFound()
    : success = false,
      drawing = null,
      hasConflict = false,
      serverVersion = null,
      serverDrawing = null;
}

class DrawingService {
  final DatabaseConnection db;

  DrawingService(this.db);

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

  (DateTime, DateTime) _dayRangeUtc(String date) {
    final parsed = DateTime.tryParse(date) ?? DateTime.now();
    final start = DateTime.utc(parsed.year, parsed.month, parsed.day);
    final end = start.add(const Duration(days: 1));
    return (start, end);
  }

  Future<bool> verifyDeviceAccess(String deviceId, String token) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final rows = await db.client
            .from('devices')
            .select('id, device_token, is_active')
            .eq('id', deviceId)
            .limit(1);
        final row = _first(rows);
        if (row == null) return false;
        final active = row['is_active'] == true;
        return active && (row['device_token'] ?? '').toString() == token;
      } catch (_) {
        if (attempt == 2) return false;
        await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
      }
    }
    return false;
  }

  Future<bool> verifyBookOwnership(String deviceId, String bookUuid) async {
    try {
      final existingBook = await db.client
          .from('books')
          .select('book_uuid, device_id')
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .limit(1);
      final bookRow = _first(existingBook);
      if (bookRow == null) {
        return false;
      }

      if (bookRow['device_id']?.toString() == deviceId) {
        return true;
      }

      final ownedRows = await db.client
          .from('books')
          .select('book_uuid')
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .eq('device_id', deviceId)
          .limit(1);
      if (_first(ownedRows) != null) return true;

      final accessRows = await db.client
          .from('book_device_access')
          .select('book_uuid')
          .eq('book_uuid', bookUuid)
          .eq('device_id', deviceId)
          .limit(1);
      if (_first(accessRows) != null) return true;

      await db.client.from('book_device_access').upsert({
        'book_uuid': bookUuid,
        'device_id': deviceId,
        'access_type': 'pulled',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'book_uuid,device_id');
      return true;
    } catch (e) {
      print('❌ Book ownership verification failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDrawing(
    String bookUuid,
    String date,
    int viewMode,
  ) async {
    final range = _dayRangeUtc(date);
    final rows = await db.client
        .from('schedule_drawings')
        .select(
          'id, book_uuid, date, view_mode, strokes_data, created_at, updated_at, version',
        )
        .eq('book_uuid', bookUuid)
        .eq('view_mode', viewMode)
        .eq('is_deleted', false)
        .gte('date', range.$1.toIso8601String())
        .lt('date', range.$2.toIso8601String())
        .limit(1);

    final row = _first(rows);
    if (row == null) return null;

    return {
      'id': row['id'],
      'bookUuid': row['book_uuid'],
      'date': _asUtc(row['date']).toIso8601String(),
      'viewMode': (row['view_mode'] as num?)?.toInt() ?? 0,
      'strokesData': row['strokes_data'],
      'createdAt': _asUtc(row['created_at']).toIso8601String(),
      'updatedAt': _asUtc(row['updated_at']).toIso8601String(),
      'version': (row['version'] as num?)?.toInt() ?? 1,
    };
  }

  Future<DrawingOperationResult> createOrUpdateDrawing({
    required String bookUuid,
    required String deviceId,
    required String date,
    required int viewMode,
    required String strokesData,
    int? expectedVersion,
  }) async {
    final _ = deviceId;
    final range = _dayRangeUtc(date);

    final allRows = await db.client
        .from('schedule_drawings')
        .select(
          'id, book_uuid, date, view_mode, strokes_data, created_at, updated_at, version, is_deleted',
        )
        .eq('book_uuid', bookUuid)
        .eq('view_mode', viewMode)
        .gte('date', range.$1.toIso8601String())
        .lt('date', range.$2.toIso8601String())
        .limit(1);

    final existing = _first(allRows);
    Map<String, dynamic> saved;

    if (existing == null) {
      final inserted = await db.client
          .from('schedule_drawings')
          .insert({
            'book_uuid': bookUuid,
            'date': range.$1.toIso8601String(),
            'view_mode': viewMode,
            'strokes_data': strokesData,
            'version': 1,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'is_deleted': false,
          })
          .select(
            'id, book_uuid, date, view_mode, strokes_data, created_at, updated_at, version',
          )
          .limit(1);
      final row = _first(inserted);
      if (row == null) return DrawingOperationResult.notFound();
      saved = row;
    } else {
      final isDeleted = existing['is_deleted'] == true;
      if (isDeleted) {
        return DrawingOperationResult.notFound();
      }

      final serverVersion = (existing['version'] as num?)?.toInt() ?? 1;
      if (expectedVersion != null && serverVersion != expectedVersion) {
        return DrawingOperationResult.conflict(
          serverVersion: serverVersion,
          serverDrawing: {
            'id': existing['id'],
            'bookUuid': existing['book_uuid'],
            'date': _asUtc(existing['date']).toIso8601String(),
            'viewMode': (existing['view_mode'] as num?)?.toInt() ?? 0,
            'strokesData': existing['strokes_data'],
            'createdAt': _asUtc(existing['created_at']).toIso8601String(),
            'updatedAt': _asUtc(existing['updated_at']).toIso8601String(),
            'version': serverVersion,
          },
        );
      }

      final updated = await db.client
          .from('schedule_drawings')
          .update({
            'strokes_data': strokesData,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'version': serverVersion + 1,
            'is_deleted': false,
          })
          .eq('id', existing['id'])
          .select(
            'id, book_uuid, date, view_mode, strokes_data, created_at, updated_at, version',
          )
          .limit(1);
      final row = _first(updated);
      if (row == null) return DrawingOperationResult.notFound();
      saved = row;
    }

    return DrawingOperationResult.success({
      'id': saved['id'],
      'bookUuid': saved['book_uuid'],
      'date': _asUtc(saved['date']).toIso8601String(),
      'viewMode': (saved['view_mode'] as num?)?.toInt() ?? 0,
      'strokesData': saved['strokes_data'],
      'createdAt': _asUtc(saved['created_at']).toIso8601String(),
      'updatedAt': _asUtc(saved['updated_at']).toIso8601String(),
      'version': (saved['version'] as num?)?.toInt() ?? 1,
    });
  }

  Future<bool> deleteDrawing(String bookUuid, String date, int viewMode) async {
    final range = _dayRangeUtc(date);
    final rows = await db.client
        .from('schedule_drawings')
        .select('id')
        .eq('book_uuid', bookUuid)
        .eq('view_mode', viewMode)
        .eq('is_deleted', false)
        .gte('date', range.$1.toIso8601String())
        .lt('date', range.$2.toIso8601String())
        .limit(1);

    final row = _first(rows);
    if (row == null) return false;

    await db.client
        .from('schedule_drawings')
        .update({
          'is_deleted': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'synced_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', row['id']);
    return true;
  }

  Future<List<Map<String, dynamic>>> batchGetDrawings({
    required String deviceId,
    required String bookUuid,
    required String startDate,
    required String endDate,
  }) async {
    final hasAccess = await verifyBookOwnership(deviceId, bookUuid);
    if (!hasAccess) return const [];

    final rows = await db.client
        .from('schedule_drawings')
        .select(
          'id, book_uuid, date, view_mode, strokes_data, created_at, updated_at, version',
        )
        .eq('book_uuid', bookUuid)
        .eq('is_deleted', false)
        .gte('date', DateTime.parse(startDate).toUtc().toIso8601String())
        .lte('date', DateTime.parse(endDate).toUtc().toIso8601String())
        .order('date', ascending: true);

    return _rows(rows)
        .map(
          (row) => {
            'id': row['id'],
            'bookUuid': row['book_uuid'],
            'date': _asUtc(row['date']).toIso8601String(),
            'viewMode': (row['view_mode'] as num?)?.toInt() ?? 0,
            'strokesData': row['strokes_data'],
            'createdAt': _asUtc(row['created_at']).toIso8601String(),
            'updatedAt': _asUtc(row['updated_at']).toIso8601String(),
            'version': (row['version'] as num?)?.toInt() ?? 1,
          },
        )
        .toList();
  }
}
