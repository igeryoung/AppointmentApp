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
  })  : success = false,
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
  /// Returns true if book exists and is owned by the device
  Future<bool> verifyBookOwnership(String deviceId, int bookId) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM books WHERE id = @bookId AND device_id = @deviceId AND is_deleted = false',
        parameters: {'bookId': bookId, 'deviceId': deviceId},
      );
      return row != null;
    } catch (e) {
      print('❌ Book ownership verification failed: $e');
      return false;
    }
  }

  /// Get a single drawing by composite key (book_id, date, view_mode)
  /// Returns null if drawing doesn't exist or is deleted
  Future<Map<String, dynamic>?> getDrawing(
    int bookId,
    String date,
    int viewMode,
  ) async {
    try {
      final row = await db.querySingle(
        '''
        SELECT id, book_id, date, view_mode, strokes_data, created_at, updated_at, version
        FROM schedule_drawings
        WHERE book_id = @bookId AND date = @date::timestamp AND view_mode = @viewMode AND is_deleted = false
        ''',
        parameters: {
          'bookId': bookId,
          'date': date,
          'viewMode': viewMode,
        },
      );

      if (row == null) return null;

      // Convert to JSON-friendly format
      return {
        'id': row['id'],
        'bookId': row['book_id'],
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
    required int bookId,
    required String deviceId,
    required String date,
    required int viewMode,
    required String strokesData,
    int? expectedVersion,
  }) async {
    try {
      // Use optimistic locking with UPSERT on composite key
      final result = await db.querySingle(
        '''
        INSERT INTO schedule_drawings (book_id, device_id, date, view_mode, strokes_data, version, created_at, updated_at, synced_at)
        VALUES (@bookId, @deviceId, @date::timestamp, @viewMode, @strokesData, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (book_id, date, view_mode) DO UPDATE
        SET strokes_data = EXCLUDED.strokes_data,
            updated_at = CURRENT_TIMESTAMP,
            synced_at = CURRENT_TIMESTAMP,
            version = schedule_drawings.version + 1,
            device_id = EXCLUDED.device_id
        WHERE (CAST(@expectedVersion AS INTEGER) IS NULL OR schedule_drawings.version = CAST(@expectedVersion AS INTEGER))
          AND schedule_drawings.is_deleted = false
        RETURNING id, book_id, date, view_mode, strokes_data, created_at, updated_at, version
        ''',
        parameters: {
          'bookId': bookId,
          'deviceId': deviceId,
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
          'bookId': result['book_id'],
          'date': (result['date'] as DateTime).toIso8601String(),
          'viewMode': result['view_mode'],
          'strokesData': result['strokes_data'],
          'createdAt': (result['created_at'] as DateTime).toIso8601String(),
          'updatedAt': (result['updated_at'] as DateTime).toIso8601String(),
          'version': result['version'],
        };
        print('✅ Drawing ${expectedVersion == null ? 'created' : 'updated'}: book=$bookId, date=$date, viewMode=$viewMode, version=${result['version']}');
        return DrawingOperationResult.success(drawing);
      }

      // No row returned - either version conflict or drawing is deleted
      // Query the current state to determine which
      final currentDrawing = await db.querySingle(
        'SELECT id, book_id, date, view_mode, strokes_data, created_at, updated_at, version, is_deleted FROM schedule_drawings WHERE book_id = @bookId AND date = @date::timestamp AND view_mode = @viewMode',
        parameters: {
          'bookId': bookId,
          'date': date,
          'viewMode': viewMode,
        },
      );

      if (currentDrawing == null) {
        print('⚠️  Drawing operation resulted in no-op, and drawing doesn\'t exist: book=$bookId, date=$date, viewMode=$viewMode');
        return DrawingOperationResult.notFound();
      }

      if (currentDrawing['is_deleted'] == true) {
        print('⚠️  Cannot update deleted drawing: book=$bookId, date=$date, viewMode=$viewMode');
        return DrawingOperationResult.notFound();
      }

      // Version conflict
      final serverDrawing = {
        'id': currentDrawing['id'],
        'bookId': currentDrawing['book_id'],
        'date': (currentDrawing['date'] as DateTime).toIso8601String(),
        'viewMode': currentDrawing['view_mode'],
        'strokesData': currentDrawing['strokes_data'],
        'createdAt': (currentDrawing['created_at'] as DateTime).toIso8601String(),
        'updatedAt': (currentDrawing['updated_at'] as DateTime).toIso8601String(),
        'version': currentDrawing['version'],
      };
      print('⚠️  Version conflict: book=$bookId, date=$date, viewMode=$viewMode, expected=$expectedVersion, server=${currentDrawing['version']}');
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
  Future<bool> deleteDrawing(int bookId, String date, int viewMode) async {
    try {
      final result = await db.querySingle(
        '''
        UPDATE schedule_drawings
        SET is_deleted = true,
            updated_at = CURRENT_TIMESTAMP,
            synced_at = CURRENT_TIMESTAMP
        WHERE book_id = @bookId AND date = @date::timestamp AND view_mode = @viewMode AND is_deleted = false
        RETURNING id
        ''',
        parameters: {
          'bookId': bookId,
          'date': date,
          'viewMode': viewMode,
        },
      );

      final deleted = result != null;
      if (deleted) {
        print('✅ Drawing deleted: book=$bookId, date=$date, viewMode=$viewMode');
      } else {
        print('⚠️  Drawing not found or already deleted: book=$bookId, date=$date, viewMode=$viewMode');
      }
      return deleted;
    } catch (e) {
      print('❌ Delete drawing failed: $e');
      rethrow;
    }
  }

  /// Batch get drawings for a date range and view mode
  /// Only returns drawings that:
  /// 1. Exist and are not deleted
  /// 2. Belong to books owned by the specified device
  ///
  /// This ensures authorization: only return drawings the device can access
  Future<List<Map<String, dynamic>>> batchGetDrawings({
    required String deviceId,
    required int bookId,
    required String startDate,
    required String endDate,
    required int viewMode,
  }) async {
    try {
      // Query drawings with authorization check
      final rows = await db.queryRows(
        '''
        SELECT d.id, d.book_id, d.date, d.view_mode, d.strokes_data, d.created_at, d.updated_at, d.version
        FROM schedule_drawings d
        INNER JOIN books b ON d.book_id = b.id
        WHERE d.book_id = @bookId
          AND d.date BETWEEN @startDate::timestamp AND @endDate::timestamp
          AND d.view_mode = @viewMode
          AND d.is_deleted = false
          AND b.is_deleted = false
          AND b.device_id = @deviceId
        ORDER BY d.date ASC
        ''',
        parameters: {
          'bookId': bookId,
          'startDate': startDate,
          'endDate': endDate,
          'viewMode': viewMode,
          'deviceId': deviceId,
        },
      );

      final drawings = rows.map((row) {
        return {
          'id': row['id'],
          'bookId': row['book_id'],
          'date': (row['date'] as DateTime).toIso8601String(),
          'viewMode': row['view_mode'],
          'strokesData': row['strokes_data'],
          'createdAt': (row['created_at'] as DateTime).toIso8601String(),
          'updatedAt': (row['updated_at'] as DateTime).toIso8601String(),
          'version': row['version'],
        };
      }).toList();

      print('✅ Batch get drawings: book=$bookId, date=$startDate to $endDate, viewMode=$viewMode, returned=${drawings.length}');
      return drawings;
    } catch (e) {
      print('❌ Batch get drawings failed: $e');
      rethrow;
    }
  }
}
