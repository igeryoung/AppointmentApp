import 'package:equatable/equatable.dart';
import '../models/event.dart';
import '../models/note.dart';

/// Base state for EventDetailCubit
abstract class EventDetailState extends Equatable {
  const EventDetailState();

  @override
  List<Object?> get props => [];
}

/// Initial state - before any data is loaded
class EventDetailInitial extends EventDetailState {
  const EventDetailInitial();
}

/// Loading state - data is being fetched
class EventDetailLoading extends EventDetailState {
  const EventDetailLoading();
}

/// Loaded state - data is available
class EventDetailLoaded extends EventDetailState {
  final Event event;
  final Note? note;
  final bool isEditMode;
  final bool isDirty; // Has unsaved changes
  final bool isSyncing;

  const EventDetailLoaded({
    required this.event,
    this.note,
    this.isEditMode = false,
    this.isDirty = false,
    this.isSyncing = false,
  });

  @override
  List<Object?> get props => [event, note, isEditMode, isDirty, isSyncing];

  /// Create a copy with updated values
  EventDetailLoaded copyWith({
    Event? event,
    Note? note,
    bool? isEditMode,
    bool? isDirty,
    bool? isSyncing,
    bool clearNote = false,
  }) {
    return EventDetailLoaded(
      event: event ?? this.event,
      note: clearNote ? null : (note ?? this.note),
      isEditMode: isEditMode ?? this.isEditMode,
      isDirty: isDirty ?? this.isDirty,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

/// Error state - an error occurred
class EventDetailError extends EventDetailState {
  final String message;

  const EventDetailError(this.message);

  @override
  List<Object?> get props => [message];
}
