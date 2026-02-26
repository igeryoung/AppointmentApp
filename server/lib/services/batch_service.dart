import '../database/connection.dart';
import 'drawing_service.dart';
import 'note_service.dart';

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
  }) : success = true,
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

/// Service for handling batch operations.
///
/// Note: This preserves the endpoint response contract, while accepting both
/// legacy and canonical field names in payloads.
class BatchService {
  final DatabaseConnection db;
  late final NoteService _noteService;
  late final DrawingService _drawingService;

  BatchService(this.db) {
    _noteService = NoteService(db);
    _drawingService = DrawingService(db);
  }

  Map<String, dynamic>? _first(dynamic data) {
    if (data is List && data.isNotEmpty) {
      final row = data.first;
      if (row is Map<String, dynamic>) return row;
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  Future<bool> _verifyDeviceAccess(String deviceId, String token) {
    return _noteService.verifyDeviceAccess(deviceId, token);
  }

  Future<bool> _verifyBookOwnership(String deviceId, String bookUuid) {
    return _noteService.verifyBookOwnership(deviceId, bookUuid);
  }

  Future<bool> _verifyEventInBook(String eventId, String bookUuid) {
    return _noteService.verifyEventInBook(eventId, bookUuid);
  }

  Future<String> _getRecordUuid(String eventId) async {
    final rows = await db.client
        .from('events')
        .select('record_uuid')
        .eq('id', eventId)
        .eq('is_deleted', false)
        .limit(1);
    final row = _first(rows);
    if (row == null || row['record_uuid'] == null) {
      throw Exception('Event not found: eventId=$eventId');
    }
    return row['record_uuid'].toString();
  }

  Future<void> _saveNote(
    String recordUuid,
    String pagesData,
    int? expectedVersion,
  ) async {
    final result = await _noteService.createOrUpdateNoteForRecord(
      recordUuid: recordUuid,
      pagesData: pagesData,
      expectedVersion: expectedVersion,
    );

    if (result.success) {
      return;
    }

    if (result.hasConflict) {
      throw Exception(
        'Version conflict: recordUuid=$recordUuid, expected=$expectedVersion, server=${result.serverVersion}',
      );
    }

    throw Exception('Failed to save note: recordUuid=$recordUuid');
  }

  Future<void> _saveDrawing(
    String bookUuid,
    String date,
    int viewMode,
    String strokesData,
    int? expectedVersion,
  ) async {
    final result = await _drawingService.createOrUpdateDrawing(
      bookUuid: bookUuid,
      deviceId: 'batch',
      date: date,
      viewMode: viewMode,
      strokesData: strokesData,
      expectedVersion: expectedVersion,
    );

    if (result.success) {
      return;
    }

    if (result.hasConflict) {
      throw Exception(
        'Version conflict: bookUuid=$bookUuid, date=$date, viewMode=$viewMode, expected=$expectedVersion, server=${result.serverVersion}',
      );
    }

    throw Exception(
      'Failed to save drawing: bookUuid=$bookUuid, date=$date, viewMode=$viewMode',
    );
  }

  String _requiredString(
    Map<String, dynamic> payload,
    List<String> keys,
    String label,
  ) {
    for (final key in keys) {
      final value = payload[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    throw Exception('Missing required field: $label');
  }

  int _requiredInt(
    Map<String, dynamic> payload,
    List<String> keys,
    String label,
  ) {
    for (final key in keys) {
      final value = payload[key];
      if (value == null) continue;
      if (value is int) return value;
      final parsed = int.tryParse(value.toString().trim());
      if (parsed != null) return parsed;
    }
    throw Exception('Missing or invalid integer field: $label');
  }

  int? _optionalInt(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value == null) continue;
      if (value is int) return value;
      final parsed = int.tryParse(value.toString().trim());
      if (parsed != null) return parsed;
    }
    return null;
  }

  Future<BatchSaveResult> batchSave({
    required String deviceId,
    required String deviceToken,
    required List<Map<String, dynamic>> notes,
    required List<Map<String, dynamic>> drawings,
  }) async {
    try {
      final hasAccess = await _verifyDeviceAccess(deviceId, deviceToken);
      if (!hasAccess) {
        return BatchSaveResult.failure('Invalid device credentials');
      }

      if (notes.isEmpty && drawings.isEmpty) {
        return BatchSaveResult.success(notesSucceeded: 0, drawingsSucceeded: 0);
      }

      var notesProcessed = 0;
      for (final note in notes) {
        final eventId = _requiredString(note, [
          'eventId',
          'event_id',
        ], 'eventId');
        final bookUuid = _requiredString(note, [
          'bookUuid',
          'book_uuid',
          'bookId',
          'book_id',
        ], 'bookUuid');
        final pagesData = _requiredString(note, [
          'pagesData',
          'pages_data',
          'strokesData',
          'strokes_data',
        ], 'pagesData');
        final version = _optionalInt(note, ['version']);

        final ownsBook = await _verifyBookOwnership(deviceId, bookUuid);
        if (!ownsBook) {
          return BatchSaveResult.failure(
            'Unauthorized access to book: bookUuid=$bookUuid',
          );
        }

        final eventInBook = await _verifyEventInBook(eventId, bookUuid);
        if (!eventInBook) {
          return BatchSaveResult.failure(
            'Event does not belong to book: eventId=$eventId, bookUuid=$bookUuid',
          );
        }

        final recordUuid = await _getRecordUuid(eventId);
        await _saveNote(recordUuid, pagesData, version);
        notesProcessed++;
      }

      var drawingsProcessed = 0;
      for (final drawing in drawings) {
        final bookUuid = _requiredString(drawing, [
          'bookUuid',
          'book_uuid',
          'bookId',
          'book_id',
        ], 'bookUuid');
        final date = _requiredString(drawing, ['date'], 'date');
        final viewMode = _requiredInt(drawing, [
          'viewMode',
          'view_mode',
        ], 'viewMode');
        final strokesData = _requiredString(drawing, [
          'strokesData',
          'strokes_data',
        ], 'strokesData');
        final version = _optionalInt(drawing, ['version']);

        final ownsBook = await _verifyBookOwnership(deviceId, bookUuid);
        if (!ownsBook) {
          return BatchSaveResult.failure(
            'Unauthorized access to book: bookUuid=$bookUuid',
          );
        }

        await _saveDrawing(bookUuid, date, viewMode, strokesData, version);
        drawingsProcessed++;
      }

      print(
        '✅ Batch save completed: notes=$notesProcessed, drawings=$drawingsProcessed',
      );
      return BatchSaveResult.success(
        notesSucceeded: notesProcessed,
        drawingsSucceeded: drawingsProcessed,
      );
    } catch (e) {
      print('❌ Batch save failed: $e');
      return BatchSaveResult.failure(e.toString());
    }
  }
}
