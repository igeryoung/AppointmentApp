# Phase 4-03: Offline UX & Auto-Sync

> **优先级**: P1 - Phase 4
> **状态**: ✅ Partially Complete
> **估计时间**: 4小时
> **依赖**: Phase 4-01, 4-02完成
> **完成时间**: 2025-10-24 (部分功能)
> **实际时间**: ~3小时
>
> **注**: 核心功能已实现但采用了不同的架构方案（详见下方说明）

---

## 🎯 实际实现总结

### 已实现功能 ✅

**1. 网络状态监听**
- **位置**: `schedule_screen.dart:166-180`, `event_detail_screen.dart:192-208`
- **实现**: 直接使用 `connectivity_plus` (已在 pubspec.yaml:49)
- **架构**: 每个screen独立监听，无全局NetworkService单例
- **特性**: 实时检测网络变化 + 服务器健康检查

**2. 自动同步**
- **位置**: `schedule_screen.dart:237-309`, `event_detail_screen.dart:229-270`
- **实现**: ContentService.syncDirtyNotesForBook() (content_service.dart:415)
- **触发时机**:
  - ✅ 网络恢复时自动触发 (schedule_screen.dart:223-232)
  - ✅ App进入前台时检查 (event_detail_screen.dart:250)
  - ❌ 定时检查(每5分钟) - 未实现
- **架构**: 无全局SyncService单例，由ContentService提供sync方法

**3. 离线UI指示**
- **EventDetailScreen**:
  - 离线banner (event_detail_screen.dart:1258-1294) - 橙色banner显示"Offline - Changes not synced"
  - 未同步banner (event_detail_screen.dart:1298-1324) - 蓝色banner显示"Syncing..."
  - AppBar图标指示 (cloud_off/cloud_upload) (event_detail_screen.dart:1105-1114)
- **ScheduleScreen**:
  - Snackbar提示同步结果 (schedule_screen.dart:260-298)
  - ❌ 无持久化的离线banner

**4. 数据安全**
- **离线保存策略** ✅
  - EventDetail: `_saveNoteWithOfflineFirst()` (event_detail_screen.dart:505)
  - 本地优先保存，标记dirty，后台同步
- **Cache保护** ⚠️
  - ❌ 离线时禁用cache淘汰 - 未明确实现
  - ✅ Dirty数据不被删除 (通过CacheManager逻辑保护)

### 架构差异：计划 vs 实际

| 组件 | 计划方案 | 实际实现 | 原因 |
|------|---------|---------|------|
| NetworkService | 全局单例 | 每个screen独立监听 | ✅ 简化架构，避免全局状态 |
| SyncService | 全局单例 | ContentService方法 | ✅ 功能聚合，减少服务层 |
| OfflineBanner | 全局widget包裹App | 每个screen独立实现 | ✅ 灵活控制不同screen的UI |
| 定时同步 | 每5分钟检查 | 仅网络恢复时触发 | ⚠️ 简化逻辑，减少后台活动 |
| Cache淘汰保护 | 离线时完全禁用 | Dirty数据受保护 | ⚠️ 部分实现 |

**为什么采用不同架构？**

1. **简单性优先**: 直接在screen中处理网络逻辑比全局单例更直观
2. **避免过度抽象**: NetworkService/SyncService增加复杂度但价值有限
3. **测试友好**: 每个screen的网络逻辑独立，容易mock和测试
4. **灵活性**: 不同screen可以有不同的离线策略和UI

**Linus哲学**: "Good code is simple code. Don't create abstractions until you need them."

---

## 📋 任务描述 (原始规划)

### 目标

实现统一的离线体验和自动同步机制：
1. **网络状态监听** - 实时检测在线/离线
2. **自动同步** - 恢复网络后自动同步dirty数据
3. **全局UI指示** - 统一的离线banner
4. **数据安全** - 离线时禁用cache淘汰

### 核心原则

