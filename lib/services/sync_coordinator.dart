import 'package:flutter/foundation.dart';
import 'note_content_service.dart';
import '../repositories/note_repository.dart';
import '../repositories/note_repository_impl.dart';
import '../repositories/event_repository.dart';

/// SyncCoordinator - Coordinates bulk sync operations for notes and drawings
///
/// Responsibilities:
/// - Sync all dirty notes to server
/// - Sync dirty notes for specific book
/// - Handle sync errors and retries
/// - Report sync progress and results
class SyncCoordinator {
  final NoteContentService _noteContentService;
  final INoteRepository _noteRepository;
  final IEventRepository _eventRepository;

  SyncCoordinator(
    this._noteContentService,
    this._noteRepository,
    this._eventRepository,
  );

  // ===================
  // Sync Operations
  // ===================

  /// Sync all dirty notes to server
  /// Returns result object with sync statistics
  Future<BulkSyncResult> syncAllDirtyNotes() async {
    try {
      debugPrint('🔄 SyncCoordinator: Starting bulk sync of all dirty notes...');

      // Get all dirty notes from repository
      final dirtyNotes = await _noteRepository.getDirtyNotes();

      if (dirtyNotes.isEmpty) {
        debugPrint('✅ SyncCoordinator: No dirty notes to sync');
        return BulkSyncResult(total: 0, success: 0, failed: 0, failedEventIds: []);
      }

      debugPrint('🔄 SyncCoordinator: Found ${dirtyNotes.length} dirty notes to sync');

      int successCount = 0;
      int failedCount = 0;
      final List<int> failedEventIds = [];

      // Sync each note
      for (final note in dirtyNotes) {
        try {
          await _noteContentService.syncNote(note.eventId);
          successCount++;
        } catch (e) {
          failedCount++;
          failedEventIds.add(note.eventId);

          // Log specific error information
          if (e.toString().contains('404') || e.toString().contains('not found')) {
            try {
              final event = await _eventRepository.getById(note.eventId);
              debugPrint('❌ SyncCoordinator: Failed to sync note ${note.eventId}: Event book ${event?.bookId} not found on server. Please backup the book first.');
            } catch (infoError) {
              debugPrint('❌ SyncCoordinator: Failed to sync note ${note.eventId}: Book not found on server. Please backup the book first.');
            }
          } else {
            debugPrint('❌ SyncCoordinator: Failed to sync note ${note.eventId}: $e');
          }
          // Continue syncing other notes even if one fails
        }
      }

      final result = BulkSyncResult(
        total: dirtyNotes.length,
        success: successCount,
        failed: failedCount,
        failedEventIds: failedEventIds,
      );

      debugPrint('✅ SyncCoordinator: Bulk sync complete - ${result.success}/${result.total} succeeded, ${result.failed} failed');
      return result;
    } catch (e) {
      debugPrint('❌ SyncCoordinator: Bulk sync failed: $e');
      rethrow;
    }
  }

  /// Sync dirty notes for a specific book
  /// Returns result object with sync statistics
  Future<BulkSyncResult> syncDirtyNotesForBook(int bookId) async {
    try {
      debugPrint('🔄 SyncCoordinator: Starting bulk sync for book $bookId...');

      // Get dirty notes for this book
      final dirtyNotes = await (_noteRepository as NoteRepositoryImpl)
          .getDirtyNotesByBookId(bookId);

      if (dirtyNotes.isEmpty) {
        debugPrint('✅ SyncCoordinator: No dirty notes to sync for book $bookId');
        return BulkSyncResult(total: 0, success: 0, failed: 0, failedEventIds: []);
      }

      debugPrint('🔄 SyncCoordinator: Found ${dirtyNotes.length} dirty notes to sync for book $bookId');

      int successCount = 0;
      int failedCount = 0;
      final List<int> failedEventIds = [];

      // Sync each note
      for (final note in dirtyNotes) {
        try {
          await _noteContentService.syncNote(note.eventId);
          successCount++;
        } catch (e) {
          failedCount++;
          failedEventIds.add(note.eventId);

          // Log specific error information
          if (e.toString().contains('404') || e.toString().contains('not found')) {
            try {
              final event = await _eventRepository.getById(note.eventId);
              debugPrint('❌ SyncCoordinator: Failed to sync note ${note.eventId}: Event book ${event?.bookId} not found on server. Please backup the book first.');
            } catch (infoError) {
              debugPrint('❌ SyncCoordinator: Failed to sync note ${note.eventId}: Book not found on server. Please backup the book first.');
            }
          } else {
            debugPrint('❌ SyncCoordinator: Failed to sync note ${note.eventId}: $e');
          }
          // Continue syncing other notes even if one fails
        }
      }

      final result = BulkSyncResult(
        total: dirtyNotes.length,
        success: successCount,
        failed: failedCount,
        failedEventIds: failedEventIds,
      );

      debugPrint('✅ SyncCoordinator: Bulk sync complete for book $bookId - ${result.success}/${result.total} succeeded, ${result.failed} failed');
      return result;
    } catch (e) {
      debugPrint('❌ SyncCoordinator: Bulk sync for book $bookId failed: $e');
      rethrow;
    }
  }

  /// Check if there are any pending changes to sync
  Future<bool> hasPendingChanges() async {
    final dirtyNotes = await _noteRepository.getDirtyNotes();
    return dirtyNotes.isNotEmpty;
  }

  /// Get count of pending changes
  Future<int> getPendingChangesCount() async {
    final dirtyNotes = await _noteRepository.getDirtyNotes();
    return dirtyNotes.length;
  }
}

/// Result object for bulk sync operations
class BulkSyncResult {
  final int total;
  final int success;
  final int failed;
  final List<int> failedEventIds;

  BulkSyncResult({
    required this.total,
    required this.success,
    required this.failed,
    required this.failedEventIds,
  });

  bool get hasFailures => failed > 0;
  bool get allSucceeded => failed == 0 && total > 0;
  bool get nothingToSync => total == 0;

  @override
  String toString() {
    return 'BulkSyncResult(total: $total, success: $success, failed: $failed)';
  }
}
