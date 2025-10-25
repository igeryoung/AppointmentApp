import 'package:postgres/postgres.dart';
import '../database/connection.dart';

/// Result of a batch save operation
class BatchSaveResult {
  final bool success;
  final Map<String, dynamic> results;
  final String? errorMessage;

  const BatchSaveResult({
    required this.success,
    required this.results,
    this.errorMessage,
  });

  BatchSaveResult.success({
    required int notesSucceeded,
    required int drawingsSucceeded,
  })  : success = true,
        results = {
          'notes': {'succeeded': notesSucceeded, 'failed': 0},
          'drawings': {'succeeded': drawingsSucceeded, 'failed': 0},
        },
        errorMessage = null;

  BatchSaveResult.failure(String error)
      : success = false,
        results = {
          'notes': {'succeeded': 0, 'failed': 0},
          'drawings': {'succeeded': 0, 'failed': 0},
        },
        errorMessage = error;
}

/// Service for handling batch operations with transaction support
///
/// Implements "all-or-nothing" strategy as recommended in Phase 2-04:
/// - All operations succeed → COMMIT
/// - Any operation fails → ROLLBACK entire batch
class BatchService {
  final DatabaseConnection db;

  BatchService(this.db);

  /// Verify device credentials
  Future<bool> _verifyDeviceAccess(
    Session session,
    String deviceId,
    String token,
  ) async {
    try {
      final result = await session.execute(
        Sql.named(
          'SELECT id FROM devices WHERE id = @id AND device_token = @token AND is_active = true',
        ),
        parameters: {'id': deviceId, 'token': token},
      );
      return result.isNotEmpty;
    } catch (e) {
      print('❌ Device verification failed: $e');
      return false;
    }
  }

  /// Verify book ownership
  Future<bool> _verifyBookOwnership(
    Session session,
    String deviceId,
    int bookId,
  ) async {
    try {
      final result = await session.execute(
        Sql.named(
          'SELECT id FROM books WHERE id = @bookId AND device_id = @deviceId AND is_deleted = false',
        ),
        parameters: {'bookId': bookId, 'deviceId': deviceId},
      );
      return result.isNotEmpty;
    } catch (e) {
      print('❌ Book ownership verification failed: $e');
      return false;
    }
  }

  /// Verify event belongs to book
  Future<bool> _verifyEventInBook(
    Session session,
    int eventId,
    int bookId,
  ) async {
    try {
      final result = await session.execute(
        Sql.named(
          'SELECT id FROM events WHERE id = @eventId AND book_id = @bookId AND is_deleted = false',
        ),
        parameters: {'eventId': eventId, 'bookId': bookId},
      );
      return result.isNotEmpty;
    } catch (e) {
      print('❌ Event-book relationship verification failed: $e');
      return false;
    }
  }

  /// Save a single note within a transaction
  Future<void> _saveNote(
    Session session,
    String deviceId,
    int eventId,
    String strokesData,
    int? expectedVersion,
  ) async {
    final result = await session.execute(
      Sql.named('''
        INSERT INTO notes (event_id, device_id, strokes_data, version, created_at, updated_at, synced_at)
        VALUES (@eventId, @deviceId, @strokesData, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (event_id) DO UPDATE
        SET strokes_data = EXCLUDED.strokes_data,
            updated_at = CURRENT_TIMESTAMP,
            synced_at = CURRENT_TIMESTAMP,
            version = notes.version + 1,
            device_id = EXCLUDED.device_id
        WHERE (CAST(@expectedVersion AS INTEGER) IS NULL OR notes.version = CAST(@expectedVersion AS INTEGER))
          AND notes.is_deleted = false
        RETURNING id, version
        '''),
      parameters: {
        'eventId': eventId,
        'deviceId': deviceId,
        'strokesData': strokesData,
        'expectedVersion': expectedVersion,
      },
    );

    if (result.isEmpty) {
      // Either version conflict or note is deleted
      final currentNote = await session.execute(
        Sql.named(
          'SELECT version, is_deleted FROM notes WHERE event_id = @eventId',
        ),
        parameters: {'eventId': eventId},
      );

      if (currentNote.isNotEmpty) {
        final row = currentNote.first.toColumnMap();
        if (row['is_deleted'] == true) {
          throw Exception('Cannot update deleted note: eventId=$eventId');
        }
        throw Exception(
          'Version conflict: eventId=$eventId, expected=$expectedVersion, server=${row['version']}',
        );
      }
      throw Exception('Failed to save note: eventId=$eventId');
    }
  }

