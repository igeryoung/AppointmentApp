# Server-Store Architecture - 迁移指南

> **作者**: Linus Torvalds
> **日期**: 2025-10-23
> **目标**: 从Sync架构安全迁移到Server-Store架构

---

## 🎯 迁移概览

### 当前状态 (Sync架构)

```
┌──────────────┐         ┌──────────────┐
│   Device A   │◄───────►│    Server    │
│   SQLite     │  Sync   │  PostgreSQL  │
│ (完整数据)    │         │ (完整数据)    │
└──────────────┘         └──────────────┘
      ▲                         ▲
      │                         │
      │         Sync            │
      │                         │
      ▼                         ▼
┌──────────────┐         ┌──────────────┐
│   Device B   │◄────────┤   Device C   │
│   SQLite     │         │   SQLite     │
│ (完整数据)    │         │ (完整数据)    │
└──────────────┘         └──────────────┘

问题:
- 每个设备存储完整数据
- 复杂的冲突解决
- 版本管理开销大
```

### 目标状态 (Server-Store架构)

```
┌──────────────┐         ┌──────────────┐
│   Device A   │────────►│    Server    │
│   SQLite     │  fetch/ │  PostgreSQL  │
│ (智能缓存)    │  store  │ (唯一真相)    │
└──────────────┘◄────────└──────────────┘
                               ▲
                               │
               ┌───────────────┼───────────────┐
               │                               │
               ▼                               ▼
        ┌──────────────┐              ┌──────────────┐
        │   Device B   │              │   Device C   │
        │   SQLite     │              │   SQLite     │
        │ (智能缓存)    │              │ (智能缓存)    │
        └──────────────┘              └──────────────┘

改进:
- Server是唯一数据源
- 设备仅缓存常用数据
- 无冲突，无复杂同步
```

---

## 📋 迁移路线图

### 里程碑时间线

```
Week 1          Week 2          Week 3
│               │               │
├─ Phase 1 ─────┼─ Phase 2 ─────┼─ Phase 3
│  Database     │  Server API   │  Client Services
│  (2天)        │  (3天)        │  (3天)
│               │               │
│               ├─ Phase 4 ─────┼─ Phase 5
│               │  Screens      │  Backup
│               │  (3天)        │  (2天)
│               │               │
│               │               ├─ Phase 6
│               │               │  Migration
│               │               │  (1天)
│               │               │
│               │               ├─ Phase 7
│               │               │  Testing
│               │               │  (3天)
└───────────────┴───────────────┴─────────────
Day 0           Day 7           Day 14        Day 18
```

---

## 🚀 Phase-by-Phase迁移计划

### Phase 1: 数据库准备 (Day 1-2)

**目标**: 更新schema，支持新架构

#### 服务端任务

```sql
-- 1. 添加book_backups表
CREATE TABLE book_backups (
    id SERIAL PRIMARY KEY,
    book_id INTEGER NOT NULL,
    book_uuid UUID NOT NULL,
    backup_path TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 2. 清理冗余sync字段 (可选，不紧急)
ALTER TABLE notes DROP COLUMN synced_at;
ALTER TABLE notes DROP COLUMN is_deleted;
```

**时间**: 2小时
**风险**: 低（仅新增表）
**回退**: 删除新表即可

#### 客户端任务

```sql
-- 升级到database v8
-- 1. 添加cache metadata
ALTER TABLE notes ADD COLUMN cached_at INTEGER;
ALTER TABLE notes ADD COLUMN cache_hit_count INTEGER DEFAULT 0;
ALTER TABLE schedule_drawings ADD COLUMN cached_at INTEGER;
ALTER TABLE schedule_drawings ADD COLUMN cache_hit_count INTEGER DEFAULT 0;

-- 2. 创建cache_policy表
CREATE TABLE cache_policy (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    max_cache_size_mb INTEGER DEFAULT 50,
    cache_duration_days INTEGER DEFAULT 7,
    auto_cleanup BOOLEAN DEFAULT true
);
```

**时间**: 2小时
**风险**: 低（自动迁移）
**回退**: 不影响现有功能

#### 验收标准

- [ ] Server新表创建成功
- [ ] Client数据库升级到v8
- [ ] 现有数据完整性验证通过
- [ ] 旧功能继续正常工作

---

### Phase 2: Server API开发 (Day 3-5)

**目标**: 实现新的fetch/store endpoints

#### 新增API Endpoints

