import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/note.dart';
import '../models/event.dart';
import '../models/schedule_drawing.dart';
import 'api_client.dart';


/// ContentService - Unified content management with cache-first strategy
///
/// **DEPRECATED**: This class is being replaced by focused services:
/// - [NoteContentService] for note operations
/// - [DrawingContentService] for drawing operations
/// - [SyncCoordinator] for bulk sync operations
///
/// This class is kept for backward compatibility during refactoring.
/// New code should use the replacement services above.
///
/// Handles Notes and Drawings with intelligent caching and network fallback
///
/// Architecture:
///   Screen → ContentService → ApiClient + CacheManager
///                             ^^^^^^^^^^^^^^^^^^^^
///                             Hide complexity from UI
///
/// Linus说: "Abstraction layers should hide complexity, not add it."
@Deprecated('Use NoteContentService, DrawingContentService, and SyncCoordinator instead')
class ContentService {
  final ApiClient _apiClient;
  final dynamic _cacheManager;  // CacheManager or mock
  final dynamic _db;  // PRDDatabaseService or mock

  // RACE CONDITION FIX: Save operation queue to serialize drawing saves
  final List<Future<void> Function()> _drawingSaveQueue = [];
  bool _isProcessingDrawingSaveQueue = false;

  ContentService(this._apiClient, this._cacheManager, this._db);

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

  /// Get note from cache only (no network call)
  ///
  /// Returns cached note immediately without checking server
  /// Used for instant display in cache-first strategy
  Future<Note?> getCachedNote(String eventId) async {
    try {
      final cachedNote = await _cacheManager.getNote(eventId);
      if (cachedNote != null) {
      } else {
      }
      return cachedNote;
    } catch (e) {
      return null;
    }
  }

