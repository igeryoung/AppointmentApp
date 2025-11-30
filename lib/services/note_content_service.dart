import 'package:flutter/foundation.dart';
import '../models/note.dart';
import '../repositories/note_repository.dart';
import '../repositories/event_repository.dart';
import '../repositories/device_repository.dart';
import 'api_client.dart';

/// NoteContentService - Manages note content with cache-first strategy
///
/// Responsibilities:
/// - Fetch notes from cache or server
/// - Save notes locally and sync to server
/// - Delete notes from cache and server
/// - Preload notes for performance
/// - Sync dirty notes
class NoteContentService {
  final ApiClient _apiClient;
  final INoteRepository _noteRepository;
  final IEventRepository _eventRepository;
  final IDeviceRepository _deviceRepository;

  NoteContentService(
    this._apiClient,
    this._noteRepository,
    this._eventRepository,
    this._deviceRepository,
  );

  // ===================
  // Get Operations
  // ===================

  /// Get note from cache only (no network call)
  ///
  /// Returns cached note immediately without checking server
  /// Used for instant display in cache-first strategy
  Future<Note?> getCachedNote(String eventId) async {
    try {
      final cachedNote = await _noteRepository.getCached(eventId);
      if (cachedNote != null) {
        debugPrint('✅ NoteContentService: Cache-only note retrieved (eventId: $eventId, isDirty: ${cachedNote.isDirty})');
      } else {
        debugPrint('ℹ️ NoteContentService: No cached note found (eventId: $eventId)');
      }
      return cachedNote;
    } catch (e) {
      debugPrint('❌ NoteContentService: Error getting cached note: $e');
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
        final cachedNote = await _noteRepository.getCached(eventId);
        if (cachedNote != null) {
          debugPrint('✅ NoteContentService: Note cache hit (eventId: $eventId)');
          return cachedNote;
        }
        debugPrint('ℹ️ NoteContentService: Note cache miss (eventId: $eventId)');
      }

      // Step 2: Fetch from server
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        debugPrint('⚠️ NoteContentService: Device not registered, cannot fetch from server');
        // Return cache if available
        return await _noteRepository.getCached(eventId);
      }

      // Get bookId for the event
      final event = await _eventRepository.getById(eventId);
      if (event == null) {
        debugPrint('⚠️ NoteContentService: Event $eventId not found');
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
        await _noteRepository.saveToCache(note, isDirty: false);
        debugPrint('✅ NoteContentService: Note fetched from server and cached (eventId: $eventId)');
        return note;
      }

