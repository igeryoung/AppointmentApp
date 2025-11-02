# Phase 8: 修复竞态条件

## Linus 的视角

> "Concurrency bugs are the worst kind of bugs. They're intermittent, hard to reproduce, and even harder to fix."

竞态条件（Race Condition）的问题：
- **难以重现** - 只在特定时序出现
- **难以调试** - 日志看起来都正常
- **后果严重** - 数据丢失、状态不一致
- **隐藏很深** - 可能潜伏几个月才暴露

**Debounce 不是修复，是掩盖症状**。真正的修复需要：
1. 明确的数据所有权
2. 适当的锁机制
3. 单一的修改路径

---

## 当前问题分析

### 问题：6 个保存触发点，Debounce "修复"

**位置**：schedule_screen.dart

#### 6 个保存触发点
1. **第 333 行**：手势结束时
2. **第 662 行**：视图切换时
3. **第 1282 行**：页面切换时
4. **第 1299 行**：绘图模式切换时
5. **第 1326 行**：应用进入后台
6. **第 1389 行**：dispose 时

#### "修复"方案（第 524-530 行）
```dart
/// RACE CONDITION FIX: Debounce saves by 500ms
void _scheduleSaveDrawing() {
  _saveDebounceTimer?.cancel();
  _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
    _saveDrawing();
  });
}
```

### 为什么 Debounce 不是真正的修复？

#### 场景 1：快速连续操作
```
时间 0ms: 用户手写第 1 笔
时间 10ms: 触发保存 #1（debounce，等待 500ms）
时间 50ms: 用户手写第 2 笔
时间 60ms: 触发保存 #2（取消 #1，等待 500ms）
...
时间 400ms: 用户手写第 10 笔
时间 410ms: 触发保存 #10（取消 #9，等待 500ms）
时间 900ms: 用户切换视图
时间 905ms: 触发保存 #11（取消 #10，等待 500ms）

结果：保存 #10 的定时器被取消，第 10 笔可能丢失
```

#### 场景 2：异步操作交叠
```
时间 0ms: 保存 #1 开始（版本 = 5）
时间 50ms: 用户手写，版本变成 6
时间 100ms: 触发保存 #2（版本 = 6）
时间 150ms: 保存 #1 检查版本（看到版本 6，但自己要保存版本 5）
时间 200ms: 保存 #1 写入数据库（覆盖版本 6！）
时间 250ms: 保存 #2 开始（版本 = 6）
时间 300ms: 保存 #2 检查版本（数据库版本已是 5）
时间 350ms: 保存 #2 写入失败（版本冲突）或成功（再次覆盖）

结果：数据不一致
```

#### 问题根源
1. **多个保存入口** - 6 个地方都能触发保存
2. **版本检查太晚** - 在异步操作之后才检查
3. **无锁机制** - `_isSaving` flag 不够（异步中间状态）
4. **数据所有权不清** - 不知道"当前版本"在哪

---

## 重构目标（基于 Phase 4）

**注意**：Phase 4 已经引入了 DrawingController 和单一数据源。Phase 8 在此基础上完善并发控制。

### 目标 1: 单一保存路径
- 所有触发点调用同一个保存方法
- 保存方法内部处理防重入和版本控制

### 目标 2: 适当的锁机制
- 使用 Mutex 或 Semaphore
- 确保同时只有一个保存操作

### 目标 3: 乐观锁 + 正确的版本检查
- 在事务开始前检查版本
- 在同一个事务中完成检查和写入
- 冲突时有明确的解决策略

### 目标 4: 测试并发场景
- 模拟快速手写
- 模拟同时保存
- 确认无数据丢失

---

## 重构方法

### 步骤 1: 完善 DrawingController 的并发控制（第 1 天）

**假设**：Phase 4 已实现 DrawingController，现在增强并发安全。

#### 1.1 引入 Mutex 库
```yaml
dependencies:
  synchronized: ^3.1.0  # Mutex 实现
```

#### 1.2 增强 DrawingController

**添加字段**：
```dart
class DrawingController {
  final Lock _saveLock = Lock();  // Mutex 锁
  int _pendingSaveCount = 0;      // 等待保存的请求数
}
```

**改进保存方法**：
```dart
Future<void> save({bool force = false}) async {
  // 使用 synchronized 包装，确保同时只有一个保存
  return await _saveLock.synchronized(() async {
    if (!hasUnsavedChanges && !force) return;

    try {
      // 乐观锁：先读取当前数据库版本
      final dbDrawing = await _repository.getById(_currentDrawing!.id);
      if (dbDrawing != null && dbDrawing.version != _savedVersion) {
        // 版本冲突，需要处理
        throw VersionConflictException(
          expected: _savedVersion,
          actual: dbDrawing.version,
        );
      }

      // 增加版本号
      _currentDrawing!.version++;

      // 保存到数据库（在锁内完成）
      await _repository.save(_currentDrawing!);

      // 更新已保存版本
      _savedVersion = _currentDrawing!.version;

      notifyListeners();
    } catch (e) {
      if (e is VersionConflictException) {
        await _handleConflict(e);
      } else {
        rethrow;
      }
    }
  });
}
```

