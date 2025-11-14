import 'package:flutter/foundation.dart';
import '../models/cache_stats.dart';
import '../models/note.dart';
import '../models/schedule_drawing.dart';
import 'database/prd_database_service.dart';

/// CacheManager - 智能缓存管理器
///
/// 实现LRU淘汰、空间限制、时间过期和自动清理机制
/// 管理notes和schedule_drawings的本地缓存
///
/// Linus说: "Caches must be managed. Unlimited growth is a bug, not a feature."
class CacheManager {
  final PRDDatabaseService _db;

  CacheManager(this._db);

  // ===================
  // Notes Cache Operations
  // ===================

  /// 从缓存获取Note（并增加命中计数）
  /// Uses person sync logic - if event has record_number, syncs with latest note from same person group
  Future<Note?> getNote(int eventId) async {
    final note = await _db.loadNoteForEvent(eventId);
    if (note != null) {
      // 增加cache命中计数
      await _db.incrementNoteCacheHit(eventId);
    }
    return note;
  }

  /// 保存Note到缓存（更新cached_at时间戳）
  ///
  /// [dirty] - 标记note是否需要同步到server (默认false)
  /// Uses person sync logic - if event has record_number, syncs strokes to all events in same person group
  /// Also releases lock on the note
  Future<void> saveNote(int eventId, Note note, {bool dirty = false}) async {
    // 如果指定dirty参数，更新note的isDirty标记
    final noteToSave = dirty ? note.copyWith(isDirty: true) : note;
    await _db.saveNoteWithSync(eventId, noteToSave);

    // 保存后检查是否需要自动清理
    final policy = await _db.getCachePolicy();
    if (policy.autoCleanup) {
      await _autoCleanupIfNeeded();
    }
  }

  /// 标记Note为clean（已同步到server）
  ///
  /// 清除isDirty标记，表示note已成功同步到server
  Future<void> markNoteClean(int eventId) async {
    final note = await _db.getCachedNote(eventId);
    if (note != null && note.isDirty) {
      final cleanNote = note.copyWith(isDirty: false);
      await _db.saveCachedNote(cleanNote);
      debugPrint('✅ CacheManager: Marked note $eventId as clean (synced)');
    }
  }

  /// 从缓存删除Note
  Future<void> deleteNote(int eventId) async {
    await _db.deleteCachedNote(eventId);
  }

  // ===================
  // Lock Mechanism
  // ===================

  /// Try to acquire a lock on a note for editing
  /// Returns true if lock was acquired, false if locked by another device
  Future<bool> acquireNoteLock(int eventId) async {
    return await _db.acquireNoteLock(eventId);
  }

  /// Release a lock on a note
  Future<void> releaseNoteLock(int eventId) async {
    await _db.releaseNoteLock(eventId);
  }

  /// Check if a note is locked by another device
  Future<bool> isNoteLockedByOther(int eventId) async {
    return await _db.isNoteLockedByOther(eventId);
  }

  /// Clean up stale locks (older than 5 minutes)
  Future<int> cleanupStaleLocks() async {
    return await _db.cleanupStaleLocks();
  }

  // ===================
  // Drawings Cache Operations
  // ===================

  /// 从缓存获取ScheduleDrawing（并增加命中计数）
  Future<ScheduleDrawing?> getDrawing(
      int bookId, DateTime date, int viewMode) async {
    final drawing = await _db.getCachedDrawing(bookId, date, viewMode);
    if (drawing != null) {
      // 增加cache命中计数
      await _db.incrementDrawingCacheHit(bookId, date, viewMode);
    }
    return drawing;
  }

  /// 保存ScheduleDrawing到缓存（更新cached_at时间戳）
  ///
  /// Note: saveCachedDrawing已经在PRDDatabaseService中处理cached_at更新
  Future<void> saveDrawing(ScheduleDrawing drawing) async {
    await _db.saveCachedDrawing(drawing);

    // 保存后检查是否需要自动清理
    final policy = await _db.getCachePolicy();
    if (policy.autoCleanup) {
      await _autoCleanupIfNeeded();
    }
  }

  /// 从缓存删除ScheduleDrawing
  Future<void> deleteDrawing(int bookId, DateTime date, int viewMode) async {
    await _db.deleteCachedDrawing(bookId, date, viewMode);
  }

  // ===================
  // Cache Management
  // ===================

  /// 删除过期的缓存条目
  ///
  /// 根据cache_policy中的cache_duration_days删除超期条目
  /// 返回删除的总条目数
  Future<int> evictExpired() async {
    final policy = await _db.getCachePolicy();
    final notesDeleted = await _db.deleteExpiredNotes(policy.cacheDurationDays);
    final drawingsDeleted =
        await _db.deleteExpiredDrawings(policy.cacheDurationDays);

    final totalDeleted = notesDeleted + drawingsDeleted;
    if (totalDeleted > 0) {
      debugPrint(
          '🗑️ CacheManager: Evicted $totalDeleted expired entries (Notes: $notesDeleted, Drawings: $drawingsDeleted)');
    }

    return totalDeleted;
  }

