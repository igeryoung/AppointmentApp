# Phase 4: 修复数据所有权

## Linus 的视角

> "Show me your flowcharts and conceal your tables, and I shall continue to be mystified. Show me your tables, and I won't usually need your flowcharts; they'll be obvious."

数据所有权混乱是系统性问题的症状：
- **不知道谁拥有数据** = 不知道谁负责修改
- **多个副本** = 不知道哪个是"真相"
- **同步问题** = 副本之间不一致
- **性能问题** = 重复拷贝数据

**核心原则：每份数据应该有且仅有一个主人（Single Source of Truth）**

---

## 当前问题分析

### 问题概览：手写笔画数据的 5 个副本

**在 schedule_screen.dart 中，同一份笔画数据在 5 个地方存在：**

#### 副本 1: HandwritingCanvas 的内部状态
- 位置：`HandwritingCanvasState._strokes`
- 作用：Widget 内部渲染用
- 修改：用户手写时实时添加

#### 副本 2: ScheduleScreen 的备份存储
- 位置：`schedule_screen.dart:73 List<Stroke> _lastKnownStrokes`
- 作用：用于比较是否变化
- 修改：每次保存时更新

#### 副本 3: 当前绘图对象
- 位置：`schedule_screen.dart:67 ScheduleDrawing? _currentDrawing`
- 作用：准备保存到数据库的对象
- 修改：从 Canvas 拷贝后更新

#### 副本 4: 数据库缓存
- 位置：`CacheManager.getCachedDrawing()`
- 作用：内存缓存，减少数据库查询
- 修改：保存到数据库后更新缓存

#### 副本 5: 数据库持久化
- 位置：SQLite `schedule_drawings` 表
- 作用：持久存储
- 修改：调用 save 时写入

### 数据流混乱图

```
用户手写
    ↓
副本1: HandwritingCanvas._strokes (实时更新)
    ↓
副本2: _lastKnownStrokes (周期性复制)
    ↓
副本3: _currentDrawing (保存时复制)
    ↓
副本4: CacheManager (保存后更新)
    ↓
副本5: Database (持久化)

问题：
- 任何环节复制失败 = 数据不一致
- 不知道哪个是"最新"的
- 竞态条件：多个地方同时修改
```

### 具体问题

#### 问题 1: 不清楚谁是主人
**代码证据**（schedule_screen.dart:524-580）：
- `_scheduleSaveDrawing()` 从 Canvas 获取笔画
- 比较 `_lastKnownStrokes`
- 更新 `_currentDrawing`
- 保存到数据库
- 更新缓存

**问题**：
- 如果 Canvas 的笔画是主人，为什么要备份到 _lastKnownStrokes？
- 如果 Database 是主人，为什么不直接从 Database 加载？
- _currentDrawing 的作用是什么？为什么需要中间对象？

#### 问题 2: copyWith() 导致的性能问题
**代码证据**（schedule_drawing.dart:84-92）：
```dart
ScheduleDrawing copyWith({
  List<Stroke>? strokes,
  // ... 其他 10 个字段
}) {
  return ScheduleDrawing(
    strokes: strokes ?? this.strokes, // 拷贝整个数组！
    // ...
  );
}
```

**场景**：用户手写 100 笔
- 每一笔：copyWith → 拷贝前 99 笔 + 新 1 笔
- 总拷贝次数：1 + 2 + 3 + ... + 100 = 5050 次拷贝
- **时间复杂度 O(n²)**

**在 C 语言中**：直接修改数组，O(1)

#### 问题 3: 竞态条件
**场景**（schedule_screen.dart 有 6 个保存触发点）：
1. `_scheduleSaveDrawing()` - debounce 定时器（500ms）
2. 手势结束 - 立即保存
3. 页面切换 - 保存当前状态
4. 视图切换 - 保存并加载新视图
5. 应用进入后台 - 保存
6. dispose - 最终保存

**问题**：
- 6 个触发点可能同时执行
- debounce 只是减少频率，不是锁
- 版本检查在异步操作之后（太晚了）
- 可能导致：保存冲突、数据丢失、版本混乱

#### 问题 4: 缓存一致性
**代码证据**：
- CacheManager 维护内存缓存
- 保存后手动更新缓存
- 但如果保存失败呢？缓存已经更新，数据库未更新
- 如果其他地方直接修改数据库呢？缓存过期

**问题**：没有自动的缓存失效机制

---

## 重构目标