**Notes API**:
```dart
// 获取单个note
GET  /api/books/:bookId/events/:eventId/note

// 保存note
POST /api/books/:bookId/events/:eventId/note
Body: { strokes_data: "...", version: 2 }

// 批量获取 (用于预加载)
POST /api/books/:bookId/notes/batch
Body: { event_ids: [1, 2, 3, ...] }
```

**Drawings API**:
```dart
GET  /api/books/:bookId/drawings?date=2025-10-23&viewMode=0
POST /api/books/:bookId/drawings
DELETE /api/books/:bookId/drawings/:id
```

**Backup API**:
```dart
POST /api/books/:bookId/backup
GET  /api/books/:bookId/backups
POST /api/books/:bookId/restore/:backupId
```

#### 实施策略

1. **Day 3**: Notes API (6小时)
2. **Day 4**: Drawings + Backup API (8小时)
3. **Day 5**: 批量操作 + 测试 (6小时)

#### 验收标准

- [ ] 所有endpoints实现完成
- [ ] 单元测试覆盖率 > 80%
- [ ] API文档更新
- [ ] Postman测试通过

**重要**: 此阶段旧Sync API保持不变，新旧共存。

---

### Phase 3: Client服务重构 (Day 6-8)

**目标**: 创建ContentService和CacheManager

#### 新增服务

**ContentService** (Day 6, 8小时):
```dart
class ContentService {
  // Cache-first策略
  Future<Note?> getNote(int eventId) async {
    // 1. 尝试cache
    final cached = await _cache.get(eventId);
    if (cached != null && !expired(cached)) {
      return cached;
    }

    // 2. Fetch from server
    final note = await _api.getNote(eventId);
    await _cache.save(note);
    return note;
  }

  // 直接写server
  Future<void> saveNote(Note note) async {
    await _api.saveNote(note);
    await _cache.save(note);
  }
}
```

**CacheManager** (Day 7, 4小时):
```dart
class CacheManager {
  // LRU清理
  Future<void> cleanup() async {
    await _deleteExpired();
    if (await _cacheSize() > maxSize) {
      await _evictLRU();
    }
  }

  // 智能预加载
  Future<void> preload(List<int> eventIds) async {
    final uncached = await _filterUncached(eventIds);
    await _batchFetch(uncached);
  }
}
```

**数据库重构** (Day 8, 4小时):
```dart
// PRDDatabaseService
// 移除: getNoteByEventId(), updateNote()
// 新增: getCachedNote(), cacheNote(), deleteCachedNote()
```

#### 迁移策略

```dart
// 第一步：保留旧方法，添加新方法
class PRDDatabaseService {
  @deprecated
  Future<Note?> getNoteByEventId(int id) => getCachedNote(id);

  Future<Note?> getCachedNote(int id) async {
    // 新实现
  }
}

// 第二步：UI改用新方法
// EventDetailScreen: _dbService.getNoteByEventId() → _contentService.getNote()

// 第三步：删除旧方法
// 删除@deprecated标记的方法
```

#### 验收标准

- [ ] ContentService单元测试通过
- [ ] CacheManager单元测试通过
- [ ] 性能测试: cache命中 < 50ms
- [ ] 旧功能继续工作（通过deprecated方法）

---

### Phase 4: UI层改造 (Day 9-11)

**目标**: 更新Screens使用ContentService

#### EventDetailScreen (Day 9, 6小时)

**Before**:
```dart
Future<void> _loadNote() async {
  final note = await _dbService.getNoteByEventId(eventId);
  setState(() => _note = note);
}
```

**After**:
```dart
Future<void> _loadNote() async {
  setState(() => _isLoading = true);

  try {
    final note = await _contentService.getNote(eventId);
    setState(() {
      _note = note;
      _isLoading = false;
    });
  } catch (e) {
    // Fallback to cache
    final cached = await _contentService.getCached(eventId);
    setState(() {
      _note = cached;
      _isLoading = false;
      _isOffline = true;  // 显示离线提示
    });
  }
}
```

#### ScheduleScreen (Day 10, 6小时)

```dart
@override
void initState() {
  super.initState();
  _loadEvents();
  _preloadNotes();  // 新增：后台预加载
}

Future<void> _preloadNotes() async {
  final eventIds = _events.map((e) => e.id!).toList();
  _contentService.preloadNotes(eventIds).catchError((e) {
    debugPrint('Preload failed: $e');  // 不影响主流程
  });
}
```

#### 离线UX (Day 11, 4小时)

