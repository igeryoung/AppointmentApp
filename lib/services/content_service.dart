import 'package:flutter/foundation.dart';
import '../models/note.dart';
import '../models/schedule_drawing.dart';
import 'api_client.dart';

/// ContentService - Unified content management with cache-first strategy
///
/// Handles Notes and Drawings with intelligent caching and network fallback
///
/// Architecture:
///   Screen → ContentService → ApiClient + CacheManager
///                             ^^^^^^^^^^^^^^^^^^^^
///                             Hide complexity from UI
///
/// Linus说: "Abstraction layers should hide complexity, not add it."
class ContentService {
  final ApiClient _apiClient;
  final dynamic _cacheManager;  // CacheManager or mock
  final dynamic _db;  // PRDDatabaseService or mock

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
      debugPrint('❌ ContentService: Health check failed: $e');
      return false;
    }
  }

  // ===================
  // Notes Operations
  // ===================

  /// Get note from cache only (no network call)
  ///
  /// Returns cached note immediately without checking server
  /// Used for instant display in cache-first strategy
  Future<Note?> getCachedNote(int eventId) async {
    try {
      final cachedNote = await _cacheManager.getNote(eventId);
      if (cachedNote != null) {
        debugPrint('✅ ContentService: Cache-only note retrieved (eventId: $eventId, isDirty: ${cachedNote.isDirty})');
      } else {
        debugPrint('ℹ️ ContentService: No cached note found (eventId: $eventId)');
      }
      return cachedNote;
    } catch (e) {
      debugPrint('❌ ContentService: Error getting cached note: $e');
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
  Future<Note?> getNote(int eventId, {bool forceRefresh = false}) async {
    try {
      // Step 1: Check cache (unless forceRefresh)
      if (!forceRefresh) {
        final cachedNote = await _cacheManager.getNote(eventId);
        if (cachedNote != null) {
          debugPrint('✅ ContentService: Note cache hit (eventId: $eventId)');
          return cachedNote;
        }
        debugPrint('ℹ️ ContentService: Note cache miss (eventId: $eventId)');
      }

      // Step 2: Fetch from server
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        debugPrint('⚠️ ContentService: Device not registered, cannot fetch from server');
        // Return cache if available
        return await _cacheManager.getNote(eventId);
      }

      // Get bookId for the event
      final event = await _db.getEventById(eventId);
      if (event == null) {
        debugPrint('⚠️ ContentService: Event $eventId not found');
        return null;
      }

      final serverNote = await _apiClient.fetchNote(
        bookId: event.bookId,
        eventId: eventId,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      if (serverNote != null) {
        // Parse and save to cache
        final note = Note.fromMap(serverNote);
        await _cacheManager.saveNote(eventId, note);
        debugPrint('✅ ContentService: Note fetched from server and cached (eventId: $eventId)');
        return note;
      }

      debugPrint('ℹ️ ContentService: Note not found on server (eventId: $eventId)');
      return null;
    } catch (e) {
      debugPrint('❌ ContentService: Error fetching note (eventId: $eventId): $e');

      // Fallback to cache on error
      try {
        final cachedNote = await _cacheManager.getNote(eventId);
        if (cachedNote != null) {
          debugPrint('⚠️ ContentService: Returning cached note after server error');
          return cachedNote;
        }
      } catch (cacheError) {
        debugPrint('❌ ContentService: Cache fallback also failed: $cacheError');
      }

      return null;
    }
  }

  /// Save note locally only (always succeeds unless disk full)
  /// Server sync should be handled separately by caller via syncNote()
  ///
  /// **Data Safety First Principle**: Local save is guaranteed,
  /// server sync is handled separately in background (best effort)
  Future<void> saveNote(int eventId, Note note) async {
    // **数据安全第一原则**: 只保存到本地 (标记为dirty)
    // Server sync由调用者通过 syncNote() 单独处理（后台best effort）
    await _cacheManager.saveNote(eventId, note, dirty: true);
    debugPrint('✅ ContentService: Note saved locally (eventId: $eventId, marked dirty)');

    // Note: 不在这里同步到server！调用者会通过 _syncNoteInBackground() 处理
    // 这样可以保证本地保存永远不会因为网络错误而失败
  }

  /// Force sync a note to server (clears dirty flag on success)
  ///
  /// Throws exception on sync failure, keeps dirty flag intact
  Future<void> syncNote(int eventId) async {
    try {
      final note = await _cacheManager.getNote(eventId);
      if (note == null) {
        debugPrint('⚠️ ContentService: Cannot sync - note $eventId not found in cache');
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
        'strokesData': noteMap['strokes_data'],
      };

      // Include event data for auto-creation on server if event doesn't exist
      final eventData = event.toMap();

      await _apiClient.saveNote(
        bookId: event.bookId,
        eventId: eventId,
        noteData: noteData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
        eventData: eventData,
      );

      // 同步成功，清除dirty标记
      await _cacheManager.markNoteClean(eventId);

      debugPrint('✅ ContentService: Note synced to server (eventId: $eventId, dirty flag cleared)');
    } catch (e) {
      debugPrint('❌ ContentService: Sync failed for note $eventId: $e');
      // 保留dirty标记，稍后重试
      rethrow;
    }
  }

  /// Delete note (from server and cache)
  Future<void> deleteNote(int eventId) async {
    try {
      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials != null) {
        // Get bookId
        final event = await _db.getEventById(eventId);
        if (event != null) {
          // Delete from server
          await _apiClient.deleteNote(
            bookId: event.bookId,
            eventId: eventId,
            deviceId: credentials.deviceId,
            deviceToken: credentials.deviceToken,
          );
        }
      }

      // Delete from cache
      await _cacheManager.deleteNote(eventId);

      debugPrint('✅ ContentService: Note deleted (eventId: $eventId)');
    } catch (e) {
      debugPrint('❌ ContentService: Error deleting note: $e');
      rethrow;
    }
  }

  /// Preload multiple notes in background (for performance)
  ///
  /// Does not block, returns immediately
  /// Failures are logged but don't throw
  Future<void> preloadNotes(List<int> eventIds) async {
    if (eventIds.isEmpty) return;

    debugPrint('🔄 ContentService: Preloading ${eventIds.length} notes...');

    // Run in background, don't block caller
    Future.microtask(() async {
      try {
        final credentials = await _db.getDeviceCredentials();
        if (credentials == null) return;

        final serverNotes = await _apiClient.batchFetchNotes(
          eventIds: eventIds,
          deviceId: credentials.deviceId,
          deviceToken: credentials.deviceToken,
        );

        // Save each to cache
        for (final noteData in serverNotes) {
          try {
            final note = Note.fromMap(noteData);
            final eventId = note.eventId;
            await _cacheManager.saveNote(eventId, note);
          } catch (e) {
            debugPrint('⚠️ ContentService: Failed to preload note: $e');
          }
        }

        debugPrint('✅ ContentService: Preloaded ${serverNotes.length} notes');
      } catch (e) {
        debugPrint('❌ ContentService: Preload notes failed: $e');
      }
    });
  }

  /// Sync all dirty notes to server
  /// Returns result object with sync statistics
  Future<BulkSyncResult> syncAllDirtyNotes() async {
    try {
      debugPrint('🔄 ContentService: Starting bulk sync of all dirty notes...');

      // Get all dirty notes from database
      final dirtyNotes = await _db.getAllDirtyNotes();

      if (dirtyNotes.isEmpty) {
        debugPrint('✅ ContentService: No dirty notes to sync');
        return BulkSyncResult(total: 0, success: 0, failed: 0, failedEventIds: []);
      }

      debugPrint('🔄 ContentService: Found ${dirtyNotes.length} dirty notes to sync');

      // Get credentials once
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        debugPrint('❌ ContentService: Device not registered, cannot sync');
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
          debugPrint('✅ ContentService: Synced note ${note.eventId} ($successCount/${dirtyNotes.length})');
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
                final book = await _db.getBookById(event.bookId);
                if (book != null) {
                  debugPrint('❌ ContentService: Failed to sync note ${note.eventId}: Book "${book.name}" (UUID: ${book.uuid}) not found on server.');
                  debugPrint('   → SOLUTION: Backup the book "${book.name}" to sync it to the server, then notes will sync automatically.');
                } else {
                  debugPrint('❌ ContentService: Failed to sync note ${note.eventId}: Book not found on server. Please backup the book first.');
                }
              }
            } catch (infoError) {
              debugPrint('❌ ContentService: Failed to sync note ${note.eventId}: Book not found on server. Please backup the book first.');
            }
          } else {
            debugPrint('❌ ContentService: Failed to sync note ${note.eventId}: $e');
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

      debugPrint('✅ ContentService: Bulk sync complete - ${result.success}/${result.total} succeeded, ${result.failed} failed');
      return result;
    } catch (e) {
      debugPrint('❌ ContentService: Bulk sync failed: $e');
      rethrow;
    }
  }

  /// Sync dirty notes for a specific book
  /// Returns result object with sync statistics
  Future<BulkSyncResult> syncDirtyNotesForBook(int bookId) async {
    try {
      debugPrint('🔄 ContentService: Starting bulk sync for book $bookId...');

      // Get dirty notes for this book
      final dirtyNotes = await _db.getDirtyNotesByBookId(bookId);

      if (dirtyNotes.isEmpty) {
        debugPrint('✅ ContentService: No dirty notes to sync for book $bookId');
        return BulkSyncResult(total: 0, success: 0, failed: 0, failedEventIds: []);
      }

      debugPrint('🔄 ContentService: Found ${dirtyNotes.length} dirty notes to sync for book $bookId');

      // Get credentials once
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        debugPrint('❌ ContentService: Device not registered, cannot sync');
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
          debugPrint('✅ ContentService: Synced note ${note.eventId} ($successCount/${dirtyNotes.length})');
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
                final book = await _db.getBookById(event.bookId);
                if (book != null) {
                  debugPrint('❌ ContentService: Failed to sync note ${note.eventId}: Book "${book.name}" (UUID: ${book.uuid}) not found on server.');
                  debugPrint('   → SOLUTION: Backup the book "${book.name}" to sync it to the server, then notes will sync automatically.');
                } else {
                  debugPrint('❌ ContentService: Failed to sync note ${note.eventId}: Book not found on server. Please backup the book first.');
                }
              }
            } catch (infoError) {
              debugPrint('❌ ContentService: Failed to sync note ${note.eventId}: Book not found on server. Please backup the book first.');
            }
          } else {
            debugPrint('❌ ContentService: Failed to sync note ${note.eventId}: $e');
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

      debugPrint('✅ ContentService: Bulk sync complete for book $bookId - ${result.success}/${result.total} succeeded, ${result.failed} failed');
      return result;
    } catch (e) {
      debugPrint('❌ ContentService: Bulk sync for book $bookId failed: $e');
      rethrow;
    }
  }

  // ===================
  // Drawings Operations
  // ===================

  /// Get drawing with cache-first strategy
  Future<ScheduleDrawing?> getDrawing({
    required int bookId,
    required DateTime date,
    required int viewMode,
    bool forceRefresh = false,
  }) async {
    try {
      // Step 1: Check cache (unless forceRefresh)
      if (!forceRefresh) {
        final cachedDrawing = await _cacheManager.getDrawing(bookId, date, viewMode);
        if (cachedDrawing != null) {
          debugPrint('✅ ContentService: Drawing cache hit (bookId: $bookId, date: $date, viewMode: $viewMode)');
          return cachedDrawing;
        }
        debugPrint('ℹ️ ContentService: Drawing cache miss');
      }

      // Step 2: Fetch from server
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        debugPrint('⚠️ ContentService: Device not registered, cannot fetch drawing');
        return await _cacheManager.getDrawing(bookId, date, viewMode);
      }

      final serverDrawing = await _apiClient.fetchDrawing(
        bookId: bookId,
        date: date,
        viewMode: viewMode,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      if (serverDrawing != null) {
        // Parse and save to cache
        final drawing = ScheduleDrawing.fromMap(serverDrawing);
        await _cacheManager.saveDrawing(drawing);
        debugPrint('✅ ContentService: Drawing fetched from server and cached');
        return drawing;
      }

      debugPrint('ℹ️ ContentService: Drawing not found on server');
      return null;
    } catch (e) {
      debugPrint('❌ ContentService: Error fetching drawing: $e');

      // Fallback to cache
      try {
        final cachedDrawing = await _cacheManager.getDrawing(bookId, date, viewMode);
        if (cachedDrawing != null) {
          debugPrint('⚠️ ContentService: Returning cached drawing after server error');
          return cachedDrawing;
        }
      } catch (cacheError) {
        debugPrint('❌ ContentService: Cache fallback failed: $cacheError');
      }

      return null;
    }
  }

  /// Save drawing (update server and cache)
  Future<void> saveDrawing(ScheduleDrawing drawing) async {
    try {
      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials == null) {
        debugPrint('⚠️ ContentService: Device not registered, saving drawing to cache only');
        await _cacheManager.saveDrawing(drawing);
        return;
      }

      // Save to server
      final drawingData = drawing.toMap();

      await _apiClient.saveDrawing(
        bookId: drawing.bookId,
        drawingData: drawingData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      // Save to cache
      await _cacheManager.saveDrawing(drawing);

      debugPrint('✅ ContentService: Drawing saved to server and cache');
    } catch (e) {
      debugPrint('❌ ContentService: Error saving drawing to server: $e');

      // Still save to cache for offline access
      try {
        await _cacheManager.saveDrawing(drawing);
        debugPrint('⚠️ ContentService: Drawing saved to cache only (offline mode)');
      } catch (cacheError) {
        debugPrint('❌ ContentService: Failed to save drawing to cache: $cacheError');
        rethrow;
      }
    }
  }

  /// Delete drawing (from server and cache)
  Future<void> deleteDrawing({
    required int bookId,
    required DateTime date,
    required int viewMode,
  }) async {
    try {
      // Get credentials
      final credentials = await _db.getDeviceCredentials();
      if (credentials != null) {
        // Delete from server
        await _apiClient.deleteDrawing(
          bookId: bookId,
          date: date,
          viewMode: viewMode,
          deviceId: credentials.deviceId,
          deviceToken: credentials.deviceToken,
        );
      }

      // Delete from cache
      await _cacheManager.deleteDrawing(bookId, date, viewMode);

      debugPrint('✅ ContentService: Drawing deleted');
    } catch (e) {
      debugPrint('❌ ContentService: Error deleting drawing: $e');
      rethrow;
    }
  }

  /// Preload drawings for a date range (for performance)
  ///
  /// Does not block, returns immediately
  Future<void> preloadDrawings({
    required int bookId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    debugPrint('🔄 ContentService: Preloading drawings from $startDate to $endDate...');

    // Run in background
    Future.microtask(() async {
      try {
        final credentials = await _db.getDeviceCredentials();
        if (credentials == null) return;

        final serverDrawings = await _apiClient.batchFetchDrawings(
          bookId: bookId,
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
            debugPrint('⚠️ ContentService: Failed to preload drawing: $e');
          }
        }

        debugPrint('✅ ContentService: Preloaded ${serverDrawings.length} drawings');
      } catch (e) {
        debugPrint('❌ ContentService: Preload drawings failed: $e');
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
