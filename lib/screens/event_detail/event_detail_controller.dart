import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/note.dart';
import '../../services/database_service_interface.dart';
import '../../services/prd_database_service.dart';
import '../../services/content_service.dart';
import '../../services/api_client.dart';
import '../../services/cache_manager.dart';
import '../../services/server_config_service.dart';
import '../../widgets/handwriting_canvas.dart';
import 'event_detail_state.dart';
import 'adapters/connectivity_watcher.dart';
import 'adapters/server_health_checker.dart';
import 'adapters/note_sync_adapter.dart';

/// Controller for Event Detail Screen business logic
class EventDetailController {
  final Event event;
  final bool isNew;
  final IDatabaseService _dbService;
  final void Function(EventDetailState) onStateChanged;

  // Services
  ContentService? _contentService;
  NoteSyncAdapter? _noteSyncAdapter;
  ServerHealthChecker? _serverHealthChecker;
  final ConnectivityWatcher _connectivityWatcher = ConnectivityWatcher();
  StreamSubscription<bool>? _connectivitySubscription;

  // State tracking
  EventDetailState _state;
  bool _wasOfflineLastCheck = false;

  EventDetailController({
    required this.event,
    required this.isNew,
    required IDatabaseService dbService,
    required this.onStateChanged,
  })  : _dbService = dbService,
        _state = EventDetailState.fromEvent(event);

  EventDetailState get state => _state;

  /// Update state and notify listeners
  void _updateState(EventDetailState newState) {
    _state = newState;
    onStateChanged(_state);
  }

