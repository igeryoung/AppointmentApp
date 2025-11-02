# Phase 5: 拆分 schedule_screen.dart

## Linus 的视角

> "If you need more than 3 levels of indentation, you're screwed already, and should fix your program."

2,004 行的单文件不是"功能丰富"，而是"维护灾难"：
- **无法理解全貌** - 任何人读不完 2000 行
- **修改影响面不可预测** - 改一处可能破坏另一处
- **测试困难** - 无法独立测试各部分
- **合并冲突** - 多人修改同一文件

**好的代码应该是模块化的**：每个文件 <500 行，每个函数 <50 行，每层嵌套 ≤3 层。

---

## 当前问题分析

### schedule_screen.dart 的职责混乱

**文件大小**：2,004 行（应该 <500 行）

**包含的关注点**（10+ 个）：
1. 屏幕框架和生命周期
2. 视图模式切换（日/3日/周）
3. 事件列表加载和管理
4. 事件渲染和布局算法
5. 时间槽渲染
6. 手写绘图集成
7. 缓存管理
8. 服务器同步
9. 手势处理
10. 对话框（创建事件、修改时间）
11. FAB 菜单
12. 调试工具

**这些不应该在一个文件里！**

### 最致命的部分

#### 1. 事件布局算法（145 行，6 层嵌套）
- 位置：第 1708-1853 行
- 功能：计算事件在视图中的位置（避免重叠）
- 问题：
  - 6 层 for 循环嵌套
  - 算法和 UI 代码混在一起
  - 无法独立测试
  - 无法在其他地方复用

#### 2. 视图构建方法（200+ 行）
- `_build3DayView()`: 183 行（第 1492-1675 行）
- `_buildTimeSlotView()`: 104 行（第 1499-1603 行）
- `_buildEventsOverlay()`: 140 行（第 1708-1853 行）
- 问题：
  - 每个方法都太长
  - Builder 套 Builder
  - 难以理解数据流

#### 3. 对话框逻辑内嵌（200+ 行）
- `_changeEventTime()`: 187 行（第 968-1155 行）
- 包含完整的对话框 UI 和逻辑
- 应该是独立的 Widget

#### 4. 状态管理混乱（50+ 个字段）
- 各种 flag：`_isDrawingMode`, `_isSaving`, `_isLoading`
- 各种 controller：`_scrollController`, `_pageController`
- 各种缓存：`_canvasKeys`, `_lastKnownStrokes`
- 没有明确的状态管理模式

---

## 重构目标

### 目标 1: 提取事件布局算法
- 独立的 `EventLayoutAlgorithm` 类
- 纯函数，无 UI 依赖
- <150 行，可独立测试

### 目标 2: 提取渲染组件
- `TimeSlotGrid` Widget
- `EventTile` Widget（已存在于 widgets/schedule/）
- `EventsOverlay` Widget
- 每个 <200 行

### 目标 3: 提取对话框
- `ChangeEventTimeDialog` Widget
- `CreateEventDialog` Widget
- 移到独立文件

### 目标 4: 引入 Cubit 管理状态
- Phase 4 已有 DrawingController
- 现在添加 ScheduleCubit
- 管理事件加载、视图切换、缓存

### 目标 5: 简化主屏幕文件
- schedule_screen.dart: 2,004 行 → <300 行
- 只保留：
  - 屏幕框架
  - 组件组合
  - Cubit 连接

---

## 重构方法

### 步骤 1: 提取事件布局算法（第 1 天）

#### 1.1 创建 EventLayoutAlgorithm 类
- 文件位置：`lib/utils/schedule/event_layout_algorithm.dart`
- 职责：计算事件在时间槽中的位置，避免重叠
- 输入：
  - 事件列表（with start/end time）
  - 时间槽配置（每槽多少分钟）
  - 视图范围（开始/结束日期）
- 输出：
  - 每个事件的位置（row, column, span）

