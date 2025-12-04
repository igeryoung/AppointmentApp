import 'dart:convert';

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

  NoteOperationResult.conflict({
    required int serverVersion,
    required Map<String, dynamic> serverNote,
  })  : success = false,
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

/// Service for handling note operations with proper auth and optimistic locking
class NoteService {
  final DatabaseConnection db;

  NoteService(this.db);

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
  /// bookUuid: UUID string of the book
  Future<bool> verifyBookOwnership(String deviceId, String bookUuid) async {
    try {
      // Allow access if the device owns the book OR has an entry in book_device_access
      final row = await db.querySingle(
        '''
        SELECT b.book_uuid
        FROM books b
        LEFT JOIN book_device_access a
          ON a.book_uuid = b.book_uuid AND a.device_id = @deviceId
        WHERE b.book_uuid = @bookUuid
          AND b.is_deleted = false
          AND (b.device_id = @deviceId OR a.device_id IS NOT NULL)
        ''',
        parameters: {'bookUuid': bookUuid, 'deviceId': deviceId},
      );

      if (row != null) {
        return true;
      }

      // Extra diagnostics to understand why access failed
      final bookRow = await db.querySingle(
        'SELECT device_id, is_deleted FROM books WHERE book_uuid = @bookUuid',
        parameters: {'bookUuid': bookUuid},
      );
      final accessRow = await db.querySingle(
        'SELECT access_type FROM book_device_access WHERE book_uuid = @bookUuid AND device_id = @deviceId',
        parameters: {'bookUuid': bookUuid, 'deviceId': deviceId},
      );

      if (bookRow == null) {
        print('⚠️  Book not found: bookUuid=$bookUuid');
        return false;
      }

      if (bookRow['is_deleted'] == true) {
        print('⚠️  Book is deleted: bookUuid=$bookUuid, ownerDeviceId=${bookRow['device_id']}');
        return false;
      }

      if (accessRow != null) {
        print('⚠️  Book access exists but verification failed: bookUuid=$bookUuid, deviceId=$deviceId, ownerDeviceId=${bookRow['device_id']}, accessType=${accessRow['access_type']}');
        return false;
      }

      // The book exists and is active but this device is not yet recorded as having access.
      // If the device knows the book UUID (e.g., after pulling), grant access lazily.
      try {
        await db.query(
          '''
          INSERT INTO book_device_access (book_uuid, device_id, access_type, created_at)
          VALUES (@bookUuid, @deviceId, 'pulled', CURRENT_TIMESTAMP)
          ON CONFLICT (book_uuid, device_id) DO NOTHING
          ''',
          parameters: {'bookUuid': bookUuid, 'deviceId': deviceId},
        );
        print('🔓 Granted book access on-demand: bookUuid=$bookUuid, deviceId=$deviceId, ownerDeviceId=${bookRow['device_id']}');
        return true;
      } catch (grantError) {
        print('⚠️  Failed to grant book access on-demand: $grantError');
      }

      print('⚠️  Book ownership mismatch: bookUuid=$bookUuid, expected deviceId=$deviceId, actual deviceId=${bookRow['device_id']}, is_deleted=${bookRow['is_deleted']}');
      return false;
    } catch (e) {
      print('❌ Book ownership verification failed: $e');
      return false;
    }
  }