**关键点**：
- `_saveLock.synchronized()` 确保同时只有一个保存操作
- 版本检查在锁内完成
- 整个"检查-修改-保存"是原子的

---

### 步骤 2: 实现版本冲突处理（第 1 天下午）

#### 2.1 定义冲突解决策略

**策略 1：Last-Write-Wins（简单）**
```dart
Future<void> _handleConflict(VersionConflictException e) async {
  // 重新加载最新版本
  await load();

  // 警告：上次修改被覆盖
  debugPrint('Warning: Drawing conflict, reloaded from database');

  // 用户的修改仍在内存中（如果 Controller 保持了）
  // 可以选择重新应用或丢弃
}
```

**策略 2：Merge（复杂但正确）**
```dart
Future<void> _handleConflict(VersionConflictException e) async {
  // 加载数据库中的最新版本
  final dbDrawing = await _repository.getById(_currentDrawing!.id);

  // 比较笔画列表
  final myStrokes = _currentDrawing!.strokes;
  final dbStrokes = dbDrawing!.strokes;

  // 合并策略：保留双方新增的笔画
  final mergedStrokes = _mergeStrokes(myStrokes, dbStrokes);

  // 更新到最新版本
  _currentDrawing = dbDrawing.copyWith(
    strokes: mergedStrokes,
    version: dbDrawing.version + 1,
  );

  // 重新保存合并结果
  await _repository.save(_currentDrawing!);
  _savedVersion = _currentDrawing!.version;

  notifyListeners();
}
```

**策略 3：Prompt User（最安全）**
```dart
Future<void> _handleConflict(VersionConflictException e) async {
  // 加载数据库版本
  final dbDrawing = await _repository.getById(_currentDrawing!.id);

  // 显示对话框让用户选择
  final choice = await showConflictDialog(
    myVersion: _currentDrawing,
    dbVersion: dbDrawing,
  );

  if (choice == ConflictChoice.keepMine) {
    // 强制覆盖数据库版本
    await _repository.save(_currentDrawing!, forceOverwrite: true);
  } else {
    // 使用数据库版本
    _currentDrawing = dbDrawing;
    _savedVersion = dbDrawing.version;
  }

  notifyListeners();
}
```

**推荐**：Phase 8 实现策略 1（简单），在用户反馈后考虑策略 2/3。

---

### 步骤 3: 简化保存触发点（第 2 天上午）

#### 3.1 统一所有触发点

**原则**：所有地方都调用 `controller.save()`，参数控制行为。

**触发点 1：手写过程中（debounce）**
```dart
void _onStrokeAdded(Stroke stroke) {
  controller.addStroke(stroke);
  // Controller 内部自动 debounce 保存
}
```

**触发点 2-6：关键时刻（立即保存）**
```dart
// 视图切换
void _onViewModeChanged() {
  await controller.save(force: true);  // 立即保存
  // 然后切换视图
}

// 应用进入后台
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    await controller.save(force: true);
  }
}

// dispose
@override
void dispose() {
  await controller.save(force: true);
  controller.dispose();
  super.dispose();
}
```

**简化后**：
- 1 个自动保存路径（debounce）
- 多个手动保存调用（force: true）
- 所有都通过 Controller.save()
- Controller 内部处理并发

---

### 步骤 4: 数据库事务支持（第 2 天下午）

#### 4.1 确保原子操作

**问题**：当前的"检查版本 → 保存"不是原子的。

**解决**：使用数据库事务。

**在 DatabaseService 中**：
```dart
Future<void> saveDrawingWithVersionCheck(ScheduleDrawing drawing) async {
  final db = await database;

  await db.transaction((txn) async {
    // 在事务内检查版本
    final current = await txn.query(
      'schedule_drawings',
      where: 'id = ?',
      whereArgs: [drawing.id],
    );

    if (current.isNotEmpty) {
      final currentVersion = current.first['version'] as int;
      if (currentVersion != drawing.version - 1) {
        throw VersionConflictException(
          expected: drawing.version - 1,
          actual: currentVersion,
        );
      }
    }

    // 在同一个事务内保存
    await txn.update(
      'schedule_drawings',
      drawing.toMap(),
      where: 'id = ?',
      whereArgs: [drawing.id],
    );
  });
}
```

**关键**：整个"检查-保存"在一个事务中，数据库层面保证原子性。

---

### 步骤 5: 添加并发测试（第 3 天）

#### 5.1 单元测试：并发保存

**测试场景 1：快速连续保存**
```dart
test('concurrent saves are serialized', () async {
  final controller = DrawingController(...);

  // 启动 10 个并发保存
  final futures = List.generate(10, (i) {
    controller.addStroke(Stroke(...));  // 修改数据
    return controller.save();            // 触发保存
  });

  // 等待所有保存完成
  await Future.wait(futures);

  // 验证：所有笔画都保存了
  final saved = await db.getDrawing(...);
  expect(saved.strokes.length, 10);

  // 验证：版本号正确递增
  expect(saved.version, 10);
});
```

