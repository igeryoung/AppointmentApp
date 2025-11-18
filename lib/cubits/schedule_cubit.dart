import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/event.dart';
import '../models/schedule_drawing.dart';
import '../repositories/event_repository.dart';
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

  // Current book ID being viewed
  int? _currentBookId;

  // RACE CONDITION FIX: Generation counter to ignore stale event queries
  int _currentRequestGeneration = 0;

  ScheduleCubit(
    this._eventRepository,
    this._drawingContentService,
    this._timeService,
  ) : super(const ScheduleInitial());

  // ===================
  // Load Operations
  // ===================

  /// Initialize schedule with a book and load today's events
  Future<void> initialize(int bookId) async {
    _currentBookId = bookId;
    final today = _timeService.now();
    await selectDate(today);
  }

  /// Load events for the selected date (using view mode window)
  ///
  /// [generation] - Request generation number for race condition prevention
  Future<void> loadEvents({DateTime? date, bool? showOldEvents, int? generation}) async {
    if (_currentBookId == null) {
      debugPrint('⚠️ ScheduleCubit: Cannot load events - no book selected');
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

      debugPrint('🔄 ScheduleCubit: Fetching events for $windowSize-day window $windowStart (generation=$generation)');

      final events = await _eventRepository.getByDateRange(
        _currentBookId!,
        windowStart,
        windowEnd,
      );

      // RACE CONDITION FIX: Check if this request is still valid
      if (generation != null && generation != _currentRequestGeneration) {
        debugPrint('⚠️ ScheduleCubit: Ignoring stale event query (gen $generation vs current $_currentRequestGeneration)');
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

      debugPrint('✅ ScheduleCubit: Loaded ${filteredEvents.length} events for $windowSize-day window starting $windowStart (generation=$generation)');
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to load events: $e');
      emit(ScheduleError('Failed to load events: $e'));
    }
  }

  /// Select a different date and load its events
  Future<void> selectDate(DateTime date) async {
    // RACE CONDITION FIX: Increment generation counter on each date change
    _currentRequestGeneration++;
    final requestGeneration = _currentRequestGeneration;
    debugPrint('🔄 ScheduleCubit: selectDate() called, generation=$requestGeneration');

    await loadEvents(date: date, showOldEvents: true, generation: requestGeneration);
  }

  // ===================
  // Event CRUD Operations
  // ===================

  /// Create a new event
  Future<Event?> createEvent(Event event) async {
    if (_currentBookId == null) {
      debugPrint('⚠️ ScheduleCubit: Cannot create event - no book selected');
      emit(const ScheduleError('No book selected'));
      return null;
    }

    if (event.bookId != _currentBookId) {
      debugPrint('⚠️ ScheduleCubit: Event bookId mismatch');
      emit(const ScheduleError('Event book ID does not match selected book'));
      return null;
    }

    try {
      final newEvent = await _eventRepository.create(event);
      debugPrint('✅ ScheduleCubit: Created event "${newEvent.name}" (id: ${newEvent.id})');

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);
      return newEvent;
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to create event: $e');
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
      debugPrint('✅ ScheduleCubit: Updated event "${event.name}"');

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to update event: $e');
      emit(ScheduleError('Failed to update event: $e'));
    }
  }

  /// Delete an event (soft delete)
  Future<void> deleteEvent(int eventId, {String reason = 'Deleted by user'}) async {
    try {
      await _eventRepository.removeEvent(eventId, reason);
      debugPrint('✅ ScheduleCubit: Deleted event (id: $eventId)');

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to delete event: $e');
      emit(ScheduleError('Failed to delete event: $e'));
    }
  }

  /// Hard delete an event (permanent deletion)
  Future<void> hardDeleteEvent(int eventId) async {
    try {
      await _eventRepository.delete(eventId);
      debugPrint('✅ ScheduleCubit: Hard deleted event (id: $eventId)');

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to hard delete event: $e');
      emit(ScheduleError('Failed to hard delete event: $e'));
    }
  }

  /// Change event time - creates new event and soft deletes original
  Future<Event?> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  ) async {
    try {
      final newEvent = await _eventRepository.changeEventTime(
        originalEvent,
        newStartTime,
        newEndTime,
        reason,
      );
      debugPrint('✅ ScheduleCubit: Changed event time for "${originalEvent.name}" (old id: ${originalEvent.id}, new id: ${newEvent.id})');

      // Reload events to update UI
      await loadEvents(generation: _currentRequestGeneration);
      return newEvent;
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to change event time: $e');
      emit(ScheduleError('Failed to change event time: $e'));
      return null;
    }
  }

  // ===================
  // Drawing Operations
  // ===================

  /// Load drawing for the current date and view mode (always 3-day view)
  Future<void> loadDrawing({int viewMode = ScheduleDrawing.VIEW_MODE_3DAY, bool forceRefresh = false}) async {
    if (_currentBookId == null) {
      debugPrint('⚠️ ScheduleCubit: Cannot load drawing - no book selected');
      return;
    }

    final currentState = state;
    if (currentState is! ScheduleLoaded) {
      debugPrint('⚠️ ScheduleCubit: Cannot load drawing - state is not ScheduleLoaded');
      return;
    }

    try {
      final drawing = await _drawingContentService.getDrawing(
        bookId: _currentBookId!,
        date: currentState.selectedDate,
        viewMode: viewMode,
        forceRefresh: forceRefresh,
      );

      emit(currentState.copyWith(drawing: drawing));
      debugPrint('✅ ScheduleCubit: Loaded drawing (${drawing != null ? "${drawing.strokes.length} strokes" : "null"})');
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to load drawing: $e');
      // Don't emit error - drawing is optional
    }
  }

  /// Save drawing
  Future<void> saveDrawing(ScheduleDrawing drawing) async {
    if (_currentBookId == null) {
      debugPrint('⚠️ ScheduleCubit: Cannot save drawing - no book selected');
      return;
    }

    try {
      await _drawingContentService.saveDrawing(drawing);

      // Update state with saved drawing
      final currentState = state;
      if (currentState is ScheduleLoaded) {
        emit(currentState.copyWith(drawing: drawing));
      }

      debugPrint('✅ ScheduleCubit: Saved drawing (${drawing.strokes.length} strokes)');
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to save drawing: $e');
      emit(ScheduleError('Failed to save drawing: $e'));
    }
  }

  /// Delete current drawing (always 3-day view)
  Future<void> deleteDrawing({int viewMode = ScheduleDrawing.VIEW_MODE_3DAY}) async {
    if (_currentBookId == null) {
      debugPrint('⚠️ ScheduleCubit: Cannot delete drawing - no book selected');
      return;
    }

    final currentState = state;
    if (currentState is! ScheduleLoaded) {
      debugPrint('⚠️ ScheduleCubit: Cannot delete drawing - state is not ScheduleLoaded');
      return;
    }

    try {
      await _drawingContentService.deleteDrawing(
        bookId: _currentBookId!,
        date: currentState.selectedDate,
        viewMode: viewMode,
      );

      emit(currentState.copyWith(clearDrawing: true));
      debugPrint('✅ ScheduleCubit: Deleted drawing');
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to delete drawing: $e');
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
    debugPrint('⚠️ ScheduleCubit: toggleOldEvents() called but is deprecated');
  }

  /// Toggle visibility of drawing overlay
  void toggleDrawing() {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    final newShowDrawing = !currentState.showDrawing;
    emit(currentState.copyWith(showDrawing: newShowDrawing));
    debugPrint('✅ ScheduleCubit: Drawing visibility updated: $newShowDrawing');
  }

  /// Change view mode (2-day or 3-day)
  Future<void> changeViewMode(int viewMode) async {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    debugPrint('🔄 ScheduleCubit: Changing view mode to $viewMode');

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
    debugPrint('✅ ScheduleCubit: Offline status updated: $isOffline');
  }

  /// Set pending next appointment data for pre-filling event creation
  void setPendingNextAppointment(PendingNextAppointment pendingAppointment) {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    emit(currentState.copyWith(pendingNextAppointment: pendingAppointment));
    debugPrint('✅ ScheduleCubit: Pending next appointment set: ${pendingAppointment.name}');
  }

  /// Clear pending next appointment data
  void clearPendingNextAppointment() {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    emit(currentState.copyWith(clearPendingNextAppointment: true));
    debugPrint('✅ ScheduleCubit: Pending next appointment cleared');
  }

  /// Change the center date and navigate to that date
  Future<void> changeDate(DateTime targetDate) async {
    debugPrint('✅ ScheduleCubit: Changing date to $targetDate');
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
