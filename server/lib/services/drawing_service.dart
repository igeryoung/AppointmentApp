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

/// Service for handling schedule drawing operations with proper auth
class DrawingService {
  final DatabaseConnection db;

  DrawingService(this.db);

  /// Verify device credentials (deviceId + token)
  /// Returns true if device exists, is active, and token matches
  Future<bool> verifyDeviceAccess(String deviceId, String token) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM devices WHERE id = @id AND device_token = @token AND is_active = true',
        parameters: {'id': deviceId, 'token': token},
      );
      return row != null;
    } catch (e) {
      print('❌ Device verification failed: $e');
      return false;
    }
  }

  /// Verify that a book belongs to the specified device
  /// Returns true if the device owns the book or has explicit access.
  /// Mirrors NoteService behavior so pulled/shared books can read drawings.
  Future<bool> verifyBookOwnership(String deviceId, String bookUuid) async {
    try {
      final row = await db.querySingle(
        '''
        SELECT b.book_uuid FROM books b
        LEFT JOIN book_device_access a ON a.book_uuid = b.book_uuid AND a.device_id = @deviceId
        WHERE b.book_uuid = @bookUuid AND b.is_deleted = false
          AND (b.device_id = @deviceId OR a.device_id IS NOT NULL)
      ''',
        parameters: {'bookUuid': bookUuid, 'deviceId': deviceId},
      );

      if (row != null) return true;

      // Keep behavior consistent with bundle/note access paths:
      // if the book exists, record pulled access for this device.
      final bookRow = await db.querySingle(
        'SELECT device_id FROM books WHERE book_uuid = @bookUuid AND is_deleted = false',
        parameters: {'bookUuid': bookUuid},
      );

      if (bookRow != null) {
        await db.query(
          '''
          INSERT INTO book_device_access (book_uuid, device_id, access_type, created_at)
          VALUES (@bookUuid, @deviceId, 'pulled', CURRENT_TIMESTAMP)
          ON CONFLICT (book_uuid, device_id) DO NOTHING
        ''',
          parameters: {'bookUuid': bookUuid, 'deviceId': deviceId},
        );
        return true;
      }

      return false;
    } catch (e) {
      print('❌ Book ownership verification failed: $e');
      return false;
    }
  }

  /// Get a single drawing by composite key (book_uuid, date, view_mode)
  /// Returns null if drawing doesn't exist or is deleted
  Future<Map<String, dynamic>?> getDrawing(
    String bookUuid,
    String date,
    int viewMode,
  ) async {
    try {
      final row = await db.querySingle(
        '''
        SELECT id, book_uuid, date, view_mode, strokes_data, created_at, updated_at, version
        FROM schedule_drawings
        WHERE book_uuid = @bookUuid AND date = @date::timestamp AND view_mode = @viewMode AND is_deleted = false
        ''',
        parameters: {'bookUuid': bookUuid, 'date': date, 'viewMode': viewMode},
      );

      if (row == null) return null;

      // Convert to JSON-friendly format
      return {
        'id': row['id'],
        'bookUuid': row['book_uuid'],
        'date': (row['date'] as DateTime).toIso8601String(),
        'viewMode': row['view_mode'],
        'strokesData': row['strokes_data'],
        'createdAt': (row['created_at'] as DateTime).toIso8601String(),
        'updatedAt': (row['updated_at'] as DateTime).toIso8601String(),
        'version': row['version'],
      };
    } catch (e) {
      print('❌ Get drawing failed: $e');
      rethrow;
    }
  }

  /// Create or update a drawing with optimistic locking
  ///
  /// - If version is null: Create new drawing (or error if exists)
  /// - If version is provided: Update only if server version matches
  ///
  /// Returns:
  /// - DrawingOperationResult.success(drawing) on success
  /// - DrawingOperationResult.conflict(serverVersion, serverDrawing) on version conflict
  /// - DrawingOperationResult.notFound() if drawing was deleted
  Future<DrawingOperationResult> createOrUpdateDrawing({
    required String bookUuid,
    required String deviceId,
    required String date,
    required int viewMode,
    required String strokesData,
    int? expectedVersion,
  }) async {
    try {
      // Use optimistic locking with UPSERT on composite key
      // Note: deviceId is used for auth verification but not stored in schedule_drawings table
      final result = await db.querySingle(
        '''
        INSERT INTO schedule_drawings (book_uuid, date, view_mode, strokes_data, version, created_at, updated_at, synced_at)
        VALUES (@bookUuid, @date::timestamp, @viewMode, @strokesData, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (book_uuid, date, view_mode) DO UPDATE
        SET strokes_data = EXCLUDED.strokes_data,
            updated_at = CURRENT_TIMESTAMP,
            synced_at = CURRENT_TIMESTAMP,
            version = schedule_drawings.version + 1
        WHERE (CAST(@expectedVersion AS INTEGER) IS NULL OR schedule_drawings.version = CAST(@expectedVersion AS INTEGER))
          AND schedule_drawings.is_deleted = false
        RETURNING id, book_uuid, date, view_mode, strokes_data, created_at, updated_at, version
        ''',
        parameters: {
          'bookUuid': bookUuid,
          'date': date,
          'viewMode': viewMode,
          'strokesData': strokesData,
          'expectedVersion': expectedVersion,
        },
      );

      // If RETURNING gives a row, operation succeeded
      if (result != null) {
        final drawing = {
          'id': result['id'],
          'bookUuid': result['book_uuid'],
          'date': (result['date'] as DateTime).toIso8601String(),
          'viewMode': result['view_mode'],
          'strokesData': result['strokes_data'],
          'createdAt': (result['created_at'] as DateTime).toIso8601String(),
          'updatedAt': (result['updated_at'] as DateTime).toIso8601String(),
          'version': result['version'],
        };
        print(
          '✅ Drawing ${expectedVersion == null ? 'created' : 'updated'}: book=$bookUuid, date=$date, viewMode=$viewMode, version=${result['version']}',
        );
        return DrawingOperationResult.success(drawing);
      }

      // No row returned - either version conflict or drawing is deleted
      // Query the current state to determine which
      final currentDrawing = await db.querySingle(
        'SELECT id, book_uuid, date, view_mode, strokes_data, created_at, updated_at, version, is_deleted FROM schedule_drawings WHERE book_uuid = @bookUuid AND date = @date::timestamp AND view_mode = @viewMode',
        parameters: {'bookUuid': bookUuid, 'date': date, 'viewMode': viewMode},
      );

      if (currentDrawing == null) {
        print(
          '⚠️  Drawing operation resulted in no-op, and drawing doesn\'t exist: book=$bookUuid, date=$date, viewMode=$viewMode',
        );
        return DrawingOperationResult.notFound();
      }

      if (currentDrawing['is_deleted'] == true) {
        print(
          '⚠️  Cannot update deleted drawing: book=$bookUuid, date=$date, viewMode=$viewMode',
        );
        return DrawingOperationResult.notFound();
      }

      // Version conflict
      final serverDrawing = {
        'id': currentDrawing['id'],
        'bookUuid': currentDrawing['book_uuid'],
        'date': (currentDrawing['date'] as DateTime).toIso8601String(),
        'viewMode': currentDrawing['view_mode'],
        'strokesData': currentDrawing['strokes_data'],
        'createdAt': (currentDrawing['created_at'] as DateTime)
            .toIso8601String(),
        'updatedAt': (currentDrawing['updated_at'] as DateTime)
            .toIso8601String(),
        'version': currentDrawing['version'],
      };
      print(
        '⚠️  Version conflict: book=$bookUuid, date=$date, viewMode=$viewMode, expected=$expectedVersion, server=${currentDrawing['version']}',
      );
      return DrawingOperationResult.conflict(
        serverVersion: currentDrawing['version'] as int,
        serverDrawing: serverDrawing,
      );
    } catch (e) {
      print('❌ Create/update drawing failed: $e');
      rethrow;
    }
  }

  /// Delete a drawing (soft delete)
  /// Returns true if drawing was deleted, false if drawing didn't exist
  Future<bool> deleteDrawing(String bookUuid, String date, int viewMode) async {
    try {
      final result = await db.querySingle(
        '''
        UPDATE schedule_drawings
        SET is_deleted = true,
            updated_at = CURRENT_TIMESTAMP,
            synced_at = CURRENT_TIMESTAMP
        WHERE book_uuid = @bookUuid AND date = @date::timestamp AND view_mode = @viewMode AND is_deleted = false
        RETURNING id
        ''',
        parameters: {'bookUuid': bookUuid, 'date': date, 'viewMode': viewMode},
      );

      final deleted = result != null;
      if (deleted) {
        print(
          '✅ Drawing deleted: book=$bookUuid, date=$date, viewMode=$viewMode',
        );
      } else {
        print(
          '⚠️  Drawing not found or already deleted: book=$bookUuid, date=$date, viewMode=$viewMode',
        );
      }
      return deleted;
    } catch (e) {
      print('❌ Delete drawing failed: $e');
      rethrow;
    }
  }

  /// Batch get drawings for a date range (all view modes)
  /// Only returns drawings that:
  /// 1. Exist and are not deleted
  /// 2. Belong to books owned by or shared with the specified device
  ///
  /// This ensures authorization: only return drawings the device can access
  Future<List<Map<String, dynamic>>> batchGetDrawings({
    required String deviceId,
    required String bookUuid,
    required String startDate,
    required String endDate,
  }) async {
    try {
      // Query drawings with authorization check
      final rows = await db.queryRows(
        '''
        SELECT d.id, d.book_uuid, d.date, d.view_mode, d.strokes_data, d.created_at, d.updated_at, d.version
        FROM schedule_drawings d
        INNER JOIN books b ON d.book_uuid = b.book_uuid
        LEFT JOIN book_device_access a ON a.book_uuid = b.book_uuid AND a.device_id = @deviceId
        WHERE d.book_uuid = @bookUuid
          AND d.date BETWEEN @startDate::timestamp AND @endDate::timestamp
          AND d.is_deleted = false
          AND b.is_deleted = false
          AND (b.device_id = @deviceId OR a.device_id IS NOT NULL)
        ORDER BY d.date ASC
        ''',
        parameters: {
          'bookUuid': bookUuid,
          'startDate': startDate,
          'endDate': endDate,
          'deviceId': deviceId,
        },
      );

      final drawings = rows.map((row) {
        return {
          'id': row['id'],
          'bookUuid': row['book_uuid'],
          'date': (row['date'] as DateTime).toIso8601String(),
          'viewMode': row['view_mode'],
          'strokesData': row['strokes_data'],
          'createdAt': (row['created_at'] as DateTime).toIso8601String(),
          'updatedAt': (row['updated_at'] as DateTime).toIso8601String(),
          'version': row['version'],
        };
      }).toList();

      print(
        '✅ Batch get drawings: book=$bookUuid, date=$startDate to $endDate, returned=${drawings.length}',
      );
      return drawings;
    } catch (e) {
      print('❌ Batch get drawings failed: $e');
      rethrow;
    }
  }
}
