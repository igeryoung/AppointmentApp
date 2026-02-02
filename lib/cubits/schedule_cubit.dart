import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/event.dart';
import '../models/schedule_drawing.dart';
import '../models/sync_models.dart';
import '../repositories/device_repository.dart';
import '../repositories/event_repository.dart';
import '../services/api_client.dart';
import '../services/database/mixins/event_operations_mixin.dart';
import '../services/drawing_content_service.dart';
import '../services/time_service.dart';
import 'schedule_state.dart';

/// ScheduleCubit - Manages schedule screen state and operations
///
/// Responsibilities:
/// - Load events for selected date and book
/// - Create, update, delete events
/// - Load and save drawings
/// - Manage selected date
/// - Track offline status
/// - Toggle old events visibility
///
/// Target: <250 lines
class ScheduleCubit extends Cubit<ScheduleState> {
  final IEventRepository _eventRepository;
  final DrawingContentService _drawingContentService;
  final TimeService _timeService;
  final ApiClient? _apiClient;
  final IDeviceRepository? _deviceRepository;

  // Current book UUID being viewed
  String? _currentBookUuid;

  // RACE CONDITION FIX: Generation counter to ignore stale event queries
  int _currentRequestGeneration = 0;

  ScheduleCubit(
    this._eventRepository,
    this._drawingContentService,
    this._timeService, {
    ApiClient? apiClient,
    IDeviceRepository? deviceRepository,
  })  : _apiClient = apiClient,
        _deviceRepository = deviceRepository,
        super(const ScheduleInitial());

  // ===================
  // Load Operations
  // ===================

  /// Initialize schedule with a book and load today's events
  Future<void> initialize(String bookUuid) async {
    _currentBookUuid = bookUuid;
    final today = _timeService.now();
    await selectDate(today);
  }

  /// Load events for the selected date (using view mode window)
  ///
  /// [generation] - Request generation number for race condition prevention
  Future<void> loadEvents({DateTime? date, bool? showOldEvents, int? generation}) async {
    if (_currentBookUuid == null) {
      emit(const ScheduleError('No book selected'));
      return;
    }

    final currentState = state;
    final selectedDate = date ??
        (currentState is ScheduleLoaded ? currentState.selectedDate : _timeService.now());

    // Get view mode from current state or default to 2-day
    final viewMode = currentState is ScheduleLoaded ? currentState.viewMode : ScheduleDrawing.VIEW_MODE_2DAY;

    // Always show all events (hardcoded to true)
    final effectiveShowOldEvents = true;

    // Preserve showDrawing from current state
    final effectiveShowDrawing = currentState is ScheduleLoaded ? currentState.showDrawing : true;

    // Preserve pendingNextAppointment from current state
    final pendingNextAppointment = currentState is ScheduleLoaded ? currentState.pendingNextAppointment : null;

    // Check if date is changing - if so, clear drawing to avoid showing old drawing on new date
    final isDateChanging = currentState is ScheduleLoaded &&
        _getWindowStart(currentState.selectedDate, viewMode) != _getWindowStart(selectedDate, viewMode);

    // Only preserve drawing if date is NOT changing (same window)
    final currentDrawing = (currentState is ScheduleLoaded && !isDateChanging) ? currentState.drawing : null;

    emit(const ScheduleLoading());

    try {
      // Load events for the current view mode window (2-day or 3-day)
      final windowStart = _getWindowStart(selectedDate, viewMode);
      final windowSize = _getWindowSize(viewMode);
      final windowEnd = windowStart.add(Duration(days: windowSize));

      List<Event> events;

      // Server-based fetching (server-only mode)
      final apiClient = _apiClient;
      final deviceRepository = _deviceRepository;
      if (apiClient != null && deviceRepository != null) {
        final credentials = await deviceRepository.getCredentials();
        if (credentials != null) {
          try {
            final serverEvents = await apiClient.fetchEventsByDateRange(
              bookUuid: _currentBookUuid!,
              startDate: windowStart,
              endDate: windowEnd,
              deviceId: credentials.deviceId,
              deviceToken: credentials.deviceToken,
            );
            events = serverEvents.map((e) => Event.fromServerResponse(e)).toList();
          } catch (e) {
            // Fallback to local repository on server error
            debugPrint('Server fetch failed, falling back to local: $e');
            events = await _eventRepository.getByDateRange(
              _currentBookUuid!,
              windowStart,
              windowEnd,
            );
          }
        } else {
          // No credentials, use local repository
          events = await _eventRepository.getByDateRange(
            _currentBookUuid!,
            windowStart,
            windowEnd,
          );
        }
      } else {
        // No API client configured, use local repository
        events = await _eventRepository.getByDateRange(
          _currentBookUuid!,
          windowStart,
          windowEnd,
        );
      }

      // RACE CONDITION FIX: Check if this request is still valid
      if (generation != null && generation != _currentRequestGeneration) {
        return; // Don't emit state for stale data
      }

      // Always show all events - no filtering by removed/rescheduled status
      final filteredEvents = events;

      emit(ScheduleLoaded(
        selectedDate: selectedDate,
        events: filteredEvents,
        drawing: currentDrawing,
        isOffline: currentState is ScheduleLoaded ? currentState.isOffline : false,
        showOldEvents: effectiveShowOldEvents,
        showDrawing: effectiveShowDrawing,
        pendingNextAppointment: pendingNextAppointment,
        viewMode: viewMode,
      ));

    } catch (e) {
      emit(ScheduleError('Failed to load events: $e'));
    }
  }

