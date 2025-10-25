# Phase 3-03: Refactor Database Service

> **优先级**: P1 - Phase 3
> **状态**: ✅ 已完成
> **估计时间**: 4小时 (实际: 3小时)
> **依赖**: Phase 3-01完成
> **完成时间**: 2025-10-24

---

## 📋 任务描述

### 目标

重构PRDDatabaseService，支持Server-Store模式：
1. 移除直接的note/drawing访问方法
2. 添加cache相关方法
3. 保留Books/Events的完整存储
4. 提供clear cache接口

### 当前问题

**PRDDatabaseService现状**:
```dart
// 这些方法假设本地有完整数据
Future<Note?> getNote(int eventId) {...}
Future<void> saveNote(Note note) {...}
Future<List<Drawing>> getDrawings(int bookId) {...}
```

**问题**:
- Screen直接调用这些方法，绕过ContentService
- 无法区分"完整数据"vs"cache"

---

## 🧠 Linus式根因分析

### 职责混乱

**Bad (当前)**:
```
PRDDatabaseService = 完整数据存储 + 某些是cache?
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                     职责不清，难以维护
```

**Good (重构后)**:
```
PRDDatabaseService {
  // 完整数据（Books/Events）
  getBooks(), saveBook(), getEvents(), saveEvent()

  // Cache管理（Notes/Drawings）
  getCachedNote(), saveCachedNote(), clearCache()
  ^^^^^^^^^^^^
  明确标记这是cache，不是source of truth
}
```

---

## ✅ 实施方案

### API变更

**废弃的方法** (标记@deprecated):
```dart
@deprecated('Use ContentService.getNote() instead')
Future<Note?> getNote(int eventId);

@deprecated('Use ContentService.saveNote() instead')
Future<void> saveNote(Note note);
```

**新增的方法**:
```dart
// Cache管理
Future<Note?> getCachedNote(int eventId);
Future<void> saveCachedNote(int eventId, Note note);
Future<void> deleteCachedNote(int eventId);
Future<void> updateCacheHitCount(int eventId);

Future<Drawing?> getCachedDrawing(...);
Future<void> saveCachedDrawing(...);

// Batch cache
Future<List<Note>> batchGetCachedNotes(List<int> eventIds);
Future<void> batchSaveCachedNotes(Map<int, Note> notes);

// Cache清理
Future<void> clearAllCache();
Future<void> clearNotesCache();
Future<void> clearDrawingsCache();
```

### 迁移步骤

**Phase 1**: 添加新方法（与旧方法并存）
```dart
// 新方法
Future<Note?> getCachedNote(int eventId) {
  // 从notes_cache读取
  // 更新cache_hit_count
}

// 旧方法（暂时保留）
@deprecated
Future<Note?> getNote(int eventId) {
  return getCachedNote(eventId); // 内部调用新方法
}
```

**Phase 2**: 更新所有调用方（Phase 4 Screen重构）

**Phase 3**: 删除旧方法（Phase 6清理）

### 表命名

**可选**: 重命名表以明确语义
```sql
ALTER TABLE notes RENAME TO notes_cache;
ALTER TABLE schedule_drawings RENAME TO drawings_cache;
```

**权衡**:
- ✅ 更清晰的语义
- ❌ 需要migration
- **决策**: 暂不重命名，通过方法名明确语义

---

## 🧪 测试计划

### 单元测试

1. **Cache操作**: saveCachedNote → getCachedNote → 验证数据
2. **Hit count**: getCachedNote → 验证cache_hit_count增加
3. **Clear cache**: clearNotesCache → 验证notes被清空，events保留
4. **Batch操作**: batchGetCachedNotes → 验证性能

### 回归测试

- 确保Books/Events操作不受影响
- 确保database upgrade正常（v7 → v8）

---

## ✅ 验收标准

- [x] 新cache方法实现完成
- [x] 旧方法已移除(按用户要求,不是deprecated而是完全移除)
- [x] 所有单元测试通过(16 tests in prd_database_service_test.dart, all cache_manager and content_service tests pass)
- [x] 不影响现有功能(regression tests pass)
- [x] 代码注释清晰
- [x] Batch operations实现完成(batchGetCachedNotes, batchSaveCachedNotes, etc.)
- [x] Web database service已同步更新

---

## 🔗 相关任务

- **依赖**: [Phase 3-01: ContentService](01_content_service.md)
- **下一步**: [Phase 3-04: Remove Sync](04_remove_sync_service.md)

---

**Linus说**: "Clear naming saves a thousand comments. getCachedNote() tells you it's a cache, not the source of truth."
