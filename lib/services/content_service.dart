import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/note.dart';
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
    List<int> eventIds, {
    Function(int loaded, int total)? onProgress,
    int? generation,
    bool Function()? isCancelled,
  }) async {
    if (eventIds.isEmpty) {
      onProgress?.call(0, 0);
      return;
    }

    final startTime = DateTime.now();
    debugPrint('🔄 ContentService: [${startTime.toIso8601String()}] Preload STARTED for ${eventIds.length} notes (generation=$generation) [eventIds: ${eventIds.join(', ')}]');

    // Run in background, don't block caller
    Future.microtask(() async {
      try {
        // RACE CONDITION FIX: Check if cancelled before starting
        if (isCancelled != null && isCancelled()) {
          debugPrint('🚫 ContentService: Preload cancelled before starting (generation=$generation)');
          return;
        }

        // Step 1: Filter out already-cached notes
        debugPrint('📦 ContentService: Checking cache for ${eventIds.length} notes...');
        final uncachedIds = <int>[];
        for (final id in eventIds) {
          // RACE CONDITION FIX: Check cancellation during cache lookup
          if (isCancelled != null && isCancelled()) {
            debugPrint('🚫 ContentService: Preload cancelled during cache check (generation=$generation)');
            return;
          }

          final cached = await _cacheManager.getNote(id);
          if (cached == null) {
            uncachedIds.add(id);
          }
        }

        if (uncachedIds.isEmpty) {
          debugPrint('✅ ContentService: All ${eventIds.length} notes already cached - preload complete (generation=$generation)');
          if (isCancelled == null || !isCancelled()) {
            onProgress?.call(eventIds.length, eventIds.length);
          }
          return;
        }

        debugPrint('📦 ContentService: Found ${eventIds.length - uncachedIds.length} cached, ${uncachedIds.length} uncached');
        debugPrint('🔄 ContentService: Need to fetch ${uncachedIds.length} notes from server: [${uncachedIds.join(', ')}]');

        // Get credentials once
        debugPrint('🔐 ContentService: Checking device credentials...');
        final credentials = await _db.getDeviceCredentials();
        if (credentials == null) {
          debugPrint('❌ ContentService: Device not registered, cannot preload from server');
          debugPrint('   → Register device to enable preloading');
          if (isCancelled == null || !isCancelled()) {
            onProgress?.call(eventIds.length - uncachedIds.length, eventIds.length);
          }
          return;
        }
        debugPrint('✅ ContentService: Device credentials found (deviceId: ${credentials.deviceId.substring(0, 8)}...)');

        // Step 2: Batch fetch (max 50 per request to avoid timeout)
        const batchSize = 50;
        int loaded = eventIds.length - uncachedIds.length; // Already cached
        final totalBatches = (uncachedIds.length / batchSize).ceil();

        debugPrint('🌐 ContentService: Starting batch fetch (${uncachedIds.length} notes in $totalBatches batch${totalBatches > 1 ? 'es' : ''})');

        for (int i = 0; i < uncachedIds.length; i += batchSize) {
          // RACE CONDITION FIX: Check cancellation before each batch
          if (isCancelled != null && isCancelled()) {
            debugPrint('🚫 ContentService: Preload cancelled during batch processing (generation=$generation)');
            return;
          }

          final batch = uncachedIds.skip(i).take(batchSize).toList();
          final batchNumber = (i ~/ batchSize) + 1;

          try {
            // Batch fetch from server
            debugPrint('🌐 ContentService: Calling POST /api/notes/batch for batch $batchNumber/${totalBatches} (${batch.length} notes: [${batch.join(', ')}])');
            final serverNotes = await _apiClient.batchFetchNotes(
              eventIds: batch,
              deviceId: credentials.deviceId,
              deviceToken: credentials.deviceToken,
            );

            // RACE CONDITION FIX: Check cancellation after fetch completes
            if (isCancelled != null && isCancelled()) {
              debugPrint('🚫 ContentService: Preload cancelled after batch fetch (generation=$generation)');
              return;
            }

            debugPrint('✅ ContentService: Batch API returned ${serverNotes.length} notes');

            // Step 3: Save each to cache
            for (final noteData in serverNotes) {
              try {
                final note = Note.fromMap(noteData);
                await _cacheManager.saveNote(note.eventId, note, dirty: false);
                loaded++;
              } catch (e) {
                debugPrint('⚠️ ContentService: Failed to parse/save note: $e');
              }
            }

            // Report progress after each batch (only if not cancelled)
            if (isCancelled == null || !isCancelled()) {
              onProgress?.call(loaded, eventIds.length);
            }

            debugPrint('✅ ContentService: Batch $batchNumber/${totalBatches} completed ($loaded/${eventIds.length} total)');
          } catch (e) {
            debugPrint('❌ ContentService: Batch $batchNumber fetch failed (skipping): $e');
            // Continue with next batch, don't fail entire preload
          }
        }

        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        debugPrint('✅ ContentService: Preload COMPLETED - $loaded/${eventIds.length} notes loaded in ${duration.inMilliseconds}ms (generation=$generation)');
      } catch (e) {
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        debugPrint('❌ ContentService: Preload FAILED after ${duration.inMilliseconds}ms (generation=$generation): $e');
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
          debugPrint('❌ ContentService: Queue save operation failed: $e');
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
        debugPrint('⚠️ ContentService: Device not registered, saving drawing to cache only');
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

      debugPrint('📤 ContentService: Saving drawing (bookId: ${drawing.bookId}, version: ${drawing.version}, retry: $retryCount)');

      final serverResponse = await _apiClient.saveDrawing(
        bookId: drawing.bookId,
        drawingData: serverDrawingData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      // Update drawing with new version from server response
      final newVersion = serverResponse['version'] as int? ?? drawing.version;
      final updatedDrawing = drawing.copyWith(version: newVersion);

      // Save to cache with updated version
      await _cacheManager.saveDrawing(updatedDrawing);

      debugPrint('✅ ContentService: Drawing saved to server (version: $newVersion) and cached');
    } catch (e) {
      // RACE CONDITION FIX: Detect version conflicts and retry with server version
      if (e is ApiConflictException && retryCount < maxRetries) {
        debugPrint('⚠️ ContentService: Version conflict detected (attempt ${retryCount + 1}/$maxRetries)');

        try {
          // Extract server version from 409 response
          final serverVersion = e.serverVersion;

          if (serverVersion != null) {
            debugPrint('   Server version: $serverVersion, Client version: ${drawing.version}');

            // Fetch drawing from cache to preserve metadata (id, createdAt)
            final latestDrawing = await _db.getCachedDrawing(
              drawing.bookId,
              drawing.date,
              drawing.viewMode,
            );

            // Last-write-wins: Use server version but keep client strokes
            final mergedDrawing = drawing.copyWith(
              id: latestDrawing?.id,
              version: serverVersion, // Use server version (authoritative)
              createdAt: latestDrawing?.createdAt,
            );

            debugPrint('🔄 ContentService: Retrying with server version: $serverVersion');

            // Retry with server version
            return await _saveDrawingInternal(mergedDrawing, retryCount: retryCount + 1);
          } else {
            debugPrint('⚠️ ContentService: Server version not available in conflict response');
          }
        } catch (retryError) {
          debugPrint('❌ ContentService: Failed to prepare retry: $retryError');
        }
      }

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
