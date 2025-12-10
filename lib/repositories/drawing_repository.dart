import '../models/schedule_drawing.dart';

/// Repository interface for ScheduleDrawing entity cache operations
/// Handles local caching of schedule drawings for display
abstract class IDrawingRepository {
  /// Retrieve a cached drawing for a specific book and date
  /// Returns null if not cached
  Future<ScheduleDrawing?> getCached(String bookUuid, DateTime date);

  /// Save a drawing to local cache
  Future<void> saveToCache(ScheduleDrawing drawing);

  /// Delete a drawing from cache
  Future<void> deleteCache(String bookUuid, DateTime date);

  /// Retrieve all cached drawings for a specific book
  Future<List<ScheduleDrawing>> getAllCachedForBook(String bookUuid);

  /// Get all cached drawings
  Future<List<ScheduleDrawing>> getAllCached();
}