**永不丢失数据 (Never Lose Data)**:
```
离线保存 → 本地dirty标记 → 网络恢复 → 自动sync → 清除dirty
^^^^^^^^^^^^^                ^^^^^^^^^^^^^^^^^^^^^^^^
用户立即得到反馈              后台自动完成，无需干预
```

---

## 🧠 Linus式根因分析

### 离线的本质

**Bad Thinking**:
```dart
// 把离线当成"错误"
if (!isOnline) {
  showError("No network! Cannot save.");  // ❌ 拒绝操作
  return;
}
```

**Good Thinking**:
```dart
// 把离线当成"状态"
await saveLocally();  // ✅ 总是成功

if (isOnline) {
  await syncToServer();  // Best effort
} else {
  markAsDirty();  // 稍后sync
}
```

### 同步时机

**Good Taste**: 用户不应该手动触发同步

**自动同步时机**:
1. **网络恢复时** - 立即sync所有dirty
2. **App进入前台时** - 检查并sync dirty
3. **定时检查** - 每5分钟尝试sync（如果有dirty）

**不要**:
- ❌ 要求用户点击"同步"按钮（太麻烦）
- ❌ 关闭App时才同步（可能被杀进程）
- ❌ 无限重试（浪费电池）

---

## ✅ 实施方案 (参考 - 采用了不同架构)

> **注意**: 以下是原始计划方案，实际实现采用了更简化的架构（见上方"实际实现总结"）

### 方案1: 网络状态监听 (❌ 未使用此方案)

**原计划: 创建NetworkService单例** (未实现):
```dart
// lib/services/network_service.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Singleton service for network status monitoring
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _networkStatusController =
      StreamController<bool>.broadcast();

  /// Stream of network status (true = online, false = offline)
  Stream<bool> get networkStatus => _networkStatusController.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// Initialize network monitoring
  Future<void> initialize() async {
    // Check initial status
    final result = await _connectivity.checkConnectivity();
    _updateNetworkStatus(result);

    // Listen to changes
    _connectivity.onConnectivityChanged.listen((result) {
      _updateNetworkStatus(result);
    });

    debugPrint('📡 NetworkService: Initialized (isOnline: $_isOnline)');
  }

  void _updateNetworkStatus(ConnectivityResult result) {
    final wasOnline = _isOnline;
    _isOnline = result != ConnectivityResult.none;

    debugPrint('📡 NetworkService: Status changed - ${wasOnline ? "online" : "offline"} → ${_isOnline ? "online" : "offline"}');

    // Notify listeners
    _networkStatusController.add(_isOnline);

    // Trigger auto-sync if came back online
    if (!wasOnline && _isOnline) {
      _onNetworkRestored();
    }
  }

  void _onNetworkRestored() {
    debugPrint('✅ NetworkService: Network restored, triggering auto-sync');

    // Trigger auto-sync via global event
    // (Will be handled by SyncService)
    SyncService().syncAllDirty();
  }

  void dispose() {
    _networkStatusController.close();
  }
}
```

**添加依赖** (pubspec.yaml):
```yaml
dependencies:
  connectivity_plus: ^5.0.0  # Network status monitoring
```

---

### 方案2: 自动同步服务 (❌ 未使用此方案)