#### 1.2 设计算法接口
```dart
class EventLayoutAlgorithm {
  /// 计算事件布局
  /// 返回每个事件的定位信息
  List<PositionedEvent> calculateLayout({
    required List<Event> events,
    required DateTime startDate,
    required DateTime endDate,
    required int minutesPerSlot,
  });
}

class PositionedEvent {
  final Event event;
  final int slotIndex;     // 从开始时间算的槽位索引
  final int slotsSpanned;  // 跨越多少槽
  final int column;        // 列（0-based，同时段事件分列）
  final int totalColumns;  // 该槽总共多少列
}
```

#### 1.3 提取算法逻辑
- 从 schedule_screen.dart:1708-1853 提取核心逻辑
- 去除 UI 相关代码（Widget 构建）
- 扁平化嵌套（目标：≤3 层）
- 分解为多个辅助方法：
  - `_groupOverlappingEvents()`
  - `_assignColumns()`
  - `_calculateSlotIndex()`

#### 1.4 编写单元测试
- **测试用例**：
  - 无重叠事件 → 每个占一列
  - 两个重叠事件 → 分两列
  - 三个部分重叠 → 正确分配列
  - 跨天事件 → 正确计算槽位
  - 边界情况（午夜、周末）

---

### 步骤 2: 提取渲染组件（第 2 天）

#### 2.1 提取 TimeSlotGrid Widget
- 文件位置：`lib/widgets/schedule/time_slot_grid.dart`
- 职责：渲染时间槽背景网格
- 输入：
  - 日期范围
  - 每槽分钟数
  - 显示配置（颜色、边框）
- 输出：Canvas 绘制的网格

#### 2.2 提取 EventsOverlay Widget
- 文件位置：`lib/widgets/schedule/events_overlay.dart`
- 职责：在网格上叠加事件卡片
- 输入：
  - `List<PositionedEvent>`（来自算法）
  - 槽位尺寸配置
  - 点击回调
- 使用现有的 `EventTile` 渲染单个事件

#### 2.3 提取 ScheduleViewBuilder Widget
- 文件位置：`lib/widgets/schedule/schedule_view_builder.dart`
- 职责：组合 TimeSlotGrid + EventsOverlay
- 根据 ViewMode 构建相应视图
- 统一日/3日/周视图的构建逻辑

#### 2.4 更新 schedule_screen.dart
- 删除 1492-1853 行的视图构建代码
- 改为调用 ScheduleViewBuilder：
  ```dart
  Widget build(BuildContext context) {
    return ScheduleViewBuilder(
      events: state.events,
      viewMode: state.viewMode,
      currentDate: state.currentDate,
      onEventTap: _handleEventTap,
    );
  }
  ```

---

### 步骤 3: 提取对话框（第 3 天上午）

#### 3.1 提取 ChangeEventTimeDialog
- 文件位置：`lib/widgets/schedule/change_event_time_dialog.dart`
- 从 schedule_screen.dart:968-1155 提取
- 独立的 StatefulWidget
- 返回新的开始/结束时间，或 null（取消）

#### 3.2 提取 CreateEventDialog
- 可能已有类似功能，检查并统一
- 或者从 schedule_screen 提取对应逻辑

#### 3.3 简化主屏幕调用
```dart
// 旧代码：187 行内嵌逻辑
void _changeEventTime(Event event) {
  showDialog(...) {
    // 187 行对话框 UI 和逻辑
  }
}

// 新代码：3 行
void _changeEventTime(Event event) async {
  final newTimes = await showChangeEventTimeDialog(context, event);
  if (newTimes != null) {
    _scheduleCubit.updateEventTime(event.id, newTimes);
  }
}
```

---

### 步骤 4: 引入 ScheduleCubit（第 3 天下午）

#### 4.1 创建 ScheduleState
```dart
class ScheduleState {
  final List<Event> events;
  final ViewMode viewMode;
  final DateTime currentDate;
  final bool isLoading;
  final String? errorMessage;

  bool get hasEvents => events.isNotEmpty;
}
```

#### 4.2 创建 ScheduleCubit
- 文件位置：`lib/cubits/schedule_cubit.dart`（可能已存在）
- 管理：
  - 事件加载（从 Repository）
  - 视图模式切换
  - 日期导航
  - 缓存管理（移到 Cubit）

#### 4.3 移动业务逻辑到 Cubit
- 从 schedule_screen 移除：
  - `_loadEvents()`
  - `_switchViewMode()`
  - `_navigateToDate()`
  - 缓存相关逻辑

