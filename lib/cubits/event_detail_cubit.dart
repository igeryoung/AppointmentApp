import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/event.dart';
import '../models/note.dart';
import '../repositories/event_repository.dart';
import '../services/note_content_service.dart';
import 'event_detail_state.dart';

/// EventDetailCubit - Manages event detail screen state and operations
///
/// Responsibilities:
/// - Load event details
/// - Update event information
/// - Load and save notes
/// - Delete notes
/// - Track edit mode
/// - Track dirty state for unsaved changes
///
/// Target: <200 lines
class EventDetailCubit extends Cubit<EventDetailState> {
  final IEventRepository _eventRepository;
  final NoteContentService _noteContentService;

  EventDetailCubit(
    this._eventRepository,
    this._noteContentService,
  ) : super(const EventDetailInitial());

  // ===================
  // Load Operations
  // ===================

  /// Load event and its note
  Future<void> loadEvent(String eventId) async {
    emit(const EventDetailLoading());

    try {
      // Load event
      final event = await _eventRepository.getById(eventId);
      if (event == null) {
        emit(const EventDetailError('Event not found'));
        return;
      }

      // Load note (cached first, then from server if needed)
      final note = await _noteContentService.getCachedNote(eventId);

      emit(EventDetailLoaded(
        event: event,
        note: note,
      ));


      // Background refresh note from server if online
      _refreshNoteInBackground(eventId);
    } catch (e) {
      emit(EventDetailError('Failed to load event: $e'));
    }
  }

  /// Refresh note from server in background (non-blocking)
  Future<void> _refreshNoteInBackground(String eventId) async {
    try {
      final serverNote = await _noteContentService.getNote(eventId, forceRefresh: true);
      final currentState = state;
      if (currentState is EventDetailLoaded && !currentState.isSyncing) {
        // Only update if not currently syncing
        emit(currentState.copyWith(note: serverNote));
      }
    } catch (e) {
      // Ignore errors - cached note is sufficient
    }
  }

  // ===================
  // Event CRUD Operations
  // ===================

  /// Update event details
  Future<void> updateEvent(Event event) async {
    final currentState = state;
    if (currentState is! EventDetailLoaded) return;

    if (event.id == null) {
      emit(const EventDetailError('Cannot update event without ID'));
      return;
    }

    try {
      final updatedEvent = await _eventRepository.update(event);

      emit(currentState.copyWith(
        event: updatedEvent,
        isDirty: false,
      ));

    } catch (e) {
      emit(EventDetailError('Failed to update event: $e'));
    }
  }

  // ===================
  // Note Operations
  // ===================

  /// Load note from server (force refresh)
  Future<void> loadNote(String eventId) async {
    final currentState = state;
    if (currentState is! EventDetailLoaded) return;

    try {
      final note = await _noteContentService.getNote(eventId, forceRefresh: true);

      emit(currentState.copyWith(
        note: note,
        isDirty: false,
      ));

    } catch (e) {
      // Don't emit error - note loading is optional
    }
  }

  /// Save note locally (marks as dirty)
  Future<void> saveNoteLocally(Note note) async {
    final currentState = state;
    if (currentState is! EventDetailLoaded) return;

    try {
      await _noteContentService.saveNote(note.eventId, note);

      emit(currentState.copyWith(
        note: note,
        isDirty: true,
      ));

    } catch (e) {
      emit(EventDetailError('Failed to save note: $e'));
    }
  }

  /// Sync note to server
  Future<void> syncNote(String eventId) async {
    final currentState = state;
    if (currentState is! EventDetailLoaded) return;

    emit(currentState.copyWith(isSyncing: true));

    try {
      await _noteContentService.syncNote(eventId);

      emit(currentState.copyWith(
        isDirty: false,
        isSyncing: false,
      ));

    } catch (e) {
      emit(currentState.copyWith(isSyncing: false));
      emit(EventDetailError('Failed to sync note: $e'));
    }
  }

  /// Delete note
  Future<void> deleteNote(String eventId) async {
    final currentState = state;
    if (currentState is! EventDetailLoaded) return;

    try {
      await _noteContentService.deleteNote(eventId);

      emit(currentState.copyWith(
        clearNote: true,
        isDirty: false,
      ));

    } catch (e) {
      emit(EventDetailError('Failed to delete note: $e'));
    }
  }

  // ===================
  // UI State Management
  // ===================

  /// Toggle edit mode
  void toggleEditMode() {
    final currentState = state;
    if (currentState is! EventDetailLoaded) return;

    emit(currentState.copyWith(isEditMode: !currentState.isEditMode));
  }

  /// Set edit mode
  void setEditMode(bool isEditMode) {
    final currentState = state;
    if (currentState is! EventDetailLoaded) return;

    emit(currentState.copyWith(isEditMode: isEditMode));
  }

  /// Update dirty state manually (for unsaved changes tracking)
  void setDirty(bool isDirty) {
    final currentState = state;
    if (currentState is! EventDetailLoaded) return;

    emit(currentState.copyWith(isDirty: isDirty));
  }
}
