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

  /// Load events for the selected date (using 3-day window)
  Future<void> loadEvents({DateTime? date, bool? showOldEvents}) async {
    if (_currentBookId == null) {
      debugPrint('⚠️ ScheduleCubit: Cannot load events - no book selected');
      emit(const ScheduleError('No book selected'));
      return;
    }

    final currentState = state;
    final selectedDate = date ??
        (currentState is ScheduleLoaded ? currentState.selectedDate : _timeService.now());

    // Preserve showOldEvents from current state if not explicitly provided
    final effectiveShowOldEvents = showOldEvents ??
        (currentState is ScheduleLoaded ? currentState.showOldEvents : true);

    // Preserve showDrawing from current state
    final effectiveShowDrawing = currentState is ScheduleLoaded ? currentState.showDrawing : true;

    // Preserve pendingNextAppointment from current state
    final pendingNextAppointment = currentState is ScheduleLoaded ? currentState.pendingNextAppointment : null;

    // Check if date is changing - if so, clear drawing to avoid showing old drawing on new date
    final isDateChanging = currentState is ScheduleLoaded &&
        _get3DayWindowStart(currentState.selectedDate) != _get3DayWindowStart(selectedDate);

    // Only preserve drawing if date is NOT changing (same 3-day window)
    final currentDrawing = (currentState is ScheduleLoaded && !isDateChanging) ? currentState.drawing : null;

    emit(const ScheduleLoading());

    try {
      // IMPORTANT: Load events for 3-day window (not just selected date)
      // This matches ScheduleScreen's 3-day view display
      final windowStart = _get3DayWindowStart(selectedDate);
      final windowEnd = windowStart.add(const Duration(days: 3));

      final events = await _eventRepository.getByDateRange(
        _currentBookId!,
        windowStart,
        windowEnd,
      );

      // Filter old events if needed
      // Old events are those that are removed or have been rescheduled (have newEventId)
      final filteredEvents = effectiveShowOldEvents
          ? events
          : events.where((e) => !e.isRemoved && e.newEventId == null).toList();

      emit(ScheduleLoaded(
        selectedDate: selectedDate,
        events: filteredEvents,
        drawing: currentDrawing,
        isOffline: currentState is ScheduleLoaded ? currentState.isOffline : false,
        showOldEvents: effectiveShowOldEvents,
        showDrawing: effectiveShowDrawing,
        pendingNextAppointment: pendingNextAppointment,
      ));

      debugPrint('✅ ScheduleCubit: Loaded ${filteredEvents.length} events for 3-day window starting $windowStart');
    } catch (e) {
      debugPrint('❌ ScheduleCubit: Failed to load events: $e');
      emit(ScheduleError('Failed to load events: $e'));
    }
  }

  /// Select a different date and load its events
  Future<void> selectDate(DateTime date) async {
    final currentState = state;
    final showOldEvents = currentState is ScheduleLoaded ? currentState.showOldEvents : true;

    await loadEvents(date: date, showOldEvents: showOldEvents);
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
      await loadEvents();
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
      await loadEvents();
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
      await loadEvents();
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
      await loadEvents();
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
      await loadEvents();
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
  void toggleOldEvents() {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    final newShowOldEvents = !currentState.showOldEvents;

    // Filter events based on new setting
    loadEvents(showOldEvents: newShowOldEvents);
  }

  /// Toggle visibility of drawing overlay
  void toggleDrawing() {
    final currentState = state;
    if (currentState is! ScheduleLoaded) return;

    final newShowDrawing = !currentState.showDrawing;
    emit(currentState.copyWith(showDrawing: newShowDrawing));
    debugPrint('✅ ScheduleCubit: Drawing visibility updated: $newShowDrawing');
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
}