  /// Select a different date and load its events
  Future<void> selectDate(DateTime date) async {
    // RACE CONDITION FIX: Increment generation counter on each date change
    _currentRequestGeneration++;
    final requestGeneration = _currentRequestGeneration;

    await loadEvents(date: date, showOldEvents: true, generation: requestGeneration);
  }

  // ===================
  // Event CRUD Operations
  // ===================

  /// Create a new event
  Future<Event?> createEvent(Event event) async {
    if (_currentBookUuid == null) {
      emit(const ScheduleError('No book selected'));
      return null;
    }

    if (event.bookUuid != _currentBookUuid) {
      emit(const ScheduleError('Event book UUID does not match selected book'));
      return null;
    }

    try {
      final newEvent = await _eventRepository.create(event);

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);
      return newEvent;
    } catch (e) {
      emit(ScheduleError('Failed to create event: $e'));
      return null;
    }
  }

  /// Update an existing event
  Future<void> updateEvent(Event event) async {
    if (event.id == null) {
      emit(const ScheduleError('Cannot update event without ID'));
      return;
    }

    try {
      await _eventRepository.update(event);

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);
    } catch (e) {
      emit(ScheduleError('Failed to update event: $e'));
    }
  }

  /// Delete an event (soft delete)
  /// Returns the updated event with isRemoved=true for syncing
  Future<Event?> deleteEvent(String eventId, {String reason = 'Deleted by user'}) async {
    try {
      final updatedEvent = await _eventRepository.removeEvent(eventId, reason);

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);
      return updatedEvent;
    } catch (e) {
      emit(ScheduleError('Failed to delete event: $e'));
      return null;
    }
  }

  /// Hard delete an event (permanent deletion)
  /// Syncs delete to server first, then removes from local database
  Future<Event?> hardDeleteEvent(String eventId) async {
    try {
      // Get event before deletion
      final event = await _eventRepository.getById(eventId);
      if (event == null) throw Exception('Event not found');

      // Push delete to server (if connected)
      final apiClient = _apiClient;
      final deviceRepository = _deviceRepository;
      if (apiClient != null && deviceRepository != null) {
        final credentials = await deviceRepository.getCredentials();
        if (credentials != null) {
          final deleteChange = SyncChange(
            tableName: 'events',
            recordId: eventId,
            operation: 'delete',
            data: event.toMap(),
            timestamp: DateTime.now(),
            version: event.version,
          );

          final request = SyncRequest(
            deviceId: credentials.deviceId,
            deviceToken: credentials.deviceToken,
            localChanges: [deleteChange],
          );

          try {
            await apiClient.pushChanges(request);
          } catch (e) {
            // Log but don't fail - will be synced later
            debugPrint('Warning: Failed to sync delete to server: $e');
          }
        }
      }

      // Hard delete from local database
      await _eventRepository.delete(eventId);

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);

      return event.copyWith(isRemoved: true, removalReason: 'Permanently deleted');
    } catch (e) {
      emit(ScheduleError('Failed to hard delete event: $e'));
      return null;
    }
  }

  /// Change event time - creates new event and soft deletes original
  /// Returns both the new event and the old event (marked as removed)
  Future<ChangeEventTimeResult?> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  ) async {
    try {
      final result = await _eventRepository.changeEventTime(
        originalEvent,
        newStartTime,
        newEndTime,
        reason,
      );

      // Push changes to server (similar to hardDeleteEvent)
      final apiClient = _apiClient;
      final deviceRepository = _deviceRepository;
      if (apiClient != null && deviceRepository != null) {
        final credentials = await deviceRepository.getCredentials();
        if (credentials != null) {
          // Sync old event (soft deleted with isRemoved=true)
          final oldEventChange = SyncChange(
            tableName: 'events',
            recordId: result.oldEvent.id!,
            operation: 'update',
            data: result.oldEvent.toMap(),
            timestamp: DateTime.now(),
            version: result.oldEvent.version,
          );

          // Sync new event (created)
          final newEventChange = SyncChange(
            tableName: 'events',
            recordId: result.newEvent.id!,
            operation: 'create',
            data: result.newEvent.toMap(),
            timestamp: DateTime.now(),
            version: result.newEvent.version,
          );

          final request = SyncRequest(
            deviceId: credentials.deviceId,
            deviceToken: credentials.deviceToken,
            localChanges: [oldEventChange, newEventChange],
          );

          try {
            await apiClient.pushChanges(request);
          } catch (e) {
            // Log but don't fail - will be synced later
            debugPrint('Warning: Failed to sync time change to server: $e');
          }
        }
      }

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);
      return result;
    } catch (e) {
      emit(ScheduleError('Failed to change event time: $e'));
      return null;
    }
  }

  // ===================
  // Drawing Operations
  // ===================

  /// Load drawing for the current date and view mode (always 3-day view)
  Future<void> loadDrawing({int viewMode = ScheduleDrawing.VIEW_MODE_3DAY, bool forceRefresh = false}) async {
    if (_currentBookUuid == null) {
      return;
    }

    final currentState = state;
    if (currentState is! ScheduleLoaded) {
      return;
    }

    try {
      final drawing = await _drawingContentService.getDrawing(
        bookUuid: _currentBookUuid!,
        date: currentState.selectedDate,
        viewMode: viewMode,
        forceRefresh: forceRefresh,
      );

      emit(currentState.copyWith(drawing: drawing));
    } catch (e) {
      // Don't emit error - drawing is optional
    }
  }

  /// Save drawing
  Future<void> saveDrawing(ScheduleDrawing drawing) async {
    if (_currentBookUuid == null) {
      return;
    }

    try {
      await _drawingContentService.saveDrawing(drawing);

      // Update state with saved drawing
      final currentState = state;
      if (currentState is ScheduleLoaded) {
        emit(currentState.copyWith(drawing: drawing));
      }

    } catch (e) {
      emit(ScheduleError('Failed to save drawing: $e'));
    }
  }

  /// Delete current drawing (always 3-day view)
  Future<void> deleteDrawing({int viewMode = ScheduleDrawing.VIEW_MODE_3DAY}) async {
    if (_currentBookUuid == null) {
      return;
    }

    final currentState = state;
    if (currentState is! ScheduleLoaded) {
      return;
    }

    try {
      await _drawingContentService.deleteDrawing(
        bookUuid: _currentBookUuid!,
        date: currentState.selectedDate,
        viewMode: viewMode,
      );

      emit(currentState.copyWith(clearDrawing: true));
    } catch (e) {
      emit(ScheduleError('Failed to delete drawing: $e'));
    }
  }

  // ===================
  // UI State Management
  // ===================

  /// Toggle visibility of old events (removed events and time-changed old versions)
  /// NOTE: This method is deprecated - all events are now always visible
  @Deprecated('All events are now always visible')
  void toggleOldEvents() {
    // No-op: All events are always visible now
  }

  /// Toggle visibility of drawing overlay
  void toggleDrawing() {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    final newShowDrawing = !currentState.showDrawing;
    emit(currentState.copyWith(showDrawing: newShowDrawing));
  }

  /// Change view mode (2-day or 3-day)
  Future<void> changeViewMode(int viewMode) async {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;


    // Clear drawing when changing view mode (different view modes have different drawings)
    emit(currentState.copyWith(viewMode: viewMode, clearDrawing: true));

    // Reload events for the new view mode window
    _currentRequestGeneration++;
    await loadEvents(date: currentState.selectedDate, generation: _currentRequestGeneration);

    // Load drawing for the new view mode
    await loadDrawing(viewMode: viewMode);
  }

  /// Update offline status
  void setOfflineStatus(bool isOffline) {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    emit(currentState.copyWith(isOffline: isOffline));
  }

  /// Set pending next appointment data for pre-filling event creation
  void setPendingNextAppointment(PendingNextAppointment pendingAppointment) {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    emit(currentState.copyWith(pendingNextAppointment: pendingAppointment));
  }

  /// Clear pending next appointment data
  void clearPendingNextAppointment() {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    emit(currentState.copyWith(clearPendingNextAppointment: true));
  }

  /// Change the center date and navigate to that date
  Future<void> changeDate(DateTime targetDate) async {
    await selectDate(targetDate);
  }

  // ===================
  // Helper Methods
  // ===================

  /// Calculate the start of the 2-day window for a given date
  /// Uses fixed anchor (2000-01-01) to ensure stable window boundaries
  DateTime _get2DayWindowStart(DateTime date) {
    final anchor = DateTime(2000, 1, 1); // Fixed epoch anchor
    final daysSinceAnchor = date.difference(anchor).inDays;
    final windowIndex = daysSinceAnchor ~/ 2;
    final windowStart = anchor.add(Duration(days: windowIndex * 2));
    return DateTime(windowStart.year, windowStart.month, windowStart.day);
  }

  /// Calculate the start of the 3-day window for a given date
  /// Uses fixed anchor (2000-01-01) to ensure stable window boundaries
  /// This matches the logic in ScheduleScreen._get3DayWindowStart()
  DateTime _get3DayWindowStart(DateTime date) {
    final anchor = DateTime(2000, 1, 1); // Fixed epoch anchor
    final daysSinceAnchor = date.difference(anchor).inDays;
    final windowIndex = daysSinceAnchor ~/ 3;
    final windowStart = anchor.add(Duration(days: windowIndex * 3));
    return DateTime(windowStart.year, windowStart.month, windowStart.day);
  }

  /// Get window start based on view mode
  DateTime _getWindowStart(DateTime date, int viewMode) {
    if (viewMode == ScheduleDrawing.VIEW_MODE_2DAY) {
      return _get2DayWindowStart(date);
    } else {
      return _get3DayWindowStart(date);
    }
  }

  /// Get window size (number of days) based on view mode
  int _getWindowSize(int viewMode) {
    return viewMode == ScheduleDrawing.VIEW_MODE_2DAY ? 2 : 3;
  }
}
