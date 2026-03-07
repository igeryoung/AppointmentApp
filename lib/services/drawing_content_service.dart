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
  final List<Future<ScheduleDrawing> Function()> _drawingSaveQueue = [];
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
  Future<ScheduleDrawing> saveDrawing(ScheduleDrawing drawing) async {
    // Create a completer to wait for the queued operation to complete
    final completer = Completer<ScheduleDrawing>();

    // Add save operation to queue
    _drawingSaveQueue.add(() async {
      try {
        final savedDrawing = await _saveDrawingInternal(drawing);
        completer.complete(savedDrawing);
        return savedDrawing;
      } catch (e) {
        completer.completeError(e);
        rethrow;
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
  Future<ScheduleDrawing> _saveDrawingInternal(
    ScheduleDrawing drawing, {
    int retryCount = 0,
  }) async {
    const maxRetries = 2;

    try {
      // Get credentials
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        throw Exception('Device not registered');
      }

      // Save to server
      final serverDrawingData = {
        'date': drawing.date.toIso8601String().split('T')[0],
        'viewMode': drawing.viewMode,
        'strokesData': drawing.toMap()['strokes_data'],
        'version': drawing.version,
      };

      final saved = await _apiClient.saveDrawing(
        bookUuid: drawing.bookUuid,
        drawingData: serverDrawingData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
      return ScheduleDrawing.fromMap(saved);

      // Keep server call for authoritative write; no local cache state is stored.
    } on ApiConflictException catch (e) {
      if (retryCount >= maxRetries) {
        rethrow;
      }

      int? serverVersion = e.serverVersion;
      int? serverId = (e.serverDrawing?['id'] as num?)?.toInt();
      DateTime? serverCreatedAt;
      final serverCreatedAtRaw = e.serverDrawing?['createdAt'];
      if (serverCreatedAtRaw is String) {
        serverCreatedAt = DateTime.tryParse(serverCreatedAtRaw)?.toUtc();
      }

      // Fallback to fresh read when conflict payload has no version.
      if (serverVersion == null) {
        final retryCredentials = await _deviceRepository.getCredentials();
        if (retryCredentials == null) {
          rethrow;
        }
        final serverDrawingMap = await _apiClient.fetchDrawing(
          bookUuid: drawing.bookUuid,
          date: drawing.date,
          viewMode: drawing.viewMode,
          deviceId: retryCredentials.deviceId,
          deviceToken: retryCredentials.deviceToken,
        );
        if (serverDrawingMap == null || serverDrawingMap['version'] == null) {
          rethrow;
        }
        serverVersion = (serverDrawingMap['version'] as num).toInt();
        serverId = (serverDrawingMap['id'] as num?)?.toInt();
        final fetchedCreatedAt = serverDrawingMap['createdAt'];
        if (fetchedCreatedAt is String) {
          serverCreatedAt = DateTime.tryParse(fetchedCreatedAt)?.toUtc();
        }
      }

      // LWW retry: keep local strokes, only advance to serverVersion + 1.
      final retryDrawing = drawing.copyWith(
        id: drawing.id ?? serverId,
        createdAt: serverCreatedAt ?? drawing.createdAt,
        version: serverVersion + 1,
        updatedAt: DateTime.now(),
      );
      return _saveDrawingInternal(retryDrawing, retryCount: retryCount + 1);
    } catch (e) {
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