  /// Get note with cache-first strategy
  ///
  /// Flow:
  /// 1. Check cache → if exists and valid → return
  /// 2. Fetch from server:
  ///    - Success → update cache → return
  ///    - Failure → return cached (if exists) or null
  ///
  /// [forceRefresh] skips cache and forces server fetch
  Future<Note?> getNote(String eventId, {bool forceRefresh = false}) async {
    try {
      // Step 1: Check cache (unless forceRefresh)
      if (!forceRefresh) {
        final cachedNote = await _cacheManager.getNote(eventId);
        if (cachedNote != null) {
          return cachedNote;
        }
      }

      // Step 2: Fetch from server
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        // Return cache if available
        return await _cacheManager.getNote(eventId);
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
        // Parse and save to cache
        final note = Note.fromMap(serverNote);
        await _cacheManager.saveNote(eventId, note);
        return note;
      }

      return null;
    } catch (e) {

      // Fallback to cache on error
      try {
        final cachedNote = await _cacheManager.getNote(eventId);
        if (cachedNote != null) {
          return cachedNote;
        }
      } catch (cacheError) {
      }

      return null;
    }
  }

  /// Save note locally and sync to server
  ///
  /// In server-based architecture, saves to cache for display
  /// Server sync is handled by the caller
  Future<void> saveNote(String eventId, Note note) async {
    await _cacheManager.saveNote(eventId, note);
  }

  /// Force sync a note to server (clears dirty flag on success)
  ///
  /// Throws exception on sync failure, keeps dirty flag intact
  /// Handles version conflicts with auto-retry using server version
  Future<void> syncNote(String eventId, {int retryCount = 0}) async {
    const maxRetries = 3;

    try {
      final note = await _cacheManager.getNote(eventId);
      if (note == null) {
        return;
      }

      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        throw Exception('Device not registered, cannot sync to server');
      }

      // Get bookId
      final event = await _db.getEventById(eventId);
      if (event == null) {
        throw Exception('Event $eventId not found');
      }

      // Save to server - use toMap() to serialize properly
      final noteMap = note.toMap();
      final noteData = {
        'pagesData': noteMap['pages_data'],
        'version': noteMap['version'], // Include version for optimistic locking
      };

      // Include event data for auto-creation on server if event doesn't exist
      final eventData = event.toMap();


      final serverNote = await _apiClient.saveNote(
        bookUuid: event.bookUuid,
        eventId: eventId,
        noteData: noteData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
        eventData: eventData,
      );

      // Update local note with server version
      final serverVersion = serverNote['version'] as int?;
      if (serverVersion != null && serverVersion != note.version) {
        final updatedNote = note.copyWith(version: serverVersion);
        await _cacheManager.saveNote(eventId, updatedNote);
      }
      // Sync successful - cache is already updated

    } catch (e) {
      // Handle version conflicts with auto-retry
      if (e is ApiConflictException && retryCount < maxRetries) {

        final serverVersion = e.serverVersion;
        final serverState = e.serverState;

        if (serverVersion != null) {

          // Fetch current note from cache to get latest local data
          final currentNote = await _cacheManager.getNote(eventId);
          if (currentNote != null) {
            // Last-write-wins: Use server version but keep local pages
            // This implements auto-retry with server version (user choice QC.1)
            final mergedNote = currentNote.copyWith(version: serverVersion);

            // Save merged note to cache with new version
            await _cacheManager.saveNote(eventId, mergedNote);


            // Retry with updated version
            return await syncNote(eventId, retryCount: retryCount + 1);
          }
        } else {
        }
      }

      // 保留dirty标记，稍后重试
      rethrow;
    }
  }

  /// Delete note (from server and cache)
  Future<void> deleteNote(String eventId) async {
    try {
      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials != null) {
        // Get bookId
        final event = await _db.getEventById(eventId);
        if (event != null) {
          // Delete from server
          await _apiClient.deleteNote(
            bookUuid: event.bookUuid,
            eventId: eventId,
            deviceId: credentials.deviceId,
            deviceToken: credentials.deviceToken,
          );
        }
      }

      // Delete from cache
      await _cacheManager.deleteNote(eventId);

    } catch (e) {
      rethrow;
    }
  }

  /// Preload multiple notes in background (for performance)
  ///
  /// Strategy:
  /// 1. Filter out already-cached notes
  /// 2. Batch fetch from server (max 50 per request)
  /// 3. Save to cache
  ///
  /// [onProgress] callback reports (loaded, total) progress
  /// [generation] - Generation number for tracking preload requests
  /// [isCancelled] - Callback to check if this preload should be cancelled
  /// Does not block, returns immediately
  /// Failures are logged but don't throw
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

    final startTime = DateTime.now();

    // Run in background, don't block caller
    Future.microtask(() async {
      try {
        // RACE CONDITION FIX: Check if cancelled before starting
        if (isCancelled != null && isCancelled()) {
          return;
        }

        // Step 1: Filter out already-cached notes
        final uncachedIds = <String>[];
        for (final id in eventIds) {
          // RACE CONDITION FIX: Check cancellation during cache lookup
          if (isCancelled != null && isCancelled()) {
            return;
          }

          final cached = await _cacheManager.getNote(id);
          if (cached == null) {
            uncachedIds.add(id);
          }
        }

        if (uncachedIds.isEmpty) {
          if (isCancelled == null || !isCancelled()) {
            onProgress?.call(eventIds.length, eventIds.length);
          }
          return;
        }


        // Get credentials once
        final credentials = await _db.getDeviceCredentials();
        if (credentials == null) {
          if (isCancelled == null || !isCancelled()) {
            onProgress?.call(eventIds.length - uncachedIds.length, eventIds.length);
          }
          return;
        }

        // Step 2: Batch fetch (max 50 per request to avoid timeout)
        const batchSize = 50;
        int loaded = eventIds.length - uncachedIds.length; // Already cached
        final totalBatches = (uncachedIds.length / batchSize).ceil();


        for (int i = 0; i < uncachedIds.length; i += batchSize) {
          // RACE CONDITION FIX: Check cancellation before each batch
          if (isCancelled != null && isCancelled()) {
            return;
          }

          final batch = uncachedIds.skip(i).take(batchSize).toList();
          final batchNumber = (i ~/ batchSize) + 1;

          try {
            // Batch fetch from server
            final serverNotes = await _apiClient.batchFetchNotes(
              eventIds: batch,
              deviceId: credentials.deviceId,
              deviceToken: credentials.deviceToken,
            );

            // RACE CONDITION FIX: Check cancellation after fetch completes
            if (isCancelled != null && isCancelled()) {
              return;
            }


            // Step 3: Save each to cache
            for (final noteData in serverNotes) {
              try {
                final note = Note.fromMap(noteData);
                await _cacheManager.saveNote(note.eventId, note);
                loaded++;
              } catch (e) {
              }
            }

            // Report progress after each batch (only if not cancelled)
            if (isCancelled == null || !isCancelled()) {
              onProgress?.call(loaded, eventIds.length);
            }

          } catch (e) {
            // Continue with next batch, don't fail entire preload
          }
        }

        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
      } catch (e) {
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
      }
    });
  }

  /// Sync all dirty notes to server
  /// Returns result object with sync statistics
  Future<BulkSyncResult> syncAllDirtyNotes() async {
    try {

      // Get all dirty notes from database
      final dirtyNotes = await _db.getAllDirtyNotes();

      if (dirtyNotes.isEmpty) {
        return BulkSyncResult(total: 0, success: 0, failed: 0, failedEventIds: []);
      }


      // Get credentials once
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        throw Exception('Device not registered');
      }

      int successCount = 0;
      int failedCount = 0;
      final List<int> failedEventIds = [];

      // Sync each note
      for (final note in dirtyNotes) {
        try {
          await syncNote(note.eventId);
          successCount++;
        } catch (e) {
          failedCount++;
          failedEventIds.add(note.eventId);

          // Check if error is 403 (book ownership issue)
          final errorStr = e.toString();
          if (errorStr.contains('403') || errorStr.contains('Unauthorized')) {
            // Get event and book info for better error message
            try {
              final event = await _db.getEventById(note.eventId);
              if (event != null) {
                final book = await _db.getBookByUuid(event.bookUuid);
                if (book != null) {
                } else {
                }
              }
            } catch (infoError) {
            }
          } else {
          }
          // Continue syncing other notes even if one fails
        }
      }

      final result = BulkSyncResult(
        total: dirtyNotes.length,
        success: successCount,
        failed: failedCount,
        failedEventIds: failedEventIds,
      );

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Sync dirty notes for a specific book
  /// Returns result object with sync statistics
  Future<BulkSyncResult> syncDirtyNotesForBook(String bookUuid) async {
    try {

      // Get dirty notes for this book
      final dirtyNotes = await _db.getDirtyNotesByBookId(bookUuid);

      if (dirtyNotes.isEmpty) {
        return BulkSyncResult(total: 0, success: 0, failed: 0, failedEventIds: []);
      }


      // Get credentials once
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        throw Exception('Device not registered');
      }

      int successCount = 0;
      int failedCount = 0;
      final List<int> failedEventIds = [];

      // Sync each note
      for (final note in dirtyNotes) {
        try {
          await syncNote(note.eventId);
          successCount++;
        } catch (e) {
          failedCount++;
          failedEventIds.add(note.eventId);

          // Check if error is 403 (book ownership issue)
          final errorStr = e.toString();
          if (errorStr.contains('403') || errorStr.contains('Unauthorized')) {
            // Get event and book info for better error message
            try {
              final event = await _db.getEventById(note.eventId);
              if (event != null) {
                final book = await _db.getBookByUuid(event.bookUuid);
                if (book != null) {
                } else {
                }
              }
            } catch (infoError) {
            }
          } else {
          }
          // Continue syncing other notes even if one fails
        }
      }

      final result = BulkSyncResult(
        total: dirtyNotes.length,
        success: successCount,
        failed: failedCount,
        failedEventIds: failedEventIds,
      );

      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ===================
  // Drawings Operations
  // ===================

  /// Get drawing with cache-first strategy
  Future<ScheduleDrawing?> getDrawing({
    required String bookUuid,
    required DateTime date,
    required int viewMode,
    bool forceRefresh = false,
  }) async {
    try {
      // Step 1: Check cache (unless forceRefresh)
      if (!forceRefresh) {
        final cachedDrawing = await _cacheManager.getDrawing(bookUuid, date, viewMode);
        if (cachedDrawing != null) {
          return cachedDrawing;
        }
      }

      // Step 2: Fetch from server
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        return await _cacheManager.getDrawing(bookUuid, date, viewMode);
      }

      final serverDrawing = await _apiClient.fetchDrawing(
        bookUuid: bookUuid,
        date: date,
        viewMode: viewMode,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      if (serverDrawing != null) {
        // Parse and save to cache
        final drawing = ScheduleDrawing.fromMap(serverDrawing);
        await _cacheManager.saveDrawing(drawing);
        return drawing;
      }

      return null;
    } catch (e) {

      // Fallback to cache
      try {
        final cachedDrawing = await _cacheManager.getDrawing(bookUuid, date, viewMode);
        if (cachedDrawing != null) {
          return cachedDrawing;
        }
      } catch (cacheError) {
      }

      return null;
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
  /// RACE CONDITION FIX: Handles version conflicts with retry logic
  Future<void> _saveDrawingInternal(ScheduleDrawing drawing, {int retryCount = 0}) async {
    const maxRetries = 3;

    try {
      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        await _cacheManager.saveDrawing(drawing);
        return;
      }

      // Save to server
      // Transform drawing data to server API format
      // Server expects: { date: "YYYY-MM-DD", viewMode: int, strokesData: string, version?: int }
      final drawingData = drawing.toMap();
      final serverDrawingData = {
        'date': drawing.date.toIso8601String().split('T')[0], // Convert to ISO date string (YYYY-MM-DD)
        'viewMode': drawing.viewMode,
        'strokesData': drawingData['strokes_data'], // Server expects camelCase
        if (drawing.id != null) 'version': drawing.version, // Include current version for updates (optimistic locking)
      };


      final serverResponse = await _apiClient.saveDrawing(
        bookUuid: drawing.bookUuid,
        drawingData: serverDrawingData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      // Update drawing with new version from server response
      final newVersion = serverResponse['version'] as int? ?? drawing.version;
      final updatedDrawing = drawing.copyWith(version: newVersion);

      // Save to cache with updated version
      await _cacheManager.saveDrawing(updatedDrawing);

    } catch (e) {
      // RACE CONDITION FIX: Detect version conflicts and retry with server version
      if (e is ApiConflictException && retryCount < maxRetries) {

        try {
          // Extract server version from 409 response
          final serverVersion = e.serverVersion;

          if (serverVersion != null) {

            // Fetch drawing from cache to preserve metadata (id, createdAt)
            final latestDrawing = await _db.getCachedDrawing(
              drawing.bookUuid,
              drawing.date,
              drawing.viewMode,
            );

            // Last-write-wins: Use server version but keep client strokes
            final mergedDrawing = drawing.copyWith(
              id: latestDrawing?.id,
              version: serverVersion, // Use server version (authoritative)
              createdAt: latestDrawing?.createdAt,
            );


            // Retry with server version
            return await _saveDrawingInternal(mergedDrawing, retryCount: retryCount + 1);
          } else {
          }
        } catch (retryError) {
        }
      }


      // Still save to cache for offline access
      try {
        await _cacheManager.saveDrawing(drawing);
      } catch (cacheError) {
        rethrow;
      }
    }
  }

  /// Delete drawing (from server and cache)
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

      // Delete from cache
      await _cacheManager.deleteDrawing(bookUuid, date, viewMode);

    } catch (e) {
      rethrow;
    }
  }

  /// Preload drawings for a date range (for performance)
  ///
  /// Does not block, returns immediately
  Future<void> preloadDrawings({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
  }) async {

    // Run in background
    Future.microtask(() async {
      try {
        final credentials = await _db.getDeviceCredentials();
        if (credentials == null) return;

        final serverDrawings = await _apiClient.batchFetchDrawings(
          bookUuid: bookUuid,
          startDate: startDate,
          endDate: endDate,
          deviceId: credentials.deviceId,
          deviceToken: credentials.deviceToken,
        );

        // Save each to cache
        for (final drawingData in serverDrawings) {
          try {
            final drawing = ScheduleDrawing.fromMap(drawingData);
            await _cacheManager.saveDrawing(drawing);
          } catch (e) {
          }
        }

      } catch (e) {
      }
    });
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