      debugPrint('ℹ️ NoteContentService: Note not found on server (eventId: $eventId)');
      return null;
    } catch (e) {
      debugPrint('❌ NoteContentService: Error fetching note (eventId: $eventId): $e');

      // Fallback to cache on error
      try {
        final cachedNote = await _noteRepository.getCached(eventId);
        if (cachedNote != null) {
          debugPrint('⚠️ NoteContentService: Returning cached note after server error');
          return cachedNote;
        }
      } catch (cacheError) {
        debugPrint('❌ NoteContentService: Cache fallback also failed: $cacheError');
      }

      return null;
    }
  }

  // ===================
  // Save Operations
  // ===================

  /// Save note locally only (always succeeds unless disk full)
  /// Server sync should be handled separately by caller via syncNote()
  ///
  /// **Data Safety First Principle**: Local save is guaranteed,
  /// server sync is handled separately in background (best effort)
  Future<void> saveNote(String eventId, Note note) async {
    await _noteRepository.saveToCache(note, isDirty: true);
    debugPrint('✅ NoteContentService: Note saved locally (eventId: $eventId, marked dirty)');
  }

  /// Force sync a note to server (clears dirty flag on success)
  ///
  /// Throws exception on sync failure, keeps dirty flag intact
  Future<void> syncNote(String eventId) async {
    try {
      final note = await _noteRepository.getCached(eventId);
      if (note == null) {
        debugPrint('⚠️ NoteContentService: Cannot sync - note $eventId not found in cache');
        return;
      }

      // Get credentials
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        throw Exception('Device not registered, cannot sync to server');
      }

      // Get bookId
      final event = await _eventRepository.getById(eventId);
      if (event == null) {
        throw Exception('Event $eventId not found');
      }

      // Save to server - use toMap() to serialize properly
      final noteMap = note.toMap();
      final noteData = {
        'pagesData': noteMap['pages_data'],
      };

      // Include event data for auto-creation on server if event doesn't exist
      final eventData = event.toMap();

      await _apiClient.saveNote(
        bookUuid: event.bookUuid,
        eventId: eventId,
        noteData: noteData,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
        eventData: eventData,
      );

      // Sync successful, clear dirty flag
      await _noteRepository.markClean(eventId);

      debugPrint('✅ NoteContentService: Note synced to server (eventId: $eventId, dirty flag cleared)');
    } catch (e) {
      debugPrint('❌ NoteContentService: Sync failed for note $eventId: $e');
      // Keep dirty flag, retry later
      rethrow;
    }
  }

  // ===================
  // Delete Operations
  // ===================

  /// Delete note (from server and cache)
  Future<void> deleteNote(int eventId) async {
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

      // Delete from cache
      await _noteRepository.deleteCache(eventId);

      debugPrint('✅ NoteContentService: Note deleted (eventId: $eventId)');
    } catch (e) {
      debugPrint('❌ NoteContentService: Error deleting note: $e');
      rethrow;
    }
  }

  // ===================
  // Batch Operations
  // ===================

  /// Preload multiple notes in background (for performance)
  ///
  /// Strategy:
  /// 1. Filter out already-cached notes
  /// 2. Batch fetch from server (max 50 per request)
  /// 3. Save to cache
  ///
  /// [onProgress] callback reports (loaded, total) progress
  /// Does not block, returns immediately
  /// Failures are logged but don't throw
  Future<void> preloadNotes(
    List<int> eventIds, {
    Function(int loaded, int total)? onProgress,
  }) async {
    if (eventIds.isEmpty) {
      onProgress?.call(0, 0);
      return;
    }

    try {
      debugPrint('📥 NoteContentService: Preloading ${eventIds.length} notes...');

      // Get credentials
      final credentials = await _deviceRepository.getCredentials();
      if (credentials == null) {
        debugPrint('⚠️ NoteContentService: Device not registered, skipping preload');
        return;
      }

      // Get cached notes to filter out
      final cachedNotes = <int>{};
      for (final eventId in eventIds) {
        final cached = await _noteRepository.getCached(eventId);
        if (cached != null) {
          cachedNotes.add(eventId);
        }
      }

      final uncachedEventIds = eventIds.where((id) => !cachedNotes.contains(id)).toList();
      if (uncachedEventIds.isEmpty) {
        debugPrint('✅ NoteContentService: All notes already cached');
        onProgress?.call(eventIds.length, eventIds.length);
        return;
      }

      debugPrint('ℹ️ NoteContentService: Fetching ${uncachedEventIds.length} uncached notes');

      // Get book IDs for events (need to group by book)
      final eventsByBook = <String, List<int>>{};
      for (final eventId in uncachedEventIds) {
        final event = await _eventRepository.getById(eventId);
        if (event != null) {
          eventsByBook.putIfAbsent(event.bookUuid, () => []).add(eventId);
        }
      }

      int loaded = cachedNotes.length;
      final total = eventIds.length;

      // Batch fetch by book (max 50 per request)
      for (final entry in eventsByBook.entries) {
        final bookUuid = entry.key;
        final bookEventIds = entry.value;

        // Split into batches of 50
        for (int i = 0; i < bookEventIds.length; i += 50) {
          final batch = bookEventIds.skip(i).take(50).toList();

          try {
            final notes = await _apiClient.batchFetchNotes(
              eventIds: batch,
              deviceId: credentials.deviceId,
              deviceToken: credentials.deviceToken,
            );

            // Save to cache
            for (final noteData in notes) {
              final note = Note.fromMap(noteData);
              await _noteRepository.saveToCache(note, isDirty: false);
              loaded++;
              onProgress?.call(loaded, total);
            }
          } catch (e) {
            debugPrint('❌ NoteContentService: Batch fetch failed for book $bookUuid: $e');
          }
        }
      }

      debugPrint('✅ NoteContentService: Preload complete ($loaded/$total notes)');
    } catch (e) {
      debugPrint('❌ NoteContentService: Preload error: $e');
      // Don't throw - preload is best-effort
    }
  }
}
