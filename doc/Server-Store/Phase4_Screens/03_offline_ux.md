# Phase 4-03: Offline UX & Auto-Sync

> **优先级**: P1 - Phase 4
> **状态**: 🟡 Not Started
> **估计时间**: 4小时
> **依赖**: Phase 4-01, 4-02完成
> **完成时间**: TBD

---

## 📋 任务描述

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

## ✅ 实施方案

### 方案1: 网络状态监听

**创建NetworkService**:
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

### 方案2: 自动同步服务

**创建SyncService**:
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

### 方案3: 离线时禁用Cache淘汰

**更新CacheManager**:
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

### 方案4: 全局离线Banner

**创建OfflineBanner Widget**:
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

- [ ] NetworkService正确检测在线/离线
- [ ] 离线时保存成功（标记dirty）
- [ ] 恢复网络后自动sync（2秒内）
- [ ] Dirty数据永不被cache淘汰
- [ ] 全局OfflineBanner正确显示
- [ ] 所有集成测试通过（3个场景）
- [ ] 单元测试通过

---

## 📝 修复检查清单

### 新增服务
- [ ] 创建`lib/services/network_service.dart`
- [ ] 创建`lib/services/sync_service.dart`
- [ ] 创建`lib/widgets/offline_banner.dart`

### Schema变更
- [ ] 添加`is_dirty`列到notes和schedule_drawings
- [ ] 创建dirty索引

### 现有服务更新
- [ ] CacheManager: 离线时跳过淘汰
- [ ] CacheManager: 永不删除dirty数据
- [ ] PRDDatabaseService: 添加`getDirtyNotes()`
- [ ] PRDDatabaseService: 添加`getDirtyDrawings()`
- [ ] ContentService: 添加`syncNote()`
- [ ] ContentService: 添加`syncDrawing()`

### App初始化
- [ ] main.dart: 初始化NetworkService
- [ ] main.dart: 初始化SyncService
- [ ] main.dart: 用OfflineBanner包裹App

### 依赖添加
- [ ] pubspec.yaml: 添加`connectivity_plus: ^5.0.0`

---

## 🔗 相关任务

- **依赖**: [Phase 4-01: EventDetailScreen](01_event_detail_screen.md)
- **依赖**: [Phase 4-02: ScheduleScreen](02_schedule_screen.md)
- **下一步**: [Phase 5: Book Backup](../Phase5_Backup/)

---

**Linus说**: "The network is unreliable. Design for it. Users shouldn't have to think about 'online' vs 'offline' - that's the app's job, not theirs."

**数据安全第一原则**: "Dirty data is sacred. Never delete it, never ignore it, always sync it. The user trusts you with their work - don't break that trust."
