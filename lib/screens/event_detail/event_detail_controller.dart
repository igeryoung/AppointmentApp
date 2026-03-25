import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/charge_item.dart';
import '../../models/note.dart';
import '../../repositories/event_repository.dart';
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
  static const String recordNumberNameConflictPrefix = '病例號已存在，且其病人不為 ';

  static bool isRecordNumberNameConflictMessage(String? message) {
    if (message == null) {
      return false;
    }
    return message.startsWith(recordNumberNameConflictPrefix);
  }

  final Event event;
  final bool isNew;
  final IDatabaseService _dbService;
  final IEventRepository? _eventRepository;
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
    IEventRepository? eventRepository,
    required this.onStateChanged,
    ContentService? contentService,
    NoteSyncAdapter? noteSyncAdapter,
    ServerHealthChecker? serverHealthChecker,
    ConnectivityWatcher? connectivityWatcher,
  }) : _dbService = dbService,
       _eventRepository = eventRepository,
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
      // Step 1: Initialize ContentService with correct server URL (unless injected).
      if (_contentService == null) {
        final prdDb = _dbService as PRDDatabaseService;
        final serverConfig = ServerConfigService(prdDb);
        final serverUrl = await serverConfig.getServerUrlOrDefault(
          defaultUrl: 'http://localhost:8080',
        );

        final apiClient = ApiClient(baseUrl: serverUrl);
        _contentService = ContentService(apiClient, _dbService);
      }
      _noteSyncAdapter ??= NoteSyncAdapter(_contentService!);
      _serverHealthChecker ??= ServerHealthChecker(_contentService!);

      // Mark services as ready
      _updateState(_state.copyWith(isServicesReady: true, isOffline: false));

      // Step 2: Load initial data (now that ContentService is ready)
      if (!isNew) {
        _updateState(_state.copyWith(isLoadingFromServer: true));
        try {
          await _refreshEventFromServer();
          await loadChargeItems(); // Load charge items from charge_items table
          if (event.hasNewTime) {
            await _loadNewEvent();
          }
        } finally {
          _updateState(_state.copyWith(isLoadingFromServer: false));
        }
      } else {
        await _hydratePrefilledRecordDataForNewEvent();
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

    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      final credentials = await prdDb.getDeviceCredentials();
      if (credentials == null) {
        return;
      }

      await _logEventTime('before_server_fetch', event);
      final bundle = await _contentService!.apiClient.fetchEventDetailBundle(
        bookUuid: event.bookUuid,
        eventId: event.id!,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
      if (bundle != null) {
        final eventPayload = bundle['event'] as Map<String, dynamic>?;
        if (eventPayload == null) {
          return;
        }
        final refreshedEvent = Event.fromServerResponse(eventPayload);
        final recordDetails = bundle['record'] as Map<String, dynamic>?;
        final notePayload = bundle['note'] as Map<String, dynamic>?;
        final serverNote = notePayload == null
            ? null
            : Note.fromServer(notePayload);

        await _cacheServerMetadataLocally(
          prdDb: prdDb,
          savedEvent: refreshedEvent,
          name: (recordDetails?['name'] ?? '').toString(),
          recordNumber:
              (recordDetails?['record_number'] ?? refreshedEvent.recordNumber)
                  .toString(),
          phone: recordDetails?['phone']?.toString(),
        );

        await _logEventTime('after_server_fetch', refreshedEvent);

        final name = (recordDetails?['name'] ?? '').toString();
        final phone = (recordDetails?['phone'] ?? '').toString();
        final recordNumber =
            (recordDetails?['record_number'] ?? refreshedEvent.recordNumber)
                .toString();

        _updateState(
          _state.copyWith(
            name: name,
            recordNumber: recordNumber,
            phone: phone,
            selectedEventTypes: refreshedEvent.eventTypes,
            startTime: refreshedEvent.startTime,
            endTime: refreshedEvent.endTime,
            note: serverNote,
            clearNote: serverNote == null,
            lastKnownPages: serverNote?.pages ?? const [[]],
            erasedStrokesByEvent: serverNote?.erasedStrokesByEvent ?? const {},
            hasUnsyncedChanges: false,
            isOffline: false,
          ),
        );
        _noteEditedInSession = false;
        _incrementNoteGeneration();
        await _logStateTime('after_state_update');
      }
    } catch (e) {
      _updateState(_state.copyWith(isOffline: true));
    }
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

      if (_hasIncomingServerNote(serverNote)) {
        _applyServerAuthoritativeNote(serverNote);
        return;
      }

      _updateState(
        _state.copyWith(isLoadingFromServer: false, isOffline: false),
      );
    } catch (e) {
      _updateState(
        _state.copyWith(isLoadingFromServer: false, isOffline: true),
      );
      throw Exception('Failed to load note: Cannot connect to server');
    }
  }

  /// Refresh note in background and apply server-authoritative state when changed.
  Future<bool> refreshNoteFromServerInBackground() async {
    if (event.id == null || _noteSyncAdapter == null) {
      return false;
    }

    try {
      Note? serverNote;
      if (event.recordUuid.isNotEmpty) {
        serverNote = await _noteSyncAdapter!.getNoteByRecordUuid(
          event.bookUuid,
          event.recordUuid,
        );
      }

      if (!_hasIncomingServerNote(serverNote)) {
        _updateState(_state.copyWith(isOffline: false));
        return false;
      }

      _applyServerAuthoritativeNote(serverNote);
      return true;
    } catch (e) {
      _updateState(_state.copyWith(isOffline: true));
      return false;
    }
  }

  bool _hasIncomingServerNote(Note? serverNote) {
    final localNote = _state.note;
    if (localNote == null && serverNote == null) {
      return false;
    }
    if (localNote == null || serverNote == null) {
      return true;
    }
    return localNote.version != serverNote.version ||
        localNote.updatedAt != serverNote.updatedAt ||
        localNote.recordUuid != serverNote.recordUuid;
  }

  void _applyServerAuthoritativeNote(
    Note? serverNote, {
    bool resetHasChanges = false,
  }) {
    _updateState(
      _state.copyWith(
        note: serverNote,
        clearNote: serverNote == null,
        lastKnownPages: serverNote?.pages ?? const [[]],
        erasedStrokesByEvent: serverNote?.erasedStrokesByEvent ?? const {},
        hasUnsyncedChanges: false,
        hasChanges: resetHasChanges ? false : _state.hasChanges,
        isLoadingFromServer: false,
        isOffline: false,
      ),
    );
    _noteEditedInSession = false;
    _incrementNoteGeneration();
  }

  Future<Event> _saveEventMetadataServerFirst({
    required PRDDatabaseService prdDb,
    required String name,
    required String recordNumber,
    required String? phone,
    required bool shouldClearEndTime,
  }) async {
    if (_contentService == null) {
      throw Exception('Cannot save event: Services not initialized');
    }

    final credentials = await prdDb.getDeviceCredentials();
    if (credentials == null) {
      throw Exception('Device not registered, cannot save to server');
    }

    final apiClient = _contentService!.apiClient;
    final resolvedRecordUuid = await _resolveServerRecordUuidForSave(
      apiClient: apiClient,
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
      name: name,
      recordNumber: recordNumber,
      phone: phone,
    );

    final title = PRDDatabaseService.generateTitle(name, recordNumber);
    final eventDraft = event.copyWith(
      recordUuid: resolvedRecordUuid,
      title: title,
      recordNumber: recordNumber,
      eventTypes: _state.selectedEventTypes,
      startTime: _state.startTime,
      endTime: _state.endTime,
      clearEndTime: shouldClearEndTime,
    );
    final payload = _buildEventSyncPayload(
      eventDraft,
      name: name,
      phone: phone,
    );
    final recordPayload = {
      'name': name,
      'phone': phone,
      'record_number': recordNumber,
    };

    late final Event savedEvent;
    if (isNew) {
      final savedPayload = await apiClient.createEvent(
        bookUuid: event.bookUuid,
        eventData: payload,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
      savedEvent = Event.fromServerResponse(savedPayload);
    } else {
      final savedBundle = await apiClient.updateEventDetailBundle(
        bookUuid: event.bookUuid,
        eventId: event.id!,
        eventData: payload,
        recordData: recordPayload,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
      final savedPayload = savedBundle['event'] as Map<String, dynamic>?;
      if (savedPayload == null) {
        throw Exception('Server did not return an event payload');
      }
      savedEvent = Event.fromServerResponse(savedPayload);
    }
    if (isNew) {
      await apiClient.updateRecord(
        recordUuid: savedEvent.recordUuid,
        recordData: recordPayload,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
    }

    await _cacheServerMetadataLocally(
      prdDb: prdDb,
      savedEvent: savedEvent,
      name: name,
      recordNumber: recordNumber,
      phone: phone,
    );

    return savedEvent;
  }

  Future<String> _resolveServerRecordUuidForSave({
    required ApiClient apiClient,
    required String deviceId,
    required String deviceToken,
    required String name,
    required String recordNumber,
    required String? phone,
  }) async {
    final currentRecordNumber = event.recordNumber.trim();
    final canReuseCurrentRecord =
        !isNew &&
        event.recordUuid.isNotEmpty &&
        currentRecordNumber == recordNumber;
    if (canReuseCurrentRecord) {
      return event.recordUuid;
    }

    final record = await apiClient.getOrCreateRecord(
      recordNumber: recordNumber,
      name: name,
      phone: phone,
      deviceId: deviceId,
      deviceToken: deviceToken,
    );
    final recordUuid = (record['record_uuid'] ?? record['recordUuid'])
        ?.toString()
        .trim();
    if (recordUuid == null || recordUuid.isEmpty) {
      throw Exception('Server did not return a record_uuid');
    }
    return recordUuid;
  }

  Future<void> _cacheServerMetadataLocally({
    required PRDDatabaseService prdDb,
    required Event savedEvent,
    required String name,
    required String recordNumber,
    required String? phone,
  }) async {
    final db = await prdDb.database;
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    final existingRecord = await prdDb.getRecordByUuid(savedEvent.recordUuid);
    if (existingRecord == null) {
      await db.insert('records', {
        'record_uuid': savedEvent.recordUuid,
        'record_number': recordNumber,
        'name': name,
        'phone': phone,
        'created_at': nowSeconds,
        'updated_at': nowSeconds,
        'version': 1,
        'is_dirty': 0,
        'is_deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.update(
        'records',
        {
          'record_number': recordNumber,
          'name': name,
          'phone': phone,
          'updated_at': nowSeconds,
          'is_dirty': 0,
          'is_deleted': 0,
        },
        where: 'record_uuid = ?',
        whereArgs: [savedEvent.recordUuid],
      );
    }

    final eventMap = savedEvent.toMap();
    eventMap['is_dirty'] = 0;
    await db.insert(
      'events',
      eventMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Save event with handwriting note
  Future<Event> saveEvent({
    Size? canvasSize,
    bool isAutoSave = false,
    List<List<Stroke>>? pagesOverride,
  }) async {
    final pages = pagesOverride ?? _state.lastKnownPages;

    _updateState(_state.copyWith(isLoading: true));

    try {
      final nameText = _state.name.trim();
      final recordNumberText = _state.recordNumber.trim();
      final phoneText = _state.phone.trim();
      final normalizedPhone = phoneText.isEmpty ? null : phoneText;

      // Check if user cleared the end time (converting close-end to open-end event)
      final shouldClearEndTime =
          event.endTime != null && _state.endTime == null;

      if (_dbService is! PRDDatabaseService) {
        throw Exception('PRDDatabaseService required');
      }
      final prdDb = _dbService as PRDDatabaseService;
      final savedEvent = await _saveEventMetadataServerFirst(
        prdDb: prdDb,
        name: nameText,
        recordNumber: recordNumberText,
        phone: normalizedPhone,
        shouldClearEndTime: shouldClearEndTime,
      );

      final oldRecordNumber = event.recordNumber.trim();
      final recordNumberAdded =
          oldRecordNumber.isEmpty && recordNumberText.isNotEmpty;
      final recordRelinked =
          event.recordUuid.isNotEmpty &&
          savedEvent.recordUuid != event.recordUuid;
      final shouldCarryForwardCurrentNote =
          recordNumberAdded && recordRelinked && _hasCurrentNoteContent(pages);

      if ((isNew && recordNumberText.isNotEmpty) || recordNumberAdded) {
        final existingNote = await _fetchExistingNoteForRecordUuid(
          bookUuid: savedEvent.bookUuid,
          recordUuid: savedEvent.recordUuid,
        );
        final shouldKeepEditedNote = _noteEditedInSession;
        if (existingNote != null &&
            existingNote.isNotEmpty &&
            !shouldCarryForwardCurrentNote &&
            !shouldKeepEditedNote) {
          _updateState(
            _state.copyWith(
              note: existingNote,
              lastKnownPages: existingNote.pages,
              isLoading: false,
              hasChanges: false,
              hasUnsyncedChanges: false,
              isOffline: false,
            ),
          );
          _noteEditedInSession = false;
          return savedEvent;
        }
      }

      if (shouldCarryForwardCurrentNote && !_noteEditedInSession) {
        _noteEditedInSession = true;
      }

      final shouldSaveNote = _shouldSaveNote(pages);
      if (shouldSaveNote) {
        await saveNoteToServer(
          savedEvent.id!,
          pages,
          eventDataOverride: savedEvent,
          canvasSize: canvasSize,
          preferIncomingServerNote: isAutoSave,
          updateStateOnSuccess: true,
        );
      }
      _updateState(
        _state.copyWith(
          isLoading: false,
          hasChanges: false,
          hasUnsyncedChanges: false,
          isOffline: false,
        ),
      );

      return savedEvent;
    } catch (e) {
      _updateState(
        _state.copyWith(
          isLoading: false,
          hasUnsyncedChanges: true,
          isOffline: true,
        ),
      );
      rethrow;
    }
  }

  /// Save note directly to server
  Future<void> saveNoteToServer(
    String eventId,
    List<List<Stroke>> pages, {
    Event? eventDataOverride,
    Size? canvasSize,
    bool preferIncomingServerNote = false,
    bool updateStateOnSuccess = true,
  }) async {
    if (_noteSyncAdapter == null) {
      throw Exception('Cannot save: Services not initialized');
    }

    // Get the event to get its recordUuid
    if (_dbService is! PRDDatabaseService) {
      throw Exception('Database service error');
    }
    final prdDb = _dbService as PRDDatabaseService;
    final eventData = eventDataOverride ?? await prdDb.getEventById(eventId);
    if (eventData == null) {
      throw Exception('Event not found');
    }

    Note? baseNote;
    if (preferIncomingServerNote && eventData.recordUuid.isNotEmpty) {
      baseNote = await _noteSyncAdapter!.getNoteByRecordUuid(
        eventData.bookUuid,
        eventData.recordUuid,
      );
    }

    final localBaseVersion = _state.note?.version ?? 0;
    final hasNewerServerNote = (baseNote?.version ?? 0) > localBaseVersion;
    final hasServerDeletion =
        preferIncomingServerNote && baseNote == null && localBaseVersion > 0;
    if (preferIncomingServerNote && (hasNewerServerNote || hasServerDeletion)) {
      debugPrint(
        '[EventDetail] autosave skipped: server note wins '
        'recordUuid=${eventData.recordUuid} local=$localBaseVersion '
        'server=${baseNote?.version ?? 0}',
      );
      _applyServerAuthoritativeNote(baseNote);
      return;
    }

    final localBaseNote = _state.note;
    final optimisticBaseVersion = localBaseNote?.version ?? 0;
    final nextVersion = optimisticBaseVersion + 1;
    final canvasWidth =
        canvasSize?.width ??
        localBaseNote?.canvasWidth ??
        baseNote?.canvasWidth;
    final canvasHeight =
        canvasSize?.height ??
        localBaseNote?.canvasHeight ??
        baseNote?.canvasHeight;

    // Merge erased strokes from the locally known note and current state.
    final mergedErasedStrokes = Map<String, List<String>>.from(
      localBaseNote?.erasedStrokesByEvent ?? const {},
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
      createdAt:
          localBaseNote?.createdAt ?? baseNote?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      version: nextVersion,
    );
    debugPrint(
      '[EventDetail] saveNoteToServer: eventId=$eventId '
      'recordUuid=${eventData.recordUuid} '
      'baseVersion=$optimisticBaseVersion nextVersion=$nextVersion',
    );

    // Save directly to server (no local cache)
    final savedNote = await _saveNoteWithConflictRetry(
      eventId: eventId,
      eventData: eventData,
      noteToSave: noteToSave,
      allowMergeOnConflict: !preferIncomingServerNote,
    );
    _noteEditedInSession = false;

    if (updateStateOnSuccess) {
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
  }

  Future<Note> _saveNoteWithConflictRetry({
    required String eventId,
    required Event eventData,
    required Note noteToSave,
    int retryCount = 0,
    bool allowMergeOnConflict = true,
  }) async {
    const maxRetries = 2;

    try {
      return await _noteSyncAdapter!.saveNote(eventId, noteToSave);
    } on ApiConflictException catch (e) {
      if (!allowMergeOnConflict) {
        if (eventData.recordUuid.isNotEmpty) {
          final serverNote = await _noteSyncAdapter!.getNoteByRecordUuid(
            eventData.bookUuid,
            eventData.recordUuid,
          );
          if (serverNote != null) {
            return serverNote;
          }
        }
        rethrow;
      }

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
        allowMergeOnConflict: allowMergeOnConflict,
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
    // has_charge_items must be server-derived from charge_items table.
    payload.remove('has_charge_items');
    payload.remove('hasChargeItems');
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

  /// Validate record number on blur.
  /// Existing record numbers hydrate matched data instead of showing conflicts.
  Future<bool> validateRecordNumberOnBlur() async {
    final recordNumber = _state.recordNumber.trim();
    final name = _state.name.trim();

    // Empty record number is always valid (treated as "留空")
    if (recordNumber.isEmpty) {
      _updateState(_state.copyWith(clearRecordNumberError: true));
      return true;
    }

    if (_state.isValidatingRecordNumber || _state.isLoadingFromServer) {
      return false;
    }

    _updateState(_state.copyWith(isValidatingRecordNumber: true));

    try {
      final conflictMessage = await _buildRecordNumberNameConflictMessage(
        recordNumber: recordNumber,
        name: name,
      );
      if (conflictMessage != null) {
        _updateState(
          _state.copyWith(
            recordNumber: '',
            isNameReadOnly: false,
            hasChanges: true,
            isValidatingRecordNumber: false,
            isLoadingFromServer: false,
            recordNumberError: conflictMessage,
          ),
        );
        return false;
      }

      final resolvedRecord = await _resolveRecordDataByRecordNumber(
        recordNumber,
      );
      if (resolvedRecord != null) {
        _applyResolvedRecordData(
          resolvedRecord,
          isOffline: !resolvedRecord.loadedFromServer,
        );
        await loadChargeItems();
        return true;
      }

      _updateState(
        _state.copyWith(
          isValidatingRecordNumber: false,
          isLoadingFromServer: false,
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
          isLoadingFromServer: false,
          recordNumberError: '載入病例資料失敗，請稍後再試',
        ),
      );
      return false;
    }
  }

  Future<String?> _buildRecordNumberNameConflictMessage({
    required String recordNumber,
    required String name,
  }) async {
    final trimmedRecordNumber = recordNumber.trim();
    final trimmedName = name.trim();
    if (trimmedRecordNumber.isEmpty || trimmedName.isEmpty) {
      return null;
    }

    if (_dbService is! PRDDatabaseService) {
      return null;
    }

    final prdDb = _dbService as PRDDatabaseService;
    final credentials = await prdDb.getDeviceCredentials();

    if (_contentService == null || credentials == null) {
      throw const ServerConnectionRequiredException(
        'Server connection is required for this operation.',
      );
    }

    try {
      final result = await _contentService!.apiClient.validateRecordNumber(
        recordNumber: trimmedRecordNumber,
        name: trimmedName,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
      if (result.hasConflict) {
        return '$recordNumberNameConflictPrefix$trimmedName.';
      }
    } catch (_) {
      throw const ServerConnectionRequiredException(
        'Server connection is required for this operation.',
      );
    }

    return null;
  }

  Future<void> _hydratePrefilledRecordDataForNewEvent() async {
    final prefilledRecordNumber = _state.recordNumber.trim();
    if (prefilledRecordNumber.isEmpty) {
      return;
    }

    try {
      final resolvedRecord = await _resolveRecordDataByRecordNumber(
        prefilledRecordNumber,
      );
      if (resolvedRecord != null) {
        _applyResolvedRecordData(
          resolvedRecord,
          isOffline: !resolvedRecord.loadedFromServer,
        );
      } else {
        _updateState(
          _state.copyWith(
            isLoadingFromServer: false,
            isValidatingRecordNumber: false,
          ),
        );
      }
      await loadChargeItems();
    } catch (_) {
      _updateState(
        _state.copyWith(
          isLoadingFromServer: false,
          isValidatingRecordNumber: false,
          isOffline: true,
        ),
      );
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

  /// Load charge items for the current record.
  /// UI handles "this event only" by prioritizing current-event items and
  /// diluting others instead of removing them from the list.
  Future<void> loadChargeItems() async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    try {
      final prdDb = _dbService as PRDDatabaseService;
      final recordUuid = await _resolveActiveRecordUuid(prdDb);
      if (recordUuid == null || recordUuid.isEmpty) {
        _updateState(_state.copyWith(chargeItems: []));
        return;
      }

      var chargeItems = await prdDb.getChargeItemsByRecordUuid(recordUuid);
      if (chargeItems.isEmpty && event.hasChargeItems) {
        await _syncChargeItemsFromServer(prdDb, recordUuid: recordUuid);
        chargeItems = await prdDb.getChargeItemsByRecordUuid(recordUuid);
      }

      _setChargeItemsState(chargeItems);
    } catch (e) {}
  }

  List<ChargeItem> _sortedChargeItems(Iterable<ChargeItem> items) {
    final sorted = List<ChargeItem>.from(items);
    sorted.sort((a, b) {
      final created = a.createdAt.compareTo(b.createdAt);
      if (created != 0) {
        return created;
      }
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  void _setChargeItemsState(Iterable<ChargeItem> items) {
    _updateState(_state.copyWith(chargeItems: _sortedChargeItems(items)));
  }

  void _upsertChargeItemInState(ChargeItem item) {
    final items = List<ChargeItem>.from(_state.chargeItems);
    final index = items.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      items[index] = item;
    } else {
      items.add(item);
    }
    _setChargeItemsState(items);
  }

  void _removeChargeItemFromState(String itemId) {
    final items = _state.chargeItems
        .where((item) => item.id != itemId)
        .toList(growable: false);
    _setChargeItemsState(items);
  }

  Future<void> _syncChargeItemsFromServer(
    PRDDatabaseService prdDb, {
    required String recordUuid,
  }) async {
    final contentService = _contentService;
    if (contentService == null || recordUuid.isEmpty) {
      return;
    }

    final credentials = await prdDb.getDeviceCredentials();
    if (credentials == null) {
      return;
    }

    final serverItems = await contentService.apiClient.fetchChargeItems(
      recordUuid: recordUuid,
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
    );

    for (final item in serverItems) {
      await prdDb.applyServerChargeItemChange(item);
    }
  }

  /// Toggle the filter to show all items or only this event's items
  Future<void> toggleChargeItemsFilter() async {
    _updateState(
      _state.copyWith(showOnlyThisEventItems: !_state.showOnlyThisEventItems),
    );
    await loadChargeItems();
  }

  /// Ensure charge-item operations can resolve a record UUID.
  /// For newly created events this may trigger a metadata save first.
  Future<bool> ensureChargeItemsReady() async {
    if (_dbService is! PRDDatabaseService) {
      return false;
    }
    final prdDb = _dbService as PRDDatabaseService;
    final existingRecordUuid = await _resolveActiveRecordUuid(prdDb);
    if (existingRecordUuid != null &&
        existingRecordUuid.isNotEmpty &&
        _isUuidLike(existingRecordUuid)) {
      return true;
    }

    final recordNumber = _state.recordNumber.trim();
    if (recordNumber.isEmpty) {
      return false;
    }

    final serverRecordUuid = await _resolveServerRecordUuidForChargeItems(
      prdDb,
      recordNumber: recordNumber,
    );
    return serverRecordUuid.isNotEmpty;
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

  /// Add a new charge item and link it to the current event.
  /// This keeps "This event only" filter consistent for items created here.
  Future<void> addChargeItem(ChargeItem item) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    final prdDb = _dbService as PRDDatabaseService;
    final effectiveEvent = await _resolveActiveEventForChargeItems(prdDb);
    var effectiveRecordUuid =
        effectiveEvent?.recordUuid.trim().isNotEmpty == true
        ? effectiveEvent!.recordUuid.trim()
        : await _resolveActiveRecordUuid(prdDb);
    final associatedEventId = isNew ? null : (effectiveEvent?.id ?? event.id);
    if (effectiveRecordUuid == null || effectiveRecordUuid.isEmpty) {
      throw Exception('Missing record UUID for charge item');
    }
    if (!_isUuidLike(effectiveRecordUuid)) {
      final recordNumber = _state.recordNumber.trim();
      if (recordNumber.isEmpty) {
        throw Exception('Cannot resolve canonical record UUID');
      }
      effectiveRecordUuid = await _resolveServerRecordUuidForChargeItems(
        prdDb,
        recordNumber: recordNumber,
      );
    }

    // Check if item already exists
    final exists = await prdDb.chargeItemExists(
      recordUuid: effectiveRecordUuid,
      eventId: associatedEventId,
      itemName: item.itemName,
    );

    if (exists) {
      return;
    }

    final newItem = item.copyWith(
      recordUuid: effectiveRecordUuid,
      eventId: associatedEventId,
    );

    final savedItem = await prdDb.saveChargeItem(newItem);
    _upsertChargeItemInState(savedItem);
    await _syncChargeItemUpsertWithBestEffortInBackground(prdDb, savedItem);
  }

  /// Edit an existing charge item
  Future<void> editChargeItem(ChargeItem item) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    final prdDb = _dbService as PRDDatabaseService;

    final exists = await prdDb.chargeItemExists(
      recordUuid: item.recordUuid,
      eventId: item.eventId,
      itemName: item.itemName,
      excludeId: item.id,
    );
    if (exists) {
      return;
    }

    final existingItem = await prdDb.getChargeItemById(item.id);
    if (existingItem == null) {
      return;
    }

    final updatedItem = existingItem.copyWith(
      itemName: item.itemName,
      itemPrice: item.itemPrice,
      receivedAmount: item.receivedAmount,
    );

    final savedItem = await prdDb.saveChargeItem(updatedItem);
    _upsertChargeItemInState(savedItem);
    await _syncChargeItemUpsertWithBestEffortInBackground(prdDb, savedItem);
  }

  /// Delete a charge item
  Future<void> deleteChargeItem(ChargeItem item) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    final prdDb = _dbService as PRDDatabaseService;
    await prdDb.deleteChargeItem(item.id);
    _removeChargeItemFromState(item.id);
    await _syncChargeItemDeleteWithBestEffortInBackground(prdDb, item);
  }

  /// Toggle paid status of a charge item
  /// Sets receivedAmount to itemPrice if not paid, or 0 if paid
  Future<void> toggleChargeItemPaidStatus(ChargeItem item) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    final prdDb = _dbService as PRDDatabaseService;
    final newReceivedAmount = item.isPaid ? 0 : item.itemPrice;
    final updatedItem = item.copyWith(receivedAmount: newReceivedAmount);
    final savedItem = await prdDb.saveChargeItem(updatedItem);
    _upsertChargeItemInState(savedItem);
    await _syncChargeItemUpsertWithBestEffortInBackground(prdDb, savedItem);
  }

  /// Update the received amount of a charge item
  Future<void> updateChargeItemReceivedAmount(
    ChargeItem item,
    int receivedAmount,
  ) async {
    if (_dbService is! PRDDatabaseService) {
      return;
    }

    final prdDb = _dbService as PRDDatabaseService;
    final updatedItem = item.copyWith(receivedAmount: receivedAmount);
    final savedItem = await prdDb.saveChargeItem(updatedItem);
    _upsertChargeItemInState(savedItem);
    await _syncChargeItemUpsertWithBestEffortInBackground(prdDb, savedItem);
  }

  /// Update charge items (legacy method - kept for compatibility but now loads from database)
  @Deprecated(
    'Use addChargeItem, editChargeItem, deleteChargeItem, or toggleChargeItemPaidStatus instead',
  )
  void updateChargeItems(List<ChargeItem> chargeItems) {
    _updateState(_state.copyWith(chargeItems: chargeItems, hasChanges: true));
  }

  Future<Event?> _resolveActiveEventForChargeItems(
    PRDDatabaseService prdDb,
  ) async {
    final currentRecordUuid = event.recordUuid.trim();
    if (currentRecordUuid.isNotEmpty) {
      return event;
    }

    final eventId = event.id?.trim();
    if (eventId == null || eventId.isEmpty) {
      return event;
    }

    return await prdDb.getEventById(eventId) ?? event;
  }

  Future<String?> _resolveActiveRecordUuid(PRDDatabaseService prdDb) async {
    final currentRecordUuid = event.recordUuid.trim();
    if (currentRecordUuid.isNotEmpty) {
      return currentRecordUuid;
    }

    final latestEvent = await _resolveActiveEventForChargeItems(prdDb);
    final latestRecordUuid = latestEvent?.recordUuid.trim() ?? '';
    if (latestRecordUuid.isNotEmpty) {
      return latestRecordUuid;
    }

    final recordNumber = _state.recordNumber.trim();
    if (recordNumber.isEmpty) {
      return null;
    }

    final resolvedRecord = await prdDb.getRecordByRecordNumber(recordNumber);
    final resolvedRecordUuid = resolvedRecord?.recordUuid?.trim() ?? '';
    if (resolvedRecordUuid.isEmpty) {
      return null;
    }
    return resolvedRecordUuid;
  }

  Future<String> _resolveServerRecordUuidForChargeItems(
    PRDDatabaseService prdDb, {
    required String recordNumber,
  }) async {
    final contentService = _contentService;
    if (contentService == null) {
      throw Exception('Cannot resolve record on server: services unavailable');
    }

    final credentials = await prdDb.getDeviceCredentials();
    if (credentials == null) {
      throw Exception('Cannot resolve record on server: missing credentials');
    }

    final normalizedName = _state.name.trim();
    final normalizedPhone = _state.phone.trim();

    final record = await contentService.apiClient.getOrCreateRecord(
      recordNumber: recordNumber,
      name: normalizedName,
      phone: normalizedPhone.isEmpty ? null : normalizedPhone,
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
    );

    final resolvedRecord = _ResolvedRecordData.fromServer(
      recordNumber: recordNumber,
      data: record,
    );
    if (resolvedRecord.recordUuid.isEmpty) {
      throw Exception('Server did not return a valid record_uuid');
    }

    await _cacheResolvedRecordLocally(prdDb, resolvedRecord);
    return resolvedRecord.recordUuid;
  }

  Future<void> _syncChargeItemUpsertToServer(
    PRDDatabaseService prdDb,
    ChargeItem item,
  ) async {
    final contentService = _contentService;
    if (contentService == null) {
      throw Exception('Cannot sync charge item: services unavailable');
    }

    final credentials = await prdDb.getDeviceCredentials();
    if (credentials == null) {
      throw Exception('Cannot sync charge item: missing credentials');
    }

    final payload = Map<String, dynamic>.from(item.toServerMap())
      ..['bookUuid'] = event.bookUuid;

    final serverItem = await contentService.apiClient.saveChargeItem(
      recordUuid: item.recordUuid,
      chargeItemData: payload,
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
    );
    await prdDb.applyServerChargeItemChange(serverItem);
  }

  Future<void> _syncChargeItemUpsertWithBestEffortInBackground(
    PRDDatabaseService prdDb,
    ChargeItem item,
  ) async {
    if (!await _canSyncChargeItems(prdDb)) {
      return;
    }

    unawaited(_runChargeItemUpsertSync(prdDb, item));
  }

  Future<void> _runChargeItemUpsertSync(
    PRDDatabaseService prdDb,
    ChargeItem item,
  ) async {
    try {
      await _syncChargeItemUpsertToServer(prdDb, item);
      final syncedItem = await prdDb.getChargeItemById(item.id);
      if (syncedItem != null) {
        _upsertChargeItemInState(syncedItem);
      }
      _updateState(_state.copyWith(isOffline: false));
    } on ApiConflictException {
      await _syncChargeItemsFromServer(prdDb, recordUuid: item.recordUuid);
      await loadChargeItems();
      _updateState(_state.copyWith(isOffline: false));
    } catch (_) {
      _updateState(_state.copyWith(isOffline: true));
    }
  }

  Future<void> _syncChargeItemDeleteToServer(
    PRDDatabaseService prdDb,
    String chargeItemId, {
    required String recordUuid,
  }) async {
    final contentService = _contentService;
    if (contentService == null) {
      throw Exception('Cannot sync charge item deletion: services unavailable');
    }

    final credentials = await prdDb.getDeviceCredentials();
    if (credentials == null) {
      throw Exception('Cannot sync charge item deletion: missing credentials');
    }

    await contentService.apiClient.deleteChargeItem(
      chargeItemId: chargeItemId,
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
      bookUuid: event.bookUuid,
    );
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final db = await prdDb.database;
    await db.update(
      'charge_items',
      {
        'is_deleted': 1,
        'is_dirty': 0,
        'synced_at': nowSeconds,
        'updated_at': nowSeconds,
      },
      where: 'id = ?',
      whereArgs: [chargeItemId],
    );
    await prdDb.updateEventsHasChargeItemsFlag(recordUuid: recordUuid);
  }

  Future<void> _syncChargeItemDeleteWithBestEffortInBackground(
    PRDDatabaseService prdDb,
    ChargeItem item,
  ) async {
    if (!await _canSyncChargeItems(prdDb)) {
      return;
    }

    unawaited(_runChargeItemDeleteSync(prdDb, item));
  }

  Future<void> _runChargeItemDeleteSync(
    PRDDatabaseService prdDb,
    ChargeItem item,
  ) async {
    try {
      await _syncChargeItemDeleteToServer(
        prdDb,
        item.id,
        recordUuid: item.recordUuid,
      );
      _updateState(_state.copyWith(isOffline: false));
    } on ApiConflictException {
      await _syncChargeItemsFromServer(prdDb, recordUuid: item.recordUuid);
      await loadChargeItems();
      _updateState(_state.copyWith(isOffline: false));
    } catch (_) {
      _updateState(_state.copyWith(isOffline: true));
    }
  }

  Future<bool> _canSyncChargeItems(PRDDatabaseService prdDb) async {
    final credentials = await prdDb.getDeviceCredentials();
    return _contentService != null && credentials != null;
  }

  bool _isUuidLike(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(normalized);
  }

  Future<Note?> _fetchExistingNoteForRecordUuid({
    required String bookUuid,
    required String recordUuid,
    bool allowServerLookup = true,
  }) async {
    if (recordUuid.isEmpty) {
      return null;
    }

    if (!allowServerLookup) {
      return null;
    }

    if (_noteSyncAdapter == null) {
      throw const ServerConnectionRequiredException(
        'Server connection is required for this operation.',
      );
    }

    try {
      return await _noteSyncAdapter!.getNoteByRecordUuid(bookUuid, recordUuid);
    } catch (_) {
      throw const ServerConnectionRequiredException(
        'Server connection is required for this operation.',
      );
    }
  }

  /// Apply an already resolved shared note to the current editing state.
  Future<void> loadExistingPersonNote(Note existingNote) async {
    _updateState(
      _state.copyWith(
        note: existingNote,
        lastKnownPages: existingNote.pages,
        erasedStrokesByEvent: existingNote.erasedStrokesByEvent,
      ),
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

    final eventRepository = _eventRepository;
    if (eventRepository != null) {
      return await eventRepository.getRecordNumbersByName(event.bookUuid, name);
    }

    throw const ServerConnectionRequiredException(
      'Server connection is required for this operation.',
    );
  }

  /// Get all unique names for autocomplete
  /// Returns empty list if DB service is not PRD
  Future<List<String>> getAllNamesForAutocomplete() async {
    final eventRepository = _eventRepository;
    if (eventRepository != null) {
      return await eventRepository.getAllNames(event.bookUuid);
    }

    throw const ServerConnectionRequiredException(
      'Server connection is required for this operation.',
    );
  }

  /// Get all record numbers with names for autocomplete
  /// Returns empty list if DB service is not PRD
  Future<List<RecordNumberOption>> getAllRecordNumbersForAutocomplete() async {
    final eventRepository = _eventRepository;
    if (eventRepository != null) {
      final results = await eventRepository.getAllNameRecordPairs(
        event.bookUuid,
      );
      return results
          .map(
            (item) => RecordNumberOption(
              recordNumber: item.recordNumber,
              name: item.name,
            ),
          )
          .toList();
    }

    throw const ServerConnectionRequiredException(
      'Server connection is required for this operation.',
    );
  }

  Future<List<String>> getNameSuggestionsForAutocomplete(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const [];
    }
    final eventRepository = _eventRepository;
    if (eventRepository == null) {
      return const [];
    }
    return await eventRepository.fetchNameSuggestions(
      event.bookUuid,
      normalized,
    );
  }

  Future<List<NameRecordPair>> getRecordNumberSuggestionsForAutocomplete({
    required String query,
    String? nameConstraint,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedNameConstraint = nameConstraint?.trim().toLowerCase();
    if (normalizedQuery.isEmpty &&
        (normalizedNameConstraint == null ||
            normalizedNameConstraint.isEmpty)) {
      return const [];
    }

    final eventRepository = _eventRepository;
    if (eventRepository == null) {
      return const [];
    }

    return await eventRepository.fetchRecordNumberSuggestions(
      event.bookUuid,
      normalizedQuery,
      namePrefix: normalizedNameConstraint,
    );
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
    final trimmedRecordNumber = recordNumber.trim();
    if (trimmedRecordNumber.isEmpty) {
      return;
    }

    if (_state.isValidatingRecordNumber || _state.isLoadingFromServer) {
      return;
    }

    _updateState(
      _state.copyWith(
        recordNumber: trimmedRecordNumber,
        clearRecordNumberError: true,
        hasChanges: true,
      ),
    );

    try {
      final resolvedRecord = await _resolveRecordDataByRecordNumber(
        trimmedRecordNumber,
      );
      if (resolvedRecord != null) {
        _applyResolvedRecordData(
          resolvedRecord,
          isOffline: !resolvedRecord.loadedFromServer,
        );
        await loadChargeItems();
      } else {
        _updateState(_state.copyWith(isLoadingFromServer: false));
      }
    } catch (e) {
      _updateState(
        _state.copyWith(
          isLoadingFromServer: false,
          recordNumberError: '載入病例資料失敗，請稍後再試',
        ),
      );
    }
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

  Future<_ResolvedRecordData?> _resolveRecordDataByRecordNumber(
    String recordNumber,
  ) async {
    final trimmedRecordNumber = recordNumber.trim();
    if (trimmedRecordNumber.isEmpty) {
      return null;
    }

    _updateState(_state.copyWith(isLoadingFromServer: true));

    if (_dbService is! PRDDatabaseService) {
      return null;
    }

    final prdDb = _dbService as PRDDatabaseService;
    final credentials = await prdDb.getDeviceCredentials();

    if (_contentService == null || credentials == null) {
      throw const ServerConnectionRequiredException(
        'Server connection is required for this operation.',
      );
    }

    try {
      final serverRecord = await _contentService!.apiClient.fetchRecordByNumber(
        recordNumber: trimmedRecordNumber,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
      if (serverRecord == null) {
        return null;
      }
      final resolvedRecord = _ResolvedRecordData.fromServer(
        recordNumber: trimmedRecordNumber,
        data: serverRecord,
      );
      await _cacheResolvedRecordLocally(prdDb, resolvedRecord);
      final note = await _fetchExistingNoteForRecordUuid(
        bookUuid: event.bookUuid,
        recordUuid: resolvedRecord.recordUuid,
      );
      return resolvedRecord.copyWith(note: note);
    } catch (_) {
      throw const ServerConnectionRequiredException(
        'Server connection is required for this operation.',
      );
    }
  }

  Future<void> _cacheResolvedRecordLocally(
    PRDDatabaseService prdDb,
    _ResolvedRecordData resolvedRecord,
  ) async {
    final db = await prdDb.database;
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final existingRecord = await prdDb.getRecordByUuid(
      resolvedRecord.recordUuid,
    );
    if (existingRecord == null) {
      await db.insert('records', {
        'record_uuid': resolvedRecord.recordUuid,
        'record_number': resolvedRecord.recordNumber,
        'name': resolvedRecord.name,
        'phone': resolvedRecord.phone,
        'created_at': nowSeconds,
        'updated_at': nowSeconds,
        'version': 1,
        'is_dirty': 0,
        'is_deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }

    await db.update(
      'records',
      {
        'record_number': resolvedRecord.recordNumber,
        'name': resolvedRecord.name,
        'phone': resolvedRecord.phone,
        'updated_at': nowSeconds,
        'is_dirty': 0,
        'is_deleted': 0,
      },
      where: 'record_uuid = ?',
      whereArgs: [resolvedRecord.recordUuid],
    );
  }

  void _applyResolvedRecordData(
    _ResolvedRecordData resolvedRecord, {
    required bool isOffline,
  }) {
    _updateState(
      _state.copyWith(
        name: resolvedRecord.name,
        recordNumber: resolvedRecord.recordNumber,
        phone: resolvedRecord.phone ?? '',
        note: resolvedRecord.note,
        clearNote: resolvedRecord.note == null,
        lastKnownPages: resolvedRecord.note?.pages ?? const [[]],
        erasedStrokesByEvent:
            resolvedRecord.note?.erasedStrokesByEvent ?? const {},
        isNameReadOnly: resolvedRecord.name.trim().isNotEmpty,
        hasChanges: true,
        isOffline: isOffline,
        isLoadingFromServer: false,
        isValidatingRecordNumber: false,
        clearRecordNumberError: true,
      ),
    );
    _noteEditedInSession = false;
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

class _ResolvedRecordData {
  final String recordUuid;
  final String recordNumber;
  final String name;
  final String? phone;
  final Note? note;
  final bool loadedFromServer;

  const _ResolvedRecordData({
    required this.recordUuid,
    required this.recordNumber,
    required this.name,
    required this.phone,
    required this.note,
    required this.loadedFromServer,
  });

  factory _ResolvedRecordData.fromServer({
    required String recordNumber,
    required Map<String, dynamic> data,
  }) {
    return _ResolvedRecordData(
      recordUuid:
          (data['record_uuid'] ?? data['recordUuid'])?.toString().trim() ?? '',
      recordNumber:
          (data['record_number'] ?? data['recordNumber'] ?? recordNumber)
              .toString(),
      name: (data['name'] ?? '').toString(),
      phone: data['phone']?.toString(),
      note: null,
      loadedFromServer: true,
    );
  }

  _ResolvedRecordData copyWith({Note? note}) {
    return _ResolvedRecordData(
      recordUuid: recordUuid,
      recordNumber: recordNumber,
      name: name,
      phone: phone,
      note: note ?? this.note,
      loadedFromServer: loadedFromServer,
    );
  }
}
