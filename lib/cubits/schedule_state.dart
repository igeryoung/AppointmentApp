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

  const ScheduleLoaded({
    required this.selectedDate,
    required this.events,
    this.drawing,
    this.isOffline = false,
    this.showOldEvents = true,
    this.showDrawing = true,
    this.pendingNextAppointment,
  });

  @override
  List<Object?> get props => [selectedDate, events, drawing, isOffline, showOldEvents, showDrawing, pendingNextAppointment];

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
  }) {
    return ScheduleLoaded(
      selectedDate: selectedDate ?? this.selectedDate,
      events: events ?? this.events,
      drawing: clearDrawing ? null : (drawing ?? this.drawing),
      isOffline: isOffline ?? this.isOffline,
      showOldEvents: showOldEvents ?? this.showOldEvents,
      showDrawing: showDrawing ?? this.showDrawing,
      pendingNextAppointment: clearPendingNextAppointment ? null : (pendingNextAppointment ?? this.pendingNextAppointment),
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
  final EventType eventType;

  const PendingNextAppointment({
    required this.name,
    required this.recordNumber,
    required this.eventType,
  });

  @override
  List<Object?> get props => [name, recordNumber, eventType];
}
