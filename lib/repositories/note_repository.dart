import '../models/note.dart';

/// Repository interface for Note entity cache operations
/// Handles local caching of notes with dirty flag tracking for sync
abstract class INoteRepository {
  /// Retrieve a cached note for a specific event
  /// Returns null if not cached
  Future<Note?> getCached(int eventId);

  /// Save a note to local cache
  /// Marks as dirty if not synced with server
  Future<void> saveToCache(Note note, {required bool isDirty});

  /// Delete a note from cache
  Future<void> deleteCache(int eventId);

  /// Retrieve all notes marked as dirty (not synced to server)
  Future<List<Note>> getDirtyNotes();

  /// Mark a note as clean (synced with server)
  Future<void> markClean(int eventId);

  /// Retrieve all cached notes for a specific book
  Future<List<Note>> getAllCachedForBook(String bookUuid);

  /// Get all cached notes
  Future<List<Note>> getAllCached();

  /// Mark a note as synced with timestamp (similar to markClean but with syncedAt)
  Future<void> markNoteSynced(int eventId, DateTime syncedAt);

  /// Apply server change to local database
  Future<void> applyServerChange(Map<String, dynamic> changeData);
}