```dart
// 添加离线指示器
Widget _buildOfflineIndicator() {
  if (!_isOffline) return SizedBox.shrink();

  return Material(
    color: Colors.orange,
    child: Padding(
      padding: EdgeInsets.all(8),
      child: Row(
        children: [
          Icon(Icons.cloud_off),
          SizedBox(width: 8),
          Text('Offline - Showing cached data'),
        ],
      ),
    ),
  );
}
```

#### 验收标准

- [ ] EventDetail: Loading指示器正常
- [ ] Schedule: 智能预加载工作
- [ ] 离线模式: 提示清晰
- [ ] 无功能回退

---

### Phase 5: Book备份 (Day 12-13)

**目标**: 实现Book级别备份和恢复

#### Server实现 (Day 12, 6小时)

```dart
class BookBackupService {
  Future<BookBackup> createBackup(int bookId) async {
    // 1. 导出Book的所有数据为SQL
    final book = await getBook(bookId);
    final events = await getEvents(bookId);
    final notes = await getNotes(bookId);
    final drawings = await getDrawings(bookId);

    // 2. 生成SQL文件
    final sql = _generateSQL(book, events, notes, drawings);
    final path = 'backups/book_${book.uuid}_${timestamp()}.sql';
    await File(path).writeAsString(sql);

    // 3. 记录备份信息
    return await _saveBackupRecord(bookId, path);
  }
}
```

#### Client UI (Day 13, 4小时)

