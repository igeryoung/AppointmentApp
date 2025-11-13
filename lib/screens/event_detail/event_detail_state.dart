import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/note.dart';
import '../../widgets/handwriting_canvas.dart';

/// Immutable state for Event Detail Screen
class EventDetailState {
  // Event metadata
  final String name;
  final String recordNumber;
  final List<EventType> selectedEventTypes;
  final DateTime startTime;
  final DateTime? endTime;

  // Note data
  final Note? note;
  final List<List<Stroke>> lastKnownPages;

  // Loading and sync state
  final bool isLoading;
  final bool isLoadingFromServer;
  final bool hasChanges;
  final bool hasUnsyncedChanges;
  final bool isOffline;
  final bool isServicesReady;

  // New event reference (for time changes)
  final Event? newEvent;

  const EventDetailState({
    required this.name,
    required this.recordNumber,
    required this.selectedEventTypes,
    required this.startTime,
    this.endTime,
    this.note,
    this.lastKnownPages = const [[]],
    this.isLoading = false,
    this.isLoadingFromServer = false,
    this.hasChanges = false,
    this.hasUnsyncedChanges = false,
    this.isOffline = false,
    this.isServicesReady = false,
    this.newEvent,
  });

  /// Create initial state from event
  factory EventDetailState.fromEvent(Event event) {
    return EventDetailState(
      name: event.name,
      recordNumber: event.recordNumber ?? '',
      selectedEventTypes: event.eventTypes,
      startTime: event.startTime,
      endTime: event.endTime,
    );
  }

  /// Create a copy with some fields updated
  EventDetailState copyWith({
    String? name,
    String? recordNumber,
    List<EventType>? selectedEventTypes,
    DateTime? startTime,
    DateTime? endTime,
    Note? note,
    List<List<Stroke>>? lastKnownPages,
    bool? isLoading,
    bool? isLoadingFromServer,
    bool? hasChanges,
    bool? hasUnsyncedChanges,
    bool? isOffline,
    bool? isServicesReady,
    Event? newEvent,
    bool clearEndTime = false,
    bool clearNewEvent = false,
  }) {
    return EventDetailState(
      name: name ?? this.name,
      recordNumber: recordNumber ?? this.recordNumber,
      selectedEventTypes: selectedEventTypes ?? this.selectedEventTypes,
      startTime: startTime ?? this.startTime,
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      note: note ?? this.note,
      lastKnownPages: lastKnownPages ?? this.lastKnownPages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingFromServer: isLoadingFromServer ?? this.isLoadingFromServer,
      hasChanges: hasChanges ?? this.hasChanges,
      hasUnsyncedChanges: hasUnsyncedChanges ?? this.hasUnsyncedChanges,
      isOffline: isOffline ?? this.isOffline,
      isServicesReady: isServicesReady ?? this.isServicesReady,
      newEvent: clearNewEvent ? null : (newEvent ?? this.newEvent),
    );
  }
}
