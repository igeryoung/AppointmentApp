import '../database/connection.dart';

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

  Future<NoteOperationResult> createOrUpdateNoteForRecord({
    required String recordUuid,
    required String pagesData,
    int? expectedVersion,
  }) async {
    try {
      final result = await db.querySingle('''
        INSERT INTO notes (record_uuid, pages_data, version, created_at, updated_at, synced_at)
        VALUES (@recordUuid, @pagesData, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (record_uuid) DO UPDATE
        SET pages_data = EXCLUDED.pages_data,
            updated_at = CURRENT_TIMESTAMP,
            synced_at = CURRENT_TIMESTAMP,
            version = notes.version + 1
        WHERE (CAST(@expectedVersion AS INTEGER) IS NULL OR notes.version = CAST(@expectedVersion AS INTEGER))
          AND notes.is_deleted = false
        RETURNING id, record_uuid, pages_data, created_at, updated_at, version
      ''', parameters: {
        'recordUuid': recordUuid,
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

        final hasContent = pagesData != '[[]]' && pagesData != '[]' && pagesData.trim().isNotEmpty;
        await db.query(
          'UPDATE events SET has_note = @hasNote WHERE record_uuid = @recordUuid',
          parameters: {'hasNote': hasContent, 'recordUuid': recordUuid},
        );

        return NoteOperationResult.success(note);
      }

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

  Future<List<Map<String, dynamic>>> batchGetNotesByRecordUuids({
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
      ''', parameters: {'recordUuids': recordUuids});

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

  /// Save note with event - handles record creation if needed
  /// Pipeline:
  /// 1. If record_number exists → use existing record_uuid
  /// 2. If record_number doesn't exist → create new record
  /// 3. If record_number is empty → create new record with empty record_number
  /// 4. Create/update event with the record_uuid
  /// 5. Create/update note with the record_uuid
  Future<SaveNoteWithEventResult> saveNoteWithEvent({
    required String bookUuid,
    required String recordNumber,
    required String name,
    required String phone,
    required String pagesData,
    int? noteVersion,
    required Map<String, dynamic> eventData,
  }) async {
    try {
      // Step 1: Ensure record exists or create new one
      final recordResult = await _ensureRecordExists(
        recordNumber: recordNumber,
        name: name,
        phone: phone,
      );
      final recordUuid = recordResult['record_uuid'] as String;
      final recordCreated = recordResult['created'] as bool;

      // Step 2: Create or update event
      final eventResult = await _createOrUpdateEvent(
        bookUuid: bookUuid,
        recordUuid: recordUuid,
        recordNumber: recordNumber,
        eventData: eventData,
      );

      // Step 3: Create or update note
      final noteResult = await createOrUpdateNoteForRecord(
        recordUuid: recordUuid,
        pagesData: pagesData,
        expectedVersion: noteVersion != null ? noteVersion - 1 : null,
      );

      if (noteResult.hasConflict) {
        return SaveNoteWithEventResult.conflict(
          serverVersion: noteResult.serverVersion!,
          serverNote: noteResult.serverNote!,
        );
      }

      return SaveNoteWithEventResult.success(
        record: {
          'record_uuid': recordUuid,
          'record_number': recordNumber,
          'name': name,
          'phone': phone,
          'created': recordCreated,
        },
        event: eventResult,
        note: noteResult.note!,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Ensure record exists by record_number, or create new one
  Future<Map<String, dynamic>> _ensureRecordExists({
    required String recordNumber,
    required String name,
    required String phone,
  }) async {
    // If record_number is non-empty, try to find existing record
    if (recordNumber.isNotEmpty) {
      final existing = await db.querySingle('''
        SELECT record_uuid, record_number, name, phone
        FROM records
        WHERE record_number = @recordNumber AND is_deleted = false
      ''', parameters: {'recordNumber': recordNumber});

      if (existing != null) {
        // Update name/phone if provided
        if (name.isNotEmpty || phone.isNotEmpty) {
          await db.query('''
            UPDATE records
            SET name = COALESCE(NULLIF(@name, ''), name),
                phone = COALESCE(NULLIF(@phone, ''), phone),
                updated_at = CURRENT_TIMESTAMP
            WHERE record_uuid = @recordUuid
          ''', parameters: {
            'recordUuid': existing['record_uuid'],
            'name': name,
            'phone': phone,
          });
        }
        return {
          'record_uuid': existing['record_uuid'],
          'created': false,
        };
      }
    }

    // Create new record (either record_number not found, or empty record_number)
    final newRecord = await db.querySingle('''
      INSERT INTO records (record_number, name, phone, created_at, updated_at, version)
      VALUES (@recordNumber, @name, @phone, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
      RETURNING record_uuid
    ''', parameters: {
      'recordNumber': recordNumber,
      'name': name,
      'phone': phone,
    });

    return {
      'record_uuid': newRecord!['record_uuid'],
      'created': true,
    };
  }

  /// Create or update event with the given record_uuid
  Future<Map<String, dynamic>> _createOrUpdateEvent({
    required String bookUuid,
    required String recordUuid,
    required String recordNumber,
    required Map<String, dynamic> eventData,
  }) async {
    final eventId = eventData['id'] as String;
    final title = eventData['title'] as String? ?? '';
    final eventTypes = eventData['event_types'] as String? ?? '[]';
    final startTime = eventData['start_time'];
    final endTime = eventData['end_time'];
    final hasChargeItems = eventData['has_charge_items'] == true;
    final isChecked = eventData['is_checked'] == true;

    // Convert timestamps
    DateTime? startDateTime;
    DateTime? endDateTime;
    if (startTime != null) {
      startDateTime = startTime is int
          ? DateTime.fromMillisecondsSinceEpoch(startTime * 1000)
          : DateTime.tryParse(startTime.toString());
    }
    if (endTime != null) {
      endDateTime = endTime is int
          ? DateTime.fromMillisecondsSinceEpoch(endTime * 1000)
          : DateTime.tryParse(endTime.toString());
    }

    // Try to update existing event first
    final updated = await db.querySingle('''
      UPDATE events
      SET record_uuid = @recordUuid,
          record_number = @recordNumber,
          title = @title,
          event_types = @eventTypes,
          start_time = @startTime,
          end_time = @endTime,
          has_charge_items = @hasChargeItems,
          is_checked = @isChecked,
          updated_at = CURRENT_TIMESTAMP,
          version = version + 1
      WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false
      RETURNING id, record_uuid, version
    ''', parameters: {
      'eventId': eventId,
      'bookUuid': bookUuid,
      'recordUuid': recordUuid,
      'recordNumber': recordNumber,
      'title': title,
      'eventTypes': eventTypes,
      'startTime': startDateTime,
      'endTime': endDateTime,
      'hasChargeItems': hasChargeItems,
      'isChecked': isChecked,
    });

    if (updated != null) {
      return {
        'id': updated['id'],
        'record_uuid': updated['record_uuid'],
        'version': updated['version'],
        'created': false,
      };
    }

    // Create new event
    final created = await db.querySingle('''
      INSERT INTO events (
        id, book_uuid, record_uuid, record_number, title, event_types,
        start_time, end_time, has_charge_items, is_checked,
        created_at, updated_at, version
      ) VALUES (
        @eventId, @bookUuid, @recordUuid, @recordNumber, @title, @eventTypes,
        @startTime, @endTime, @hasChargeItems, @isChecked,
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1
      )
      RETURNING id, record_uuid, version
    ''', parameters: {
      'eventId': eventId,
      'bookUuid': bookUuid,
      'recordUuid': recordUuid,
      'recordNumber': recordNumber,
      'title': title,
      'eventTypes': eventTypes,
      'startTime': startDateTime,
      'endTime': endDateTime,
      'hasChargeItems': hasChargeItems,
      'isChecked': isChecked,
    });

    return {
      'id': created!['id'],
      'record_uuid': created['record_uuid'],
      'version': created['version'],
      'created': true,
    };
  }
}

/// Result class for saveNoteWithEvent operation
class SaveNoteWithEventResult {
  final bool success;
  final Map<String, dynamic>? record;
  final Map<String, dynamic>? event;
  final Map<String, dynamic>? note;
  final bool hasConflict;
  final int? serverVersion;
  final Map<String, dynamic>? serverNote;

  const SaveNoteWithEventResult({
    required this.success,
    this.record,
    this.event,
    this.note,
    this.hasConflict = false,
    this.serverVersion,
    this.serverNote,
  });

  SaveNoteWithEventResult.success({
    required Map<String, dynamic> record,
    required Map<String, dynamic> event,
    required Map<String, dynamic> note,
  })  : success = true,
        record = record,
        event = event,
        note = note,
        hasConflict = false,
        serverVersion = null,
        serverNote = null;

  SaveNoteWithEventResult.conflict({
    required int serverVersion,
    required Map<String, dynamic> serverNote,
  })  : success = false,
        record = null,
        event = null,
        note = null,
        hasConflict = true,
        serverVersion = serverVersion,
        serverNote = serverNote;
}
