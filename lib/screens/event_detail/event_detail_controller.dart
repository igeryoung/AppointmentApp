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
      _contentService = ContentService(apiClient, _dbService);
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

        // Get record data (name, phone) from record via recordUuid
        String name = '';
        String phone = '';
        if (_dbService is PRDDatabaseService) {
          final prdDb = _dbService as PRDDatabaseService;
          final record = await prdDb.getRecordByUuid(refreshedEvent.recordUuid);
          if (record != null) {
            name = record.name ?? '';
            phone = record.phone ?? '';
          }
        }

        _updateState(_state.copyWith(
          name: name,
          recordNumber: refreshedEvent.recordNumber,
          phone: phone,
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


  }

  /// Load note from server
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
      _updateState(_state.copyWith(
        isLoadingFromServer: false,
        isOffline: true,
      ));
      throw Exception('Failed to load note: Cannot connect to server');
    }

    _updateState(_state.copyWith(isLoadingFromServer: false));
  }

  /// Save event with handwriting note
  Future<Event> saveEvent() async {

    final pages = _state.lastKnownPages;

    _updateState(_state.copyWith(isLoading: true));

    try {
      final nameText = _state.name.trim();
      final recordNumberText = _state.recordNumber.trim();
      final phoneText = _state.phone.trim();

      // Check if user cleared the end time (converting close-end to open-end event)
      final shouldClearEndTime = event.endTime != null && _state.endTime == null;

      if (_dbService is! PRDDatabaseService) {
        throw Exception('PRDDatabaseService required');
      }
      final prdDb = _dbService as PRDDatabaseService;

      Event savedEvent;
      if (isNew) {
        // Create new event with record handling
        savedEvent = await prdDb.createEventWithRecord(
          bookUuid: event.bookUuid,
          name: nameText,
          recordNumber: recordNumberText.isEmpty ? null : recordNumberText,
          phone: phoneText.isEmpty ? null : phoneText,
          eventTypes: _state.selectedEventTypes,
          startTime: _state.startTime,
          endTime: _state.endTime,
        );

        // Check for existing note for this record
        if (recordNumberText.isNotEmpty) {
          final existingNote = await prdDb.findNoteByRecordNumber(recordNumberText);
          if (existingNote != null && existingNote.isNotEmpty) {
            // Load existing note (safety: never lose existing patient data)
            _updateState(_state.copyWith(
              note: existingNote,
              lastKnownPages: existingNote.pages,
            ));
            // Save to server
            await saveNoteToServer(savedEvent.id!, existingNote.pages);
            return savedEvent;
          }
        }
      } else {
        // Update existing event with record handling
        savedEvent = await prdDb.updateEventWithRecord(
          event: event,
          name: nameText,
          recordNumber: recordNumberText.isEmpty ? null : recordNumberText,
          phone: phoneText.isEmpty ? null : phoneText,
          eventTypes: _state.selectedEventTypes,
          startTime: _state.startTime,
          endTime: _state.endTime,
          clearEndTime: shouldClearEndTime,
        );

        // Check if record_number was added and there's an existing note
        final oldRecordNumber = event.recordNumber.trim();
        final recordNumberAdded = oldRecordNumber.isEmpty && recordNumberText.isNotEmpty;

        if (recordNumberAdded) {
          final existingNote = await prdDb.findNoteByRecordNumber(recordNumberText);
          if (existingNote != null && existingNote.isNotEmpty) {
            // Load existing note
            _updateState(_state.copyWith(
              note: existingNote,
              lastKnownPages: existingNote.pages,
            ));
            // Save to server
            await saveNoteToServer(savedEvent.id!, existingNote.pages);
            return savedEvent;
          }
        }
      }

      // Save handwriting note to server
      await saveNoteToServer(savedEvent.id!, pages);

      return savedEvent;
    } catch (e) {
      _updateState(_state.copyWith(isLoading: false));
      rethrow;
    }
  }

  /// Save note directly to server
  Future<void> saveNoteToServer(String eventId, List<List<Stroke>> pages) async {
    if (_noteSyncAdapter == null) {
      throw Exception('Cannot save: Services not initialized');
    }

    // Get the event to get its recordUuid
    if (_dbService is! PRDDatabaseService) {
      throw Exception('Database service error');
    }
    final prdDb = _dbService as PRDDatabaseService;
    final eventData = await prdDb.getEventById(eventId);
    if (eventData == null) {
      throw Exception('Event not found');
    }

    final noteToSave = Note(
      recordUuid: eventData.recordUuid,
      pages: pages,
      createdAt: _state.note?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Save directly to server (no local cache)
    await _noteSyncAdapter!.saveNote(eventId, noteToSave);

    // Update UI state on success
    _updateState(_state.copyWith(
      note: noteToSave,
      hasChanges: false,
      hasUnsyncedChanges: false,
      lastKnownPages: pages,
    ));
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

  /// Save phone number to record table
  /// Note: Phone is now stored in the records table, not person_info
  Future<void> savePhone() async {
    final recordNumber = _state.recordNumber.trim();
    final phone = _state.phone.trim();

    // Only save if we have a record number
    if (recordNumber.isEmpty) {
      return;
    }

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;

      // Get record by record number and update phone
      final record = await prdDb.getRecordByRecordNumber(recordNumber);
      if (record != null && record.recordUuid != null) {
        await prdDb.updateRecord(
          recordUuid: record.recordUuid!,
          phone: phone.isEmpty ? null : phone,
        );
      }
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

    final recordNumber = _state.recordNumber.trim();

    if (recordNumber.isEmpty) {
      return null;
    }

    if (_dbService is PRDDatabaseService) {
      final prdDb = _dbService as PRDDatabaseService;
      return await prdDb.findNoteByRecordNumber(recordNumber);
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
      name = await prdDb.getNameByRecordNumber(recordNumber);
    }

    if (name == null || name.isEmpty) {
      return; // No person found with this record number
    }

    // Step 3: Fetch phone number from record
    final phone = await prdDb.getPhoneByRecordNumber(recordNumber);

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
        noteToLoad = await prdDb.findNoteByRecordNumber(recordNumber);
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
