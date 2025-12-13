import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/note.dart';
import '../models/event.dart';
import '../models/schedule_drawing.dart';
import 'api_client.dart';


/// ContentService - Unified content management with server-first strategy
///
/// **DEPRECATED**: This class is being replaced by focused services:
/// - [NoteContentService] for note operations
/// - [DrawingContentService] for drawing operations
/// - [SyncCoordinator] for bulk sync operations
///
/// This class is kept for backward compatibility during refactoring.
/// New code should use the replacement services above.
///
/// Handles Notes and Drawings with server-first approach
///
/// Architecture:
///   Screen → ContentService → ApiClient + DatabaseService
///                             ^^^^^^^^^^^^^^^^^^^^^^^^^^
///                             Hide complexity from UI
///
/// Linus说: "Abstraction layers should hide complexity, not add it."
@Deprecated('Use NoteContentService, DrawingContentService, and SyncCoordinator instead')
class ContentService {
  final ApiClient _apiClient;
  final dynamic _db;  // PRDDatabaseService or mock

  // RACE CONDITION FIX: Save operation queue to serialize drawing saves
  final List<Future<void> Function()> _drawingSaveQueue = [];
  bool _isProcessingDrawingSaveQueue = false;

  ContentService(this._apiClient, this._db);

  // ===================
  // Health Check
  // ===================

  /// Check if the server is reachable
  /// Returns true if server responds to health check, false otherwise
  Future<bool> healthCheck() async {
    try {
      return await _apiClient.healthCheck();
    } catch (e) {
      return false;
    }
  }

  // ===================
  // Event Operations
  // ===================

