import 'package:equatable/equatable.dart';
import '../models/event.dart';
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

  const ScheduleLoaded({
    required this.selectedDate,
    required this.events,
    this.drawing,
    this.isOffline = false,
    this.showOldEvents = true,
  });

  @override
  List<Object?> get props => [selectedDate, events, drawing, isOffline, showOldEvents];

  /// Create a copy with updated values
  ScheduleLoaded copyWith({
    DateTime? selectedDate,
    List<Event>? events,
    ScheduleDrawing? drawing,
    bool? isOffline,
    bool? showOldEvents,
    bool clearDrawing = false,
  }) {
    return ScheduleLoaded(
      selectedDate: selectedDate ?? this.selectedDate,
      events: events ?? this.events,
      drawing: clearDrawing ? null : (drawing ?? this.drawing),
      isOffline: isOffline ?? this.isOffline,
      showOldEvents: showOldEvents ?? this.showOldEvents,
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