**原计划: 创建SyncService单例** (未实现，改用ContentService方法):
```dart
// lib/services/sync_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'content_service.dart';
import 'network_service.dart';
import 'prd_database_service.dart';

/// Service for auto-syncing dirty data to server
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  late ContentService _contentService;
  late PRDDatabaseService _dbService;

  bool _isSyncing = false;
  Timer? _periodicSyncTimer;

  final StreamController<SyncProgress> _progressController =
      StreamController<SyncProgress>.broadcast();

  Stream<SyncProgress> get syncProgress => _progressController.stream;

  /// Initialize sync service
  void initialize(ContentService contentService, PRDDatabaseService dbService) {
    _contentService = contentService;
    _dbService = dbService;

    // Start periodic sync check (every 5 minutes)
    _startPeriodicSync();

    debugPrint('🔄 SyncService: Initialized');
  }

  /// Start periodic sync timer
  void _startPeriodicSync() {
    _periodicSyncTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      if (NetworkService().isOnline && !_isSyncing) {
        debugPrint('⏰ SyncService: Periodic sync check');
        syncAllDirty();
      }
    });
  }

  /// Sync all dirty notes and drawings to server
  Future<void> syncAllDirty() async {
    if (_isSyncing) {
      debugPrint('⏭️ SyncService: Already syncing, skipping');
      return;
    }

    if (!NetworkService().isOnline) {
      debugPrint('⏭️ SyncService: Offline, skipping sync');
      return;
    }

    _isSyncing = true;
    debugPrint('🔄 SyncService: Starting sync of dirty data...');

    try {
      // Step 1: Get all dirty notes
      final dirtyNotes = await _dbService.getDirtyNotes();
      debugPrint('🔄 SyncService: Found ${dirtyNotes.length} dirty notes');

      _progressController.add(SyncProgress(
        total: dirtyNotes.length,
        completed: 0,
        type: 'notes',
      ));

      // Step 2: Sync notes one by one
      int syncedCount = 0;
      for (final note in dirtyNotes) {
        try {
          await _contentService.syncNote(note.eventId);
          syncedCount++;

          _progressController.add(SyncProgress(
            total: dirtyNotes.length,
            completed: syncedCount,
            type: 'notes',
          ));

          debugPrint('✅ SyncService: Synced note ${note.eventId} ($syncedCount/${dirtyNotes.length})');
        } catch (e) {
          debugPrint('❌ SyncService: Failed to sync note ${note.eventId}: $e');
          // Continue with next note
        }
      }

      // Step 3: Get all dirty drawings
      final dirtyDrawings = await _dbService.getDirtyDrawings();
      debugPrint('🔄 SyncService: Found ${dirtyDrawings.length} dirty drawings');

      // Step 4: Sync drawings
      int drawingSyncedCount = 0;
      for (final drawing in dirtyDrawings) {
        try {
          await _contentService.syncDrawing(drawing);
          drawingSyncedCount++;
          debugPrint('✅ SyncService: Synced drawing ($drawingSyncedCount/${dirtyDrawings.length})');
        } catch (e) {
          debugPrint('❌ SyncService: Failed to sync drawing: $e');
        }
      }

      debugPrint('✅ SyncService: Sync completed - Notes: $syncedCount/${dirtyNotes.length}, Drawings: $drawingSyncedCount/${dirtyDrawings.length}');

    } catch (e) {
      debugPrint('❌ SyncService: Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Manually trigger sync (for UI buttons)
  Future<void> manualSync() async {
    debugPrint('👆 SyncService: Manual sync triggered by user');
    await syncAllDirty();
  }

  void dispose() {
    _periodicSyncTimer?.cancel();
    _progressController.close();
  }
}

class SyncProgress {
  final int total;
  final int completed;
  final String type;

  SyncProgress({
    required this.total,
    required this.completed,
    required this.type,
  });

  double get percentage => total > 0 ? completed / total : 0.0;
}
```

**数据库方法** (PRDDatabaseService):
```dart
/// Get all dirty notes (not synced to server)
Future<List<Note>> getDirtyNotes() async {
  final db = await database;
  final result = await db.query(
    'notes',
    where: 'is_dirty = ?',
    whereArgs: [1],
  );

  return result.map((map) => Note.fromMap(map)).toList();
}

/// Get all dirty drawings
Future<List<ScheduleDrawing>> getDirtyDrawings() async {
  final db = await database;
  final result = await db.query(
    'schedule_drawings',
    where: 'is_dirty = ?',
    whereArgs: [1],
  );

  return result.map((map) => ScheduleDrawing.fromMap(map)).toList();
}
```

---

### 方案3: 离线时禁用Cache淘汰 (⚠️ 部分实现)

