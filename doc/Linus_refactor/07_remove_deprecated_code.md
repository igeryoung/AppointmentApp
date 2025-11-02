# Phase 7: 删除 Deprecated 代码

## Linus 的视角

> "Dead code is not just useless. It's actively harmful."

Deprecated 代码是技术债务的明确标志：
- **你不确定是否还需要** - 所以标记 deprecated 而不敢删
- **你不确定谁在用** - 所以不敢删
- **你不敢破坏向后兼容** - 所以一直留着

**但结果是**：
- 代码库越来越大
- 新人不知道该用哪个 API
- 维护成本持续增加
- **债务永远还不清**

**正确的做法**："要么用，要么删。Deprecated 只应该是删除前的过渡状态（最多 2 周）。"

---

## 当前问题分析

### 问题 1: 174 行 Deprecated API 仍在运行

**位置**：`server/lib/routes/book_backup_routes.dart`

**第 310-484 行（174 行）**：
```dart
/// Upload a complete book backup (JSON format - DEPRECATED)
/// Use the event-based incremental backup API instead
router.post('/backup', ...);  // 326-378 行

/// List all backups for a device (DEPRECATED)
router.get('/backups', ...);  // 380-425 行

/// Download backup data directly - DEPRECATED
router.get('/backup/:backupId', ...);  // 427-482 行
```

**问题**：
- 标记为 deprecated 但仍然实现和维护
- 占用 174 行代码
- 不知道是否还有客户端在用
- 新 API 已经实现（event-based），但旧 API 不敢删

---

### 问题 2: ContentService 的混乱状态

**位置**：`lib/services/content_service.dart`

**第 9-25 行**：
```dart
/// **DEPRECATED**: This class is being replaced by focused services:
/// - NoteContentService
/// - DrawingContentService
/// - SyncCoordinator
@Deprecated('Use NoteContentService, DrawingContentService...')
class ContentService {
  // 但实际上在 70+ 个地方使用！
}
```

**使用情况**：
- `schedule_screen.dart`: 40+ 次调用
- `event_detail_screen.dart`: 30+ 次调用
- 其他 Service: 10+ 次调用

**问题**：
- 标记 deprecated，但到处在用
- 新 Service（NoteContentService 等）已实现
- 但迁移未完成
- **既不能用旧的（deprecated），也没完全切换到新的**

---

### 问题 3: 备份文件混乱

**位置**：根目录

**已删除的文档文件（git status 显示）**：
```
D BOOK_BACKUP_GUIDE.md
D IOS_DEVICE_SETUP.md
D PHASE2_REFACTORING_COMPLETE.md
D Phase6_PreCleanup_Checklist.md
D Phase6_Summary.md
D QUICK_START.md
D REFACTORING_SUMMARY.md
D SETUP_COMPLETE.md
D SYNC_GUIDE.md
D SYNC_IMPLEMENTATION_SUMMARY.md
D ScheduleScreenRafactorPlan.md
D TESTING_GUIDE.md
```

**屏幕备份文件（未删除）**：
```
lib/screens/schedule_screen.dart.backup
lib/screens/schedule_screen.dart.bak2
lib/screens/schedule_screen.dart.bak3
```

**问题**：
- 文档文件已删除（好）
- 但 .backup 文件还在（需要清理）
- 说明重构还在进行中

---

## 重构目标

### 目标 1: 删除服务器端 Deprecated API
- 分析客户端使用情况
- 如果无人使用 → 删除
- 如果有人使用 → 强制迁移到新 API

### 目标 2: 解决 ContentService 状态
- **选项 A**: 完成迁移，删除 ContentService
- **选项 B**: 取消 deprecated 标记，正式支持
- **推荐**: 选项 A（已有替代方案）

### 目标 3: 清理备份文件
- 删除所有 .backup / .bak* 文件
- 提交干净的重构结果

### 目标 4: 建立 Deprecated 管理流程
- 任何标记 deprecated 的代码必须有删除日期
- 2 周内完成迁移或取消标记

---

## 重构方法

### 步骤 1: 分析服务器 API 使用情况（第 1 天上午）

#### 1.1 检查客户端代码
- 搜索 `/backup` API 调用
- 搜索 `/backups` API 调用
- 确认是否还在使用

#### 1.2 检查服务器日志（如果有）
- 统计最近 30 天的 API 调用
- 确认是否有真实流量

#### 1.3 做出决定

**场景 A：无人使用**
- 直接删除 310-484 行
- 删除相关测试
- 更新 API 文档

**场景 B：有少量使用**
- 通知用户迁移到新 API
- 设置截止日期（如 2 周后）
- 发布新版本客户端（强制更新）
- 截止后删除旧 API

**场景 C：大量使用**
- 重新评估是否应该 deprecated
- 可能需要取消 deprecated 标记
- 或者提供自动迁移工具

---

### 步骤 2: 删除服务器 Deprecated API（第 1 天下午）

#### 2.1 删除路由处理函数（假设场景 A）
```dart
// 删除这些
router.post('/backup', _handleLegacyBackup);  // 326-378 行
router.get('/backups', _handleListBackups);   // 380-425 行
router.get('/backup/:backupId', _handleDownloadBackup);  // 427-482 行
```

#### 2.2 删除相关辅助方法
- 查找只被 deprecated API 使用的方法
- 一并删除

#### 2.3 更新 API 文档
- 从文档中删除旧 API
- 强调只支持新的 event-based API

#### 2.4 更新测试
- 删除旧 API 的测试用例
- 确保新 API 测试覆盖充分

