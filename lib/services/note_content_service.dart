import '../models/note.dart';
import '../repositories/event_repository.dart';
import '../repositories/device_repository.dart';
import 'api_client.dart';

/// NoteContentService - Manages note content with server-only strategy
///
/// Responsibilities:
/// - Fetch notes from server
/// - Delete notes on server
class NoteContentService {
  final ApiClient _apiClient;
  final IEventRepository _eventRepository;
  final IDeviceRepository _deviceRepository;

  NoteContentService(
    this._apiClient,
    this._eventRepository,
    this._deviceRepository,
  );

  // ===================
  // Get Operations
  // ===================

  /// Cache is disabled in server-only mode.
  Future<Note?> getCachedNote(String eventId) async {
    return null;
  }

  /// Get note from server.
  /// [forceRefresh] is kept for compatibility and ignored in server-only mode.
  Future<Note?> getNote(String eventId, {bool forceRefresh = false}) async {
    try {
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        throw Exception('Device not registered');
      }

      // Get bookId for the event
      final event = await _eventRepository.getById(eventId);
      if (event == null) {
        return null;
      }

      final serverNote = await _apiClient.fetchNote(
        bookUuid: event.bookUuid,
        eventId: eventId,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      return serverNote;
    } catch (e) {
      return null;
    }
  }

  // ===================
  // Save Operations
  // ===================

  /// Cache writes are disabled in server-only mode.
  /// This method is kept for compatibility with older cubit paths.
  Future<void> saveNote(String eventId, Note note) async {
    return;
  }

  /// Sync is unnecessary in server-only mode because notes are saved directly.
  Future<void> syncNote(String eventId) async {
    return;
  }

  // ===================
  // Delete Operations
  // ===================

  /// Delete note from server.
  Future<void> deleteNote(String eventId) async {
    try {
      // Get credentials
      final credentials = await _deviceRepository.getCredentials();
      if (credentials != null) {
        // Get bookId
        final event = await _eventRepository.getById(eventId);
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
    } catch (e) {
      rethrow;
    }
  }

  // ===================
  // Batch Operations
  // ===================

  /// Preload is disabled in server-only mode.
  Future<void> preloadNotes(
    List<String> eventIds, {
    Function(int loaded, int total)? onProgress,
  }) async {
    onProgress?.call(eventIds.length, eventIds.length);
  }
}
