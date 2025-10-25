# Phase 1-03: Cache Policy Design

> **优先级**: P1 - Phase 1
> **状态**: ✅ 已完成
> **估计时间**: 1小时 (实际: 50分钟)
> **依赖**: Phase 1-02 ✅
> **完成时间**: 2025-10-24

---

## 📋 任务描述

### 目标

设计和实现cache策略配置系统：
1. 定义合理的默认cache策略
2. 创建CachePolicy模型类
3. 支持用户自定义cache设置

---

## 🧠 Linus式分析

**核心问题**: 如何在"节省空间"和"良好体验"之间取得平衡？

**Bad Taste (硬编码)**:
```dart
// 在代码里写死
const MAX_CACHE_SIZE = 50 * 1024 * 1024;  // 50MB
const CACHE_DURATION = 7; // 7天

// 用户无法调整，出问题只能等更新
```

**Good Taste (可配置)**:
```dart
// 从数据库读取，用户可调整
final policy = await cacheManager.getPolicy();
if (cacheSize > policy.maxCacheSizeMb * 1024 * 1024) {
  await evict();
}

// 用户设备存储足够？调高限制
// 用户存储不足？调低限制
```

---

## ✅ 实施方案

### 1. CachePolicy模型

**文件**: `lib/models/cache_policy.dart` (新建)

```dart
/// Cache策略配置
class CachePolicy {
  final int maxCacheSizeMb;       // 最大缓存大小（MB）
  final int cacheDurationDays;    // 缓存保留天数
  final bool autoCleanup;         // 是否自动清理
  final DateTime? lastCleanupAt;  // 最后清理时间

  const CachePolicy({
    required this.maxCacheSizeMb,
    required this.cacheDurationDays,
    required this.autoCleanup,
    this.lastCleanupAt,
  });

  /// 默认策略
  factory CachePolicy.defaultPolicy() {
    return const CachePolicy(
      maxCacheSizeMb: 50,           // 50MB - 约250-500个notes
      cacheDurationDays: 7,         // 7天 - 平衡新鲜度和可用性
      autoCleanup: true,            // 默认开启自动清理
    );
  }

  /// 激进策略（存储空间不足时）
  factory CachePolicy.aggressive() {
    return const CachePolicy(
      maxCacheSizeMb: 20,
      cacheDurationDays: 3,
      autoCleanup: true,
    );
  }

  /// 宽松策略（存储空间充足时）
  factory CachePolicy.relaxed() {
    return const CachePolicy(
      maxCacheSizeMb: 100,
      cacheDurationDays: 14,
      autoCleanup: true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': 1,  // 单行表
      'max_cache_size_mb': maxCacheSizeMb,
      'cache_duration_days': cacheDurationDays,
      'auto_cleanup': autoCleanup ? 1 : 0,
      'last_cleanup_at': lastCleanupAt?.millisecondsSinceEpoch ~/ 1000,
    };
  }

  factory CachePolicy.fromMap(Map<String, dynamic> map) {
    return CachePolicy(
      maxCacheSizeMb: map['max_cache_size_mb'] as int,
      cacheDurationDays: map['cache_duration_days'] as int,
      autoCleanup: (map['auto_cleanup'] as int) == 1,
      lastCleanupAt: map['last_cleanup_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_cleanup_at'] * 1000)
          : null,
    );
  }

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
}
```

### 2. 策略选择逻辑

**合理的默认值推导**:

| 设备类型 | 默认策略 | 原因 |
|---------|---------|------|
| **iPhone 14+ (256GB+)** | Relaxed | 存储充足，优先体验 |
| **iPhone 13/12 (128GB)** | Default | 平衡 |
| **iPhone SE (64GB)** | Aggressive | 存储紧张，优先节省 |
| **Android 旗舰** | Relaxed | 存储充足 |
| **Android 中端** | Default | 平衡 |
| **Web** | Default | 使用浏览器限制 |

**自动选择算法**:

```dart
Future<CachePolicy> _selectInitialPolicy() async {
  // 获取设备存储信息
  final totalSpace = await _getDeviceTotalSpace();
  final freeSpace = await _getDeviceFreeSpace();

  // 根据可用空间选择策略
  if (freeSpace < 5 * 1024 * 1024 * 1024) {  // < 5GB
    return CachePolicy.aggressive();
  } else if (freeSpace > 20 * 1024 * 1024 * 1024) {  // > 20GB
    return CachePolicy.relaxed();
  } else {
    return CachePolicy.defaultPolicy();
  }
}
```

### 3. 用户界面配置

**SettingsScreen中添加Cache设置**:

```dart
class CacheSettingsWidget extends StatelessWidget {
  final CachePolicy policy;
  final Function(CachePolicy) onUpdate;

  Widget build(BuildContext context) {
    return Column(
      children: [
        // Cache大小滑块
        ListTile(
          title: Text('Max Cache Size'),
          subtitle: Text('${policy.maxCacheSizeMb} MB'),
        ),
        Slider(
          value: policy.maxCacheSizeMb.toDouble(),
          min: 10,
          max: 200,
          divisions: 19,
          label: '${policy.maxCacheSizeMb} MB',
          onChanged: (value) {
            onUpdate(policy.copyWith(
              maxCacheSizeMb: value.toInt(),
            ));
          },
        ),

        // 缓存时长
        ListTile(
          title: Text('Cache Duration'),
          subtitle: Text('${policy.cacheDurationDays} days'),
        ),
        Slider(
          value: policy.cacheDurationDays.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          label: '${policy.cacheDurationDays} days',
          onChanged: (value) {
            onUpdate(policy.copyWith(
              cacheDurationDays: value.toInt(),
            ));
          },
        ),

        // 自动清理开关
        SwitchListTile(
          title: Text('Auto Cleanup'),
          subtitle: Text('Automatically remove old cache'),
          value: policy.autoCleanup,
          onChanged: (value) {
            onUpdate(policy.copyWith(autoCleanup: value));
          },
        ),
      ],
    );
  }
}
```

---

## 🧪 测试计划

### 测试 1: 默认策略

```dart
test('Default policy has reasonable values', () {
  final policy = CachePolicy.defaultPolicy();

  expect(policy.maxCacheSizeMb, 50);
  expect(policy.cacheDurationDays, 7);
  expect(policy.autoCleanup, true);
});
```

### 测试 2: 策略持久化

```dart
test('Policy persists across app restarts', () async {
  final db = PRDDatabaseService();

  // 保存自定义策略
  final custom = CachePolicy(
    maxCacheSizeMb: 100,
    cacheDurationDays: 14,
    autoCleanup: false,
  );
  await db.database.update('cache_policy', custom.toMap());

  // 重新打开数据库
  await db.close();
  final dbNew = PRDDatabaseService();

  // 读取策略
  final loaded = await dbNew.database.query('cache_policy');
  final policy = CachePolicy.fromMap(loaded.first);

  expect(policy.maxCacheSizeMb, 100);
  expect(policy.cacheDurationDays, 14);
  expect(policy.autoCleanup, false);
});
```

### 测试 3: 策略调整建议

```dart
test('Suggests policy based on available space', () async {
  // 模拟低存储
  when(mockDeviceInfo.getFreeSpace()).thenAnswer((_) async => 3 * 1024 * 1024 * 1024); // 3GB

  final suggested = await selectOptimalPolicy();

  expect(suggested.maxCacheSizeMb, lessThanOrEqualTo(20));
  expect(suggested.cacheDurationDays, lessThanOrEqualTo(3));
});
```

---

## 📊 策略对比

### 默认策略效果

| 策略类型 | 缓存大小 | 缓存时长 | 预期notes数 | 适用场景 |
|---------|---------|---------|-----------|----------|
| **Aggressive** | 20MB | 3天 | ~100 notes | 存储< 5GB |
| **Default** | 50MB | 7天 | ~250 notes | 大多数用户 |
| **Relaxed** | 100MB | 14天 | ~500 notes | 存储> 20GB |