**原计划: 更新CacheManager禁用淘汰** (未完全实现此逻辑):
```dart
// lib/services/cache_manager.dart

class CacheManager {
  // ... existing code

  /// Evict expired cache entries (ONLY if online)
  Future<void> evictExpired() async {
    // **数据安全第一**: 离线时不删除cache
    if (!NetworkService().isOnline) {
      debugPrint('⏭️ CacheManager: Offline, skipping cache eviction');
      return;
    }

    final policy = await _getCachePolicy();
    final expirationSeconds = policy.cacheDurationDays * 24 * 3600;
    final cutoffTime = DateTime.now().millisecondsSinceEpoch ~/ 1000 - expirationSeconds;

    debugPrint('🗑️ CacheManager: Evicting cache older than ${policy.cacheDurationDays} days');

    // Delete expired notes (only non-dirty ones!)
    final db = await _db.database;
    final deletedNotes = await db.delete(
      'notes',
      where: 'cached_at < ? AND (is_dirty IS NULL OR is_dirty = 0)',
      //                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      //                          Never delete dirty data!
      whereArgs: [cutoffTime],
    );

    // Delete expired drawings (only non-dirty ones!)
    final deletedDrawings = await db.delete(
      'schedule_drawings',
      where: 'cached_at < ? AND (is_dirty IS NULL OR is_dirty = 0)',
      whereArgs: [cutoffTime],
    );

    debugPrint('✅ CacheManager: Evicted $deletedNotes notes, $deletedDrawings drawings');
  }

  /// Evict LRU cache (ONLY if online)
  Future<void> evictLRU(int targetSizeMB) async {
    // **数据安全第一**: 离线时不删除cache
    if (!NetworkService().isOnline) {
      debugPrint('⏭️ CacheManager: Offline, skipping LRU eviction');
      return;
    }

    // ... existing LRU logic, but skip dirty entries
    final db = await _db.database;
    await db.delete(
      'notes',
      where: 'id IN (SELECT id FROM notes WHERE (is_dirty IS NULL OR is_dirty = 0) ORDER BY cache_hit_count ASC LIMIT ?)',
      //                                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      //                                        Never delete dirty data!
      whereArgs: [batchSize],
    );
  }
}
```

**Good Taste**:
- ✅ 离线时保留所有cache（即使过期）
- ✅ 永远不删除dirty数据
- ✅ 恢复在线后才允许淘汰

---

### 方案4: 全局离线Banner (❌ 未使用全局方案)

**原计划: 创建全局OfflineBanner Widget** (未实现，各screen独立实现banner):

**实际实现**: EventDetailScreen已有离线banner (event_detail_screen.dart:1258-1294)

```dart
// lib/widgets/offline_banner.dart

import 'package:flutter/material.dart';
import '../services/network_service.dart';
import '../services/sync_service.dart';

class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOffline = false;
  bool _isSyncing = false;
  double _syncProgress = 0.0;

  @override
  void initState() {
    super.initState();

    // Listen to network status
    NetworkService().networkStatus.listen((isOnline) {
      setState(() {
        _isOffline = !isOnline;
      });
    });

    // Listen to sync progress
    SyncService().syncProgress.listen((progress) {
      setState(() {
        _isSyncing = progress.total > 0 && progress.completed < progress.total;
        _syncProgress = progress.percentage;
      });
    });

    // Initialize state
    _isOffline = !NetworkService().isOnline;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Offline banner
        if (_isOffline)
          Material(
            color: Colors.orange.shade700,
            elevation: 4,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Offline - Changes will sync when online',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Syncing banner
        if (_isSyncing && !_isOffline)
          Material(
            color: Colors.blue.shade700,
            elevation: 4,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      value: _syncProgress,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Syncing changes... ${(_syncProgress * 100).toInt()}%',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Main content
        Expanded(child: widget.child),
      ],
    );
  }
}
```

**在App中使用**:
```dart
// lib/main.dart

class ScheduleNoteApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ...
      home: OfflineBanner(  // 包裹整个App
        child: BookListScreen(),
      ),
    );
  }
}
```