  /// Save a single drawing within a transaction
  Future<void> _saveDrawing(
    Session session,
    String deviceId,
    int bookId,
    String date,
    int viewMode,
    String strokesData,
    int? expectedVersion,
  ) async {
    final result = await session.execute(
      Sql.named('''
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
        RETURNING id, version
        '''),
      parameters: {
        'bookId': bookId,
        'deviceId': deviceId,
        'date': date,
        'viewMode': viewMode,
        'strokesData': strokesData,
        'expectedVersion': expectedVersion,
      },
    );

    if (result.isEmpty) {
      // Either version conflict or drawing is deleted
      final currentDrawing = await session.execute(
        Sql.named(
          'SELECT version, is_deleted FROM schedule_drawings WHERE book_id = @bookId AND date = @date::timestamp AND view_mode = @viewMode',
        ),
        parameters: {
          'bookId': bookId,
          'date': date,
          'viewMode': viewMode,
        },
      );

      if (currentDrawing.isNotEmpty) {
        final row = currentDrawing.first.toColumnMap();
        if (row['is_deleted'] == true) {
          throw Exception(
            'Cannot update deleted drawing: bookId=$bookId, date=$date, viewMode=$viewMode',
          );
        }
        throw Exception(
          'Version conflict: bookId=$bookId, date=$date, viewMode=$viewMode, expected=$expectedVersion, server=${row['version']}',
        );
      }
      throw Exception(
        'Failed to save drawing: bookId=$bookId, date=$date, viewMode=$viewMode',
      );
    }
  }

  /// Batch save notes and drawings in a single atomic transaction
  ///
  /// Strategy: All-or-nothing
  /// - If any operation fails, the entire batch is rolled back
  /// - Returns success with counts on success
  /// - Returns failure with error message on any failure
  ///
  /// Request format:
  /// {
  ///   "notes": [
  ///     { "eventId": 1, "bookId": 1, "strokesData": "...", "version": 2 }
  ///   ],
  ///   "drawings": [
  ///     { "bookId": 1, "date": "2025-10-23", "viewMode": 0, "strokesData": "...", "version": 1 }
  ///   ]
  /// }
  Future<BatchSaveResult> batchSave({
    required String deviceId,
    required String deviceToken,
    required List<Map<String, dynamic>> notes,
    required List<Map<String, dynamic>> drawings,
  }) async {
    try {
      // Execute entire batch in a transaction
      final result = await db.transaction<BatchSaveResult>((session) async {
        // 1. Verify device credentials (even for empty batches)
        final hasAccess = await _verifyDeviceAccess(
          session,
          deviceId,
          deviceToken,
        );
        if (!hasAccess) {
          throw Exception('Invalid device credentials');
        }

        // Handle empty batch after authentication
        if (notes.isEmpty && drawings.isEmpty) {
          print('✅ Batch save: empty batch (authenticated), returning success');
          return BatchSaveResult.success(notesSucceeded: 0, drawingsSucceeded: 0);
        }

        // 2. Process all notes
        int notesProcessed = 0;
        for (final note in notes) {
          final eventId = note['eventId'] as int;
          final bookId = note['bookId'] as int;
          final strokesData = note['strokesData'] as String;
          final version = note['version'] as int?;

          // Verify book ownership
          final ownsBook = await _verifyBookOwnership(session, deviceId, bookId);
          if (!ownsBook) {
            throw Exception('Unauthorized access to book: bookId=$bookId');
          }

          // Verify event belongs to book
          final eventInBook = await _verifyEventInBook(session, eventId, bookId);
          if (!eventInBook) {
            throw Exception(
              'Event does not belong to book: eventId=$eventId, bookId=$bookId',
            );
          }

          // Save note
          await _saveNote(session, deviceId, eventId, strokesData, version);
          notesProcessed++;
        }

        // 3. Process all drawings
        int drawingsProcessed = 0;
        for (final drawing in drawings) {
          final bookId = drawing['bookId'] as int;
          final date = drawing['date'] as String;
          final viewMode = drawing['viewMode'] as int;
          final strokesData = drawing['strokesData'] as String;
          final version = drawing['version'] as int?;

          // Verify book ownership
          final ownsBook = await _verifyBookOwnership(session, deviceId, bookId);
          if (!ownsBook) {
            throw Exception('Unauthorized access to book: bookId=$bookId');
          }

          // Save drawing
          await _saveDrawing(
            session,
            deviceId,
            bookId,
            date,
            viewMode,
            strokesData,
            version,
          );
          drawingsProcessed++;
        }

        print('✅ Batch save completed: notes=$notesProcessed, drawings=$drawingsProcessed');
        return BatchSaveResult.success(
          notesSucceeded: notesProcessed,
          drawingsSucceeded: drawingsProcessed,
        );
      });

      return result;
    } catch (e) {
      print('❌ Batch save failed (transaction rolled back): $e');
      return BatchSaveResult.failure(e.toString());
    }
  }
}