---

### 步骤 3: 迁移 ContentService 使用（第 2 天）

#### 3.1 制定迁移映射
```
ContentService.saveNote() → NoteContentService.save()
ContentService.saveDrawing() → DrawingContentService.save()
ContentService.syncAll() → SyncCoordinator.syncAll()
```

#### 3.2 更新 schedule_screen.dart（40+ 处）
- 替换 `_contentService.saveDrawing()` 为 `_drawingService.save()`
- 使用 Phase 4 的 DrawingController（如果已实现）
- 或者直接调用 DatabaseService

#### 3.3 更新 event_detail_screen.dart（30+ 处）
- 替换 `_contentService.saveNote()` 为 `_noteService.save()`
- 或者通过 Repository/DatabaseService

#### 3.4 更新其他使用点
- 搜索所有 `ContentService` 引用
- 逐一替换为新 Service
- 确保功能不变

#### 3.5 删除 ContentService
- 删除 `lib/services/content_service.dart`
- 删除相关测试
- 从 service_locator 删除注册

---

### 步骤 4: 清理备份文件（第 2 天下午）

#### 4.1 删除代码备份文件
```bash
rm lib/screens/schedule_screen.dart.backup
rm lib/screens/schedule_screen.dart.bak2
rm lib/screens/schedule_screen.dart.bak3
```

#### 4.2 提交删除的文档文件
```bash
git add -u  # 添加所有删除
git commit -m "docs: remove obsolete documentation files"
```

#### 4.3 检查其他备份文件
- 搜索项目中的 *.backup, *.bak, *.old 文件
- 确认都不需要后删除

---

### 步骤 5: 建立 Deprecated 管理流程（第 2 天下午）

#### 5.1 制定规则
```dart
// 正确的 deprecated 标记方式
/// DEPRECATED: Use [NewClass] instead
/// Will be removed after: 2025-02-15
@Deprecated('Use NewClass.newMethod(). Removal date: 2025-02-15')
void oldMethod() {
  // ...
}
```

#### 5.2 添加 Lint 规则
- 检查所有 @Deprecated 标记必须有删除日期
- 检查删除日期不超过 2 周

#### 5.3 文档化流程
- README 中添加 "Deprecation Policy"
- 说明如何标记 deprecated
- 说明如何跟踪和删除

---

## 测试要求

### 服务器端测试

#### API 删除验证
- **测试场景**：
  - 调用旧 API 返回 404
  - 新 API 功能正常
  - 数据迁移完整（如果需要）

### 客户端测试

#### ContentService 迁移
- **测试场景**：
  - 保存 Note 功能正常
  - 保存 Drawing 功能正常
  - 同步功能正常
  - 所有原有功能不变

### 回归测试

#### 完整功能测试
- **测试清单**：
  - 创建和编辑事件
  - 手写笔记
  - 备份和恢复
  - 服务器同步
- **验证**：所有功能正常，无遗漏

---

## 风险与缓解

### 风险 1: 误删仍在使用的 API（高风险）
**症状**：删除后发现有用户还在用旧版本客户端
**影响**：旧客户端功能失效
**缓解**：
- 详细检查使用情况
- 服务器日志分析
- 发布前通知用户
- 保留回滚能力

### 风险 2: ContentService 迁移遗漏（中风险）
**症状**：某些地方还在用 ContentService
**影响**：编译失败或运行时错误
**缓解**：
- 全局搜索确认所有使用点
- 逐个模块迁移和测试
- 编译器会捕获大部分遗漏

### 风险 3: 功能行为改变（中风险）
**症状**：新 Service 行为与旧 ContentService 不完全一致
**影响**：用户体验变化
**缓解**：
- 详细的行为对比测试
- Before/After 测试用例
- 充分的手工测试

---

## 成功标准

### 代码清理标准
- ✅ 删除 174 行服务器端 deprecated API
- ✅ 删除 ContentService（约 500 行）
- ✅ 删除所有 .backup / .bak* 文件
- ✅ 无遗留 @Deprecated 标记（或都有删除日期）

### 功能完整性标准
- ✅ 所有原有功能正常工作
- ✅ 新 API 替代旧 API
- ✅ 测试覆盖充分

### 流程标准
- ✅ 建立 Deprecated Policy
- ✅ Lint 规则强制执行
- ✅ 文档更新

---

## 预期收益

### 即时收益
- **代码减少**: -700+ 行（174 API + 500 ContentService + 备份文件）
- **维护负担**: 不再维护 deprecated 代码
- **清晰度**: 只有一个 API 版本

### 长期收益
- **技术债务**: 债务被清除而非累积
- **新人友好**: 不会困惑"该用哪个 API"
- **测试简化**: 只测试活跃代码

---

## 时间估算

- **步骤 1（分析）**: 2 小时
- **步骤 2（删除 API）**: 3 小时
- **步骤 3（迁移 ContentService）**: 6 小时
- **步骤 4（清理文件）**: 1 小时
- **步骤 5（流程）**: 2 小时

**总计**: 14 小时（约 2 个工作日）

---

## 下一步

完成 Phase 7 后，进入 **Phase 8: 修复竞态条件**。

Phase 7 清理了历史债务：
- Deprecated 代码删除
- 只保留活跃和维护的代码
- 为最后的清理和验证做准备

**核心教训**: "Deprecated 代码是债务。每天不删，利息就在增长。要么用，要么删，不要让它永远处于'将要删除'的状态。"