### 目标 1: 建立单一数据源（Single Source of Truth）
- **主人**：数据库是唯一的真相源
- **UI 状态**：从数据库加载，修改后写回
- **删除所有中间副本**

### 目标 2: 使用可变状态 + 版本控制
- 删除 copyWith，直接修改对象
- 使用版本号实现乐观锁
- 冲突时有明确的解决策略

### 目标 3: 单一保存路径
- 6 个触发点 → 统一调用一个保存函数
- 保存函数内部处理防重入
- 明确的保存策略（立即 vs 延迟）

### 目标 4: 简化缓存策略
- 要么不用缓存（数据库足够快）
- 要么用自动失效的缓存（LRU）
- 不要手动管理缓存一致性

---

## 重构方法

### 步骤 1: 设计新的数据流（第 1 天上午）

#### 1.1 定义单一数据源原则

**新的数据流**：
```
数据库 (唯一真相源)
    ↕ (加载/保存)
DrawingController (状态管理)
    ↕ (通知)
HandwritingCanvas (UI渲染)
```

**关键设计决策**：
1. **数据库是主人**：所有修改最终写入数据库
2. **Controller 是协调者**：管理加载、修改、保存
3. **Canvas 是视图**：只负责渲染和捕获手势
4. **无中间副本**：删除 _lastKnownStrokes, _currentDrawing

#### 1.2 创建 DrawingController
- 职责：
  - 从数据库加载当前 Drawing
  - 提供修改方法（addStroke, removeStroke）
  - 管理保存时机（debounce + 明确触发）
  - 版本控制和冲突处理
- 不负责：
  - UI 渲染（Canvas 负责）
  - 手势检测（Canvas 负责）

#### 1.3 修改 ScheduleDrawing 模型
- 添加 `version` 字段（乐观锁）
- 使用可变的 `List<Stroke> strokes`（而非 final）
- 删除 copyWith 方法
- 添加 `addStroke(Stroke)`、`removeStroke(int index)` 方法

---

### 步骤 2: 实现 DrawingController（第 1 天下午）

#### 2.1 Controller 基本结构
```dart
class DrawingController extends ChangeNotifier {
  final int bookId;
  final DateTime date;
  final ViewMode viewMode;

  ScheduleDrawing? _currentDrawing;  // 当前编辑的 drawing
  int _savedVersion = 0;              // 上次保存的版本
  bool _isSaving = false;             // 保存中标志
  Timer? _autoSaveTimer;              // 自动保存定时器

  // 获取当前笔画（只读）
  List<Stroke> get strokes => _currentDrawing?.strokes ?? [];

  // 是否有未保存的变更
  bool get hasUnsavedChanges =>
      _currentDrawing?.version != _savedVersion;
}
```

#### 2.2 实现加载逻辑
```dart
Future<void> load() async {
  _currentDrawing = await _drawingRepository.get(
    bookId: bookId,
    date: date,
    viewMode: viewMode,
  );
  _savedVersion = _currentDrawing?.version ?? 0;
  notifyListeners();
}
```

#### 2.3 实现修改逻辑
```dart
void addStroke(Stroke stroke) {
  _ensureDrawingExists();
  _currentDrawing!.addStroke(stroke);  // 直接修改
  _currentDrawing!.version++;           // 增加版本
  notifyListeners();
  _scheduleAutoSave();
}

void _scheduleAutoSave() {
  _autoSaveTimer?.cancel();
  _autoSaveTimer = Timer(
    Duration(milliseconds: 500),
    () => save(),
  );
}
```

#### 2.4 实现保存逻辑（带锁）
```dart
Future<void> save({bool force = false}) async {
  if (_isSaving) return;  // 防重入
  if (!hasUnsavedChanges && !force) return;

  _isSaving = true;
  try {
    await _drawingRepository.save(_currentDrawing!);
    _savedVersion = _currentDrawing!.version;
    notifyListeners();
  } catch (e) {
    // 处理冲突（版本不匹配）
    if (e is VersionConflictException) {
      await _handleConflict();
    }
  } finally {
    _isSaving = false;
  }
}
```

---

### 步骤 3: 修改 ScheduleDrawing 模型（第 2 天上午）

#### 3.1 将 strokes 改为可变
```dart
class ScheduleDrawing {
  final int? id;
  final int bookId;
  final DateTime date;
  final ViewMode viewMode;
  List<Stroke> strokes;  // 不再是 final！
  int version;           // 乐观锁版本号

  // 直接修改方法
  void addStroke(Stroke stroke) {
    strokes.add(stroke);
  }

  void removeStroke(int index) {
    strokes.removeAt(index);
  }

  void clear() {
    strokes.clear();
  }
}
```

