import '../models/note.dart';

/// Repository interface for Note entity cache operations
/// Handles local caching of notes for display
abstract class INoteRepository {
  /// Retrieve a cached note for a specific event
  /// Returns null if not cached
  Future<Note?> getCached(String eventId);

  /// Save a note to local cache
  Future<void> saveToCache(Note note);

  /// Delete a note from cache
  Future<void> deleteCache(String eventId);

  /// Retrieve all cached notes for a specific book
  Future<List<Note>> getAllCachedForBook(String bookUuid);

  /// Get all cached notes
  Future<List<Note>> getAllCached();

  /// Apply server change to local database
  Future<void> applyServerChange(Map<String, dynamic> changeData);
}