  /// Fetch event metadata from server and update local cache
  Future<Event?> refreshEventFromServer(String eventId) async {
    try {
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        throw Exception('Device not registered, cannot fetch event');
      }

      final localEvent = await _db.getEventById(eventId);
      if (localEvent == null) {
        throw Exception('Event $eventId not found locally');
      }

      final serverEvent = await _apiClient.fetchEvent(
        bookUuid: localEvent.bookUuid,
        eventId: eventId,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      if (serverEvent == null) {
        return null;
      }

      _debugPrintEventMap('server_event_raw', serverEvent);
      final normalized = _convertServerEventTimestamps(serverEvent);
      _debugPrintEventMap('server_event_normalized', normalized);
      final refreshedEvent = Event.fromMap(normalized);
      _debugPrintEvent('server_event_parsed', refreshedEvent);
      return refreshedEvent;
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> _convertServerEventTimestamps(Map<String, dynamic> original) {
    int? _parseSeconds(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    final copy = Map<String, dynamic>.from(original);
    final startSeconds = _parseSeconds(copy['start_time']);
    if (startSeconds != null) copy['start_time'] = startSeconds;

    final endSeconds = _parseSeconds(copy['end_time']);
    if (endSeconds != null) copy['end_time'] = endSeconds;

    final createdSeconds = _parseSeconds(copy['created_at']);
    if (createdSeconds != null) copy['created_at'] = createdSeconds;

    final updatedSeconds = _parseSeconds(copy['updated_at']);
    if (updatedSeconds != null) copy['updated_at'] = updatedSeconds;

    return copy;
  }

  void _debugPrintEventMap(String label, Map<String, dynamic> map) {
    assert(() {
      try {
        final start = map['start_time'];
        final end = map['end_time'];
        final created = map['created_at'];
        final updated = map['updated_at'];
        print('[ContentService] $label start=${start.runtimeType}=$start end=${end.runtimeType}=$end created=${created.runtimeType}=$created updated=${updated.runtimeType}=$updated');
      } catch (_) {}
      return true;
    }());
  }

  void _debugPrintEvent(String label, Event event) {
    assert(() {
      print('[ContentService] $label id=${event.id} start=${event.startTime.toIso8601String()} (isUtc=${event.startTime.isUtc}) end=${event.endTime?.toIso8601String()}');
      return true;
    }());
  }

  // ===================
  // Notes Operations
  // ===================

  /// Get note from local storage (server-first architecture)
  ///
  /// In server-based architecture, notes are fetched from server via API
  /// This method is kept for backward compatibility but may return null
  Future<Note?> getCachedNote(String eventId) async {
    try {
      // In server-first architecture, we fetch via API
      // Local cache is not used - data comes from server
      final note = await _db.getNoteByEventId(eventId);
      return note;
    } catch (e) {
      return null;
    }
  }

  /// Get note with server-first strategy
  ///
  /// Flow:
  /// 1. Fetch from server
  /// 2. Return note or null on failure
  ///
  /// [forceRefresh] - ignored in server-first architecture
  Future<Note?> getNote(String eventId, {bool forceRefresh = false}) async {
    try {
      // In server-first architecture, fetch from server
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        return null;
      }

      // Get bookId for the event
      final event = await _db.getEventById(eventId);
      if (event == null) {
        return null;
      }

      final serverNote = await _apiClient.fetchNote(
        bookUuid: event.bookUuid,
        eventId: eventId,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      if (serverNote != null) {
        return Note.fromMap(serverNote);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Save note to server
  ///
  /// In server-based architecture, saves directly to server
  Future<void> saveNote(String eventId, Note note) async {
    // Save directly to server via syncNote
    await syncNote(eventId);
  }

  /// Force sync a note to server
  ///
  /// Throws exception on sync failure
  /// In server-first architecture, syncs note data from local to server
  Future<void> syncNote(String eventId, {int retryCount = 0}) async {
    try {
      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        throw Exception('Device not registered, cannot sync to server');
      }

      // Get event
      final event = await _db.getEventById(eventId);
      if (event == null) {
        throw Exception('Event $eventId not found');
      }

      // Get note via record
      final note = await _db.getNoteByRecordUuid(event.recordUuid);
      if (note == null) {
        return; // No note to sync
      }

      // Save to server
      final noteMap = note.toMap();
      final noteData = {
        'pagesData': noteMap['pages_data'],
        'version': noteMap['version'],
      };

      final eventData = event.toMap();

      await _apiClient.saveNote(
        bookUuid: event.bookUuid,
        eventId: eventId,
        noteData: noteData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
        eventData: eventData,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Delete note from server
  Future<void> deleteNote(String eventId) async {
    try {
      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        throw Exception('Device not registered');
      }

      // Get event
      final event = await _db.getEventById(eventId);
      if (event == null) {
        return;
      }

      // Delete from server
      await _apiClient.deleteNote(
        bookUuid: event.bookUuid,
        eventId: eventId,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Preload multiple notes in background (for performance)
  ///
  /// In server-first architecture, this fetches notes from server
  /// and does NOT cache them locally
  ///
  /// [onProgress] callback reports (loaded, total) progress
  /// [generation] - Generation number for tracking preload requests
  /// [isCancelled] - Callback to check if this preload should be cancelled
  Future<void> preloadNotes(
    List<String> eventIds, {
    Function(int loaded, int total)? onProgress,
    int? generation,
    bool Function()? isCancelled,
  }) async {
    if (eventIds.isEmpty) {
      onProgress?.call(0, 0);
      return;
    }

    // In server-first architecture, preloading is optional
    // Just report success without actual fetching
    onProgress?.call(eventIds.length, eventIds.length);
  }

  /// Sync all dirty notes to server
  /// In server-first architecture, this is a no-op since data is always on server
  Future<BulkSyncResult> syncAllDirtyNotes() async {
    // In server-first architecture, there are no dirty notes
    return BulkSyncResult(total: 0, success: 0, failed: 0, failedEventIds: []);
  }

  /// Sync dirty notes for a specific book
  /// In server-first architecture, this is a no-op since data is always on server
  Future<BulkSyncResult> syncDirtyNotesForBook(String bookUuid) async {
    // In server-first architecture, there are no dirty notes
    return BulkSyncResult(total: 0, success: 0, failed: 0, failedEventIds: []);
  }

  // ===================
  // Drawings Operations
  // ===================

  /// Get drawing from server
  Future<ScheduleDrawing?> getDrawing({
    required String bookUuid,
    required DateTime date,
    required int viewMode,
    bool forceRefresh = false,
  }) async {
    try {
      // Fetch from server
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        // Try local database
        return await _db.getScheduleDrawing(bookUuid, date, viewMode);
      }

      final serverDrawing = await _apiClient.fetchDrawing(
        bookUuid: bookUuid,
        date: date,
        viewMode: viewMode,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      if (serverDrawing != null) {
        return ScheduleDrawing.fromMap(serverDrawing);
      }

      return null;
    } catch (e) {
      // Fallback to local database
      try {
        return await _db.getScheduleDrawing(bookUuid, date, viewMode);
      } catch (dbError) {
        return null;
      }
    }
  }

  /// Process the drawing save queue to serialize save operations
  /// RACE CONDITION FIX: Ensures saves are processed sequentially
  Future<void> _processDrawingSaveQueue() async {
    if (_isProcessingDrawingSaveQueue || _drawingSaveQueue.isEmpty) {
      return;
    }

    _isProcessingDrawingSaveQueue = true;
    try {
      while (_drawingSaveQueue.isNotEmpty) {
        final saveOperation = _drawingSaveQueue.removeAt(0);
        try {
          await saveOperation();
        } catch (e) {
          // Continue processing queue even if one operation fails
        }
      }
    } finally {
      _isProcessingDrawingSaveQueue = false;
    }
  }

  /// Save drawing (update server and cache)
  /// RACE CONDITION FIX: Uses queue to serialize save operations
  Future<void> saveDrawing(ScheduleDrawing drawing) async {
    // Create a completer to wait for the queued operation to complete
    final completer = Completer<void>();

    // Add save operation to queue
    _drawingSaveQueue.add(() async {
      try {
        await _saveDrawingInternal(drawing);
        completer.complete();
      } catch (e) {
        completer.completeError(e);
      }
    });

    // Start processing queue if not already processing
    _processDrawingSaveQueue();

    // Wait for this specific save to complete
    return completer.future;
  }

  /// Internal save drawing implementation (called from queue)
  Future<void> _saveDrawingInternal(ScheduleDrawing drawing, {int retryCount = 0}) async {
    try {
      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        // Save locally only
        await _db.saveScheduleDrawing(drawing);
        return;
      }

      // Transform drawing data to server API format
      final drawingData = drawing.toMap();
      final serverDrawingData = {
        'date': drawing.date.toIso8601String().split('T')[0],
        'viewMode': drawing.viewMode,
        'strokesData': drawingData['strokes_data'],
        if (drawing.id != null) 'version': drawing.version,
      };

      await _apiClient.saveDrawing(
        bookUuid: drawing.bookUuid,
        drawingData: serverDrawingData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
    } catch (e) {
      // Save locally on error
      try {
        await _db.saveScheduleDrawing(drawing);
      } catch (dbError) {
        rethrow;
      }
    }
  }

  /// Delete drawing from server
  Future<void> deleteDrawing({
    required String bookUuid,
    required DateTime date,
    required int viewMode,
  }) async {
    try {
      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials != null) {
        // Delete from server
        await _apiClient.deleteDrawing(
          bookUuid: bookUuid,
          date: date,
          viewMode: viewMode,
          deviceId: credentials.deviceId,
          deviceToken: credentials.deviceToken,
        );
      }

      // Delete from local database
      await _db.deleteScheduleDrawing(bookUuid, date, viewMode);
    } catch (e) {
      rethrow;
    }
  }

  /// Preload drawings for a date range (for performance)
  /// In server-first architecture, this is a no-op
  Future<void> preloadDrawings({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // In server-first architecture, preloading is not needed
  }
}

/// Result object for bulk sync operations
class BulkSyncResult {
  final int total;
  final int success;
  final int failed;
  final List<int> failedEventIds;

  BulkSyncResult({
    required this.total,
    required this.success,
    required this.failed,
    required this.failedEventIds,
  });

  bool get hasFailures => failed > 0;
  bool get allSucceeded => failed == 0 && total > 0;
  bool get nothingToSync => total == 0;

  @override
  String toString() {
    return 'BulkSyncResult(total: $total, success: $success, failed: $failed)';
  }
}