  /// Verify that an event belongs to the specified book
  /// Returns true if event exists and belongs to the book
  /// bookUuid: UUID string of the book
  Future<bool> verifyEventInBook(String eventId, String bookUuid) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM events WHERE id = @eventId AND book_uuid = @bookUuid AND is_deleted = false',
        parameters: {'eventId': eventId, 'bookUuid': bookUuid},
      );

      if (row == null) {
        print('⚠️  Event not found in book: eventId=$eventId, bookUuid=$bookUuid');
      }

      return row != null;
    } catch (e) {
      print('❌ Event-book relationship verification failed: $e');
      return false;
    }
  }

  /// Get a single note by event ID
  /// Returns null if note doesn't exist or is deleted
  Future<Map<String, dynamic>?> getNote(String eventId) async {
    try {
      final row = await db.querySingle(
        '''
        SELECT id, event_id, pages_data, created_at, updated_at, version
        FROM notes
        WHERE event_id = @eventId AND is_deleted = false
        ''',
        parameters: {'eventId': eventId},
      );

      if (row == null) return null;

      // Convert to JSON-friendly format
      return {
        'id': row['id'],
        'eventId': row['event_id'],
        'pagesData': row['pages_data'],
        'createdAt': (row['created_at'] as DateTime).toIso8601String(),
        'updatedAt': (row['updated_at'] as DateTime).toIso8601String(),
        'version': row['version'],
      };
    } catch (e) {
      print('❌ Get note failed: $e');
      rethrow;
    }
  }

  /// Create or update a note with optimistic locking
  ///
  /// - If version is null: Create new note (or error if exists)
  /// - If version is provided: Update only if server version matches
  ///
  /// Returns:
  /// - NoteOperationResult.success(note) on success
  /// - NoteOperationResult.conflict(serverVersion, serverNote) on version conflict
  /// - NoteOperationResult.notFound() if note was deleted
  Future<NoteOperationResult> createOrUpdateNote({
    required String eventId,
    required String deviceId,
    String? pagesData,
    String? strokesData,
    int? expectedVersion,
  }) async {
    try {
      // Prefer pagesData (new format), fallback to strokesData (legacy)
      // If strokesData provided but not pagesData, migrate to pagesData format: [strokes] -> [[strokes]]
      final String finalPagesData;
      if (pagesData != null) {
        finalPagesData = pagesData;
      } else if (strokesData != null) {
        // Wrap single-page strokes in array for migration
        finalPagesData = '[$strokesData]';
      } else {
        // Start with empty page
        finalPagesData = '[[]]';
      }

      // Use optimistic locking with UPSERT
      // The WHERE clause in ON CONFLICT ensures version check
      final result = await db.querySingle(
        '''
        INSERT INTO notes (event_id, device_id, pages_data, version, created_at, updated_at, synced_at)
        VALUES (@eventId, @deviceId, @pagesData, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (event_id) DO UPDATE
        SET pages_data = EXCLUDED.pages_data,
            updated_at = CURRENT_TIMESTAMP,
            synced_at = CURRENT_TIMESTAMP,
            version = notes.version + 1,
            device_id = EXCLUDED.device_id
        WHERE (CAST(@expectedVersion AS INTEGER) IS NULL OR notes.version = CAST(@expectedVersion AS INTEGER))
          AND notes.is_deleted = false
        RETURNING id, event_id, pages_data, created_at, updated_at, version
        ''',
        parameters: {
          'eventId': eventId,
          'deviceId': deviceId,
          'pagesData': finalPagesData,
          'expectedVersion': expectedVersion,
        },
      );

      // If RETURNING gives a row, operation succeeded
      if (result != null) {
        final note = {
          'id': result['id'],
          'eventId': result['event_id'],
          'pagesData': result['pages_data'],
          'createdAt': (result['created_at'] as DateTime).toIso8601String(),
          'updatedAt': (result['updated_at'] as DateTime).toIso8601String(),
          'version': result['version'],
        };

        // Update hasNote field on events table
        // Check if note has any content (not empty or just "[[]]")
        final hasContent = finalPagesData != '[[]]' &&
                          finalPagesData != '[]' &&
                          finalPagesData.trim().isNotEmpty;

        await db.query(
          'UPDATE events SET has_note = @hasNote WHERE id = @eventId',
          parameters: {
            'hasNote': hasContent,
            'eventId': eventId,
          },
        );

        print('✅ Note ${expectedVersion == null ? 'created' : 'updated'}: event=$eventId, version=${result['version']}, hasNote=$hasContent');
        return NoteOperationResult.success(note);
      }

      // No row returned - either version conflict or note is deleted
      // Query the current state to determine which
      final currentNote = await db.querySingle(
        'SELECT id, event_id, pages_data, created_at, updated_at, version, is_deleted FROM notes WHERE event_id = @eventId',
        parameters: {'eventId': eventId},
      );

      if (currentNote == null) {
        // Should never happen, but treat as not found
        print('⚠️  Note operation resulted in no-op, and note doesn\'t exist: event=$eventId');
        return NoteOperationResult.notFound();
      }

      if (currentNote['is_deleted'] == true) {
        print('⚠️  Cannot update deleted note: event=$eventId');
        return NoteOperationResult.notFound();
      }

      // Version conflict
      final serverNote = {
        'id': currentNote['id'],
        'eventId': currentNote['event_id'],
        'pagesData': currentNote['pages_data'],
        'createdAt': (currentNote['created_at'] as DateTime).toIso8601String(),
        'updatedAt': (currentNote['updated_at'] as DateTime).toIso8601String(),
        'version': currentNote['version'],
      };
      print('⚠️  Version conflict: event=$eventId, expected=$expectedVersion, server=${currentNote['version']}');
      return NoteOperationResult.conflict(
        serverVersion: currentNote['version'] as int,
        serverNote: serverNote,
      );
    } catch (e) {
      print('❌ Create/update note failed: $e');
      rethrow;
    }
  }

  /// Delete a note (soft delete)
  /// Returns true if note was deleted, false if note didn't exist
  Future<bool> deleteNote(String eventId) async {
    try {
      final result = await db.querySingle(
        '''
        UPDATE notes
        SET is_deleted = true,
            updated_at = CURRENT_TIMESTAMP,
            synced_at = CURRENT_TIMESTAMP
        WHERE event_id = @eventId AND is_deleted = false
        RETURNING id
        ''',
        parameters: {'eventId': eventId},
      );

      final deleted = result != null;
      if (deleted) {
        // Update hasNote field on events table
        await db.query(
          'UPDATE events SET has_note = false WHERE id = @eventId',
          parameters: {'eventId': eventId},
        );
        print('✅ Note deleted: event=$eventId, hasNote set to false');
      } else {
        print('⚠️  Note not found or already deleted: event=$eventId');
      }
      return deleted;
    } catch (e) {
      print('❌ Delete note failed: $e');
      rethrow;
    }
  }

  /// Batch get notes for multiple event IDs
  /// Only returns notes that:
  /// 1. Exist and are not deleted
  /// 2. Belong to events in books owned by the specified device
  ///
  /// This ensures authorization: only return notes the device can access
  Future<List<Map<String, dynamic>>> batchGetNotes({
    required String deviceId,
    required List<int> eventIds,
  }) async {
    if (eventIds.isEmpty) {
      return [];
    }

    try {
      // Query notes with authorization check in a single query
      // Join through events -> books to verify ownership
      final rows = await db.queryRows(
        '''
        SELECT n.id, n.event_id, n.pages_data, n.created_at, n.updated_at, n.version
        FROM notes n
        INNER JOIN events e ON n.event_id = e.id
        INNER JOIN books b ON e.book_id = b.id
        WHERE n.event_id = ANY(@eventIds)
          AND n.is_deleted = false
          AND e.is_deleted = false
          AND b.is_deleted = false
          AND b.device_id = @deviceId
        ORDER BY n.event_id
        ''',
        parameters: {
          'eventIds': eventIds,
          'deviceId': deviceId,
        },
      );

      final notes = rows.map((row) {
        return {
          'id': row['id'],
          'eventId': row['event_id'],
          'pagesData': row['pages_data'],
          'createdAt': (row['created_at'] as DateTime).toIso8601String(),
          'updatedAt': (row['updated_at'] as DateTime).toIso8601String(),
          'version': row['version'],
        };
      }).toList();

      print('✅ Batch get notes: requested=${eventIds.length}, returned=${notes.length}');
      return notes;
    } catch (e) {
      print('❌ Batch get notes failed: $e');
      rethrow;
    }
  }

  /// Create event if it doesn't exist on the server
  /// This handles the case where the client created an event locally but hasn't synced it yet
  ///
  /// Parameters:
  /// - eventData: Map containing event fields from client (id, book_id, name, etc.)
  /// - deviceId: UUID of the device creating the event
  Future<void> createEventIfMissing({
    required Map<String, dynamic> eventData,
    required String deviceId,
  }) async {
    try {
      final eventId = eventData['id'] as String?;
      if (eventId == null || eventId.isEmpty) {
        throw ArgumentError('Event data must include id (UUID)');
      }

      // Check if event already exists
      final existing = await db.querySingle(
      'SELECT id, book_uuid FROM events WHERE id = @id',
        parameters: {'id': eventId},
      );

      if (existing != null) {
        final existingBookUuid = existing['book_uuid'] as String;
        final newBookUuid = eventData['book_uuid'] as String?;

        // If book_uuid differs, update it (can happen during initial sync)
        if (newBookUuid != null && existingBookUuid != newBookUuid) {
          print('🔄 Event exists with different book_uuid, updating: id=$eventId, old=$existingBookUuid, new=$newBookUuid');
          await db.query(
            'UPDATE events SET book_uuid = @newBookUuid WHERE id = @id',
            parameters: {
              'id': eventId,
              'newBookUuid': newBookUuid,
            },
          );
          print('✅ Updated event book_uuid: id=$eventId');
        } else {
          print('ℹ️  Event already exists with correct book_uuid: id=$eventId');
        }
        return;
      }

      // Parse timestamps (client sends Unix seconds)
      final startTime = _parseTimestamp(eventData['start_time']);
      if (startTime == null) {
        throw ArgumentError('Event data must include start_time');
      }

      final endTime = _parseTimestamp(eventData['end_time']);
      final createdAt = _parseTimestamp(eventData['created_at']) ?? DateTime.now();
      final updatedAt = _parseTimestamp(eventData['updated_at']) ?? DateTime.now();

      final eventTypes = _parseEventTypes(eventData);
      final eventTypesJson = jsonEncode(eventTypes);
      final primaryEventType = eventTypes.first;

      // Insert event with client-provided ID
      await db.query(
        '''
        INSERT INTO events (
          id, book_uuid, device_id, name, record_number, phone, event_type, event_types,
          has_charge_items, start_time, end_time, created_at, updated_at,
          is_removed, removal_reason, original_event_id, new_event_id,
          synced_at, version, is_deleted
        ) VALUES (
          @id, @bookUuid, @deviceId, @name, @recordNumber, @phone, @eventType, @eventTypes,
          @hasChargeItems, @startTime, @endTime, @createdAt, @updatedAt,
          @isRemoved, @removalReason, @originalEventId, @newEventId,
          CURRENT_TIMESTAMP, 1, false
        )
        ''',
        parameters: {
          'id': eventId,
          'bookUuid': eventData['book_uuid'],
          'deviceId': deviceId,
          'name': eventData['name'] ?? '',
          'recordNumber': eventData['record_number'],
          'phone': _normalizePhone(eventData['phone']),
          'eventType': primaryEventType,
          'eventTypes': eventTypesJson,
          'hasChargeItems': eventData['has_charge_items'] == 1 || eventData['has_charge_items'] == true,
          'startTime': startTime,
          'endTime': endTime,
          'createdAt': createdAt,
          'updatedAt': updatedAt,
          'isRemoved': eventData['is_removed'] == 1 || eventData['is_removed'] == true,
          'removalReason': eventData['removal_reason'],
          'originalEventId': eventData['original_event_id'],
          'newEventId': eventData['new_event_id'],
        },
      );

      print('✅ Event auto-created: id=$eventId, book=${eventData['book_id']}, name="${eventData['name']}"');
    } catch (e) {
      print('❌ Create event failed: $e');
      rethrow;
    }
  }

  /// Update event metadata when eventData is provided during note sync
  Future<void> updateEventMetadata({
    required Map<String, dynamic> eventData,
    required String bookUuid,
  }) async {
    final eventId = eventData['id'] as String?;
    if (eventId == null || eventId.isEmpty) {
      throw ArgumentError('Event data must include id (UUID)');
    }

    final resolvedBookUuid = (eventData['book_uuid'] as String?) ?? bookUuid;
    final startTime = _parseTimestamp(eventData['start_time']);
    if (startTime == null) {
      throw ArgumentError('Event data must include start_time');
    }

    final endTime = _parseTimestamp(eventData['end_time']);
    final updatedAt = _parseTimestamp(eventData['updated_at']) ?? DateTime.now();
    final eventTypes = _parseEventTypes(eventData);
    final primaryEventType = eventTypes.isNotEmpty ? eventTypes.first : 'other';
    final eventTypesJson = jsonEncode(eventTypes);

    final parameters = {
      'id': eventId,
      'bookUuid': resolvedBookUuid,
      'name': eventData['name']?.toString().trim() ?? '',
      'recordNumber': _normalizeNullableString(eventData['record_number']),
      'phone': _normalizePhone(eventData['phone']),
      'eventType': primaryEventType,
      'eventTypes': eventTypesJson,
      'hasChargeItems': _toBool(eventData['has_charge_items']),
      'startTime': startTime,
      'endTime': endTime,
      'updatedAt': updatedAt,
      'isRemoved': _toBool(eventData['is_removed']),
      'removalReason': _normalizeNullableString(eventData['removal_reason']),
      'originalEventId': _normalizeNullableString(eventData['original_event_id']),
      'newEventId': _normalizeNullableString(eventData['new_event_id']),
      'isChecked': _toBool(eventData['is_checked']),
      'version': _toInt(eventData['version']) ?? 1,
    };

    await db.query(
      '''
      UPDATE events
      SET
        name = @name,
        record_number = @recordNumber,
        phone = @phone,
        event_type = @eventType,
        event_types = @eventTypes,
        has_charge_items = @hasChargeItems,
        start_time = @startTime,
        end_time = @endTime,
        updated_at = @updatedAt,
        is_removed = @isRemoved,
        removal_reason = @removalReason,
        original_event_id = @originalEventId,
        new_event_id = @newEventId,
        is_checked = @isChecked,
        version = @version,
        synced_at = CURRENT_TIMESTAMP,
        is_deleted = false
      WHERE id = @id AND book_uuid = @bookUuid
      ''',
      parameters: parameters,
    );

    print('✅ Event metadata updated via note sync: id=$eventId');
  }

  List<String> _parseEventTypes(Map<String, dynamic> eventData) {
    final parsed = _decodeEventTypes(eventData['event_types']);
    if (parsed.isNotEmpty) {
      return parsed;
    }

    final legacyValue = eventData['event_type'];
    if (legacyValue != null) {
      final legacyType = legacyValue.toString().trim();
      if (legacyType.isNotEmpty) {
        return [legacyType];
      }
    }

    return const ['other'];
  }

  List<String> _decodeEventTypes(dynamic rawValue) {
    if (rawValue == null) return const [];

    try {
      List<dynamic> rawList;
      if (rawValue is List) {
        rawList = rawValue;
      } else if (rawValue is String) {
        final trimmed = rawValue.trim();
        if (trimmed.isEmpty) return const [];
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          rawList = decoded;
        } else {
          rawList = [decoded];
        }
      } else {
        rawList = [rawValue];
      }

      final cleaned = rawList
          .map((value) => value == null ? null : value.toString().trim())
          .where((value) => value != null && value!.isNotEmpty)
          .map((value) => value!)
          .toList();

      cleaned.sort((a, b) => a.compareTo(b));
      return cleaned;
    } catch (e) {
      print('⚠️  Failed to decode event_types payload: $e');
      return const [];
    }
  }

  String? _normalizePhone(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizeNullableString(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    if (value is String && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null) return null;
      return parsed.isUtc ? parsed : parsed.toUtc();
    }
    return null;
  }
}