```dart
// BookBackupScreen
class BookBackupScreen extends StatelessWidget {
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Book Backup')),
      body: Column(
        children: [
          // 创建备份按钮
          ElevatedButton(
            onPressed: _createBackup,
            child: Text('Create Backup'),
          ),
          // 备份列表
          Expanded(
            child: ListView.builder(
              itemBuilder: (context, index) {
                final backup = backups[index];
                return ListTile(
                  title: Text(backup.createdAt.toString()),
                  subtitle: Text('${backup.sizeMB} MB'),
                  trailing: IconButton(
                    icon: Icon(Icons.restore),
                    onPressed: () => _restore(backup),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

#### 验收标准

- [ ] 备份创建成功
- [ ] 备份文件完整性验证
- [ ] 恢复功能正常
- [ ] UI操作流畅

---

### Phase 6: 数据迁移 (Day 14)

**目标**: 将现有Sync数据迁移到Server-Store模式

#### 迁移脚本 (4小时)

```dart
class DataMigration {
  Future<void> migrate() async {
    print('开始迁移...');

    // 1. 备份现有数据
    await _createFullBackup();

    // 2. 上传所有Books
    final books = await _local.getAllBooks();
    for (final book in books) {
      await _server.createBook(book);
    }

    // 3. 上传所有Events
    for (final book in books) {
      final events = await _local.getAllEvents(book.id!);
      for (final event in events) {
        await _server.createEvent(event);
      }
    }

    // 4. 上传所有Notes（大数据）
    int total = 0, success = 0;
    for (final book in books) {
      final events = await _local.getAllEvents(book.id!);
      total += events.length;

      for (final event in events) {
        final note = await _local.getNote(event.id!);
        if (note != null) {
          try {
            await _server.saveNote(event.id!, note);
            success++;
            print('Progress: $success/$total');
          } catch (e) {
            print('Failed to upload note ${event.id}: $e');
          }
        }
      }
    }

    // 5. 验证数据完整性
    final valid = await _validateMigration();
    if (!valid) {
      throw Exception('Migration validation failed!');
    }

    // 6. 清理本地重量数据（保留Events元数据）
    await _cleanupLocalCache();

    print('迁移完成: $success/$total notes uploaded');
  }
}
```

#### 数据验证 (2小时)

```dart
Future<bool> _validateMigration() async {
  // 检查Books数量
  final localBooks = await _local.getAllBooks();
  final serverBooks = await _server.getAllBooks();
  if (localBooks.length != serverBooks.length) {
    print('ERROR: Book count mismatch');
    return false;
  }

  // 抽样检查Notes (10%)
  final sampleSize = (localBooks.length * 0.1).toInt();
  final samples = _random.sample(localBooks, sampleSize);

  for (final book in samples) {
    final localEvents = await _local.getAllEvents(book.id!);
    final serverEvents = await _server.getAllEvents(book.id!);

    if (localEvents.length != serverEvents.length) {
      print('ERROR: Event count mismatch for book ${book.id}');
      return false;
    }
  }

  print('✅ Validation passed');
  return true;
}
```

#### 回滚方案 (2小时)

```dart
class MigrationRollback {
  Future<void> rollback() async {
    print('开始回滚...');

    // 1. 恢复本地备份
    await _restoreLocalBackup();

    // 2. 回退数据库schema到v7
    await _downgradeSchema();

    // 3. 恢复旧SyncService
    // (保留在代码中，仅需取消注释)

    print('回滚完成');
  }
}
```

#### 验收标准

- [ ] 迁移脚本测试通过
- [ ] 数据验证通过（100%完整）
- [ ] 回滚脚本测试通过
- [ ] 迁移文档完整

---

### Phase 7: 测试与优化 (Day 15-17)

**目标**: 全面测试，性能优化

#### 集成测试 (Day 15, 8小时)

```dart
void main() {
  group('Server-Store Integration Tests', () {
    testWidgets('EventDetail loads note from server', (tester) async {
      // 1. 清空cache
      await cacheManager.clearAll();

      // 2. 打开EventDetail
      await tester.pumpWidget(EventDetailScreen(event: testEvent));

      // 3. 验证Loading显示
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 4. 等待加载完成
      await tester.pumpAndSettle();

      // 5. 验证note显示
      expect(find.text('Test Note Content'), findsOneWidget);

      // 6. 验证cache已保存
      final cached = await cacheManager.get(testEvent.id!);
      expect(cached, isNotNull);
    });

    testWidgets('Offline mode shows cached data', (tester) async {
      // 模拟网络失败
      mockNetworkFailure = true;

      // ... 验证离线提示
    });
  });
}
```

#### 性能测试 (Day 16, 6小时)

```dart
void main() {
  group('Performance Benchmarks', () {
    test('Cache hit latency < 50ms', () async {
      final stopwatch = Stopwatch()..start();

      await contentService.getNote(cachedEventId);

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('Preload 100 notes < 5s', () async {
      final stopwatch = Stopwatch()..start();

      await cacheManager.preload(eventIds100);

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });
}
```

#### 用户验收测试 (Day 17, 4小时)

**UAT Checklist**:
- [ ] 医生可以正常创建预约
- [ ] 打开EventDetail < 2s
- [ ] 手写笔记保存成功
- [ ] 离线时可查看缓存数据
- [ ] 恢复在线后自动同步
- [ ] Book备份和恢复正常
- [ ] 无明显性能下降

---

## 🎯 关键成功因素

### 技术指标

| 指标 | 目标 | 验证方式 |
|------|------|----------|
| 迁移成功率 | 100% | 数据对比 |
| 数据完整性 | 0丢失 | 校验和对比 |
| 性能回退 | < 10% | 基准测试 |
| Cache命中率 | > 80% | 生产监控 |

### 风险管理

| 风险 | 缓解措施 | 负责人 |
|------|---------|--------|
| 数据丢失 | 全量备份 + 验证 | Dev Team |
| 性能下降 | 性能测试 + 优化 | Dev Team |
| 用户体验差 | UAT + 快速回退 | Product |
| 迁移失败 | 回滚方案 + 演练 | Dev Team |

---

## ✅ 最终检查清单

### Phase 1完成
- [ ] Server schema更新
- [ ] Client schema升级到v8
- [ ] 现有功能继续工作

### Phase 2完成
- [ ] Notes API上线
- [ ] Drawings API上线
- [ ] Backup API上线
- [ ] API文档完整

### Phase 3完成
- [ ] ContentService实现
- [ ] CacheManager实现
- [ ] 数据库服务重构
- [ ] 单元测试通过

### Phase 4完成
- [ ] EventDetail改造
- [ ] Schedule改造
- [ ] 离线UX实现
- [ ] 集成测试通过

### Phase 5完成
- [ ] Server备份服务
- [ ] Client备份UI
- [ ] 恢复流程测试

### Phase 6完成
- [ ] 迁移脚本执行
- [ ] 数据验证通过
- [ ] 回滚方案测试

### Phase 7完成
- [ ] 所有测试通过
- [ ] 性能达标
- [ ] UAT通过
- [ ] 文档更新

---

## 📞 支持和升级

### 遇到问题？

1. **迁移失败**: 执行回滚方案（Phase 6-03）
2. **性能问题**: 查看Phase 7-02性能优化
3. **数据不一致**: 运行验证脚本（Phase 6-02）

### 后续优化

- [ ] 增量备份（降低备份时间）
- [ ] 实时推送（减少轮询）
- [ ] 数据压缩（减少流量）
- [ ] CDN加速（提升全球访问速度）

---

**记住**: "Migration is not a one-time event, it's a process. Test, validate, and be ready to rollback."
