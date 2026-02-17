import 'dart:async';
import '../models/schedule_drawing.dart';
import '../repositories/device_repository.dart';
import 'api_client.dart';

/// DrawingContentService - Manages schedule drawings with server-only strategy
///
/// Responsibilities:
/// - Fetch drawings from server
/// - Save drawings with race condition prevention (queued saves)
/// - Delete drawings from server
class DrawingContentService {
  final ApiClient _apiClient;
  final IDeviceRepository _deviceRepository;

  // RACE CONDITION FIX: Save operation queue to serialize drawing saves
  final List<Future<void> Function()> _drawingSaveQueue = [];
  bool _isProcessingDrawingSaveQueue = false;

  DrawingContentService(this._apiClient, this._deviceRepository);

  // ===================
  // Get Operations
  // ===================

  /// Get drawing from server.
  /// [forceRefresh] is kept for compatibility and ignored in server-only mode.
  Future<ScheduleDrawing?> getDrawing({
    required String bookUuid,
    required DateTime date,
    required int viewMode,
    bool forceRefresh = false,
  }) async {
    try {
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        throw Exception('Device not registered');
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
      rethrow;
    }
  }

  // ===================
  // Save Operations
  // ===================

  /// Save drawing to server
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
        } catch (e) {}
      }
      _isProcessingDrawingSaveQueue = false;
    });
  }

  /// Internal save drawing implementation (called from queue)
  /// RACE CONDITION FIX: Handles version conflicts with retry logic
  Future<void> _saveDrawingInternal(
    ScheduleDrawing drawing, {
    int retryCount = 0,
  }) async {
    const maxRetries = 3;

    try {
      // Get credentials
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        throw Exception('Device not registered');
      }

      // Save to server
      final serverDrawingData = {
        'date': drawing.date.toIso8601String(),
        'viewMode': drawing.viewMode,
        'strokesData': drawing.toMap()['strokes_data'],
        if (drawing.id != null) 'version': drawing.version,
      };

      await _apiClient.saveDrawing(
        bookUuid: drawing.bookUuid,
        drawingData: serverDrawingData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      // Keep server call for authoritative write; no local cache state is stored.
    } catch (e) {
      // RACE CONDITION FIX: Detect version conflicts and retry with server version
      if (e is ApiConflictException && retryCount < maxRetries) {
        try {
          // Get credentials for retry
          final retryCredentials = await _deviceRepository.getCredentials();
          if (retryCredentials == null) {
            return;
          }

          // Fetch current server version
          final serverDrawingMap = await _apiClient.fetchDrawing(
            bookUuid: drawing.bookUuid,
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
              bookUuid: drawing.bookUuid,
              date: drawing.date,
              viewMode: drawing.viewMode,
              strokes: [...serverDrawing.strokes, ...drawing.strokes],
              version: serverVersion,
              createdAt: serverDrawing.createdAt,
              updatedAt: DateTime.now(),
            );

            // Retry with server version
            return await _saveDrawingInternal(
              mergedDrawing,
              retryCount: retryCount + 1,
            );
          }
        } catch (retryError) {}
      }
      rethrow;
    }
  }

  // ===================
  // Delete Operations
  // ===================

  /// Delete drawing from server.
  Future<void> deleteDrawing({
    required String bookUuid,
    required DateTime date,
    required int viewMode,
  }) async {
    try {
      // Get credentials
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        throw Exception('Device not registered');
      }
      // Delete from server
      await _apiClient.deleteDrawing(
        bookUuid: bookUuid,
        date: date,
        viewMode: viewMode,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
    } catch (e) {
      rethrow;
    }
  }

  // ===================
  // Batch Operations
  // ===================

  /// Preload drawings is disabled in server-only mode.
  Future<void> preloadDrawings({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
  }) async {}
}
