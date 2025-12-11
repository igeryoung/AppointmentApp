import '../database/connection.dart';

/// Result of note operation that may have version conflict
class NoteOperationResult {
  final bool success;
  final Map<String, dynamic>? note;
  final bool hasConflict;
  final int? serverVersion;
  final Map<String, dynamic>? serverNote;

  const NoteOperationResult({
    required this.success,
    this.note,
    this.hasConflict = false,
    this.serverVersion,
    this.serverNote,
  });

  NoteOperationResult.success(Map<String, dynamic> note)
      : success = true,
        note = note,
        hasConflict = false,
        serverVersion = null,
        serverNote = null;

  NoteOperationResult.conflict({required int serverVersion, required Map<String, dynamic> serverNote})
      : success = false,
        note = null,
        hasConflict = true,
        serverVersion = serverVersion,
        serverNote = serverNote;

  NoteOperationResult.notFound()
      : success = false,
        note = null,
        hasConflict = false,
        serverVersion = null,
        serverNote = null;
}

/// Service for handling note operations (record-based architecture)
class NoteService {
  final DatabaseConnection db;

  NoteService(this.db);

  Future<bool> verifyDeviceAccess(String deviceId, String token) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM devices WHERE id = @id AND device_token = @token AND is_active = true',
        parameters: {'id': deviceId, 'token': token},
      );
      return row != null;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyBookOwnership(String deviceId, String bookUuid) async {
    try {
      final row = await db.querySingle('''
        SELECT b.book_uuid FROM books b
        LEFT JOIN book_device_access a ON a.book_uuid = b.book_uuid AND a.device_id = @deviceId
        WHERE b.book_uuid = @bookUuid AND b.is_deleted = false
          AND (b.device_id = @deviceId OR a.device_id IS NOT NULL)
      ''', parameters: {'bookUuid': bookUuid, 'deviceId': deviceId});

      if (row != null) return true;

      // Grant access on-demand if book exists
      final bookRow = await db.querySingle(
        'SELECT device_id FROM books WHERE book_uuid = @bookUuid AND is_deleted = false',
        parameters: {'bookUuid': bookUuid},
      );

      if (bookRow != null) {
        await db.query('''
          INSERT INTO book_device_access (book_uuid, device_id, access_type, created_at)
          VALUES (@bookUuid, @deviceId, 'pulled', CURRENT_TIMESTAMP)
          ON CONFLICT (book_uuid, device_id) DO NOTHING
        ''', parameters: {'bookUuid': bookUuid, 'deviceId': deviceId});
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyEventInBook(String eventId, String bookUuid) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM events WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false',
        parameters: {'eventId': eventId, 'bookUuid': bookUuid},
      );
      return row != null;
    } catch (e) {
      return false;
    }
  }

  /// Get note by record_uuid
  Future<Map<String, dynamic>?> getNoteByRecordUuid(String recordUuid) async {
    try {
      final row = await db.querySingle('''
        SELECT id, record_uuid, pages_data, created_at, updated_at, version
        FROM notes WHERE record_uuid = @recordUuid AND is_deleted = false
      ''', parameters: {'recordUuid': recordUuid});

      if (row == null) return null;

      return {
        'id': row['id'],
        'record_uuid': row['record_uuid'],
        'pages_data': row['pages_data'],
        'created_at': (row['created_at'] as DateTime).toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toIso8601String(),
        'version': row['version'],
      };
    } catch (e) {
      rethrow;
    }
  }

  /// Create or update note for a record
  Future<NoteOperationResult> createOrUpdateNoteForRecord({
    required String recordUuid,
    required String deviceId,
    required String pagesData,
    int? expectedVersion,
  }) async {
    try {
      final result = await db.querySingle('''
        INSERT INTO notes (record_uuid, device_id, pages_data, version, created_at, updated_at, synced_at)
        VALUES (@recordUuid, @deviceId, @pagesData, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (record_uuid) DO UPDATE
        SET pages_data = EXCLUDED.pages_data,
            updated_at = CURRENT_TIMESTAMP,
            synced_at = CURRENT_TIMESTAMP,
            version = notes.version + 1,
            device_id = EXCLUDED.device_id
        WHERE (CAST(@expectedVersion AS INTEGER) IS NULL OR notes.version = CAST(@expectedVersion AS INTEGER))
          AND notes.is_deleted = false
        RETURNING id, record_uuid, pages_data, created_at, updated_at, version
      ''', parameters: {
        'recordUuid': recordUuid,
        'deviceId': deviceId,
        'pagesData': pagesData,
        'expectedVersion': expectedVersion,
      });

      if (result != null) {
        final note = {
          'id': result['id'],
          'record_uuid': result['record_uuid'],
          'pages_data': result['pages_data'],
          'created_at': (result['created_at'] as DateTime).toIso8601String(),
          'updated_at': (result['updated_at'] as DateTime).toIso8601String(),
          'version': result['version'],
        };

        // Update has_note flag on all events for this record
        final hasContent = pagesData != '[[]]' && pagesData != '[]' && pagesData.trim().isNotEmpty;
        await db.query(
          'UPDATE events SET has_note = @hasNote WHERE record_uuid = @recordUuid',
          parameters: {'hasNote': hasContent, 'recordUuid': recordUuid},
        );

        return NoteOperationResult.success(note);
      }

      // Check for conflict
      final currentNote = await db.querySingle(
        'SELECT id, record_uuid, pages_data, created_at, updated_at, version, is_deleted FROM notes WHERE record_uuid = @recordUuid',
        parameters: {'recordUuid': recordUuid},
      );

      if (currentNote == null || currentNote['is_deleted'] == true) {
        return NoteOperationResult.notFound();
      }

      final serverNote = {
        'id': currentNote['id'],
        'record_uuid': currentNote['record_uuid'],
        'pages_data': currentNote['pages_data'],
        'created_at': (currentNote['created_at'] as DateTime).toIso8601String(),
        'updated_at': (currentNote['updated_at'] as DateTime).toIso8601String(),
        'version': currentNote['version'],
      };

      return NoteOperationResult.conflict(
        serverVersion: currentNote['version'] as int,
        serverNote: serverNote,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Delete note by record_uuid
  Future<bool> deleteNoteByRecordUuid(String recordUuid) async {
    try {
      final result = await db.querySingle('''
        UPDATE notes SET is_deleted = true, updated_at = CURRENT_TIMESTAMP, synced_at = CURRENT_TIMESTAMP
        WHERE record_uuid = @recordUuid AND is_deleted = false
        RETURNING id
      ''', parameters: {'recordUuid': recordUuid});

      if (result != null) {
        await db.query(
          'UPDATE events SET has_note = false WHERE record_uuid = @recordUuid',
          parameters: {'recordUuid': recordUuid},
        );
      }

      return result != null;
    } catch (e) {
      rethrow;
    }
  }

  /// Batch get notes by record UUIDs
  Future<List<Map<String, dynamic>>> batchGetNotesByRecordUuids({
    required String deviceId,
    required List<String> recordUuids,
  }) async {
    if (recordUuids.isEmpty) return [];

    try {
      final rows = await db.queryRows('''
        SELECT n.id, n.record_uuid, n.pages_data, n.created_at, n.updated_at, n.version
        FROM notes n
        INNER JOIN records r ON n.record_uuid = r.record_uuid
        WHERE n.record_uuid = ANY(@recordUuids)
          AND n.is_deleted = false
          AND r.is_deleted = false
        ORDER BY n.record_uuid
      ''', parameters: {'recordUuids': recordUuids, 'deviceId': deviceId});

      return rows.map((row) => {
        'id': row['id'],
        'record_uuid': row['record_uuid'],
        'pages_data': row['pages_data'],
        'created_at': (row['created_at'] as DateTime).toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toIso8601String(),
        'version': row['version'],
      }).toList();
    } catch (e) {
      rethrow;
    }
  }
}