**测试场景 2：冲突处理**
```dart
test('handles version conflict correctly', () async {
  final controller = DrawingController(...);

  // 模拟另一个设备修改了数据库
  await db.updateDrawingDirectly(...);  // 版本变成 2

  // 当前 controller 认为版本还是 1
  controller.addStroke(Stroke(...));

  // 保存时应该检测到冲突
  await controller.save();

  // 验证：冲突被处理（根据策略）
  // ...
});
```

#### 5.2 集成测试：真实用户场景

**场景：快速手写 + 视图切换**
```dart
testWidgets('fast drawing + view switch', (tester) async {
  await tester.pumpWidget(MyApp());

  // 快速手写 5 笔
  for (int i = 0; i < 5; i++) {
    await simulateStroke(tester);
    await tester.pump(Duration(milliseconds: 10));  // 快速
  }

  // 立即切换视图（不等 debounce）
  await tester.tap(find.byIcon(Icons.view_week));
  await tester.pumpAndSettle();

  // 验证：5 笔都保存了
  final drawing = await db.getDrawing(...);
  expect(drawing.strokes.length, 5);
});
```

#### 5.3 压力测试：极限场景

**场景：连续 100 笔手写**
```dart
test('stress test: 100 strokes', () async {
  final controller = DrawingController(...);

  final start = DateTime.now();

  for (int i = 0; i < 100; i++) {
    controller.addStroke(Stroke(...));
    if (i % 10 == 0) {
      await controller.save();  // 每 10 笔保存一次
    }
  }

  await controller.save(force: true);  // 最终保存

  final duration = DateTime.now().difference(start);

  // 验证：所有笔画都在
  final saved = await db.getDrawing(...);
  expect(saved.strokes.length, 100);

  // 验证：性能可接受（<2 秒）
  expect(duration.inSeconds, lessThan(2));
});
```

---

## 测试要求总结

### 并发测试（关键）
- ✅ 10 个并发保存请求
- ✅ 快速手写 + 立即切换视图
- ✅ 模拟版本冲突
- ✅ 压力测试（100 笔）

### 功能测试
- ✅ 正常手写和保存
- ✅ 自动保存触发（debounce）
- ✅ 立即保存触发（force）
- ✅ 应用后台/恢复

### 数据完整性测试
- ✅ 无笔画丢失
- ✅ 版本号正确
- ✅ 冲突正确处理

---

## 风险与缓解

### 风险 1: 锁导致性能下降（低风险）
**症状**：保存变慢，UI 卡顿
**影响**：用户体验下降
**缓解**：
- 锁的粒度尽量小
- 异步操作在锁外完成
- 性能测试验证

### 风险 2: 死锁（中风险）
**症状**：应用挂起，无响应
**影响**：用户必须重启应用
**缓解**：
- 使用超时机制
- 简单的锁结构（不嵌套）
- 充分测试

### 风险 3: 冲突处理不当导致数据丢失（高风险）
**症状**：用户手写内容消失
**影响**：用户信任度降低
**缓解**：
- 保守的冲突策略（提示用户）
- 记录所有冲突到日志
- 提供数据恢复机制

---

## 成功标准

### 功能标准
- ✅ 无竞态条件（并发测试通过）
- ✅ 无数据丢失（压力测试通过）
- ✅ 版本冲突正确处理

### 性能标准
- ✅ 保存性能不降低（<50ms per save）
- ✅ UI 无卡顿（锁不阻塞 UI 线程）
- ✅ 100 笔手写 <2 秒

### 代码质量标准
- ✅ 单一保存路径
- ✅ 明确的并发控制
- ✅ 清晰的错误处理

---

## 预期收益

### 数据安全
- **消除数据丢失风险**
- **版本冲突明确处理**
- **可预测的并发行为**

### 代码质量
- **6 个触发点 → 1 个保存方法**
- **清晰的并发控制（Mutex）**
- **可测试的并发逻辑**

### 用户信任
- **手写内容不会丢失**
- **多设备同步更可靠**
- **行为一致和可预测**

---

## 时间估算

- **步骤 1（增强 Controller）**: 4 小时
- **步骤 2（冲突处理）**: 4 小时
- **步骤 3（简化触发点）**: 3 小时
- **步骤 4（事务支持）**: 3 小时
- **步骤 5（并发测试）**: 6 小时

**总计**: 20 小时（2.5 个工作日）

---

## 下一步

完成 Phase 8 后，进入 **Phase 9: 清理和验证**。

Phase 8 是数据安全的关键：
- 真正修复竞态条件
- 保护用户数据
- 为最终发布做准备

**核心教训**: "Debounce 不是并发控制，只是延迟。真正的修复需要锁、事务和明确的数据所有权。并发 bug 是最难调试的，必须通过设计而非运气来避免。"
