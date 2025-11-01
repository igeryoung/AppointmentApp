import '../models/schedule_drawing.dart';

/// Repository interface for ScheduleDrawing entity cache operations
/// Handles local caching of schedule drawings with dirty flag tracking for sync
abstract class IDrawingRepository {
  /// Retrieve a cached drawing for a specific book and date
  /// Returns null if not cached
  Future<ScheduleDrawing?> getCached(int bookId, DateTime date);

  /// Save a drawing to local cache
  /// Marks as dirty if not synced with server
  Future<void> saveToCache(ScheduleDrawing drawing, {required bool isDirty});

  /// Delete a drawing from cache
  Future<void> deleteCache(int bookId, DateTime date);

  /// Retrieve all drawings marked as dirty (not synced to server)
  Future<List<ScheduleDrawing>> getDirtyDrawings();

  /// Mark a drawing as clean (synced with server)
  Future<void> markClean(int bookId, DateTime date);

  /// Retrieve all cached drawings for a specific book
  Future<List<ScheduleDrawing>> getAllCachedForBook(int bookId);

  /// Get all cached drawings
  Future<List<ScheduleDrawing>> getAllCached();
}