### 性能影响

| 指标 | Aggressive | Default | Relaxed |
|------|-----------|---------|---------|
| **Cache命中率** | ~60% | ~80% | ~90% |
| **平均加载时间** | 800ms | 300ms | 150ms |
| **存储占用** | 20MB | 50MB | 100MB |
| **清理频率** | 每天 | 每3天 | 每周 |

---

## ✅ 验收标准

- [x] CachePolicy模型类实现
- [x] 默认策略合理
- [x] 策略持久化正常
- [x] Database methods (getCachePolicy/updateCachePolicy) implemented
- [x] 单元测试通过 (19/19 tests)
- [ ] Settings UI实现 (待Phase 4)
- [ ] 策略调整立即生效 (待Phase 4)

---

## 📝 实施清单

### 代码实现
- [ ] 创建CachePolicy模型
- [ ] 添加策略选择逻辑
- [ ] 实现Settings UI
- [ ] 添加策略验证

### 测试
- [ ] 单元测试
- [ ] UI测试
- [ ] 性能测试（不同策略）

### 文档
- [ ] 用户文档：如何调整cache设置
- [ ] 开发文档：策略设计原理

---

## 🔗 相关任务

- **依赖**: [Phase 1-02: Client Schema Changes](02_client_schema_changes.md)
- **使用者**: [Phase 3-02: CacheManager](../Phase3_ClientServices/02_cache_manager.md)

---

## 📊 状态追踪

| 阶段 | 状态 | 完成时间 | 负责人 |
|------|------|----------|--------|
| 策略设计 | ✅ | 2025-10-23 | Linus |
| 模型实现 | ✅ | 2025-10-24 | Claude |
| Database方法 | ✅ | 2025-10-24 | Claude |
| 单元测试 | ✅ | 2025-10-24 | Claude |
| UI实现 | ⏸️ | - | 待Phase 4 |
| 测试验证 | ⏸️ | - | 待Phase 4 |

### 实施总结

**已完成的工作** (2025-10-24):

1. **CachePolicy Model** (`lib/models/cache_policy.dart`)
   - ✅ 4个字段: maxCacheSizeMb, cacheDurationDays, autoCleanup, lastCleanupAt
   - ✅ toMap() / fromMap() 方法（支持数据库序列化）
   - ✅ copyWith() 方法（支持部分字段更新）
   - ✅ 3个工厂构造函数：
     - defaultPolicy() - 50MB, 7天
     - aggressive() - 20MB, 3天
     - relaxed() - 100MB, 14天
   - ✅ 重写 toString(), ==, hashCode

2. **Database Methods** (`lib/services/prd_database_service.dart`)
   - ✅ getCachePolicy() - 从cache_policy表读取配置
   - ✅ updateCachePolicy(CachePolicy) - 更新配置
   - ✅ 单行表支持（id=1固定）
   - ✅ 错误处理（fallback到默认值）

3. **Unit Tests**
   - ✅ Model tests (12/12 passed): `test/models/cache_policy_test.dart`
     - toMap/fromMap round-trip
     - Factory constructors
     - copyWith behavior
     - Equality and hashCode
     - null handling
   - ✅ Database tests (7/7 passed): `test/services/cache_policy_db_test.dart`
     - Read default policy after v8 migration
     - Update policy values
     - Persist lastCleanupAt
     - Single-row table constraint
     - Factory constructors persistence

4. **代码质量**
   - ✅ 无编译错误
   - ✅ 类型安全（null safety）
   - ✅ 文档注释完整
   - ✅ 遵循Dart conventions

**待Phase 4实施**:
- Settings UI (cache配置界面)
- 用户可调整cache大小和时长
- 实时生效逻辑

---

**Linus说**: "Defaults matter. Most users will never change settings. Choose defaults that work for 80% of cases."
