import 'package:equatable/equatable.dart';
import '../models/event.dart';
import '../models/event_type.dart';
import '../models/schedule_drawing.dart';

/// Base state for ScheduleCubit
abstract class ScheduleState extends Equatable {
  const ScheduleState();

  @override
  List<Object?> get props => [];
}

/// Initial state - before any data is loaded
class ScheduleInitial extends ScheduleState {
  const ScheduleInitial();
}

/// Loading state - data is being fetched
class ScheduleLoading extends ScheduleState {
  const ScheduleLoading();
}

/// Loaded state - data is available
class ScheduleLoaded extends ScheduleState {
  final DateTime selectedDate;
  final List<Event> events;
  final ScheduleDrawing? drawing;
  final bool isOffline;
  final bool showOldEvents;
  final bool showDrawing;
  final PendingNextAppointment? pendingNextAppointment;
  final int viewMode;

  const ScheduleLoaded({
    required this.selectedDate,
    required this.events,
    this.drawing,
    this.isOffline = false,
    this.showOldEvents = true,
    this.showDrawing = true,
    this.pendingNextAppointment,
    this.viewMode = ScheduleDrawing.VIEW_MODE_2DAY,
  });

  @override
  List<Object?> get props => [
    selectedDate,
    events,
    drawing,
    isOffline,
    showOldEvents,
    showDrawing,
    pendingNextAppointment,
    viewMode,
  ];

  /// Create a copy with updated values
  ScheduleLoaded copyWith({
    DateTime? selectedDate,
    List<Event>? events,
    ScheduleDrawing? drawing,
    bool? isOffline,
    bool? showOldEvents,
    bool? showDrawing,
    bool clearDrawing = false,
    PendingNextAppointment? pendingNextAppointment,
    bool clearPendingNextAppointment = false,
    int? viewMode,
  }) {
    return ScheduleLoaded(
      selectedDate: selectedDate ?? this.selectedDate,
      events: events ?? this.events,
      drawing: clearDrawing ? null : (drawing ?? this.drawing),
      isOffline: isOffline ?? this.isOffline,
      showOldEvents: showOldEvents ?? this.showOldEvents,
      showDrawing: showDrawing ?? this.showDrawing,
      pendingNextAppointment: clearPendingNextAppointment
          ? null
          : (pendingNextAppointment ?? this.pendingNextAppointment),
      viewMode: viewMode ?? this.viewMode,
    );
  }
}

/// Refreshing state - keeps existing data visible while re-fetching from server
class ScheduleRefreshing extends ScheduleLoaded {
  const ScheduleRefreshing({
    required super.selectedDate,
    required super.events,
    super.drawing,
    super.isOffline,
    super.showOldEvents,
    super.showDrawing,
    super.pendingNextAppointment,
    super.viewMode,
  });

  factory ScheduleRefreshing.fromLoaded(
    ScheduleLoaded loaded, {
    DateTime? selectedDate,
    List<Event>? events,
    ScheduleDrawing? drawing,
    bool? isOffline,
    bool? showOldEvents,
    bool? showDrawing,
    PendingNextAppointment? pendingNextAppointment,
    int? viewMode,
  }) {
    return ScheduleRefreshing(
      selectedDate: selectedDate ?? loaded.selectedDate,
      events: events ?? loaded.events,
      drawing: drawing ?? loaded.drawing,
      isOffline: isOffline ?? loaded.isOffline,
      showOldEvents: showOldEvents ?? loaded.showOldEvents,
      showDrawing: showDrawing ?? loaded.showDrawing,
      pendingNextAppointment:
          pendingNextAppointment ?? loaded.pendingNextAppointment,
      viewMode: viewMode ?? loaded.viewMode,
    );
  }
}

/// Error state - an error occurred
class ScheduleError extends ScheduleState {
  final String message;

  const ScheduleError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Pending next appointment data for pre-filling event creation
class PendingNextAppointment extends Equatable {
  final String name;
  final String recordNumber;
  final String? phone;
  final List<EventType> eventTypes;

  const PendingNextAppointment({
    required this.name,
    required this.recordNumber,
    this.phone,
    required this.eventTypes,
  });

  @override
  List<Object?> get props => [name, recordNumber, phone, eventTypes];
}
