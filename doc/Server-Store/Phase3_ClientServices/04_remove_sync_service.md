# Phase 3-04: Remove Sync Service

> **优先级**: P3 - Phase 3
> **状态**: ⏸️ 待实施
> **估计时间**: 2小时
> **依赖**: Phase 3-01, 3-02, 3-03完成

---

## 📋 任务描述

### 目标

清理旧的Sync相关代码：
1. 删除SyncService
2. 删除sync相关models
3. 清理sync相关UI
4. 更新依赖

**警告**: 这是Phase 3的最后一步，确保新架构完全工作后再执行

---

## 🧠 Linus式根因分析

### 为什么不早点删除？

**Pragmatism原则**:
```
Phase 1-2: 新旧并存 → 可快速回退
Phase 3: 逐步切换 → 验证新架构
Phase 3-04: 删除旧代码 → 不再需要
         ^^^^^^^^^^^^^^^^^^^^^^^^^^
         只在确认新架构稳定后清理
```

**Good Taste**:
- ✅ 保守策略，可回退
- ✅ 渐进式演进，不破坏现有功能
- ✅ 等价于Linux的"删除废弃代码"流程

---

## ✅ 实施方案

### 需要删除的文件

**Client侧**:
```
lib/services/
  ├── sync_service.dart              ❌ 删除
  └── sync_background_service.dart   ❌ 删除（如果存在）

lib/models/
  └── sync/
      ├── sync_change.dart           ❌ 删除
      └── sync_request.dart          ❌ 删除
```

**Server侧** (可选，Phase 6再删除):
```
server/lib/routes/
  └── sync_routes.dart               ⏸️ 保留（标记deprecated）

server/lib/services/
  └── sync_service.dart              ⏸️ 保留（标记deprecated）
```

### 需要修改的代码

**ApiClient**:
```dart
// 删除sync相关方法
@deprecated
Future<SyncResponse> pullChanges(...) {...}  ❌ 删除

@deprecated
Future<SyncResponse> pushChanges(...) {...}  ❌ 删除
```

**Providers** (如果有):
```dart
// SyncProvider.dart
❌ 整个文件删除
```

**UI层**:
```dart
// 删除"同步中"的loading indicator
// 删除"最后同步时间"显示
// 删除"手动同步"按钮
```

### 清理步骤

1. **搜索所有引用**:
```bash
grep -r "SyncService" lib/
grep -r "sync_service" lib/
grep -r "pullChanges" lib/
grep -r "pushChanges" lib/
```

2. **逐个删除或重构**:
   - 如果代码仍在使用 → 先改用ContentService
   - 如果已废弃 → 直接删除

3. **更新import**:
   - 删除`import 'services/sync_service.dart'`
   - 删除`import 'models/sync/sync_change.dart'`

4. **运行测试**:
```bash
flutter test
flutter analyze
```

---

## 🧪 测试计划

### 验证清理完整性

1. **编译测试**: `flutter build` 无错误
2. **静态分析**: `flutter analyze` 无警告
3. **功能测试**: 所有核心功能正常
4. **搜索验证**: 无残留sync相关代码

### 回归测试

- EventDetail打开正常
- Note保存/加载正常
- Drawing保存/加载正常
- Book备份/恢复正常

---

## 📦 向后兼容性

**无需兼容**:
- 这是清理步骤，不需要向后兼容
- 但需要确保Phase 3-01/02/03已完成并稳定

**回滚策略**:
- 如果出现问题，可从git恢复旧代码
- 建议在清理前打tag: `git tag pre-sync-cleanup`

---

## ✅ 验收标准

- [ ] 所有sync相关文件已删除
- [ ] 所有sync相关代码已删除或重构
- [ ] 编译无错误
- [ ] 静态分析无警告
- [ ] 所有功能测试通过
- [ ] 代码库减少至少500行

---

## 🔗 相关任务

- **依赖**: [Phase 3-01](01_content_service.md), [Phase 3-02](02_cache_manager.md), [Phase 3-03](03_refactor_database.md)
- **下一步**: [Phase 4-01: Screen重构](../Phase4_Screens/01_event_detail_screen.md)

---

**Linus说**: "Dead code is worse than no code. Delete it. Git remembers it if you need it back."