  /// Initialize ContentService and load initial data
  Future<void> initialize() async {
    try {
      debugPrint('🔧 EventDetailController: Starting ContentService initialization...');

      // Step 1: Initialize ContentService with correct server URL
      final prdDb = _dbService as PRDDatabaseService;
      final serverConfig = ServerConfigService(prdDb);

      // Get server URL from device settings (or use localhost:8080 as fallback)
      final serverUrl = await serverConfig.getServerUrlOrDefault(
        defaultUrl: 'http://localhost:8080',
      );

      debugPrint('🔧 EventDetailController: Initializing ContentService with server URL: $serverUrl');

      // Get device credentials for logging
      final credentials = await prdDb.getDeviceCredentials();
      if (credentials != null) {
        debugPrint('🔧 EventDetailController: Device registered - ID: ${credentials.deviceId.substring(0, 8)}..., Token: ${credentials.deviceToken.substring(0, 16)}...');
      } else {
        debugPrint('⚠️ EventDetailController: No device credentials found! User needs to register device first.');
      }

      final apiClient = ApiClient(baseUrl: serverUrl);
      final cacheManager = CacheManager(prdDb);
      _contentService = ContentService(apiClient, cacheManager, _dbService);
      _noteSyncAdapter = NoteSyncAdapter(_contentService!);
      _serverHealthChecker = ServerHealthChecker(_contentService!);

      // Mark services as ready
      _updateState(_state.copyWith(isServicesReady: true));

      debugPrint('✅ EventDetailController: ContentService initialized successfully');

      // Step 1.5: Check actual server connectivity on startup
      debugPrint('🔍 EventDetailController: Checking initial server connectivity...');
      final serverReachable = await _checkServerConnectivity();
      _updateState(_state.copyWith(
        isOffline: !serverReachable,
      ));
      _wasOfflineLastCheck = !serverReachable;
      debugPrint('✅ EventDetailController: Initial connectivity check complete - offline: ${_state.isOffline}');

      // Step 2: Load initial data (now that ContentService is ready)
      if (!isNew) {
        await loadNote();
        if (event.hasNewTime) {
          await _loadNewEvent();
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ EventDetailController: Failed to initialize ContentService: $e');
      debugPrint('❌ EventDetailController: Stack trace: $stackTrace');

      // Mark services as ready anyway to avoid blocking UI forever
      _updateState(_state.copyWith(
        isServicesReady: true,
        isOffline: true, // Mark as offline since initialization failed
      ));

      rethrow; // Let the caller handle showing error to user
    }
  }

  /// Load new event for time change display
  Future<void> _loadNewEvent() async {
    if (event.newEventId == null) return;
    try {
      final newEvent = await _dbService.getEventById(event.newEventId!);
      _updateState(_state.copyWith(newEvent: newEvent));
    } catch (e) {
      debugPrint('Error loading new event: $e');
    }
  }

  /// Setup network connectivity monitoring for automatic sync retry
  void setupConnectivityMonitoring() {
    debugPrint('🌐 EventDetailController: Setting up connectivity monitoring...');

    _connectivityWatcher.startWatching();
    _connectivitySubscription = _connectivityWatcher.onConnectivityChanged.listen(
      (hasConnection) {
        _onConnectivityChanged(hasConnection);
      },
    );
  }

  /// Check actual server connectivity using health check
  Future<bool> _checkServerConnectivity() async {
    if (_serverHealthChecker == null) {
      debugPrint('⚠️ EventDetailController: Cannot check server - ServerHealthChecker not initialized');
      return false;
    }

    return await _serverHealthChecker!.checkServerConnectivity();
  }

  /// Handle connectivity changes - automatically retry sync when network returns
  void _onConnectivityChanged(bool hasConnection) async {
    debugPrint('🌐 EventDetailController: Connectivity changed - hasConnection: $hasConnection');

    // Verify actual server connectivity
    final serverReachable = await _checkServerConnectivity();
    final wasOfflineBefore = _wasOfflineLastCheck;

    _updateState(_state.copyWith(isOffline: !serverReachable));
    _wasOfflineLastCheck = !serverReachable;

    debugPrint('🌐 EventDetailController: Offline state updated based on server check: ${_state.isOffline}');

    // Network just came back online
    if (serverReachable && wasOfflineBefore) {
      debugPrint('🌐 EventDetailController: Server restored! Checking for unsynced changes...');

      // If we have unsynced changes, automatically retry sync
      if (_state.hasUnsyncedChanges && event.id != null) {
        debugPrint('🌐 EventDetailController: Auto-retrying sync after server restoration...');

        // Wait a bit for network to stabilize
        await Future.delayed(const Duration(seconds: 1));
        if (_state.hasUnsyncedChanges) {
          await syncNoteInBackground(event.id!);
        }
      }
    }
  }

  /// Load note with cache-first strategy
  Future<void> loadNote() async {
    if (event.id == null) {
      debugPrint('🔍 EventDetailController: Cannot load note - event ID is null');
      return;
    }

    if (_noteSyncAdapter == null) {
      debugPrint('⚠️ EventDetailController: Cannot load note - NoteSyncAdapter not initialized');
      return;
    }

    debugPrint('📖 EventDetailController: Loading note for event ${event.id}');

    // Step 1: Load from cache immediately
    final cachedNote = await _noteSyncAdapter!.getCachedNote(event.id!);
    if (cachedNote != null) {
      _updateState(_state.copyWith(
        note: cachedNote,
        lastKnownPages: cachedNote.pages,
        hasUnsyncedChanges: cachedNote.isDirty,
      ));
      debugPrint('✅ EventDetailController: Loaded from cache (${cachedNote.strokes.length} strokes, isDirty: ${cachedNote.isDirty})');
    }

    // Step 2: Background refresh from server
    if (cachedNote != null && cachedNote.isDirty) {
      debugPrint('📤 EventDetailController: Cached note is dirty, syncing to server instead of fetching');
      _updateState(_state.copyWith(isLoadingFromServer: true));

      try {
        await _noteSyncAdapter!.syncNote(event.id!);
        _updateState(_state.copyWith(
          hasUnsyncedChanges: false,
          isLoadingFromServer: false,
          isOffline: false,
        ));
        debugPrint('✅ EventDetailController: Dirty note synced to server successfully');
      } catch (e) {
        debugPrint('⚠️ EventDetailController: Failed to sync dirty note: $e');
        _updateState(_state.copyWith(
          isLoadingFromServer: false,
          isOffline: true,
        ));
      }
      return;
    }

    // Normal flow: Fetch from server
    _updateState(_state.copyWith(isLoadingFromServer: true));

    try {
      final serverNote = await _noteSyncAdapter!.getNote(
        event.id!,
        forceRefresh: false,
      );

      if (serverNote != null) {
        _updateState(_state.copyWith(
          note: serverNote,
          lastKnownPages: serverNote.pages,
          hasUnsyncedChanges: false,
          isLoadingFromServer: false,
          isOffline: false,
        ));
        debugPrint('✅ EventDetailController: Refreshed from server');
      } else {
        _updateState(_state.copyWith(isLoadingFromServer: false));
      }
    } catch (e) {
      _updateState(_state.copyWith(
        isLoadingFromServer: false,
        isOffline: true,
      ));
      debugPrint('⚠️ EventDetailController: Server fetch failed, using cache: $e');
    }
  }

  /// Save event with handwriting note
  Future<Event> saveEvent() async {
    debugPrint('💾 EventDetailController: Saving event...');

    final pages = _state.lastKnownPages;
    _updateState(_state.copyWith(isLoading: true));

    try {
      final recordNumberText = _state.recordNumber.trim();
      final eventToSave = event.copyWith(
        name: _state.name.trim(),
        recordNumber: recordNumberText.isEmpty ? null : recordNumberText,
        eventType: _state.selectedEventType,
        startTime: _state.startTime,
        endTime: _state.endTime,
      );

      // Detect if record_number changed from null/empty to a value
      final oldRecordNumber = event.recordNumber?.trim() ?? '';
      final newRecordNumber = eventToSave.recordNumber?.trim() ?? '';
      final recordNumberAdded = oldRecordNumber.isEmpty && newRecordNumber.isNotEmpty;

      Event savedEvent;
      if (isNew) {
        savedEvent = await _dbService.createEvent(eventToSave);

        // Safety check: If new event has record number, check for existing person note
        // This prevents accidental overwriting if UI dialog wasn't shown
        if (recordNumberText.isNotEmpty && _dbService is PRDDatabaseService) {
          debugPrint('🔍 EventDetailController: NEW event with record number, checking for existing person note...');
          final prdDb = _dbService as PRDDatabaseService;
          final existingNote = await prdDb.findExistingPersonNote(
            _state.name.trim(),
            recordNumberText,
          );

          if (existingNote != null) {
            // DB has handwriting - auto-load it (safety: never lose existing patient data)
            final totalStrokes = existingNote.pages.fold<int>(0, (sum, page) => sum + page.length);
            debugPrint('⚠️ EventDetailController: Found existing person note (${existingNote.pages.length} pages, $totalStrokes strokes), loading DB handwriting');
            await prdDb.handleRecordNumberUpdate(savedEvent.id!, savedEvent);
            _updateState(_state.copyWith(
              note: existingNote,
              lastKnownPages: existingNote.pages,
              isLoading: false,
            ));
            debugPrint('✅ EventDetailController: Loaded DB handwriting, skipping canvas save (patient data protected)');
            return savedEvent;
          }
        }
      } else {
        savedEvent = await _dbService.updateEvent(eventToSave);

        // If record_number was added, handle person note sync
        if (recordNumberAdded && savedEvent.id != null && _dbService is PRDDatabaseService) {
          debugPrint('🔄 EventDetailController: Record number added, syncing with person group...');
          final prdDb = _dbService as PRDDatabaseService;
          final syncedNote = await prdDb.handleRecordNumberUpdate(savedEvent.id!, savedEvent);

          if (syncedNote != null && syncedNote.isNotEmpty) {
            // Update state with synced note if it has content
            _updateState(_state.copyWith(
              note: syncedNote,
              lastKnownPages: syncedNote.pages,
            ));
            debugPrint('✅ EventDetailController: Note synced from person group, skipping save');
            // Return early - we don't need to save the note again since it was synced
            _updateState(_state.copyWith(isLoading: false));
            return savedEvent;
          }
        }
      }

      // Save handwriting note using offline-first strategy
      await saveNoteWithOfflineFirst(savedEvent.id!, pages);

      return savedEvent;
    } catch (e) {
      _updateState(_state.copyWith(isLoading: false));
      rethrow;
    }
  }

  /// Save note with offline-first strategy
  Future<void> saveNoteWithOfflineFirst(int eventId, List<List<Stroke>> pages) async {
    debugPrint('💾 EventDetailController: Starting offline-first note save for event $eventId');

    if (_noteSyncAdapter == null) {
      throw Exception('NoteSyncAdapter not initialized. Cannot save note.');
    }

    final totalStrokes = pages.fold<int>(0, (sum, page) => sum + page.length);
    debugPrint('💾 EventDetailController: Saving note with ${pages.length} pages, $totalStrokes total strokes');

    final noteToSave = Note(
      eventId: eventId,
      pages: pages,
      createdAt: _state.note?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      debugPrint('💾 EventDetailController: Calling NoteSyncAdapter.saveNote()...');
      await _noteSyncAdapter!.saveNote(eventId, noteToSave);
      debugPrint('✅ EventDetailController: NoteSyncAdapter.saveNote() completed');

      // Verify local save succeeded
      debugPrint('🔍 EventDetailController: Verifying local save by reading back from cache...');
      final verifyNote = await _noteSyncAdapter!.getCachedNote(eventId);

      if (verifyNote == null) {
        throw Exception('Local save verification failed: Note not found in cache after save');
      }

      final verifyTotalStrokes = verifyNote.pages.fold<int>(0, (sum, page) => sum + page.length);
      if (verifyTotalStrokes != totalStrokes) {
        throw Exception('Local save verification failed: Expected $totalStrokes strokes but found $verifyTotalStrokes');
      }

      debugPrint('✅ EventDetailController: Local save verified - ${verifyNote.pages.length} pages, $verifyTotalStrokes strokes in cache, isDirty: ${verifyNote.isDirty}');

      _updateState(_state.copyWith(
        note: noteToSave,
        hasChanges: false,
        hasUnsyncedChanges: true,
        lastKnownPages: pages,
      ));

      debugPrint('✅ EventDetailController: Note saved locally with ${pages.length} pages, $totalStrokes total strokes');

      // Background sync to server
      await syncNoteInBackground(eventId);
    } catch (e, stackTrace) {
      debugPrint('❌ EventDetailController: Failed to save note: $e');
      debugPrint('❌ EventDetailController: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Background sync note to server
  Future<void> syncNoteInBackground(int eventId) async {
    if (_noteSyncAdapter == null) {
      debugPrint('⚠️ EventDetailController: Cannot sync note - NoteSyncAdapter not initialized');
      return;
    }

    try {
      debugPrint('🔄 EventDetailController: Starting background sync for note $eventId...');
      await _noteSyncAdapter!.syncNote(eventId);
      debugPrint('✅ EventDetailController: Background sync completed successfully');

      _updateState(_state.copyWith(
        hasUnsyncedChanges: false,
        isOffline: false,
      ));
      _wasOfflineLastCheck = false;

      debugPrint('✅ EventDetailController: Note synced to server (eventId: $eventId), offline status updated');
    } catch (e) {
      debugPrint('⚠️ EventDetailController: Background sync failed (will retry later): $e');

      // Verify server connectivity after failure
      final serverReachable = await _checkServerConnectivity();

      _updateState(_state.copyWith(isOffline: !serverReachable));
      _wasOfflineLastCheck = !serverReachable;

      debugPrint('ℹ️ EventDetailController: Verified connectivity after sync failure - offline: ${_state.isOffline}');
    }
  }

  /// Delete event permanently
  Future<void> deleteEvent() async {
    if (isNew) return;

    _updateState(_state.copyWith(isLoading: true));
    try {
      await _dbService.deleteEvent(event.id!);
    } catch (e) {
      _updateState(_state.copyWith(isLoading: false));
      rethrow;
    }
  }

  /// Remove event with reason
  Future<void> removeEvent(String reason) async {
    if (isNew) return;

    _updateState(_state.copyWith(isLoading: true));
    try {
      await _dbService.removeEvent(event.id!, reason);
    } catch (e) {
      _updateState(_state.copyWith(isLoading: false));
      rethrow;
    }
  }

  /// Change event time with reason
  Future<void> changeEventTime(DateTime newStartTime, DateTime? newEndTime, String reason) async {
    if (isNew) return;

    _updateState(_state.copyWith(isLoading: true));
    try {
      await _dbService.changeEventTime(event, newStartTime, newEndTime, reason);
    } catch (e) {
      _updateState(_state.copyWith(isLoading: false));
      rethrow;
    }
  }

  /// Update name
  void updateName(String name) {
    _updateState(_state.copyWith(name: name, hasChanges: true));
  }

  /// Update record number
  void updateRecordNumber(String recordNumber) {
    _updateState(_state.copyWith(recordNumber: recordNumber, hasChanges: true));
  }

  /// Update event type
  void updateEventType(EventType eventType) {
    _updateState(_state.copyWith(selectedEventType: eventType, hasChanges: true));
  }

  /// Check for existing person note when record number is set (for NEW events only)
  /// Returns the existing note if found, null otherwise
  /// This is called when user finishes typing record number
  Future<Note?> checkExistingPersonNote() async {
    // Only check for new events
    if (!isNew) {
      return null;
    }

    final name = _state.name.trim();
    final recordNumber = _state.recordNumber.trim();

    if (name.isEmpty || recordNumber.isEmpty) {
      return null;
    }

    if (_dbService is PRDDatabaseService) {
      final prdDb = _dbService as PRDDatabaseService;
      return await prdDb.findExistingPersonNote(name, recordNumber);
    }

    return null;
  }

  /// Load existing person note (when user chooses "載入現有")
  /// Replaces current canvas with DB handwriting
  Future<void> loadExistingPersonNote(Note existingNote) async {
    final totalStrokes = existingNote.pages.fold<int>(0, (sum, page) => sum + page.length);
    _updateState(_state.copyWith(
      note: existingNote,
      lastKnownPages: existingNote.pages,
    ));
    debugPrint('✅ EventDetailController: Loaded existing person note (${existingNote.pages.length} pages, $totalStrokes strokes)');
  }

  /// Get all record numbers for the current person name
  /// Returns empty list if name is empty or DB service is not PRD
  Future<List<String>> getRecordNumbersForCurrentName() async {
    final name = _state.name.trim();

    if (name.isEmpty) {
      return [];
    }

    if (_dbService is PRDDatabaseService) {
      final prdDb = _dbService as PRDDatabaseService;
      return await prdDb.getRecordNumbersByName(event.bookId, name);
    }

    return [];
  }

  /// Update start time
  void updateStartTime(DateTime startTime) {
    _updateState(_state.copyWith(startTime: startTime, hasChanges: true));
  }

  /// Update end time
  void updateEndTime(DateTime? endTime) {
    _updateState(_state.copyWith(endTime: endTime, hasChanges: true));
  }

  /// Clear end time
  void clearEndTime() {
    _updateState(_state.copyWith(clearEndTime: true, hasChanges: true));
  }

  /// Update strokes (called when canvas changes)
  void updatePages(List<List<Stroke>> pages) {
    _updateState(_state.copyWith(
      lastKnownPages: pages,
      hasChanges: true,
    ));
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityWatcher.dispose();
  }
}
