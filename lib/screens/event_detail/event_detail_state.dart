import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/charge_item.dart';
import '../../models/note.dart';
import '../../widgets/handwriting_canvas.dart';

/// Immutable state for Event Detail Screen
class EventDetailState {
  // Event metadata
  final String name;
  final String recordNumber;
  final String phone;
  final List<EventType> selectedEventTypes;
  final List<ChargeItem> chargeItems;
  final DateTime startTime;
  final DateTime? endTime;

  // Note data
  final Note? note;
  final List<List<Stroke>> lastKnownPages;
  final Map<String, List<String>>
  erasedStrokesByEvent; // Track erased strokes per event

  // Loading and sync state
  final bool isLoading;
  final bool isLoadingFromServer;
  final bool hasChanges;
  final bool hasUnsyncedChanges;
  final bool isOffline;
  final bool isServicesReady;

  // Name field state (for autocomplete behavior)
  final bool isNameReadOnly;

  // Record number validation state
  final String? recordNumberError;
  final bool isValidatingRecordNumber;

  // Charge items filter state
  final bool showOnlyThisEventItems;

  // New event reference (for time changes)
  final Event? newEvent;

  const EventDetailState({
    required this.name,
    required this.recordNumber,
    required this.phone,
    required this.selectedEventTypes,
    required this.chargeItems,
    required this.startTime,
    this.endTime,
    this.note,
    this.lastKnownPages = const [[]],
    this.erasedStrokesByEvent = const {},
    this.isLoading = false,
    this.isLoadingFromServer = false,
    this.hasChanges = false,
    this.hasUnsyncedChanges = false,
    this.isOffline = false,
    this.isServicesReady = false,
    this.isNameReadOnly = false,
    this.recordNumberError,
    this.isValidatingRecordNumber = false,
    this.showOnlyThisEventItems = false,
    this.newEvent,
  });

  /// Create initial state from event
  factory EventDetailState.fromEvent(Event event) {
    final hasRecordNumber = event.recordNumber.trim().isNotEmpty;
    return EventDetailState(
      name: event.title,
      recordNumber: event.recordNumber,
      phone: '', // Phone is now on records table, fetched separately
      selectedEventTypes: event.eventTypes,
      chargeItems: event.chargeItems,
      startTime: event.startTime,
      endTime: event.endTime,
      isNameReadOnly: hasRecordNumber,
    );
  }

  /// Create a copy with some fields updated
  EventDetailState copyWith({
    String? name,
    String? recordNumber,
    String? phone,
    List<EventType>? selectedEventTypes,
    List<ChargeItem>? chargeItems,
    DateTime? startTime,
    DateTime? endTime,
    Note? note,
    List<List<Stroke>>? lastKnownPages,
    Map<String, List<String>>? erasedStrokesByEvent,
    bool? isLoading,
    bool? isLoadingFromServer,
    bool? hasChanges,
    bool? hasUnsyncedChanges,
    bool? isOffline,
    bool? isServicesReady,
    bool? isNameReadOnly,
    String? recordNumberError,
    bool clearRecordNumberError = false,
    bool? isValidatingRecordNumber,
    bool? showOnlyThisEventItems,
    Event? newEvent,
    bool clearEndTime = false,
    bool clearNewEvent = false,
    bool clearNote = false,
  }) {
    return EventDetailState(
      name: name ?? this.name,
      recordNumber: recordNumber ?? this.recordNumber,
      phone: phone ?? this.phone,
      selectedEventTypes: selectedEventTypes ?? this.selectedEventTypes,
      chargeItems: chargeItems ?? this.chargeItems,
      startTime: startTime ?? this.startTime,
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      note: clearNote ? null : (note ?? this.note),
      lastKnownPages: lastKnownPages ?? this.lastKnownPages,
      erasedStrokesByEvent: erasedStrokesByEvent ?? this.erasedStrokesByEvent,
      isLoading: isLoading ?? this.isLoading,
      isLoadingFromServer: isLoadingFromServer ?? this.isLoadingFromServer,
      hasChanges: hasChanges ?? this.hasChanges,
      hasUnsyncedChanges: hasUnsyncedChanges ?? this.hasUnsyncedChanges,
      isOffline: isOffline ?? this.isOffline,
      isServicesReady: isServicesReady ?? this.isServicesReady,
      isNameReadOnly: isNameReadOnly ?? this.isNameReadOnly,
      recordNumberError: clearRecordNumberError
          ? null
          : (recordNumberError ?? this.recordNumberError),
      isValidatingRecordNumber:
          isValidatingRecordNumber ?? this.isValidatingRecordNumber,
      showOnlyThisEventItems:
          showOnlyThisEventItems ?? this.showOnlyThisEventItems,
      newEvent: clearNewEvent ? null : (newEvent ?? this.newEvent),
    );
  }
}
