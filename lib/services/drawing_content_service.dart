import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/schedule_drawing.dart';
import '../repositories/drawing_repository.dart';
import '../repositories/drawing_repository_impl.dart';
import '../repositories/device_repository.dart';
import 'api_client.dart';

/// DrawingContentService - Manages schedule drawings with cache-first strategy
///
/// Responsibilities:
/// - Fetch drawings from cache or server
/// - Save drawings with race condition prevention (queued saves)
/// - Delete drawings from cache and server
/// - Preload drawings for performance
class DrawingContentService {
  final ApiClient _apiClient;
  final IDrawingRepository _drawingRepository;
  final IDeviceRepository _deviceRepository;

  // RACE CONDITION FIX: Save operation queue to serialize drawing saves
  final List<Future<void> Function()> _drawingSaveQueue = [];
  bool _isProcessingDrawingSaveQueue = false;

  DrawingContentService(
    this._apiClient,
    this._drawingRepository,
    this._deviceRepository,
  );

  // ===================
  // Get Operations
  // ===================

  /// Get drawing with cache-first strategy
  ///
  /// Flow:
  /// 1. Check cache → if exists → return
  /// 2. Fetch from server:
  ///    - Success → update cache → return
  ///    - Failure → return cached (if exists) or null
  ///
  /// [forceRefresh] skips cache and forces server fetch
  Future<ScheduleDrawing?> getDrawing({
    required int bookId,
    required DateTime date,
    required int viewMode,
    bool forceRefresh = false,
  }) async {
    try {
      // Step 1: Check cache (unless forceRefresh)
      if (!forceRefresh) {
        final cachedDrawing = await (_drawingRepository as DrawingRepositoryImpl)
            .getCachedWithViewMode(bookId, date, viewMode);
        if (cachedDrawing != null) {
          debugPrint('✅ DrawingContentService: Drawing cache hit (bookId: $bookId, date: $date, viewMode: $viewMode)');
          return cachedDrawing;
        }
        debugPrint('ℹ️ DrawingContentService: Drawing cache miss');
      }

      // Step 2: Fetch from server
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        debugPrint('⚠️ DrawingContentService: Device not registered, cannot fetch drawing');
        return await (_drawingRepository as DrawingRepositoryImpl)
            .getCachedWithViewMode(bookId, date, viewMode);
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
        await _drawingRepository.saveToCache(drawing, isDirty: false);
        debugPrint('✅ DrawingContentService: Drawing fetched from server and cached');
        return drawing;
      }

      debugPrint('ℹ️ DrawingContentService: Drawing not found on server');
      return null;
    } catch (e) {
      debugPrint('❌ DrawingContentService: Error fetching drawing: $e');

      // Fallback to cache
      try {
        final cachedDrawing = await (_drawingRepository as DrawingRepositoryImpl)
            .getCachedWithViewMode(bookId, date, viewMode);
        if (cachedDrawing != null) {
          debugPrint('⚠️ DrawingContentService: Returning cached drawing after server error');
          return cachedDrawing;
        }
      } catch (cacheError) {
        debugPrint('❌ DrawingContentService: Cache fallback also failed: $cacheError');
      }

      return null;
    }
  }

  // ===================
  // Save Operations
  // ===================

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

    // Process queue
    _processDrawingSaveQueue();

    return completer.future;
  }

  /// Process the drawing save queue (one operation at a time)
  void _processDrawingSaveQueue() {
    if (_isProcessingDrawingSaveQueue) return;
    if (_drawingSaveQueue.isEmpty) return;

    _isProcessingDrawingSaveQueue = true;

    Future(() async {
      while (_drawingSaveQueue.isNotEmpty) {
        final operation = _drawingSaveQueue.removeAt(0);
        try {
          await operation();
        } catch (e) {
          debugPrint('❌ DrawingContentService: Queue operation failed: $e');
        }
      }
      _isProcessingDrawingSaveQueue = false;
    });
  }

  /// Internal save drawing implementation (called from queue)
  /// RACE CONDITION FIX: Handles version conflicts with retry logic
  Future<void> _saveDrawingInternal(ScheduleDrawing drawing, {int retryCount = 0}) async {
    const maxRetries = 3;

    try {
      // Get credentials
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        debugPrint('⚠️ DrawingContentService: Device not registered, saving drawing to cache only');
        await _drawingRepository.saveToCache(drawing, isDirty: true);
        return;
      }

      // Save to server
      final serverDrawingData = {
        'date': drawing.date.toIso8601String(),
        'viewMode': drawing.viewMode,
        'strokesData': drawing.toMap()['strokes_data'],
        if (drawing.id != null) 'version': drawing.version,
      };

      debugPrint('📤 DrawingContentService: Saving drawing (bookId: ${drawing.bookId}, version: ${drawing.version}, retry: $retryCount)');

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
      await _drawingRepository.saveToCache(updatedDrawing, isDirty: false);

      debugPrint('✅ DrawingContentService: Drawing saved to server (version: $newVersion) and cached');
    } catch (e) {
      // RACE CONDITION FIX: Detect version conflicts and retry with server version
      if (e is ApiConflictException && retryCount < maxRetries) {
        debugPrint('⚠️ DrawingContentService: Version conflict detected, fetching server version...');

        try {
          // Get credentials for retry
          final retryCredentials = await _deviceRepository.getCredentials();
          if (retryCredentials == null) {
            debugPrint('⚠️ DrawingContentService: Device not registered, cannot retry');
            return;
          }

          // Fetch current server version
          final serverDrawingMap = await _apiClient.fetchDrawing(
            bookId: drawing.bookId,
            date: drawing.date,
            viewMode: drawing.viewMode,
            deviceId: retryCredentials.deviceId,
            deviceToken: retryCredentials.deviceToken,
          );

          if (serverDrawingMap != null && serverDrawingMap['version'] != null) {
            final serverVersion = serverDrawingMap['version'] as int;
            final serverDrawing = ScheduleDrawing.fromMap(serverDrawingMap);

            // Merge: combine server strokes with new strokes
            final mergedDrawing = ScheduleDrawing(
              id: serverDrawing.id,
              bookId: drawing.bookId,
              date: drawing.date,
              viewMode: drawing.viewMode,
              strokes: [...serverDrawing.strokes, ...drawing.strokes],
              version: serverVersion,
              createdAt: serverDrawing.createdAt,
              updatedAt: DateTime.now(),
            );

            debugPrint('🔄 DrawingContentService: Retrying with server version: $serverVersion');

            // Retry with server version
            return await _saveDrawingInternal(mergedDrawing, retryCount: retryCount + 1);
          } else {
            debugPrint('⚠️ DrawingContentService: Server version not available in conflict response');
          }
        } catch (retryError) {
          debugPrint('❌ DrawingContentService: Failed to prepare retry: $retryError');
        }
      }

      debugPrint('❌ DrawingContentService: Error saving drawing to server: $e');

      // Still save to cache for offline access
      try {
        await _drawingRepository.saveToCache(drawing, isDirty: true);
        debugPrint('⚠️ DrawingContentService: Drawing saved to cache only (offline mode)');
      } catch (cacheError) {
        debugPrint('❌ DrawingContentService: Failed to save drawing to cache: $cacheError');
        rethrow;
      }
    }
  }

  // ===================
  // Delete Operations
  // ===================

  /// Delete drawing (from server and cache)
  Future<void> deleteDrawing({
    required int bookId,
    required DateTime date,
    required int viewMode,
  }) async {
    try {
      // Get credentials
      final credentials = await _deviceRepository.getCredentials();
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
      await (_drawingRepository as DrawingRepositoryImpl)
          .deleteCacheWithViewMode(bookId, date, viewMode);

      debugPrint('✅ DrawingContentService: Drawing deleted');
    } catch (e) {
      debugPrint('❌ DrawingContentService: Error deleting drawing: $e');
      rethrow;
    }
  }

  // ===================
  // Batch Operations
  // ===================

  /// Preload drawings for a date range (for performance)
  ///
  /// Does not block, returns immediately
  Future<void> preloadDrawings({
    required int bookId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    debugPrint('🔄 DrawingContentService: Preloading drawings from $startDate to $endDate...');

    try {
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        debugPrint('⚠️ DrawingContentService: Device not registered, skipping preload');
        return;
      }

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
          await _drawingRepository.saveToCache(drawing, isDirty: false);
        } catch (e) {
          debugPrint('⚠️ DrawingContentService: Failed to preload drawing: $e');
        }
      }

      debugPrint('✅ DrawingContentService: Preloaded ${serverDrawings.length} drawings');
    } catch (e) {
      debugPrint('❌ DrawingContentService: Preload error: $e');
      // Don't throw - preload is best-effort
    }
  }
}