#### 4.4 Screen 监听 Cubit
```dart
BlocBuilder<ScheduleCubit, ScheduleState>(
  builder: (context, state) {
    if (state.isLoading) return LoadingIndicator();
    if (state.errorMessage != null) return ErrorView();

    return ScheduleViewBuilder(
      events: state.events,
      viewMode: state.viewMode,
      currentDate: state.currentDate,
      onEventTap: (event) => context.read<ScheduleCubit>().selectEvent(event),
    );
  },
)
```

---

### 步骤 5: 清理主屏幕文件（第 4 天）

#### 5.1 移除已提取的代码
- 事件布局算法 → EventLayoutAlgorithm
- 视图构建 → Widgets
- 对话框 → 独立 Widgets
- 业务逻辑 → Cubit
- 绘图管理 → DrawingController（Phase 4）

#### 5.2 保留的内容
- Scaffold 框架
- AppBar
- FAB（使用 widgets/schedule/fab_menu.dart）
- 组件组合和布局
- BlocBuilder/BlocListener

#### 5.3 简化状态管理
- 删除 50+ 个 State 字段
- 只保留必要的 UI 状态（如当前选中）
- 业务状态都在 Cubit

#### 5.4 目标文件结构
```dart
class ScheduleScreen extends StatelessWidget {
  // <300 行
  // 主要是组件组合
}
```

---

### 步骤 6: 扁平化嵌套（第 4 天下午）

#### 6.1 扫描剩余深层嵌套
- 使用 lint 工具或手工检查
- 找出所有 >3 层嵌套的地方

#### 6.2 应用扁平化策略

**策略 A：提取方法**
```dart
// 旧代码：嵌套 Builder
build() {
  return Builder(builder: (context) {
    return LayoutBuilder(builder: (context, constraints) {
      return ListView.builder(itemBuilder: (context, index) {
        // 4 层嵌套
      });
    });
  });
}

// 新代码：提取
build() {
  return Builder(builder: _buildContent);
}

Widget _buildContent(BuildContext context) {
  return LayoutBuilder(builder: _buildWithConstraints);
}

Widget _buildWithConstraints(BuildContext context, BoxConstraints constraints) {
  return ListView.builder(itemBuilder: _buildListItem);
}
```

**策略 B：提取 Widget**
```dart
// 旧代码：内嵌复杂 widget
Widget build() {
  return Column(children: [
    // 50 行复杂内容
  ]);
}

// 新代码：提取 Widget
Widget build() {
  return Column(children: [
    _HeaderWidget(),
    _ContentWidget(),
    _FooterWidget(),
  ]);
}
```

**策略 C：早返回**
```dart
// 旧代码：嵌套 if
if (condition1) {
  if (condition2) {
    if (condition3) {
      // 实际逻辑
    }
  }
}

// 新代码：早返回
if (!condition1) return;
if (!condition2) return;
if (!condition3) return;
// 实际逻辑（0 层嵌套）
```

---

## 最终文件结构

```
lib/
├── screens/
│   └── schedule_screen.dart          # <300 行（主屏幕）
├── widgets/schedule/
│   ├── schedule_view_builder.dart    # <200 行（视图组合）
│   ├── time_slot_grid.dart           # <150 行（网格渲染）
│   ├── events_overlay.dart           # <150 行（事件叠加）
│   ├── event_tile.dart               # 已存在（事件卡片）
│   ├── change_event_time_dialog.dart # <200 行（对话框）
│   └── fab_menu.dart                 # 已存在（FAB菜单）
├── cubits/
│   └── schedule_cubit.dart           # <200 行（状态管理）
└── utils/schedule/
    └── event_layout_algorithm.dart   # <150 行（布局算法）
```

**总行数**：~1,350 行（分布在 9 个文件）
**vs 旧代码**：2,004 行（1 个文件）
**删除**：~650 行重复和无用代码

---

## 测试要求

### 单元测试

#### EventLayoutAlgorithm
- **测试用例**：
  - 简单场景：2 个不重叠事件
  - 复杂场景：10 个事件，多种重叠
  - 边界情况：跨天、跨周、午夜
  - 性能：1000 个事件布局 <100ms