---

## 🧪 测试计划

### 集成测试

**测试场景1: 离线保存 + 自动同步**
```
1. 开启飞行模式
2. 打开EventDetail，创建10个notes
   ✓ 所有notes保存成功
   ✓ 显示"离线模式"banner
   ✓ 所有notes标记为dirty

3. 关闭飞行模式
   ✓ 2秒内自动触发sync
   ✓ 显示"Syncing... 0%"
   ✓ 显示"Syncing... 50%"
   ✓ 显示"Syncing... 100%"
   ✓ Banner消失

4. 在另一台设备登录
   ✓ 10个notes都在
```

**测试场景2: 网络不稳定**
```
1. 创建note，立即断网
   ✓ Note保存成功（本地）
   ✓ 标记为dirty

2. 连网1秒，再断网
   ✓ 尝试sync（可能失败）
   ✓ 保留dirty标记

3. 恢复稳定网络
   ✓ 成功sync
   ✓ 清除dirty标记
```

**测试场景3: Cache淘汰保护**
```
1. 离线状态
2. Cache超过7天过期
3. 触发cache清理
   ✓ Dirty notes不被删除
   ✓ Non-dirty过期notes保留（因为离线）

4. 恢复在线
5. 触发cache清理
   ✓ Dirty notes仍不被删除
   ✓ Non-dirty过期notes被删除
```

### 单元测试

```dart
void main() {
  group('NetworkService', () {
    test('Detects network status changes', () async {
      final service = NetworkService();
      final statuses = <bool>[];

      service.networkStatus.listen((isOnline) {
        statuses.add(isOnline);
      });

      // Simulate network changes
      // ...

      await Future.delayed(Duration(seconds: 1));

      expect(statuses, [true, false, true]);
    });
  });

  group('SyncService', () {
    test('Syncs all dirty notes', () async {
      // Setup: 5 dirty notes
      when(mockDbService.getDirtyNotes())
          .thenAnswer((_) async => List.generate(5, (i) => Note(eventId: i)));

      await syncService.syncAllDirty();

      // Verify all synced
      verify(mockContentService.syncNote(any)).called(5);
    });

    test('Skips sync when offline', () async {
      when(mockNetworkService.isOnline).thenReturn(false);

      await syncService.syncAllDirty();

      // Should not call any sync
      verifyNever(mockContentService.syncNote(any));
    });
  });
}
```

---

## 📦 向后兼容性

**迁移策略**:
1. ✅ 现有cache数据标记为`is_dirty = 0`
2. ✅ NetworkService初始化不影响现有功能
3. ✅ SyncService静默失败，不阻塞UI

**Schema变更** (需要在Phase 1-02补充):
```sql
-- 添加is_dirty列到cache表
ALTER TABLE notes ADD COLUMN is_dirty INTEGER DEFAULT 0;
ALTER TABLE schedule_drawings ADD COLUMN is_dirty INTEGER DEFAULT 0;

-- 创建索引加速dirty查询
CREATE INDEX idx_notes_dirty ON notes(is_dirty) WHERE is_dirty = 1;
CREATE INDEX idx_drawings_dirty ON schedule_drawings(is_dirty) WHERE is_dirty = 1;
```

---

## ✅ 验收标准

- [x] 网络状态监听工作正常（connectivity_plus + health check）✅
- [x] 离线时保存成功（标记dirty）✅
- [x] 恢复网络后自动sync ✅ (schedule_screen.dart:223-232)
- [x] Dirty数据受到保护不被cache淘汰 ✅
- [x] 离线UI指示正确显示 ✅ (EventDetailScreen有banner)
- [ ] ScheduleScreen也有离线banner ❌ (仅有snackbar)
- [ ] 所有集成测试通过（3个场景）⚠️ 待验证
- [ ] 单元测试通过 ⚠️ 待验证

---

## 📝 修复检查清单

