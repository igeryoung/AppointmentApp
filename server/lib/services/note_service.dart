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
  Future<bool> verifyBookOwnership(String deviceId, int bookId) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM books WHERE id = @bookId AND device_id = @deviceId AND is_deleted = false',
        parameters: {'bookId': bookId, 'deviceId': deviceId},
      );

      if (row == null) {
        // Check if book exists but with different device_id
        final anyBook = await db.querySingle(
          'SELECT device_id, is_deleted FROM books WHERE id = @bookId',
          parameters: {'bookId': bookId},
        );

        if (anyBook != null) {
          print('⚠️  Book ownership mismatch: bookId=$bookId, expected deviceId=$deviceId, actual deviceId=${anyBook['device_id']}, is_deleted=${anyBook['is_deleted']}');
        } else {
          print('⚠️  Book not found: bookId=$bookId');
        }
      }

      return row != null;
    } catch (e) {
      print('❌ Book ownership verification failed: $e');
      return false;
    }
  }

  /// Verify that an event belongs to the specified book
  /// Returns true if event exists and belongs to the book
  Future<bool> verifyEventInBook(int eventId, int bookId) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM events WHERE id = @eventId AND book_id = @bookId AND is_deleted = false',
        parameters: {'eventId': eventId, 'bookId': bookId},
      );
      return row != null;
    } catch (e) {
      print('❌ Event-book relationship verification failed: $e');
      return false;
    }
  }

  /// Get a single note by event ID
  /// Returns null if note doesn't exist or is deleted
  Future<Map<String, dynamic>?> getNote(int eventId) async {
    try {
      final row = await db.querySingle(
        '''
        SELECT id, event_id, strokes_data, created_at, updated_at, version
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
    required int eventId,
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
        print('✅ Note ${expectedVersion == null ? 'created' : 'updated'}: event=$eventId, version=${result['version']}');
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
  Future<bool> deleteNote(int eventId) async {
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
        print('✅ Note deleted: event=$eventId');
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
        SELECT n.id, n.event_id, n.strokes_data, n.created_at, n.updated_at, n.version
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
      final eventId = eventData['id'] as int?;
      if (eventId == null) {
        throw ArgumentError('Event data must include id');
      }

      // Check if event already exists
      final existing = await db.querySingle(
        'SELECT id FROM events WHERE id = @id',
        parameters: {'id': eventId},
      );

      if (existing != null) {
        print('ℹ️  Event already exists: id=$eventId, skipping creation');
        return;
      }

      // Parse timestamps (client sends Unix seconds)
      final startTime = eventData['start_time'] is int
          ? DateTime.fromMillisecondsSinceEpoch((eventData['start_time'] as int) * 1000)
          : eventData['start_time'] as DateTime;

      final endTime = eventData['end_time'] != null
          ? (eventData['end_time'] is int
              ? DateTime.fromMillisecondsSinceEpoch((eventData['end_time'] as int) * 1000)
              : eventData['end_time'] as DateTime)
          : null;

      final createdAt = eventData['created_at'] != null
          ? (eventData['created_at'] is int
              ? DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000)
              : eventData['created_at'] as DateTime)
          : DateTime.now();

      final updatedAt = eventData['updated_at'] != null
          ? (eventData['updated_at'] is int
              ? DateTime.fromMillisecondsSinceEpoch((eventData['updated_at'] as int) * 1000)
              : eventData['updated_at'] as DateTime)
          : DateTime.now();

      // Insert event with client-provided ID
      await db.query(
        '''
        INSERT INTO events (
          id, book_id, device_id, name, record_number, event_type,
          start_time, end_time, created_at, updated_at,
          is_removed, removal_reason, original_event_id, new_event_id,
          synced_at, version, is_deleted
        ) VALUES (
          @id, @bookId, @deviceId, @name, @recordNumber, @eventType,
          @startTime, @endTime, @createdAt, @updatedAt,
          @isRemoved, @removalReason, @originalEventId, @newEventId,
          CURRENT_TIMESTAMP, 1, false
        )
        ''',
        parameters: {
          'id': eventId,
          'bookId': eventData['book_id'],
          'deviceId': deviceId,
          'name': eventData['name'] ?? '',
          'recordNumber': eventData['record_number'],
          'eventType': eventData['event_type'] ?? '',
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

      // Update the sequence to prevent future ID conflicts
      await db.query(
        "SELECT setval('events_id_seq', (SELECT MAX(id) FROM events))",
      );

      print('✅ Event auto-created: id=$eventId, book=${eventData['book_id']}, name="${eventData['name']}"');
    } catch (e) {
      print('❌ Create event failed: $e');
      rethrow;
    }
  }
}