#### ScheduleCubit
- **测试用例**：
  - 加载事件
  - 切换视图模式
  - 日期导航
  - 错误处理

### Widget 测试

#### TimeSlotGrid
- **测试**：
  - 渲染正确数量的槽
  - 时间标签正确
  - 网格线正确

#### EventsOverlay
- **测试**：
  - 事件定位正确
  - 点击检测正确
  - 重叠事件显示正确

### 集成测试

#### 完整用户流程
- **测试场景**：
  - 打开日程屏幕
  - 查看日/3日/周视图
  - 创建新事件
  - 修改事件时间
  - 手写笔记
  - 确认所有功能正常

### 视觉回归测试

#### Before/After 截图对比
- **对比点**：
  - 日视图外观
  - 3日视图外观
  - 周视图外观
  - 事件卡片样式
  - 手写叠加
- **工具**：可以使用 Golden tests

---

## 风险与缓解

### 风险 1: 破坏现有功能（高风险）
**症状**：重构后某些功能失效
**影响**：用户无法正常使用
**缓解**：
- 大量的集成测试
- 每提取一个模块就测试
- 逐步提取，不要一次改完
- 保留原文件作为参考（重命名为 .old）

### 风险 2: 布局算法提取错误（中风险）
**症状**：事件位置计算不正确
**影响**：事件重叠或错位
**缓解**：
- 详细的单元测试（覆盖所有已知场景）
- 视觉回归测试
- 手工测试多种事件组合

### 风险 3: 状态管理迁移问题（中风险）
**症状**：状态不同步，UI 不更新
**影响**：界面显示错误
**缓解**：
- 逐步迁移状态到 Cubit
- 每迁移一块就测试
- 使用 BlocObserver 监控状态变化

### 风险 4: 性能回归（低风险）
**症状**：拆分后渲染变慢
**影响**：用户体验下降
**缓解**：
- 性能基准测试（before/after）
- 避免不必要的重建（const constructors）
- 使用 DevTools 检查渲染性能

---

## 成功标准

### 代码结构标准
- ✅ schedule_screen.dart <300 行
- ✅ 所有新文件 <200 行
- ✅ 无函数 >50 行
- ✅ 无嵌套 >3 层

### 功能完整性标准
- ✅ 所有现有功能正常工作
- ✅ 所有集成测试通过
- ✅ 视觉回归测试通过

### 可维护性标准
- ✅ 每个文件单一职责
- ✅ 算法可独立测试
- ✅ Widget 可独立复用
- ✅ 新人能快速理解结构

### 性能标准
- ✅ 渲染性能不降低
- ✅ 布局算法性能可接受
- ✅ 内存使用合理

---

## 预期收益

### 代码质量
- **可读性**：从 2004 行单文件 → 9 个清晰模块
- **可测试性**：算法可单元测试，Widget 可独立测试
- **可维护性**：修改一个功能只影响一个文件

### 开发效率
- **理解成本**：新人上手时间减少 80%
- **修改成本**：改动影响范围缩小 90%
- **合并冲突**：多人协作不再冲突

### 团队协作
- **并行开发**：不同人可以修改不同模块
- **代码审查**：每个 PR 只涉及一个模块
- **知识分散**：不再依赖"唯一懂这个文件的人"

---

## 时间估算

- **步骤 1（布局算法）**: 8 小时
- **步骤 2（渲染组件）**: 8 小时
- **步骤 3（对话框）**: 4 小时
- **步骤 4（Cubit）**: 6 小时
- **步骤 5（清理主文件）**: 4 小时
- **步骤 6（扁平化）**: 4 小时

**总计**: 34 小时（4-5 个工作日）

**缓冲**: +1 天用于处理意外和充分测试

---

## 下一步

完成 Phase 5 后，进入 **Phase 6: 简化 Repository 层**。

Phase 5 是重构的核心，拆分后：
- 代码结构清晰
- 各模块可独立测试和维护
- 为后续优化打下基础

**核心教训**: "复杂性是可以管理的，但前提是你要先把它拆分成简单的部分。2000 行的函数没人能理解，但 10 个 200 行的模块每个人都能看懂。"