  /// LRU淘汰 - 删除最少使用的条目直到达到目标大小
  ///
  /// [targetSizeMB] 目标缓存大小（MB）
  /// 返回删除的总条目数
  Future<int> evictLRU(int targetSizeMB) async {
    int totalDeleted = 0;
    final targetSizeBytes = targetSizeMB * 1024 * 1024;

    // 循环删除最少使用的条目，直到达到目标大小
    while (true) {
      final currentSize = await getCacheSizeBytes();
      if (currentSize <= targetSizeBytes) {
        break; // 已达到目标
      }

      // 删除最少使用的notes和drawings（各删除一些）
      // 每次删除一批，避免一次性删除过多
      final batchSize = 10;

      final notesDeleted = await _db.deleteLRUNotes(batchSize);
      final drawingsDeleted = await _db.deleteLRUDrawings(batchSize);

      final int deleted = notesDeleted + drawingsDeleted;
      if (deleted == 0) {
        // 没有更多可删除的条目
        break;
      }

      totalDeleted += deleted;

      // 避免无限循环
      if (totalDeleted > 1000) {
        debugPrint('⚠️ CacheManager: LRU eviction limit reached (1000 entries)');
        break;
      }
    }

    if (totalDeleted > 0) {
      final finalSize = await getCacheSizeMB();
      debugPrint(
          '🗑️ CacheManager: LRU evicted $totalDeleted entries. Cache size: ${finalSize.toStringAsFixed(2)}MB');
    }

    return totalDeleted;
  }

  /// 获取当前缓存大小（字节）
  Future<int> getCacheSizeBytes() async {
    final notesSize = await _db.getNotesCacheSize();
    final drawingsSize = await _db.getDrawingsCacheSize();
    return notesSize + drawingsSize;
  }

  /// 获取当前缓存大小（MB）
  Future<double> getCacheSizeMB() async {
    final sizeBytes = await getCacheSizeBytes();
    return sizeBytes / (1024 * 1024);
  }

  /// 清空所有缓存
  Future<void> clearAll() async {
    await _db.clearNotesCache();
    await _db.clearDrawingsCache();
    debugPrint('🗑️ CacheManager: All cache cleared');
  }

  // ===================
  // Statistics
  // ===================

  /// 获取缓存统计信息
  Future<CacheStats> getStats() async {
    final policy = await _db.getCachePolicy();

    final notesCount = await _db.getNotesCount();
    final drawingsCount = await _db.getDrawingsCount();

    final notesSizeBytes = await _db.getNotesCacheSize();
    final drawingsSizeBytes = await _db.getDrawingsCacheSize();

    final notesHits = await _db.getNotesHitCount();
    final drawingsHits = await _db.getDrawingsHitCount();

    final expiredNotes = await _db.countExpiredNotes(policy.cacheDurationDays);
    final expiredDrawings =
        await _db.countExpiredDrawings(policy.cacheDurationDays);

    return CacheStats(
      notesCount: notesCount,
      drawingsCount: drawingsCount,
      notesSizeBytes: notesSizeBytes,
      drawingsSizeBytes: drawingsSizeBytes,
      notesHits: notesHits,
      drawingsHits: drawingsHits,
      expiredCount: expiredNotes + expiredDrawings,
    );
  }

  // ===================
  // Auto-Cleanup
  // ===================

  /// 自动清理 - App启动时调用
  ///
  /// 执行步骤:
  /// 1. 删除过期条目
  /// 2. 检查缓存大小
  /// 3. 如果超限，执行LRU淘汰
  Future<void> performStartupCleanup() async {
    final policy = await _db.getCachePolicy();
    if (!policy.autoCleanup) {
      debugPrint('ℹ️ CacheManager: Auto-cleanup disabled, skipping startup cleanup');
      return;
    }

    debugPrint('🧹 CacheManager: Starting startup cleanup...');

    // 1. 删除过期条目
    final expiredCount = await evictExpired();

    // 2. 检查缓存大小
    final currentSizeMB = await getCacheSizeMB();
    final maxSizeMB = policy.maxCacheSizeMb;

    debugPrint(
        'ℹ️ CacheManager: Cache size: ${currentSizeMB.toStringAsFixed(2)}MB / ${maxSizeMB}MB');

    // 3. 如果超限，LRU淘汰
    int lruCount = 0;
    if (currentSizeMB > maxSizeMB) {
      lruCount = await evictLRU(maxSizeMB);
    }

    // 更新last_cleanup_at
    final updatedPolicy = policy.copyWith(lastCleanupAt: DateTime.now());
    await _db.updateCachePolicy(updatedPolicy);

    debugPrint(
        '✅ CacheManager: Startup cleanup complete (Expired: $expiredCount, LRU: $lruCount)');
  }

  /// 内部: 检查是否需要自动清理（保存后调用）
  Future<void> _autoCleanupIfNeeded() async {
    final policy = await _db.getCachePolicy();
    final currentSizeMB = await getCacheSizeMB();

    // 只有超过限制时才清理
    if (currentSizeMB > policy.maxCacheSizeMb) {
      debugPrint(
          '⚠️ CacheManager: Cache size (${currentSizeMB.toStringAsFixed(2)}MB) exceeds limit (${policy.maxCacheSizeMb}MB), triggering cleanup...');

      // 先删除过期
      await evictExpired();

      // 再检查，如果还超限则LRU淘汰
      final sizeAfterExpiry = await getCacheSizeMB();
      if (sizeAfterExpiry > policy.maxCacheSizeMb) {
        await evictLRU(policy.maxCacheSizeMb);
      }
    }
  }
}
