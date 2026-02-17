import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/charge_item.dart';
import '../../models/note.dart';
import '../../services/database_service_interface.dart';
import '../../services/database/prd_database_service.dart';
import '../../services/content_service.dart';
import '../../services/api_client.dart';
import '../../services/server_config_service.dart';
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
  final ConnectivityWatcher _connectivityWatcher;
  StreamSubscription<bool>? _connectivitySubscription;

  // State tracking
  EventDetailState _state;
  int _noteEditGeneration = 0;
  bool _noteEditedInSession = false;

  EventDetailController({
    required this.event,
    required this.isNew,
    required IDatabaseService dbService,
    required this.onStateChanged,
    ContentService? contentService,
    NoteSyncAdapter? noteSyncAdapter,
    ServerHealthChecker? serverHealthChecker,
    ConnectivityWatcher? connectivityWatcher,
  }) : _dbService = dbService,
       _contentService = contentService,
       _noteSyncAdapter =
           noteSyncAdapter ??
           (contentService != null ? NoteSyncAdapter(contentService) : null),
       _serverHealthChecker =
           serverHealthChecker ??
           (contentService != null
               ? ServerHealthChecker(contentService)
               : null),
       _connectivityWatcher = connectivityWatcher ?? ConnectivityWatcher(),
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

      final apiClient = ApiClient(baseUrl: serverUrl);
      _contentService = ContentService(apiClient, _dbService);
      _noteSyncAdapter = NoteSyncAdapter(_contentService!);
      _serverHealthChecker = ServerHealthChecker(_contentService!);

      // Mark services as ready
      _updateState(_state.copyWith(isServicesReady: true));

      // Step 1.5: Check actual server connectivity on startup
      final serverReachable = await _checkServerConnectivity();
      _updateState(_state.copyWith(isOffline: !serverReachable));

      // Step 2: Load initial data (now that ContentService is ready)
      if (!isNew) {
        await _logLocalEventSnapshot();
        await _refreshEventFromServer();
        await loadNote();
        await loadChargeItems(); // Load charge items from charge_items table
        if (event.hasNewTime) {
          await _loadNewEvent();
        }
      }
    } catch (e) {
      // Mark services as ready anyway to avoid blocking UI forever
      _updateState(
        _state.copyWith(
          isServicesReady: true,
          isOffline: true, // Mark as offline since initialization failed
        ),
      );

      rethrow; // Let the caller handle showing error to user
    }
  }

  /// Load new event for time change display
  Future<void> _loadNewEvent() async {
    if (event.newEventId == null) return;
    try {
      final newEvent = await _dbService.getEventById(event.newEventId!);
      _updateState(_state.copyWith(newEvent: newEvent));
    } catch (e) {}
  }

  Future<void> _refreshEventFromServer() async {
    if (_contentService == null || event.id == null) {
      return;
    }

    try {
      await _logEventTime('before_server_fetch', event);
      final refreshedEvent = await _contentService!.refreshEventFromServer(
        event.id!,
      );
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

        _updateState(
          _state.copyWith(
            name: name,
            recordNumber: refreshedEvent.recordNumber,
            phone: phone,
            selectedEventTypes: refreshedEvent.eventTypes,
            startTime: refreshedEvent.startTime,
            endTime: refreshedEvent.endTime,
          ),
        );
        await _logStateTime('after_state_update');
      }
    } catch (e) {}
  }

  /// Setup network connectivity monitoring for automatic sync retry
  void setupConnectivityMonitoring() {
    _connectivityWatcher.startWatching();
    _connectivitySubscription = _connectivityWatcher.onConnectivityChanged
        .listen((hasConnection) {
          _onConnectivityChanged(hasConnection);
        });
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

    _updateState(_state.copyWith(isOffline: !serverReachable));
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
      Note? serverNote;
      if (event.recordUuid.isNotEmpty) {
        serverNote = await _noteSyncAdapter!.getNoteByRecordUuid(
          event.bookUuid,
          event.recordUuid,
        );
      }

      if (_noteEditGeneration != noteLoadGeneration) {
        _updateState(_state.copyWith(isLoadingFromServer: false));
        return;
      }

      if (serverNote != null) {
        _updateState(
          _state.copyWith(
            note: serverNote,
            lastKnownPages: serverNote.pages,
            erasedStrokesByEvent: serverNote.erasedStrokesByEvent,
            hasUnsyncedChanges: false,
            isLoadingFromServer: false,
            isOffline: false,
          ),
        );
        _noteEditedInSession = false;
        return;
      } else {}
    } catch (e) {
      _updateState(
        _state.copyWith(isLoadingFromServer: false, isOffline: true),
      );
      throw Exception('Failed to load note: Cannot connect to server');
    }

    _updateState(_state.copyWith(isLoadingFromServer: false));
  }

  /// Save event with handwriting note
  Future<Event> saveEvent({Size? canvasSize}) async {
    final pages = _state.lastKnownPages;

    _updateState(_state.copyWith(isLoading: true));

    try {
      final nameText = _state.name.trim();
      final recordNumberText = _state.recordNumber.trim();
      final phoneText = _state.phone.trim();

      // Check if user cleared the end time (converting close-end to open-end event)
      final shouldClearEndTime =
          event.endTime != null && _state.endTime == null;

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
          eventId: event.id,
        );

        // Check for existing note for this record
        if (recordNumberText.isNotEmpty) {
          final existingNote = await _fetchExistingNoteForRecordNumber(
            recordNumber: recordNumberText,
            name: nameText,
          );
          if (existingNote != null && existingNote.isNotEmpty) {
            // Load existing note (safety: never lose existing patient data)
            _updateState(
              _state.copyWith(
                note: existingNote,
                lastKnownPages: existingNote.pages,
              ),
            );
            // Loaded existing note only; do not save unless user edited note in this session.
            _noteEditedInSession = false;
            await _syncMetadataToServer(
              eventData: savedEvent,
              name: nameText,
              recordNumber: recordNumberText,
              phone: phoneText.isEmpty ? null : phoneText,
              allowCreateOnMissingEvent: true,
            );
            _updateState(
              _state.copyWith(
                isLoading: false,
                hasChanges: false,
                hasUnsyncedChanges: false,
              ),
            );
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
        final recordNumberAdded =
            oldRecordNumber.isEmpty && recordNumberText.isNotEmpty;
        final recordRelinked =
            event.recordUuid.isNotEmpty &&
            savedEvent.recordUuid != event.recordUuid;
        final shouldCarryForwardCurrentNote =
            recordNumberAdded &&
            recordRelinked &&
            _hasCurrentNoteContent(pages);

        if (recordNumberAdded) {
          final existingNote = await _fetchExistingNoteForRecordNumber(
            recordNumber: recordNumberText,
            name: nameText,
          );
          if (existingNote != null &&
              existingNote.isNotEmpty &&
              !shouldCarryForwardCurrentNote) {
            // Load existing note
            _updateState(
              _state.copyWith(
                note: existingNote,
                lastKnownPages: existingNote.pages,
              ),
            );
            // Loaded existing note only; do not save unless user edited note in this session.
            _noteEditedInSession = false;
            await _syncMetadataToServer(
              eventData: savedEvent,
              name: nameText,
              recordNumber: recordNumberText,
              phone: phoneText.isEmpty ? null : phoneText,
              allowCreateOnMissingEvent: false,
            );
            _updateState(
              _state.copyWith(
                isLoading: false,
                hasChanges: false,
                hasUnsyncedChanges: false,
              ),
            );
            return savedEvent;
          }
        }

        if (shouldCarryForwardCurrentNote && !_noteEditedInSession) {
          _noteEditedInSession = true;
        }
      }

      // Save handwriting note only when this event actually edited note content.
      if (_shouldSaveNote(pages)) {
        await saveNoteToServer(savedEvent.id!, pages, canvasSize: canvasSize);
      }
      await _syncMetadataToServer(
        eventData: savedEvent,
        name: nameText,
        recordNumber: recordNumberText,
        phone: phoneText.isEmpty ? null : phoneText,
        allowCreateOnMissingEvent: isNew,
      );
      _updateState(
        _state.copyWith(
          isLoading: false,
          hasChanges: false,
          hasUnsyncedChanges: false,
        ),
      );

      return savedEvent;
    } catch (e) {
      _updateState(_state.copyWith(isLoading: false));
      rethrow;
    }
  }

  /// Save note directly to server
  Future<void> saveNoteToServer(
    String eventId,
    List<List<Stroke>> pages, {
    Size? canvasSize,
  }) async {
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

    Note? baseNote;
    if (eventData.recordUuid.isNotEmpty) {
      baseNote = await _noteSyncAdapter!.getNoteByRecordUuid(
        eventData.bookUuid,
        eventData.recordUuid,
      );
    }

    final nextVersion = (baseNote?.version ?? 0) + 1;
    final canvasWidth = canvasSize?.width ?? baseNote?.canvasWidth;
    final canvasHeight = canvasSize?.height ?? baseNote?.canvasHeight;

    // Merge erased strokes from base note and current state
    final mergedErasedStrokes = Map<String, List<String>>.from(
      baseNote?.erasedStrokesByEvent ?? {},
    );
    for (final entry in _state.erasedStrokesByEvent.entries) {
      final existingList = mergedErasedStrokes[entry.key] ?? [];
      final newList = [...existingList];
      for (final id in entry.value) {
        if (!newList.contains(id)) {
          newList.add(id);
        }
      }
      mergedErasedStrokes[entry.key] = newList;
    }

    final noteToSave = Note(
      recordUuid: eventData.recordUuid,
      pages: pages,
      erasedStrokesByEvent: mergedErasedStrokes,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      createdAt: baseNote?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      version: nextVersion,
    );
    debugPrint(
      '[EventDetail] saveNoteToServer: eventId=$eventId '
      'recordUuid=${eventData.recordUuid} '
      'baseVersion=${baseNote?.version} nextVersion=$nextVersion',
    );

    // Save directly to server (no local cache)
    final savedNote = await _saveNoteWithConflictRetry(
      eventId: eventId,
      eventData: eventData,
      noteToSave: noteToSave,
    );
    _noteEditedInSession = false;

    // Update UI state on success
    _updateState(
      _state.copyWith(
        note: savedNote,
        hasChanges: false,
        hasUnsyncedChanges: false,
        lastKnownPages: savedNote.pages,
      ),
    );
  }

  Future<Note> _saveNoteWithConflictRetry({
    required String eventId,
    required Event eventData,
    required Note noteToSave,
    int retryCount = 0,
  }) async {
    const maxRetries = 2;

    try {
      return await _noteSyncAdapter!.saveNote(eventId, noteToSave);
    } on ApiConflictException catch (e) {
      if (retryCount >= maxRetries) {
        rethrow;
      }

      debugPrint(
        '[EventDetail] note save conflict: eventId=$eventId '
        'recordUuid=${eventData.recordUuid} '
        'clientVersion=${noteToSave.version} serverVersion=${e.serverVersion} '
        'retry=${retryCount + 1}/$maxRetries',
      );

      Note? serverNote;
      if (eventData.recordUuid.isNotEmpty) {
        serverNote = await _noteSyncAdapter!.getNoteByRecordUuid(
          eventData.bookUuid,
          eventData.recordUuid,
        );
      }

      final mergedPages = _mergeNotePages(
        serverPages: serverNote?.pages ?? const [[]],
        localPages: noteToSave.pages,
      );
      final mergedErasedStrokes = _mergeErasedStrokesByEvent(
        server: serverNote?.erasedStrokesByEvent ?? const {},
        local: noteToSave.erasedStrokesByEvent,
      );
      final baseVersion =
          serverNote?.version ?? e.serverVersion ?? noteToSave.version;

      final retryNote = noteToSave.copyWith(
        pages: mergedPages,
        erasedStrokesByEvent: mergedErasedStrokes,
        canvasWidth: noteToSave.canvasWidth ?? serverNote?.canvasWidth,
        canvasHeight: noteToSave.canvasHeight ?? serverNote?.canvasHeight,
        createdAt: serverNote?.createdAt ?? noteToSave.createdAt,
        updatedAt: DateTime.now(),
        version: baseVersion + 1,
      );

      return _saveNoteWithConflictRetry(
        eventId: eventId,
        eventData: eventData,
        noteToSave: retryNote,
        retryCount: retryCount + 1,
      );
    }
  }

  List<List<Stroke>> _mergeNotePages({
    required List<List<Stroke>> serverPages,
    required List<List<Stroke>> localPages,
  }) {
    final pageCount = math.max(serverPages.length, localPages.length);
    if (pageCount == 0) {
      return const [[]];
    }

    final mergedPages = <List<Stroke>>[];
    for (int i = 0; i < pageCount; i++) {
      final serverPage = i < serverPages.length
          ? serverPages[i]
          : const <Stroke>[];
      final localPage = i < localPages.length
          ? localPages[i]
          : const <Stroke>[];
      mergedPages.add(_mergePageStrokes(serverPage, localPage));
    }

    return mergedPages;
  }

  List<Stroke> _mergePageStrokes(List<Stroke> server, List<Stroke> local) {
    if (server.isEmpty) return List<Stroke>.from(local);
    if (local.isEmpty) return List<Stroke>.from(server);

    final byId = <String, Stroke>{};
    final localNullId = <Stroke>[];
    for (final stroke in server) {
      final id = stroke.id;
      if (id != null && id.isNotEmpty) {
        byId[id] = stroke;
      }
    }
    for (final stroke in local) {
      final id = stroke.id;
      if (id != null && id.isNotEmpty) {
        byId[id] = stroke;
      } else {
        localNullId.add(stroke);
      }
    }

    final merged = <Stroke>[];
    final addedIds = <String>{};

    for (final stroke in server) {
      final id = stroke.id;
      if (id != null && id.isNotEmpty) {
        final chosen = byId[id] ?? stroke;
        merged.add(chosen);
        addedIds.add(id);
      } else {
        merged.add(stroke);
      }
    }

    for (final stroke in local) {
      final id = stroke.id;
      if (id == null || id.isEmpty) continue;
      if (addedIds.contains(id)) continue;
      merged.add(stroke);
      addedIds.add(id);
    }

    merged.addAll(localNullId);
    return merged;
  }

  Map<String, List<String>> _mergeErasedStrokesByEvent({
    required Map<String, List<String>> server,
    required Map<String, List<String>> local,
  }) {
    final merged = <String, List<String>>{};

    for (final entry in server.entries) {
      merged[entry.key] = List<String>.from(entry.value);
    }

    for (final entry in local.entries) {
      final current = merged[entry.key] ?? <String>[];
      final next = <String>[...current];
      for (final id in entry.value) {
        if (!next.contains(id)) {
          next.add(id);
        }
      }
      merged[entry.key] = next;
    }

    return merged;
  }

  Map<String, dynamic> _buildEventSyncPayload(
    Event eventData, {
    required String name,
    required String? phone,
  }) {
    final payload = Map<String, dynamic>.from(eventData.toMap());
    // has_note must always be derived on server from stroke ownership.
    payload.remove('has_note');
    payload.remove('hasNote');
    payload['name'] = name;
    payload['record_name'] = name;
    payload['recordName'] = name;
    payload['phone'] = phone;
    payload['eventTypes'] = eventData.eventTypes.map((t) => t.name).toList();
    return payload;
  }

  Future<void> _syncMetadataToServer({
    required Event eventData,
    required String name,
    required String recordNumber,
    required String? phone,
    bool allowCreateOnMissingEvent = false,
  }) async {
    if (_contentService == null) {
      throw Exception('Cannot sync metadata: Services not initialized');
    }
    if (eventData.id == null) {
      throw Exception('Cannot sync metadata: Event ID is missing');
    }
    if (_dbService is! PRDDatabaseService) return;

    final prdDb = _dbService as PRDDatabaseService;
    final credentials = await prdDb.getDeviceCredentials();
    if (credentials == null) {
      throw Exception('Device not registered, cannot sync metadata to server');
    }

    try {
      final apiClient = _contentService!.apiClient;
      final eventPayload = _buildEventSyncPayload(
        eventData,
        name: name,
        phone: phone,
      );
      Map<String, dynamic>? syncedEventPayload;

      debugPrint(
        '[EventDetail] metadata sync start: eventId=${eventData.id} '
        'bookUuid=${eventData.bookUuid} recordUuid=${eventData.recordUuid} '
        'recordNumber="$recordNumber" allowCreateOnMissingEvent=$allowCreateOnMissingEvent',
      );

      try {
        syncedEventPayload = await apiClient.updateEvent(
          bookUuid: eventData.bookUuid,
          eventId: eventData.id!,
          eventData: eventPayload,
          deviceId: credentials.deviceId,
          deviceToken: credentials.deviceToken,
        );
      } on ApiException catch (e) {
        final shouldCreateFallback =
            allowCreateOnMissingEvent && e.statusCode == 404;
        if (!shouldCreateFallback) {
          rethrow;
        }

        debugPrint(
          '[EventDetail] metadata sync updateEvent 404 for eventId=${eventData.id}; '
          'falling back to createEvent',
        );
        syncedEventPayload = await apiClient.createEvent(
          bookUuid: eventData.bookUuid,
          eventData: eventPayload,
          deviceId: credentials.deviceId,
          deviceToken: credentials.deviceToken,
        );
      }

      if (eventData.recordUuid.isNotEmpty) {
        final recordData = {
          'name': name,
          'phone': phone,
          'record_number': recordNumber,
        };
        var recordUuidForSync = eventData.recordUuid;
        final serverRecordUuid = _extractRecordUuidFromEventPayload(
          syncedEventPayload,
        );
        if (serverRecordUuid != null &&
            serverRecordUuid.isNotEmpty &&
            serverRecordUuid != recordUuidForSync) {
          debugPrint(
            '[EventDetail] metadata sync record_uuid remap from event response: '
            'local=$recordUuidForSync server=$serverRecordUuid',
          );
          recordUuidForSync = serverRecordUuid;
        }

        debugPrint(
          '[EventDetail] metadata sync updateRecord start: '
          'eventId=${eventData.id} recordUuid=$recordUuidForSync',
        );

        try {
          await apiClient.updateRecord(
            recordUuid: recordUuidForSync,
            recordData: recordData,
            deviceId: credentials.deviceId,
            deviceToken: credentials.deviceToken,
          );
        } on ApiException catch (e) {
          final shouldRetryWithServerRecord =
              e.statusCode == 404 && recordUuidForSync == eventData.recordUuid;
          if (!shouldRetryWithServerRecord) {
            rethrow;
          }

          debugPrint(
            '[EventDetail] metadata sync updateRecord 404: '
            'recordUuid=${eventData.recordUuid}; fetching server event for remap',
          );
          final serverEvent = await apiClient.fetchEvent(
            bookUuid: eventData.bookUuid,
            eventId: eventData.id!,
            deviceId: credentials.deviceId,
            deviceToken: credentials.deviceToken,
          );
          final retryRecordUuid = _extractRecordUuidFromEventPayload(
            serverEvent,
          );
          if (retryRecordUuid == null || retryRecordUuid.isEmpty) {
            rethrow;
          }

          debugPrint(
            '[EventDetail] metadata sync retry updateRecord with server recordUuid=$retryRecordUuid',
          );
          await apiClient.updateRecord(
            recordUuid: retryRecordUuid,
            recordData: recordData,
            deviceId: credentials.deviceId,
            deviceToken: credentials.deviceToken,
          );
          recordUuidForSync = retryRecordUuid;
        }

        if (recordUuidForSync != eventData.recordUuid) {
          await _updateLocalEventRecordUuid(
            eventId: eventData.id!,
            recordUuid: recordUuidForSync,
          );
        }
      }

      debugPrint(
        '[EventDetail] metadata sync success: eventId=${eventData.id}',
      );
      _updateState(_state.copyWith(isOffline: false));
    } catch (e) {
      if (e is ApiException) {
        debugPrint(
          '[EventDetail] metadata sync failed: eventId=${eventData.id} '
          'status=${e.statusCode} body=${e.responseBody}',
        );
      } else {
        debugPrint(
          '[EventDetail] metadata sync failed: eventId=${eventData.id} error=$e',
        );
      }
      _updateState(_state.copyWith(isOffline: true));
      rethrow;
    }
  }

  String? _extractRecordUuidFromEventPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final value = payload['record_uuid'] ?? payload['recordUuid'];
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  Future<void> _updateLocalEventRecordUuid({
    required String eventId,
    required String recordUuid,
  }) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }
    final prdDb = _dbService as PRDDatabaseService;
    final localEvent = await prdDb.getEventById(eventId);
    if (localEvent == null) {
      return;
    }

    if (localEvent.recordUuid == recordUuid) {
      return;
    }

    final localRecord = await prdDb.getRecordByUuid(recordUuid);
    if (localRecord == null) {
      debugPrint(
        '[EventDetail] local event record_uuid update skipped: '
        'target record not found locally (eventId=$eventId target=$recordUuid)',
      );
      return;
    }

    debugPrint(
      '[EventDetail] local event record_uuid update: eventId=$eventId '
      'from=${localEvent.recordUuid} to=$recordUuid',
    );
    final updatedEvent = localEvent.copyWith(recordUuid: recordUuid);
    await prdDb.updateEvent(updatedEvent);
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
  Future<void> changeEventTime(
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  ) async {
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
    _updateState(
      _state.copyWith(
        recordNumber: recordNumber,
        hasChanges: true,
        clearRecordNumberError: true, // Clear error when user types
      ),
    );

    // Note: Charge items are now loaded based on recordUuid from the event,
    // not from name/recordNumber. They will be reloaded when the event is saved
    // and the recordUuid is updated.
  }

  /// Validate record number on blur (when user leaves the field)
  /// Returns true if valid, false if there's a conflict
  Future<bool> validateRecordNumberOnBlur() async {
    final recordNumber = _state.recordNumber.trim();
    final name = _state.name.trim();

    // Empty record number is always valid (treated as "留空")
    if (recordNumber.isEmpty) {
      _updateState(_state.copyWith(clearRecordNumberError: true));
      return true;
    }

    _updateState(_state.copyWith(isValidatingRecordNumber: true));

    try {
      // Check if we have PRD database service
      if (_dbService is! PRDDatabaseService) {
        _updateState(
          _state.copyWith(
            isValidatingRecordNumber: false,
            clearRecordNumberError: true,
          ),
        );
        return true;
      }

      final prdDb = _dbService as PRDDatabaseService;
      final credentials = await prdDb.getDeviceCredentials();

      if (credentials == null) {
        // Truly offline - no credentials - fall back to local validation only
        final localRecord = await prdDb.getRecordByRecordNumber(recordNumber);
        if (localRecord != null &&
            localRecord.name != null &&
            localRecord.name != name) {
          _updateState(
            _state.copyWith(
              isValidatingRecordNumber: false,
              recordNumberError: '病例號已存在',
              recordNumber: '', // Clear the record number field
            ),
          );
          return false;
        }
        _updateState(
          _state.copyWith(
            isValidatingRecordNumber: false,
            clearRecordNumberError: true,
          ),
        );
        return true;
      }

      if (_contentService == null) {
        // Online but not initialized yet - cannot validate properly
        // Return false to prevent proceeding without validation
        _updateState(
          _state.copyWith(
            isValidatingRecordNumber: false,
            recordNumberError: '服務初始化中，請稍後再試',
          ),
        );
        return false;
      }

      // Call server validation API
      final result = await _contentService!.apiClient.validateRecordNumber(
        recordNumber: recordNumber,
        name: name,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      if (result.hasConflict) {
        _updateState(
          _state.copyWith(
            isValidatingRecordNumber: false,
            recordNumberError: '病例號已存在',
            recordNumber: '', // Clear the record number field
          ),
        );
        return false;
      }

      _updateState(
        _state.copyWith(
          isValidatingRecordNumber: false,
          clearRecordNumberError: true,
        ),
      );
      return true;
    } catch (e) {
      // On error, do NOT allow user to continue - validation failed
      debugPrint(
        '[EventDetailController] validateRecordNumberOnBlur error: $e',
      );
      _updateState(
        _state.copyWith(
          isValidatingRecordNumber: false,
          recordNumberError: '驗證失敗，請稍後再試',
        ),
      );
      return false;
    }
  }

  /// Clear record number validation error
  void clearRecordNumberError() {
    if (_state.recordNumberError != null) {
      _updateState(_state.copyWith(clearRecordNumberError: true));
    }
  }

  /// Update phone
  void updatePhone(String phone) {
    _updateState(_state.copyWith(phone: phone, hasChanges: true));
  }

  /// Update event types
  void updateEventTypes(List<EventType> eventTypes) {
    _updateState(
      _state.copyWith(selectedEventTypes: eventTypes, hasChanges: true),
    );
  }

  /// Load charge items for the current event (based on record_uuid)
  /// If showOnlyThisEventItems is true, only show items associated with this event
  Future<void> loadChargeItems() async {
    // Need recordUuid to load charge items
    if (event.recordUuid.isEmpty) {
      _updateState(_state.copyWith(chargeItems: []));
      return;
    }

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;

      List<ChargeItem> chargeItems;
      if (_state.showOnlyThisEventItems && event.id != null) {
        // Get only items associated with this event
        chargeItems = await prdDb.getChargeItemsByRecordAndEvent(
          event.recordUuid,
          eventId: event.id,
        );
      } else {
        // Get all items for the record
        chargeItems = await prdDb.getChargeItemsByRecordUuid(event.recordUuid);
      }

      _updateState(_state.copyWith(chargeItems: chargeItems));
    } catch (e) {}
  }

  /// Toggle the filter to show all items or only this event's items
  Future<void> toggleChargeItemsFilter() async {
    _updateState(
      _state.copyWith(showOnlyThisEventItems: !_state.showOnlyThisEventItems),
    );
    await loadChargeItems();
  }

  /// Save phone number to record table
  /// Note: Phone is now stored in the records table, not person_info
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

      // Get record by name AND record number and update phone
      final record = await prdDb.getRecordByNameAndRecordNumber(
        name,
        recordNumber,
      );
      if (record != null && record.recordUuid != null) {
        await prdDb.updateRecord(
          recordUuid: record.recordUuid!,
          phone: phone.isEmpty ? null : phone,
        );
      }
    } catch (e) {}
  }

  /// Add a new charge item
  /// If associateWithEvent is true, the item will be linked to this event
  Future<void> addChargeItem(
    ChargeItem item, {
    bool associateWithEvent = false,
  }) async {
    if (event.recordUuid.isEmpty) {
      return;
    }

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;

      // Check if item already exists
      final exists = await prdDb.chargeItemExists(
        recordUuid: event.recordUuid,
        eventId: associateWithEvent ? event.id : null,
        itemName: item.itemName,
      );

      if (exists) {
        // TODO: Show error message to user
        return;
      }

      // Create charge item with recordUuid from event
      final newItem = item.copyWith(
        recordUuid: event.recordUuid,
        eventId: associateWithEvent ? event.id : null,
      );

      // Save to database
      await prdDb.saveChargeItem(newItem);

      // Reload all charge items
      await loadChargeItems();
    } catch (e) {}
  }

  /// Edit an existing charge item
  Future<void> editChargeItem(ChargeItem item) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;

      // Check if new name conflicts with existing item
      final exists = await prdDb.chargeItemExists(
        recordUuid: item.recordUuid,
        eventId: item.eventId,
        itemName: item.itemName,
        excludeId: item.id,
      );

      if (exists) {
        // TODO: Show error message to user
        return;
      }

      // Get existing item
      final existingItem = await prdDb.getChargeItemById(item.id);
      if (existingItem == null) {
        return;
      }

      // Update item - preserve recordUuid and eventId
      final updatedItem = existingItem.copyWith(
        itemName: item.itemName,
        itemPrice: item.itemPrice,
        receivedAmount: item.receivedAmount,
      );

      await prdDb.saveChargeItem(updatedItem);

      // Reload all charge items
      await loadChargeItems();
    } catch (e) {}
  }

  /// Delete a charge item
  Future<void> deleteChargeItem(ChargeItem item) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      await prdDb.deleteChargeItem(item.id);

      // Reload all charge items
      await loadChargeItems();
    } catch (e) {}
  }

  /// Toggle paid status of a charge item
  /// Sets receivedAmount to itemPrice if not paid, or 0 if paid
  Future<void> toggleChargeItemPaidStatus(ChargeItem item) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      // Toggle: if not fully paid, set to full price; if fully paid, set to 0
      final newReceivedAmount = item.isPaid ? 0 : item.itemPrice;
      await prdDb.updateChargeItemReceivedAmount(
        id: item.id,
        receivedAmount: newReceivedAmount,
      );

      // Reload all charge items
      await loadChargeItems();
    } catch (e) {}
  }

  /// Update the received amount of a charge item
  Future<void> updateChargeItemReceivedAmount(
    ChargeItem item,
    int receivedAmount,
  ) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      await prdDb.updateChargeItemReceivedAmount(
        id: item.id,
        receivedAmount: receivedAmount,
      );

      // Reload all charge items
      await loadChargeItems();
    } catch (e) {}
  }

  /// Update charge items (legacy method - kept for compatibility but now loads from database)
  @Deprecated(
    'Use addChargeItem, editChargeItem, deleteChargeItem, or toggleChargeItemPaidStatus instead',
  )
  void updateChargeItems(List<ChargeItem> chargeItems) {
    _updateState(_state.copyWith(chargeItems: chargeItems, hasChanges: true));
  }

  Future<Note?> _fetchExistingNoteForRecordNumber({
    required String recordNumber,
    String? name,
  }) async {
    final trimmedRecordNumber = recordNumber.trim();
    if (trimmedRecordNumber.isEmpty) {
      return null;
    }

    if (_dbService is! PRDDatabaseService) {
      return null;
    }

    final prdDb = _dbService as PRDDatabaseService;
    final nameText = (name ?? _state.name).trim();

    var record = nameText.isNotEmpty
        ? await prdDb.getRecordByNameAndRecordNumber(
            nameText,
            trimmedRecordNumber,
          )
        : null;
    record ??= await prdDb.getRecordByRecordNumber(trimmedRecordNumber);

    final recordUuid = record?.recordUuid ?? '';
    if (recordUuid.isEmpty) {
      return null;
    }

    if (_noteSyncAdapter != null) {
      try {
        final serverNote = await _noteSyncAdapter!.getNoteByRecordUuid(
          event.bookUuid,
          recordUuid,
        );
        if (serverNote != null) {
          return serverNote;
        }
      } catch (e) {
        return null;
      }
    }

    return null;
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

    return await _fetchExistingNoteForRecordNumber(recordNumber: recordNumber);
  }

  /// Load existing person note (when user chooses "載入現有")
  /// Replaces current canvas with DB handwriting
  Future<void> loadExistingPersonNote(Note existingNote) async {
    _updateState(
      _state.copyWith(note: existingNote, lastKnownPages: existingNote.pages),
    );
    _noteEditedInSession = false;
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
          .map(
            (item) => RecordNumberOption(
              recordNumber: item['recordNumber']!,
              name: item['name']!,
            ),
          )
          .toList();
    }
    return [];
  }

  /// Handle name field focused - clear record number
  void onNameFieldFocused() {
    if (_state.recordNumber.trim().isNotEmpty) {
      _updateState(
        _state.copyWith(
          recordNumber: '',
          isNameReadOnly: false,
          hasChanges: true,
        ),
      );
    }
  }

  /// Handle record number field focused - clear name
  void onRecordNumberFieldFocused() {
    if (_state.name.trim().isNotEmpty) {
      _updateState(
        _state.copyWith(name: '', isNameReadOnly: false, hasChanges: true),
      );
    }
  }

  /// Handle record number selected - auto-fill name, phone, and note
  Future<void> onRecordNumberSelected(String recordNumber) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    final prdDb = _dbService as PRDDatabaseService;
    final name = await prdDb.getNameByRecordNumber(recordNumber);
    if (name == null || name.isEmpty) {
      return;
    }

    final phone = await prdDb.getPhoneByRecordNumber(recordNumber);

    _updateState(
      _state.copyWith(
        name: name,
        recordNumber: recordNumber,
        phone: phone ?? '',
        isNameReadOnly: true,
        hasChanges: true,
      ),
    );

    // Note: Charge items are loaded based on recordUuid from the event.
    // For existing events, they're already loaded. For new events, they'll be
    // loaded after the event is saved and the recordUuid is established.

    // Load person note from server.
    try {
      final noteToLoad = await _fetchExistingNoteForRecordNumber(
        recordNumber: recordNumber,
        name: name,
      );

      if (noteToLoad != null && noteToLoad.isNotEmpty) {
        loadExistingPersonNote(noteToLoad);
      }
    } catch (e) {}
  }

  /// Handle name selected from autocomplete - set editable mode
  void onNameSelected(String name) {
    _updateState(
      _state.copyWith(name: name, isNameReadOnly: false, hasChanges: true),
    );
  }

  /// Clear record number (called when "留空" option is selected)
  void clearRecordNumber() {
    _updateState(
      _state.copyWith(
        recordNumber: '',
        isNameReadOnly: false,
        hasChanges: true,
      ),
    );
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
    _updateState(_state.copyWith(lastKnownPages: pages, hasChanges: true));
    _noteEditedInSession = true;
    _incrementNoteGeneration();
  }

  /// Track erased strokes for the current event
  void onStrokesErased(List<String> erasedStrokeIds) {
    if (erasedStrokeIds.isEmpty || event.id == null) return;

    final currentEventId = event.id!;
    final updatedMap = Map<String, List<String>>.from(
      _state.erasedStrokesByEvent,
    );
    final existingList = updatedMap[currentEventId] ?? [];
    // Add new erased stroke IDs (avoiding duplicates)
    final newList = [...existingList];
    for (final id in erasedStrokeIds) {
      if (!newList.contains(id)) {
        newList.add(id);
      }
    }
    updatedMap[currentEventId] = newList;

    _updateState(
      _state.copyWith(erasedStrokesByEvent: updatedMap, hasChanges: true),
    );
    _noteEditedInSession = true;
  }

  void _incrementNoteGeneration() {
    _noteEditGeneration++;
  }

  bool _hasCurrentNoteContent(List<List<Stroke>> pages) {
    final hasAnyStroke = pages.any((page) => page.isNotEmpty);
    final hasLoadedNote = _state.note?.isNotEmpty ?? false;
    final hasAnyErasedStroke = _state.erasedStrokesByEvent.values.any(
      (ids) => ids.isNotEmpty,
    );
    return hasAnyStroke || hasLoadedNote || hasAnyErasedStroke;
  }

  bool _shouldSaveNote(List<List<Stroke>> pages) {
    if (!_noteEditedInSession) return false;
    final hasAnyStroke = pages.any((page) => page.isNotEmpty);
    final hasAnyErasedStroke = _state.erasedStrokesByEvent.values.any(
      (ids) => ids.isNotEmpty,
    );
    return hasAnyStroke || hasAnyErasedStroke;
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

  RecordNumberOption({required this.recordNumber, required this.name});

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
