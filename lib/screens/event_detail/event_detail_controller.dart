import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/charge_item.dart';
import '../../models/note.dart';
import '../../models/person_charge_item.dart';
import '../../services/database_service_interface.dart';
import '../../services/database/prd_database_service.dart';
import '../../services/database/mixins/person_info_utilities_mixin.dart';
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
  int _noteEditGeneration = 0;

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

      // Step 1: Initialize ContentService with correct server URL
      final prdDb = _dbService as PRDDatabaseService;
      final serverConfig = ServerConfigService(prdDb);

      // Get server URL from device settings (or use localhost:8080 as fallback)
      final serverUrl = await serverConfig.getServerUrlOrDefault(
        defaultUrl: 'http://localhost:8080',
      );


      // Get device credentials for logging
      final credentials = await prdDb.getDeviceCredentials();
      if (credentials != null) {
      } else {
      }

      final apiClient = ApiClient(baseUrl: serverUrl);
      final cacheManager = CacheManager(prdDb);
      _contentService = ContentService(apiClient, cacheManager, _dbService);
      _noteSyncAdapter = NoteSyncAdapter(_contentService!);
      _serverHealthChecker = ServerHealthChecker(_contentService!);

      // Mark services as ready
      _updateState(_state.copyWith(isServicesReady: true));


      // Step 1.5: Check actual server connectivity on startup
      final serverReachable = await _checkServerConnectivity();
      _updateState(_state.copyWith(
        isOffline: !serverReachable,
      ));
      _wasOfflineLastCheck = !serverReachable;

      // Step 2: Load initial data (now that ContentService is ready)
      if (!isNew) {
        await _logLocalEventSnapshot();
        await _refreshEventFromServer();
        await loadNote();
        await loadChargeItems(); // Load charge items from person_charge_items table
        if (event.hasNewTime) {
          await _loadNewEvent();
        }
      }
    } catch (e, stackTrace) {

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
    }
  }

  Future<void> _refreshEventFromServer() async {
    if (_contentService == null || event.id == null) {
      return;
    }

    try {
      await _logEventTime('before_server_fetch', event);
      final refreshedEvent = await _contentService!.refreshEventFromServer(event.id!);
      if (refreshedEvent != null) {
        // Persist server-authoritative data locally to prevent stale local values from overriding UI
        await _dbService.replaceEventWithServerData(refreshedEvent);

        await _logEventTime('after_server_fetch', refreshedEvent);
        _updateState(_state.copyWith(
          name: refreshedEvent.name,
          recordNumber: refreshedEvent.recordNumber ?? '',
          phone: refreshedEvent.phone ?? '',
          selectedEventTypes: refreshedEvent.eventTypes,
          startTime: refreshedEvent.startTime,
          endTime: refreshedEvent.endTime,
        ));
        await _logStateTime('after_state_update');
      }
    } catch (e) {
    }
  }

  /// Setup network connectivity monitoring for automatic sync retry
  void setupConnectivityMonitoring() {

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
      return false;
    }

    return await _serverHealthChecker!.checkServerConnectivity();
  }

  /// Handle connectivity changes - automatically retry sync when network returns
  void _onConnectivityChanged(bool hasConnection) async {

    // Verify actual server connectivity
    final serverReachable = await _checkServerConnectivity();
    final wasOfflineBefore = _wasOfflineLastCheck;

    _updateState(_state.copyWith(isOffline: !serverReachable));
    _wasOfflineLastCheck = !serverReachable;


    // Network just came back online
    if (serverReachable && wasOfflineBefore) {

      // If we have unsynced changes, automatically retry sync
      if (_state.hasUnsyncedChanges && event.id != null) {

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
      return;
    }

    if (_noteSyncAdapter == null) {
      return;
    }

    final noteLoadGeneration = _noteEditGeneration;

    // Always fetch from server first
    _updateState(_state.copyWith(isLoadingFromServer: true));
    try {
      final serverNote = await _noteSyncAdapter!.getNote(
        event.id!,
        forceRefresh: true,
      );

      if (_noteEditGeneration != noteLoadGeneration) {
        _updateState(_state.copyWith(isLoadingFromServer: false));
        return;
      }

      if (serverNote != null) {
        _updateState(_state.copyWith(
          note: serverNote,
          lastKnownPages: serverNote.pages,
          hasUnsyncedChanges: false,
          isLoadingFromServer: false,
          isOffline: false,
        ));
        return;
      } else {
      }
    } catch (e) {
      _updateState(_state.copyWith(isOffline: true));
    }

    // Fallback to cache if server fetch failed or note absent
    final cachedNote = await _noteSyncAdapter!.getCachedNote(event.id!);
    if (cachedNote != null) {
      if (_noteEditGeneration != noteLoadGeneration) {
      } else {
        final totalStrokes = cachedNote.pages.fold<int>(0, (sum, page) => sum + page.length);
        _updateState(_state.copyWith(
          note: cachedNote,
          lastKnownPages: cachedNote.pages,
          hasUnsyncedChanges: false,  // Server-based architecture: no dirty tracking
          isLoadingFromServer: false,
        ));
        return;
      }
    }

    _updateState(_state.copyWith(isLoadingFromServer: false));
  }

  /// Save event with handwriting note
  Future<Event> saveEvent() async {

    final pages = _state.lastKnownPages;
    final totalStrokes = pages.fold<int>(0, (sum, page) => sum + page.length);

    _updateState(_state.copyWith(isLoading: true));

    try {
      final recordNumberText = _state.recordNumber.trim();
      final phoneText = _state.phone.trim();

      // Check if user cleared the end time (converting close-end to open-end event)
      final shouldClearEndTime = event.endTime != null && _state.endTime == null;

      final eventToSave = event.copyWith(
        name: _state.name.trim(),
        recordNumber: recordNumberText.isEmpty ? null : recordNumberText,
        phone: phoneText.isEmpty ? null : phoneText,
        eventTypes: _state.selectedEventTypes,
        // Note: chargeItems are now stored in person_charge_items table, not in events
        startTime: _state.startTime,
        endTime: _state.endTime,
        clearEndTime: shouldClearEndTime,
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
          final prdDb = _dbService as PRDDatabaseService;
          final existingNote = await prdDb.findExistingPersonNote(
            _state.name.trim(),
            recordNumberText,
          );

          if (existingNote != null) {
            // DB has handwriting - auto-load it (safety: never lose existing patient data)
            final totalStrokes = existingNote.pages.fold<int>(0, (sum, page) => sum + page.length);
            await prdDb.handleRecordNumberUpdate(savedEvent.id!, savedEvent);
            _updateState(_state.copyWith(
              note: existingNote,
              lastKnownPages: existingNote.pages,
            ));
            // Still sync to server even when using existing note
            await saveNoteWithOfflineFirst(savedEvent.id!, existingNote.pages);
            return savedEvent;
          }
        }
      } else {
        savedEvent = await _dbService.updateEvent(eventToSave);

        // If record_number was added, handle person note sync
        if (recordNumberAdded && savedEvent.id != null && _dbService is PRDDatabaseService) {
          final prdDb = _dbService as PRDDatabaseService;
          final syncedNote = await prdDb.handleRecordNumberUpdate(savedEvent.id!, savedEvent);

          if (syncedNote != null && syncedNote.isNotEmpty) {
            // Update state with synced note if it has content
            _updateState(_state.copyWith(
              note: syncedNote,
              lastKnownPages: syncedNote.pages,
            ));
            // Still sync to server even when using synced note
            await saveNoteWithOfflineFirst(savedEvent.id!, syncedNote.pages);
            return savedEvent;
          }
        }
      }

      // Save phone number to person_info table if record number is present
      if (recordNumberText.isNotEmpty) {
        await savePhone();
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
  Future<void> saveNoteWithOfflineFirst(String eventId, List<List<Stroke>> pages) async {

    if (_noteSyncAdapter == null) {
      throw Exception('NoteSyncAdapter not initialized. Cannot save note.');
    }

    final totalStrokes = pages.fold<int>(0, (sum, page) => sum + page.length);

    final noteToSave = Note(
      eventId: eventId,
      pages: pages,
      createdAt: _state.note?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      await _noteSyncAdapter!.saveNote(eventId, noteToSave);

      // Verify local save succeeded
      final verifyNote = await _noteSyncAdapter!.getCachedNote(eventId);

      if (verifyNote == null) {
        throw Exception('Local save verification failed: Note not found in cache after save');
      }

      final verifyTotalStrokes = verifyNote.pages.fold<int>(0, (sum, page) => sum + page.length);
      if (verifyTotalStrokes != totalStrokes) {
        throw Exception('Local save verification failed: Expected $totalStrokes strokes but found $verifyTotalStrokes');
      }


      _updateState(_state.copyWith(
        note: noteToSave,
        hasChanges: false,
        hasUnsyncedChanges: true,
        lastKnownPages: pages,
      ));


      // Background sync to server
      await syncNoteInBackground(eventId);
    } catch (e, stackTrace) {
      rethrow;
    }
  }

  /// Background sync note to server
  Future<void> syncNoteInBackground(String eventId) async {
    if (_noteSyncAdapter == null) {
      return;
    }

    try {
      await _noteSyncAdapter!.syncNote(eventId);

      _updateState(_state.copyWith(
        hasUnsyncedChanges: false,
        isOffline: false,
      ));
      _wasOfflineLastCheck = false;

    } catch (e) {

      // Verify server connectivity after failure
      final serverReachable = await _checkServerConnectivity();

      _updateState(_state.copyWith(isOffline: !serverReachable));
      _wasOfflineLastCheck = !serverReachable;

    }
  }

  /// Delete event permanently
  Future<void> deleteEvent() async {
    if (isNew) return;

    _updateState(_state.copyWith(isLoading: true));
    try {
      await _dbService.deleteEvent(event.id!);

      // Sync deleted event state to server
      if (event.id != null) {
        await syncNoteInBackground(event.id!);
      }
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

      // Sync removed event to server
      if (event.id != null) {
        await syncNoteInBackground(event.id!);
      }
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
      final result = await _dbService.changeEventTime(event, newStartTime, newEndTime, reason);

      // Sync both old event (with isRemoved=true) and new event to server
      // Old event must be synced first to ensure server knows it's removed
      if (result.oldEvent.id != null) {
        await syncNoteInBackground(result.oldEvent.id!);
      }
      if (result.newEvent.id != null) {
        await syncNoteInBackground(result.newEvent.id!);
      }
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
    final oldRecordNumber = _state.recordNumber.trim();
    final newRecordNumber = recordNumber.trim();

    _updateState(_state.copyWith(recordNumber: recordNumber, hasChanges: true));

    // Reload charge items and phone if record number changed (debounced)
    if (oldRecordNumber != newRecordNumber) {
      // Load charge items asynchronously (don't wait for it)
      loadChargeItems().catchError((e) {
      });
    }
  }

  /// Update phone
  void updatePhone(String phone) {
    _updateState(_state.copyWith(phone: phone, hasChanges: true));
  }

  /// Update event types
  void updateEventTypes(List<EventType> eventTypes) {
    _updateState(_state.copyWith(selectedEventTypes: eventTypes, hasChanges: true));
  }

  /// Load charge items for the current event (based on name + record number)
  Future<void> loadChargeItems() async {
    final name = _state.name.trim();
    final recordNumber = _state.recordNumber.trim();

    // Only load if we have both name and record number
    if (name.isEmpty || recordNumber.isEmpty) {
      _updateState(_state.copyWith(chargeItems: []));
      return;
    }

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      final nameNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(name);
      final recordNumberNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(recordNumber);

      // Get person charge items
      final personChargeItems = await prdDb.getPersonChargeItems(
        personNameNormalized: nameNormalized,
        recordNumberNormalized: recordNumberNormalized,
      );

      // Convert to ChargeItem list
      final chargeItems = personChargeItems
          .map((item) => ChargeItem.fromPersonChargeItem(item))
          .toList();

      _updateState(_state.copyWith(chargeItems: chargeItems));
    } catch (e) {
    }
  }

  /// Save phone number to person_info table
  Future<void> savePhone() async {
    final name = _state.name.trim();
    final recordNumber = _state.recordNumber.trim();
    final phone = _state.phone.trim();

    // Only save if we have both name and record number
    if (name.isEmpty || recordNumber.isEmpty) {
      return;
    }

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      final nameNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(name);
      final recordNumberNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(recordNumber);

      // Save person phone
      await prdDb.setPersonPhone(
        personNameNormalized: nameNormalized,
        recordNumberNormalized: recordNumberNormalized,
        phone: phone.isEmpty ? null : phone,
      );

    } catch (e) {
    }
  }

  /// Add a new charge item
  Future<void> addChargeItem(ChargeItem item) async {
    final name = _state.name.trim();
    final recordNumber = _state.recordNumber.trim();

    if (name.isEmpty || recordNumber.isEmpty) {
      return;
    }

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      final nameNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(name);
      final recordNumberNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(recordNumber);

      // Check if item already exists
      final exists = await prdDb.personChargeItemExists(
        personNameNormalized: nameNormalized,
        recordNumberNormalized: recordNumberNormalized,
        itemName: item.itemName,
      );

      if (exists) {
        // TODO: Show error message to user
        return;
      }

      // Create PersonChargeItem
      final personItem = PersonChargeItem(
        personNameNormalized: nameNormalized,
        recordNumberNormalized: recordNumberNormalized,
        itemName: item.itemName,
        cost: item.cost,
        isPaid: item.isPaid,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save to database
      final savedItem = await prdDb.savePersonChargeItem(personItem);

      // Reload all charge items
      await loadChargeItems();

    } catch (e) {
    }
  }

  /// Edit an existing charge item
  Future<void> editChargeItem(ChargeItem item) async {
    if (item.id == null) {
      return;
    }

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      final nameNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(_state.name.trim());
      final recordNumberNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(_state.recordNumber.trim());

      // Check if new name conflicts with existing item
      final exists = await prdDb.personChargeItemExists(
        personNameNormalized: nameNormalized,
        recordNumberNormalized: recordNumberNormalized,
        itemName: item.itemName,
        excludeId: item.id,
      );

      if (exists) {
        // TODO: Show error message to user
        return;
      }

      // Get existing item
      final existingItem = await prdDb.getPersonChargeItemById(item.id!);
      if (existingItem == null) {
        return;
      }

      // Update item
      final updatedItem = existingItem.copyWith(
        itemName: item.itemName,
        cost: item.cost,
        isPaid: item.isPaid,
      );

      await prdDb.savePersonChargeItem(updatedItem);

      // Reload all charge items
      await loadChargeItems();

    } catch (e) {
    }
  }

  /// Delete a charge item
  Future<void> deleteChargeItem(ChargeItem item) async {
    if (item.id == null) {
      return;
    }

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      await prdDb.deletePersonChargeItem(item.id!);

      // Reload all charge items
      await loadChargeItems();

    } catch (e) {
    }
  }

  /// Toggle paid status of a charge item
  Future<void> toggleChargeItemPaidStatus(ChargeItem item) async {
    if (item.id == null) {
      return;
    }

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      await prdDb.updatePersonChargeItemPaidStatus(
        id: item.id!,
        isPaid: !item.isPaid,
      );

      // Reload all charge items
      await loadChargeItems();

    } catch (e) {
    }
  }

  /// Update charge items (legacy method - kept for compatibility but now loads from database)
  @Deprecated('Use addChargeItem, editChargeItem, deleteChargeItem, or toggleChargeItemPaidStatus instead')
  void updateChargeItems(List<ChargeItem> chargeItems) {
    _updateState(_state.copyWith(chargeItems: chargeItems, hasChanges: true));
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
    _incrementNoteGeneration();
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
      return await prdDb.getRecordNumbersByName(event.bookUuid, name);
    }

    return [];
  }

  /// Get all unique names for autocomplete
  /// Returns empty list if DB service is not PRD
  Future<List<String>> getAllNamesForAutocomplete() async {
    if (_dbService is PRDDatabaseService) {
      final prdDb = _dbService as PRDDatabaseService;
      return await prdDb.getAllNamesInBook(event.bookUuid);
    }
    return [];
  }

  /// Get all record numbers with names for autocomplete
  /// Returns empty list if DB service is not PRD
  Future<List<RecordNumberOption>> getAllRecordNumbersForAutocomplete() async {
    if (_dbService is PRDDatabaseService) {
      final prdDb = _dbService as PRDDatabaseService;
      final results = await prdDb.getAllRecordNumbersWithNames(event.bookUuid);
      return results
          .map((item) => RecordNumberOption(
                recordNumber: item['recordNumber']!,
                name: item['name']!,
              ))
          .toList();
    }
    return [];
  }

  /// Handle name field focused - clear record number
  void onNameFieldFocused() {
    if (_state.recordNumber.trim().isNotEmpty) {
      _updateState(_state.copyWith(
        recordNumber: '',
        isNameReadOnly: false,
        hasChanges: true,
      ));
    }
  }

  /// Handle record number field focused - clear name
  void onRecordNumberFieldFocused() {
    if (_state.name.trim().isNotEmpty) {
      _updateState(_state.copyWith(
        name: '',
        isNameReadOnly: false,
        hasChanges: true,
      ));
    }
  }

  /// Handle record number selected - auto-fill name, phone, and note
  /// Tries to fetch from server first, falls back to local database
  Future<void> onRecordNumberSelected(String recordNumber) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    final prdDb = _dbService as PRDDatabaseService;
    String? name;
    Note? serverNote;

    // Step 1: Try to fetch person data from server (name + note)
    if (_contentService != null) {
      try {
        final credentials = await prdDb.getDeviceCredentials();
        if (credentials != null) {
          final apiClient = ApiClient(baseUrl: await _getServerUrl());
          final personData = await apiClient.fetchPersonByRecordNumber(
            bookUuid: event.bookUuid,
            recordNumber: recordNumber,
            deviceId: credentials.deviceId,
            deviceToken: credentials.deviceToken,
          );

          if (personData != null) {
            name = personData['name'] as String?;

            // Parse server note if available
            final latestNote = personData['latestNote'] as Map<String, dynamic>?;
            if (latestNote != null && latestNote['strokes_data'] != null) {
              serverNote = Note.fromMap(latestNote);
            }
          }
        }
      } catch (e) {
        // Server fetch failed, will fallback to local database
      }
    }

    // Step 2: Fallback to local database if server didn't return name
    if (name == null || name.isEmpty) {
      name = await prdDb.getNameByRecordNumber(event.bookUuid, recordNumber);
    }

    if (name == null || name.isEmpty) {
      return; // No person found with this record number
    }

    // Step 3: Fetch phone number from local person_info table
    final nameNorm = PersonInfoUtilitiesMixin.normalizePersonKey(name);
    final recordNorm = PersonInfoUtilitiesMixin.normalizePersonKey(recordNumber);
    final phone = await prdDb.getPersonPhone(
      personNameNormalized: nameNorm,
      recordNumberNormalized: recordNorm,
    );

    // Step 4: Update state with name, record number, and phone
    _updateState(_state.copyWith(
      name: name,
      recordNumber: recordNumber,
      phone: phone ?? '',
      isNameReadOnly: true,
      hasChanges: true,
    ));

    // Step 5: Load associated charge items
    loadChargeItems().catchError((e) {
    });

    // Step 6: Load person note (prefer server version, fallback to local)
    try {
      Note? noteToLoad = serverNote;

      // If no server note, try local database
      if (noteToLoad == null || noteToLoad.isEmpty) {
        noteToLoad = await prdDb.findExistingPersonNote(name, recordNumber);
      }

      if (noteToLoad != null && noteToLoad.isNotEmpty) {
        loadExistingPersonNote(noteToLoad);
      }
    } catch (e) {
    }
  }

  /// Get server URL from config
  Future<String> _getServerUrl() async {
    final prdDb = _dbService as PRDDatabaseService;
    final serverConfig = ServerConfigService(prdDb);
    return await serverConfig.getServerUrlOrDefault(
      defaultUrl: 'http://localhost:8080',
    );
  }

  /// Handle name selected from autocomplete - set editable mode
  void onNameSelected(String name) {
    _updateState(_state.copyWith(
      name: name,
      isNameReadOnly: false,
      hasChanges: true,
    ));
  }

  /// Clear record number (called when "留空" option is selected)
  void clearRecordNumber() {
    _updateState(_state.copyWith(
      recordNumber: '',
      isNameReadOnly: false,
      hasChanges: true,
    ));
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
    final totalStrokes = pages.fold<int>(0, (sum, page) => sum + page.length);
    _updateState(_state.copyWith(
      lastKnownPages: pages,
      hasChanges: true,
    ));
    _incrementNoteGeneration();
  }

  void _incrementNoteGeneration() {
    _noteEditGeneration++;
  }

  Future<void> _logLocalEventSnapshot() async {
    if (!kDebugMode || event.id == null) return;

    try {
      final local = await _dbService.getEventById(event.id!);
      if (local == null) {
        debugPrint('[EventDetail] Local fetch for ${event.id} returned null');
        return;
      }

      debugPrint(
        '[EventDetail] Local event snapshot id=${local.id} start=${local.startTime.toIso8601String()} (isUtc=${local.startTime.isUtc}) '
        'end=${local.endTime?.toIso8601String()} created=${local.createdAt.toIso8601String()} updated=${local.updatedAt.toIso8601String()}',
      );
    } catch (e) {
      debugPrint('[EventDetail] Failed to log local event snapshot: $e');
    }
  }

  Future<void> _logEventTime(String label, Event e) async {
    if (!kDebugMode) return;
    debugPrint(
      '[EventDetail] $label id=${e.id} start=${e.startTime.toIso8601String()} (isUtc=${e.startTime.isUtc}) '
      'end=${e.endTime?.toIso8601String()}',
    );
  }

  Future<void> _logStateTime(String label) async {
    if (!kDebugMode) return;
    debugPrint(
      '[EventDetail] $label state start=${_state.startTime.toIso8601String()} (isUtc=${_state.startTime.isUtc}) '
      'end=${_state.endTime?.toIso8601String()}',
    );
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityWatcher.dispose();
  }
}

/// Helper class for record number autocomplete options
/// Represents a record number with its associated name
class RecordNumberOption {
  final String recordNumber;
  final String name;

  RecordNumberOption({
    required this.recordNumber,
    required this.name,
  });

  /// Display text for the dropdown: "recordNumber - name"
  String get displayText => '$recordNumber - $name';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordNumberOption &&
          runtimeType == other.runtimeType &&
          recordNumber == other.recordNumber &&
          name == other.name;

  @override
  int get hashCode => recordNumber.hashCode ^ name.hashCode;
}