#### 3.2 更新序列化
- toMap/fromMap 包含 version 字段
- 数据库需要存储 version

#### 3.3 更新 Repository
```dart
Future<void> save(ScheduleDrawing drawing) async {
  // 乐观锁检查
  if (drawing.id != null) {
    final current = await getById(drawing.id!);
    if (current?.version != drawing.version - 1) {
      throw VersionConflictException();
    }
  }

  // 保存时自动增加版本
  await db.update('schedule_drawings', drawing.toMap());
}
```

---

### 步骤 4: 重构 ScheduleScreen（第 2 天下午）

#### 4.1 引入 DrawingController
```dart
class ScheduleScreenState extends State<ScheduleScreen> {
  late final DrawingController _drawingController;

  @override
  void initState() {
    super.initState();
    _drawingController = DrawingController(
      bookId: widget.book.id!,
      date: _currentDate,
      viewMode: _viewMode,
    );
    _drawingController.load();
  }
}
```

#### 4.2 删除中间副本
- 删除 `List<Stroke> _lastKnownStrokes`
- 删除 `ScheduleDrawing? _currentDrawing`
- 删除 `int _lastSavedCanvasVersion`

#### 4.3 简化保存逻辑
```dart
// 旧代码：40+ 行，6 个触发点，复杂的比较逻辑
// 新代码：
void _onStrokeAdded(Stroke stroke) {
  _drawingController.addStroke(stroke);
  // Controller 内部处理 debounce 和保存
}

@override
void dispose() {
  _drawingController.save(force: true);  // 立即保存
  _drawingController.dispose();
  super.dispose();
}
```

#### 4.4 连接 Canvas
```dart
HandwritingCanvas(
  strokes: _drawingController.strokes,  // 只读
  onStrokeAdded: _drawingController.addStroke,
  onStrokeRemoved: _drawingController.removeStroke,
)
```

---

### 步骤 5: 简化缓存策略（第 3 天上午）

#### 5.1 评估是否需要缓存
**测量数据库性能**：
- 查询一个 Drawing：<10ms
- 查询 100 个 Drawings：<100ms

**结论**：
- 如果足够快 → 不需要缓存，直接数据库
- 如果不够快 → 使用 LRU 缓存

#### 5.2 选择方案 A：移除缓存（如果数据库够快）
- 删除 CacheManager
- DrawingRepository 直接查询数据库
- 简化代码

#### 5.3 选择方案 B：使用 LRU 缓存（如果需要缓存）
- 使用 `package:collection` 的 LruMap
- 在 Repository 层透明实现
- 自动失效，不需要手动管理

```dart
class DrawingRepositoryImpl {
  final LruMap<String, ScheduleDrawing> _cache =
      LruMap(maximumSize: 50);

  Future<ScheduleDrawing?> get(...) async {
    final key = _makeKey(bookId, date, viewMode);

    // 检查缓存
    if (_cache.containsKey(key)) {
      return _cache[key];
    }

    // 查询数据库
    final drawing = await _queryDatabase(...);

    // 存入缓存
    if (drawing != null) {
      _cache[key] = drawing;
    }

    return drawing;
  }
}
```

---

### 步骤 6: 处理冲突（第 3 天下午）

#### 6.1 定义冲突场景
**场景 1**：同一设备，多个保存请求
- **解决**：防重入锁（_isSaving 标志）

**场景 2**：多设备同步，版本冲突
- **解决**：乐观锁 + 合并策略

#### 6.2 实现冲突检测
```dart
class VersionConflictException implements Exception {
  final int expectedVersion;
  final int actualVersion;
}
```

#### 6.3 实现冲突解决策略

**策略 1：Last-Write-Wins（最简单）**
- 强制覆盖服务器版本
- 适用于单用户场景

**策略 2：Merge（复杂但正确）**
- 比较两个版本的笔画
- 合并新增的笔画
- 保留不冲突的修改

**策略 3：Prompt User（最安全）**
- 检测到冲突时提示用户
- 让用户选择保留哪个版本

**推荐**：Phase 4 先实现策略 1，Phase 8（修复竞态）实现策略 2/3

---

## 测试要求

### 单元测试

#### DrawingController
- **测试用例**：
  - 加载 Drawing
  - 添加笔画（version 增加）
  - 保存 Drawing
  - hasUnsavedChanges 标志正确
  - 防重入保存（多次调用 save）
  - 自动保存触发