### 新增服务 (采用不同架构)
- [ ] ~~创建`lib/services/network_service.dart`~~ ❌ 未创建（直接在screens中使用connectivity_plus）
- [ ] ~~创建`lib/services/sync_service.dart`~~ ❌ 未创建（使用ContentService方法）
- [ ] ~~创建`lib/widgets/offline_banner.dart`~~ ❌ 未创建（各screen独立实现）

### Schema变更
- [x] 添加`is_dirty`列到notes和schedule_drawings ✅
- [x] 创建dirty索引 ✅

### 现有服务更新
- [x] CacheManager: 永不删除dirty数据 ✅
- [ ] CacheManager: 离线时跳过淘汰 ⚠️ 未明确实现
- [x] PRDDatabaseService: 添加`getDirtyNotes()` ✅
- [ ] PRDDatabaseService: 添加`getDirtyDrawings()` ⚠️ 需确认
- [x] ContentService: 添加`syncNote()` ✅ (content_service.dart:150)
- [x] ContentService: 添加`syncDirtyNotesForBook()` ✅ (content_service.dart:415)
- [ ] ContentService: 添加`syncDrawing()` ❌ 未实现

### Screen更新
- [x] ScheduleScreen: 集成connectivity监听 ✅
- [x] ScheduleScreen: 实现auto-sync ✅
- [x] EventDetailScreen: 集成connectivity监听 ✅
- [x] EventDetailScreen: 实现offline-first保存 ✅
- [x] EventDetailScreen: 实现离线banner UI ✅

### App初始化 (采用不同架构)
- [ ] ~~main.dart: 初始化NetworkService~~ ❌ 不需要
- [ ] ~~main.dart: 初始化SyncService~~ ❌ 不需要
- [ ] ~~main.dart: 用OfflineBanner包裹App~~ ❌ 不需要

### 依赖添加
- [x] pubspec.yaml: 添加`connectivity_plus: ^5.0.0` ✅ (已有:49)

---

## 🔗 相关任务

- **依赖**: [Phase 4-01: EventDetailScreen](01_event_detail_screen.md)
- **依赖**: [Phase 4-02: ScheduleScreen](02_schedule_screen.md)
- **下一步**: [Phase 5: Book Backup](../Phase5_Backup/)

---

## 🔮 Future Enhancements (未实现功能)

以下功能在原始规划中但未在当前版本实现，可作为未来优化方向：

### 1. 全局NetworkService单例
- **好处**: 统一网络状态管理，减少重复代码
- **当前方案**: 各screen独立监听，简单直接
- **是否需要**: 低优先级（当前方案已足够）

### 2. 定时自动同步
- **计划**: 每5分钟检查并同步dirty数据
- **当前方案**: 仅在网络恢复和App进入前台时同步
- **是否需要**: 中优先级（可提高数据同步及时性）

### 3. ScheduleScreen离线Banner
- **计划**: 持久化banner提示离线状态
- **当前方案**: 仅有Snackbar临时提示
- **是否需要**: 低优先级（用户主要在EventDetail编辑）

### 4. 离线时禁用Cache淘汰
- **计划**: 离线时完全禁用cache清理
- **当前方案**: Dirty数据受保护，但非dirty过期数据可能被清理
- **是否需要**: 中优先级（提高离线可用性）

### 5. Drawing同步
- **计划**: 实现drawing的dirty标记和同步
- **当前方案**: Drawing仅本地存储
- **是否需要**: 高优先级（如果需要多设备同步drawing）

### 6. 全局OfflineBanner组件
- **计划**: 可复用的widget包裹整个App
- **当前方案**: 各screen独立实现
- **是否需要**: 低优先级（当前各screen需求不同）

---

**Linus说**: "The network is unreliable. Design for it. Users shouldn't have to think about 'online' vs 'offline' - that's the app's job, not theirs."

**数据安全第一原则**: "Dirty data is sacred. Never delete it, never ignore it, always sync it. The user trusts you with their work - don't break that trust."

**实际架构哲学**: "Premature abstraction is the root of all complexity. Build what you need, when you need it."
