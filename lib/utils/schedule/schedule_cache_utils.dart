import 'package:flutter/material.dart';
import '../../models/event.dart';
import '../../services/cache_manager.dart';
import '../../services/database_service_interface.dart';
import '../../services/database/prd_database_service.dart';

/// Utility class for cache management in ScheduleScreen
class ScheduleCacheUtils {
  /// Show Clear Cache dialog with cached event names
  static Future<void> showClearCacheDialog({
    required BuildContext context,
    required CacheManager? cacheManager,
    required List<Event> events,
    required IDatabaseService dbService,
    required int bookId,
    required DateTime effectiveDate,
    required VoidCallback onReloadDrawing,
    required VoidCallback onPreloadNotes,
  }) async {
    if (cacheManager == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cache Manager not initialized'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Get cache stats
    final stats = await cacheManager.getStats();
    final cacheSize = (stats.notesSizeBytes + stats.drawingsSizeBytes) / (1024 * 1024);
    final notesSizeMB = stats.notesSizeBytes / (1024 * 1024);
    final drawingsSizeMB = stats.drawingsSizeBytes / (1024 * 1024);

    // Get cached event names for current events
    final cachedEventNames = <String>[];
    for (final event in events) {
      if (event.id != null) {
        final cachedNote = await cacheManager.getNote(event.id!);
        if (cachedNote != null) {
          cachedEventNames.add(event.name);
        }
      }
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache (Experimental)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.cached,
                color: Colors.amber,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'Cache Stats:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('• ${stats.notesCount} cached notes (${notesSizeMB.toStringAsFixed(2)} MB)'),
              Text('• ${stats.drawingsCount} cached drawings (${drawingsSizeMB.toStringAsFixed(2)} MB)'),
              Text('• Total Size: ${cacheSize.toStringAsFixed(2)} MB'),
              const SizedBox(height: 12),
              if (cachedEventNames.isNotEmpty) ...[
                const Text(
                  'Cached events in current view:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                ...cachedEventNames.map((name) => Text('  • $name')),
                const SizedBox(height: 12),
              ],
              const Text(
                'Choose what to clear:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'drawings_only'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Text('Clear Drawings Only'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'all'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
            ),
            child: const Text('Clear All Cache'),
          ),
        ],
      ),
    );

    if (result == 'drawings_only') {
      await clearDrawingsCacheAndReload(
        context: context,
        cacheManager: cacheManager,
        dbService: dbService,
        bookId: bookId,
        effectiveDate: effectiveDate,
        onReloadDrawing: onReloadDrawing,
      );
    } else if (result == 'all') {
      await clearCacheAndReload(
        context: context,
        cacheManager: cacheManager,
        onPreloadNotes: onPreloadNotes,
      );
    }
  }

  /// Clear all cache and optionally trigger preload
  static Future<void> clearCacheAndReload({
    required BuildContext context,
    required CacheManager? cacheManager,
    required VoidCallback onPreloadNotes,
  }) async {
    if (cacheManager == null) return;

    try {
      // Get stats before clearing
      final statsBefore = await cacheManager.getStats();
      final totalItemsBefore = statsBefore.notesCount + statsBefore.drawingsCount;

      // Clear all cache
      debugPrint('🗑️ ScheduleScreen: Clearing all cache...');
      await cacheManager.clearAll();
      debugPrint('✅ ScheduleScreen: Cache cleared');

      // Get stats after clearing to confirm
      final statsAfter = await cacheManager.getStats();
      final totalItemsAfter = statsAfter.notesCount + statsAfter.drawingsCount;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cache cleared: $totalItemsBefore items → $totalItemsAfter items'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Optionally trigger preload again to test
      debugPrint('🔄 ScheduleScreen: Triggering preload to test cache mechanism...');
      onPreloadNotes();

    } catch (e) {
      debugPrint('❌ ScheduleScreen: Failed to clear cache: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear cache: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Clear drawings cache only and reload current drawing from server
  static Future<void> clearDrawingsCacheAndReload({
    required BuildContext context,
    required CacheManager? cacheManager,
    required IDatabaseService dbService,
    required int bookId,
    required DateTime effectiveDate,
    required VoidCallback onReloadDrawing,
  }) async {
    if (cacheManager == null) return;

    try {
      // Get stats before clearing
      final statsBefore = await cacheManager.getStats();
      final drawingsCountBefore = statsBefore.drawingsCount;

      // Clear drawings cache only
      debugPrint('🗑️ ScheduleScreen: Clearing drawings cache...');
      await cacheManager.deleteDrawing(
        bookId,
        effectiveDate,
        1, // viewMode for 3-day view
      );

      // Actually clear all drawings cache to properly test
      final db = dbService as PRDDatabaseService;
      await db.clearDrawingsCache();
      debugPrint('✅ ScheduleScreen: Drawings cache cleared');

      // Get stats after clearing to confirm
      final statsAfter = await cacheManager.getStats();
      final drawingsCountAfter = statsAfter.drawingsCount;

      // Reload current drawing - this will trigger server fetch via ContentService
      debugPrint('🔄 ScheduleScreen: Reloading drawing from server...');
      onReloadDrawing();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Drawings cache cleared: $drawingsCountBefore → $drawingsCountAfter\nReloaded from server'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      }

    } catch (e) {
      debugPrint('❌ ScheduleScreen: Failed to clear drawings cache: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear drawings cache: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