#### ScheduleDrawing 可变方法
- **测试用例**：
  - addStroke 添加到列表末尾
  - removeStroke 删除正确位置
  - clear 清空所有笔画
  - version 手动管理

#### Repository 乐观锁
- **测试用例**：
  - 保存时检查版本
  - 版本不匹配抛出异常
  - 成功保存后版本更新

### 集成测试

#### 端到端手写流程
- **测试场景**：
  - 用户手写 10 笔
  - 等待自动保存
  - 关闭应用
  - 重新打开
  - 确认 10 笔都在

#### 并发保存测试
- **测试场景**：
  - 快速手写 100 笔
  - 多次触发保存（不等待完成）
  - 确认没有数据丢失
  - 确认版本号正确

#### 跨视图保存测试
- **测试场景**：
  - 在日视图手写
  - 切换到 3 日视图
  - 确认保存成功
  - 切换回日视图
  - 确认数据一致

### 性能测试

#### copyWith vs 直接修改
- **测试数据**：添加 1000 笔
- **测量**：
  - 旧方法（copyWith）时间
  - 新方法（直接修改）时间
- **期望**：新方法快 10x+

#### 保存性能
- **测试场景**：
  - 保存 100 个笔画的 Drawing
  - 测量保存时间
- **期望**：<50ms

---

## 风险与缓解

### 风险 1: 可变状态引入 Bug（中风险）
**症状**：多个地方意外修改 strokes 列表
**影响**：数据不一致，难以调试
**缓解**：
- 只通过 Controller 暴露修改接口
- strokes getter 返回不可变列表视图
- 充分的单元测试
- 代码审查检查直接修改

### 风险 2: 版本冲突处理不当（中风险）
**症状**：冲突时数据丢失
**影响**：用户手写内容消失
**缓解**：
- Phase 4 先用简单策略（Last-Write-Wins）
- 记录所有冲突到日志
- Phase 8 实现更好的合并策略
- 用户反馈机制

### 风险 3: 性能回归（低风险）
**症状**：去掉缓存后变慢
**影响**：用户体验下降
**缓解**：
- 先测量数据库性能
- 保留 LRU 缓存作为备选
- A/B 测试
- 性能监控

### 风险 4: 迁移期间数据不一致（低风险）
**症状**：新旧代码混用期间状态混乱
**影响**：临时的显示问题
**缓解**：
- 一次性完整迁移（不分阶段）
- 充分测试后才合并
- 如有问题快速回滚

---

## 成功标准

### 功能标准
- ✅ 手写笔画正确保存和加载
- ✅ 无数据丢失
- ✅ 并发保存正确处理
- ✅ 版本冲突有明确处理

### 代码质量标准
- ✅ 删除所有中间副本（_lastKnownStrokes, _currentDrawing）
- ✅ schedule_screen.dart 减少 100+ 行代码
- ✅ 清晰的数据流（单一方向）
- ✅ 无复杂的比较逻辑

### 性能标准
- ✅ 添加笔画性能提升 10x+（O(n²) → O(1)）
- ✅ 保存性能不降低
- ✅ 内存使用减少（少 4 个副本）

---

## 预期收益

### 即时收益
- **性能**：手写响应速度提升 10x
- **代码量**：schedule_screen.dart -100 行
- **可读性**：数据流清晰，易于理解

### 长期收益
- **可维护性**：修改保存逻辑只需改 Controller
- **可测试性**：Controller 可独立测试
- **可扩展性**：添加撤销/重做功能容易

### 架构收益
- **单一数据源**：不会出现"哪个是最新"的困惑
- **职责清晰**：Controller、Model、View 各司其职
- **并发安全**：明确的锁和版本控制

---

## 时间估算

- **步骤 1（设计）**: 3 小时
- **步骤 2（Controller）**: 5 小时
- **步骤 3（Model）**: 4 小时
- **步骤 4（Screen）**: 5 小时
- **步骤 5（缓存）**: 3 小时
- **步骤 6（冲突）**: 4 小时

**总计**: 24 小时（3 个工作日）

---

## 下一步

完成 Phase 4 后，进入 **Phase 5: 拆分 schedule_screen.dart**。

Phase 4 清理了数据所有权，为拆分大文件做好准备：
- Controller 提取出来了
- 数据流清晰了
- 下一步可以专注拆分 UI 逻辑

**核心教训**: "清晰的数据所有权是系统健康的标志。如果你不知道谁拥有数据，你就不知道谁负责修复 bug。"
