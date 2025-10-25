/// Cache策略配置
///
/// 控制Server-Store架构中的本地缓存行为，包括大小限制、过期时间和自动清理策略。
/// 配置存储在cache_policy表中（单行表，id=1）
class CachePolicy {
  /// 最大缓存大小（MB）
  final int maxCacheSizeMb;

  /// 缓存保留天数
  final int cacheDurationDays;

  /// 是否自动清理过期缓存
  final bool autoCleanup;

  /// 最后一次清理时间
  final DateTime? lastCleanupAt;

  const CachePolicy({
    required this.maxCacheSizeMb,
    required this.cacheDurationDays,
    required this.autoCleanup,
    this.lastCleanupAt,
  });

  /// 默认策略 - 适合大多数用户
  ///
  /// - 50MB缓存 (约250-500个notes)
  /// - 7天保留期
  /// - 自动清理开启
  factory CachePolicy.defaultPolicy() {
    return const CachePolicy(
      maxCacheSizeMb: 50,
      cacheDurationDays: 7,
      autoCleanup: true,
    );
  }

  /// 激进策略 - 存储空间不足时使用
  ///
  /// - 20MB缓存 (约100个notes)
  /// - 3天保留期
  /// - 自动清理开启
  factory CachePolicy.aggressive() {
    return const CachePolicy(
      maxCacheSizeMb: 20,
      cacheDurationDays: 3,
      autoCleanup: true,
    );
  }

  /// 宽松策略 - 存储空间充足时使用
  ///
  /// - 100MB缓存 (约500个notes)
  /// - 14天保留期
  /// - 自动清理开启
  factory CachePolicy.relaxed() {
    return const CachePolicy(
      maxCacheSizeMb: 100,
      cacheDurationDays: 14,
      autoCleanup: true,
    );
  }

  /// 序列化到数据库
  Map<String, dynamic> toMap() {
    return {
      'id': 1, // 单行表，固定id=1
      'max_cache_size_mb': maxCacheSizeMb,
      'cache_duration_days': cacheDurationDays,
      'auto_cleanup': autoCleanup ? 1 : 0,
      'last_cleanup_at': lastCleanupAt != null
          ? lastCleanupAt!.millisecondsSinceEpoch ~/ 1000
          : null,
    };
  }

  /// 从数据库反序列化
  factory CachePolicy.fromMap(Map<String, dynamic> map) {
    return CachePolicy(
      maxCacheSizeMb: map['max_cache_size_mb'] as int,
      cacheDurationDays: map['cache_duration_days'] as int,
      autoCleanup: (map['auto_cleanup'] as int) == 1,
      lastCleanupAt: map['last_cleanup_at'] != null && map['last_cleanup_at'] != 0
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['last_cleanup_at'] as int) * 1000)
          : null,
    );
  }

  /// 创建副本并修改部分字段
  CachePolicy copyWith({
    int? maxCacheSizeMb,
    int? cacheDurationDays,
    bool? autoCleanup,
    DateTime? lastCleanupAt,
  }) {
    return CachePolicy(
      maxCacheSizeMb: maxCacheSizeMb ?? this.maxCacheSizeMb,
      cacheDurationDays: cacheDurationDays ?? this.cacheDurationDays,
      autoCleanup: autoCleanup ?? this.autoCleanup,
      lastCleanupAt: lastCleanupAt ?? this.lastCleanupAt,
    );
  }

  @override
  String toString() {
    return 'CachePolicy('
        'maxSize: ${maxCacheSizeMb}MB, '
        'duration: ${cacheDurationDays}days, '
        'autoCleanup: $autoCleanup, '
        'lastCleanup: $lastCleanupAt'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CachePolicy &&
        other.maxCacheSizeMb == maxCacheSizeMb &&
        other.cacheDurationDays == cacheDurationDays &&
        other.autoCleanup == autoCleanup &&
        other.lastCleanupAt == lastCleanupAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      maxCacheSizeMb,
      cacheDurationDays,
      autoCleanup,
      lastCleanupAt,
    );
  }
}
