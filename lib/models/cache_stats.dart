/// Cache统计信息
///
/// 用于监控和报告缓存系统的性能和使用情况
class CacheStats {
  /// Notes缓存条目数
  final int notesCount;

  /// Drawings缓存条目数
  final int drawingsCount;

  /// Notes缓存总大小（字节）
  final int notesSizeBytes;

  /// Drawings缓存总大小（字节）
  final int drawingsSizeBytes;

  /// Notes缓存命中次数
  final int notesHits;

  /// Drawings缓存命中次数
  final int drawingsHits;

  /// 过期条目数（超过保留期限）
  final int expiredCount;

  const CacheStats({
    required this.notesCount,
    required this.drawingsCount,
    required this.notesSizeBytes,
    required this.drawingsSizeBytes,
    required this.notesHits,
    required this.drawingsHits,
    required this.expiredCount,
  });

  /// 空统计（用于初始化）
  factory CacheStats.empty() {
    return const CacheStats(
      notesCount: 0,
      drawingsCount: 0,
      notesSizeBytes: 0,
      drawingsSizeBytes: 0,
      notesHits: 0,
      drawingsHits: 0,
      expiredCount: 0,
    );
  }

  /// 总条目数
  int get totalCount => notesCount + drawingsCount;

  /// 总缓存大小（字节）
  int get totalSizeBytes => notesSizeBytes + drawingsSizeBytes;

  /// 总缓存大小（MB）
  double get totalSizeMB => totalSizeBytes / (1024 * 1024);

  /// Notes缓存大小（MB）
  double get notesSizeMB => notesSizeBytes / (1024 * 1024);

  /// Drawings缓存大小（MB）
  double get drawingsSizeMB => drawingsSizeBytes / (1024 * 1024);

  /// 总命中次数
  int get totalHits => notesHits + drawingsHits;

  /// 平均每条目命中次数
  double get averageHitRate {
    if (totalCount == 0) return 0.0;
    return totalHits / totalCount;
  }

  /// 格式化输出（用于调试）
  String toFormattedString() {
    return '''
CacheStats:
  Total Entries: $totalCount (Notes: $notesCount, Drawings: $drawingsCount)
  Total Size: ${totalSizeMB.toStringAsFixed(2)} MB
    - Notes: ${notesSizeMB.toStringAsFixed(2)} MB
    - Drawings: ${drawingsSizeMB.toStringAsFixed(2)} MB
  Total Hits: $totalHits (Avg: ${averageHitRate.toStringAsFixed(1)} per entry)
  Expired: $expiredCount
''';
  }

  @override
  String toString() {
    return 'CacheStats(entries: $totalCount, size: ${totalSizeMB.toStringAsFixed(2)}MB, hits: $totalHits, expired: $expiredCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CacheStats &&
        other.notesCount == notesCount &&
        other.drawingsCount == drawingsCount &&
        other.notesSizeBytes == notesSizeBytes &&
        other.drawingsSizeBytes == drawingsSizeBytes &&
        other.notesHits == notesHits &&
        other.drawingsHits == drawingsHits &&
        other.expiredCount == expiredCount;
  }

  @override
  int get hashCode {
    return Object.hash(
      notesCount,
      drawingsCount,
      notesSizeBytes,
      drawingsSizeBytes,
      notesHits,
      drawingsHits,
      expiredCount,
    );
  }

  /// 创建副本
  CacheStats copyWith({
    int? notesCount,
    int? drawingsCount,
    int? notesSizeBytes,
    int? drawingsSizeBytes,
    int? notesHits,
    int? drawingsHits,
    int? expiredCount,
  }) {
    return CacheStats(
      notesCount: notesCount ?? this.notesCount,
      drawingsCount: drawingsCount ?? this.drawingsCount,
      notesSizeBytes: notesSizeBytes ?? this.notesSizeBytes,
      drawingsSizeBytes: drawingsSizeBytes ?? this.drawingsSizeBytes,
      notesHits: notesHits ?? this.notesHits,
      drawingsHits: drawingsHits ?? this.drawingsHits,
      expiredCount: expiredCount ?? this.expiredCount,
    );
  }
}
