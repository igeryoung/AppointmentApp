# Phase 2: 集中化特殊情况处理

## Linus 的视角

> "Good code has no special cases. If you need a special case, your data structure is wrong."

特殊情况（if/else 分支）是代码复杂度的主要来源。每个 if 都是一个维护负担：
- 新人要理解每个分支的条件
- 测试要覆盖所有分支组合
- 修改一个分支可能破坏另一个

**好的设计让特殊情况消失。** 不是通过隐藏它们，而是通过正确的数据结构让它们不再是"特殊"。

---

## 当前问题分析

### 问题 1: 空检查泛滥（147 次 in schedule_screen.dart）

**典型模式**：
```dart
if (event.id == null) return;
if (widget.book.id == null) return;
if (_contentService == null) return;
if (_cacheManager == null) return;
if (canvasState == null) return;
```

**问题**：
- 如果 book.id 是 null，整个屏幕就是无效的
- 为什么要在 147 个地方检查？
- 说明初始化逻辑不够健壮

**应该怎么做**：
- 在构造函数/init 时确保数据有效
- 使用非空类型（`late final` 或者构造函数断言）
- 快速失败原则：启动时就崩溃，不要在运行时反复检查

**影响**：147 个空检查 → 应该减少到 ~10-20 个（真正可能为空的地方）

---

### 问题 2: ViewMode 魔法数字（6 个文件）

**位置**：
- `drawing_repository_impl.dart`
- `schedule_screen.dart`
- `schedule_cubit.dart`
- `content_service.dart`
- 等等...

**模式**：
```dart
final viewMode = 1; // 总是 3日视图
if (viewMode == 0) { /* 日视图 */ }
else if (viewMode == 1) { /* 3日视图 */ }
else if (viewMode == 2) { /* 周视图 */ }
```

**问题**：
- 数字 0、1、2 没有语义
- 容易写错（0 还是 1？）
- 添加新视图时要改 6 个文件
- 编译器无法检查是否处理所有情况

**应该怎么做**：
```dart
enum ViewMode { day, threeDay, week }

// 使用 switch（编译器强制检查完整性）
switch (viewMode) {
  case ViewMode.day: // 处理日视图
  case ViewMode.threeDay: // 处理 3日视图
  case ViewMode.week: // 处理周视图
}
```

**影响**：6 个文件的 if-else 改为类型安全的 switch

---

### 问题 3: 平台判断分散（已在 Phase 1 部分解决）

Phase 1 已经集中化数据库服务获取，但还有其他平台相关判断：

**位置**：
- UI 布局相关（`kIsWeb ? padding : noPadding`）
- 手势处理（Mobile 支持，Web 不支持）
- 文件选择器（不同平台 API）

**问题**：
- 平台判断散布在业务逻辑中
- 难以测试（需要模拟平台）
- 添加新平台（如 Desktop）需要全局搜索替换

**应该怎么做**：
- 创建 Platform Adapter 层
- 业务逻辑不知道平台
- 适配器处理所有平台差异

---

### 问题 4: 类型转换和格式判断

**位置**：`note.dart` 和 `schedule_drawing.dart`

**模式**：
```dart
// 处理 snake_case 和 camelCase
final strokesDataRaw = map['strokesData'] ?? map['strokes_data'];

// 处理字符串和列表
if (strokesDataRaw is String) {
  final strokesJson = jsonDecode(strokesDataRaw);
} else if (strokesDataRaw is List) {
  // 已经是列表
}

// 处理不同时间戳格式
if (value is String) return DateTime.parse(value);
if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
```

**问题**：
- 每次读取都要判断类型
- 数据层不一致
- 性能开销（每次序列化/反序列化都要检查）

**应该怎么做**：
- Phase 3 会统一数据格式
- 本阶段先将判断逻辑集中到一个地方
- 准备迁移到单一格式

---

### 问题 5: 事件类型判断

**位置**：多处使用 `event.eventType` 字符串比较

**模式**：
```dart
if (event.eventType == 'appointment') { ... }
else if (event.eventType == 'todo') { ... }
else if (event.eventType == 'note') { ... }
```

**问题**：
- 字符串容易拼写错误
- 没有编译时检查
- 添加新类型容易遗漏处理

**应该怎么做**：
```dart
enum EventType { appointment, todo, note }

// 类型安全
switch (event.eventType) {
  case EventType.appointment: // ...
  case EventType.todo: // ...
  case EventType.note: // ...
}
```

---

## 重构目标

### 目标 1: 减少防御性空检查
- 147 个空检查 → ~10-20 个真正需要的
- 使用非空类型和断言
- 快速失败而不是反复检查

### 目标 2: 引入类型安全的枚举
- ViewMode: int → enum ViewMode
- EventType: String → enum EventType
- 消除魔法数字和字符串

### 目标 3: 集中化平台相关逻辑
- 创建 PlatformAdapter
- 业务代码无平台判断
- 适配器模式隔离差异

### 目标 4: 集中化数据格式判断
- 将类型判断移到 fromMap 方法
- 上层代码假设数据已规范化
- 为 Phase 3 的格式统一做准备

---

## 重构方法

### 步骤 1: 减少空检查（第 1 天上午）

#### 1.1 识别必要的空检查
- **真正可能为空**：
  - 用户输入（如搜索框文本）
  - 网络请求结果
  - 可选的配置项
- **不应该为空**：
  - 从数据库加载的实体 ID
  - 构造函数传入的必需参数
  - 服务依赖（应该在初始化时就绪）

#### 1.2 重构 ScheduleScreen 初始化
- 在构造函数确保 book.id 非空：
  ```dart
  ScheduleScreen({required Book book})
    : assert(book.id != null, 'Book must have an ID'),
      _bookId = book.id!;
  ```
- 将 `late final` 用于必定初始化的字段
- 删除函数体内的重复空检查

#### 1.3 重构服务依赖
- 服务应该在 initState 时就获取：
  ```dart
  late final ContentService _contentService;

  @override
  void initState() {
    super.initState();
    _contentService = getIt<ContentService>();
    // 如果获取失败，这里就会抛异常（快速失败）
  }
  ```
- 删除方法体内的 `if (_contentService == null)` 检查

#### 1.4 重构可空返回值
- 对于真正可空的情况，使用 `?.` 和 `??` 操作符
- 减少显式的 if-null-return 模式

---

### 步骤 2: 引入枚举类型（第 1 天下午）

#### 2.1 定义 ViewMode 枚举
- 文件位置：`lib/models/view_mode.dart`
- 定义枚举：
  ```dart
  enum ViewMode {
    day,
    threeDay,
    week;

    // 辅助方法（如需要）
    int get daysCount { ... }
    String get displayName { ... }
  }
  ```

#### 2.2 迁移数据模型
- `ScheduleDrawing` 的 viewMode 字段：
  - 从 `int viewMode` 改为 `ViewMode viewMode`
  - 更新 toMap/fromMap 处理枚举序列化
  - 保持数据库兼容性（存储为 int index）

#### 2.3 更新使用点
- `schedule_screen.dart` 的视图切换逻辑
- `schedule_cubit.dart` 的状态管理
- `drawing_repository` 的查询条件
- 将所有 `if (viewMode == 1)` 改为 `if (viewMode == ViewMode.threeDay)`

#### 2.4 定义 EventType 枚举
- 文件位置：`lib/models/event_type.dart`
- 定义枚举：
  ```dart
  enum EventType {
    appointment,
    todo,
    note;

    // 从字符串解析（兼容旧数据）
    static EventType parse(String value) { ... }
  }
  ```

#### 2.5 更新 Event 模型
- eventType 字段从 String 改为 EventType
- 更新序列化/反序列化
- 更新所有使用点的字符串比较

---

### 步骤 3: 创建平台适配器（第 2 天上午）

#### 3.1 定义适配器接口
- 文件位置：`lib/services/platform_adapter.dart`
- 定义接口：
  ```dart
  abstract class PlatformAdapter {
    // UI 相关
    EdgeInsets get contentPadding;
    bool get supportsGestures;

    // 文件操作
    Future<File?> pickFile();

    // 其他平台特定能力
  }
  ```

#### 3.2 实现平台特定适配器
- `WebPlatformAdapter`
- `MobilePlatformAdapter`
- 在 service_locator 根据平台注册

#### 3.3 替换业务代码中的平台判断
- 搜索所有 `kIsWeb` 用法
- 不在数据层/服务层的判断都移到适配器
- UI 层通过适配器获取平台相关配置

**注意**：数据库服务选择（Phase 1 已处理）保持不变

---

### 步骤 4: 集中化数据格式判断（第 2 天下午）

#### 4.1 创建序列化工具类
- 文件位置：`lib/utils/serialization_utils.dart`
- 提供辅助方法：
  ```dart
  class SerializationUtils {
    // 处理 snake_case/camelCase
    static dynamic getField(Map map, String camelCase, String snakeCase) {
      return map[camelCase] ?? map[snakeCase];
    }

    // 处理多种时间戳格式
    static DateTime parseTimestamp(dynamic value) { ... }

    // 处理 JSON 字符串或对象
    static List<dynamic> parseJsonArray(dynamic value) { ... }
  }
  ```

#### 4.2 更新 Model 的 fromMap 方法
- `Note.fromMap()` 使用 `SerializationUtils.getField()`
- `ScheduleDrawing.fromMap()` 同样处理
- 上层代码不再需要知道格式差异

#### 4.3 文档化格式兼容性
- 注释说明为什么需要双格式支持
- 标记为临时方案（Phase 3 会统一）
- 添加迁移计划的 TODO

---

## 测试要求

### 单元测试

#### 空检查减少
- **测试场景**：
  - 使用 null book.id 构造 ScheduleScreen 应该断言失败
  - 服务未初始化时应该在 initState 抛异常
  - 合法数据不应触发任何空检查

#### 枚举类型
- **测试 ViewMode**：
  - 序列化/反序列化正确
  - 旧数据（int）能正确加载
  - switch 语句覆盖所有情况
- **测试 EventType**：
  - 字符串解析正确
  - 未知类型有合理的默认值或异常

#### 平台适配器
- **测试场景**：
  - Mock 适配器注入测试
  - 不同平台返回不同配置
  - 业务逻辑不包含平台判断

#### 序列化工具
- **测试用例**：
  - camelCase 和 snake_case 都能读取
  - ISO 时间戳和 Unix 时间戳都能解析
  - JSON 字符串和对象都能处理
  - 错误格式抛出清晰异常

### 集成测试

#### 视图模式切换
- **测试场景**：
  - 从日视图切换到 3日视图
  - 保存绘图并重新加载
  - 确认 viewMode 正确存储和读取

#### 事件类型过滤
- **测试场景**：
  - 创建不同类型的事件
  - 按类型过滤显示
  - 确认类型判断逻辑正确

### 行为验证测试

#### Before/After 对比
- **关键验证点**：
  - 所有界面渲染结果相同
  - 事件过滤逻辑一致
  - 视图切换行为不变
  - 错误处理逻辑一致

---

## 风险与缓解

### 风险 1: 断言导致应用崩溃（中风险）
**症状**：assert 失败导致应用在生产环境崩溃
**影响**：用户无法使用应用
**缓解**：
- assert 只在 debug 模式生效
- 生产环境用条件检查 + 错误上报
- 充分测试边界情况

### 风险 2: 枚举迁移破坏旧数据（高风险）
**症状**：旧数据库中的 int 无法映射到枚举
**影响**：用户数据丢失或显示错误
**缓解**：
- 保持数据库存储为 int
- 只在内存对象中使用枚举
- 添加迁移测试用例

### 风险 3: 平台适配器遗漏场景（中风险）
**症状**：某些平台相关功能失效
**影响**：特定平台功能异常
**缓解**：
- 详细审查所有 kIsWeb 用法
- 每个平台都要手工测试
- 逐步迁移，保留回退方案

### 风险 4: 序列化逻辑回归（低风险）
**症状**：某些边缘格式处理不正确
**影响**：特定数据加载失败
**缓解**：
- 全面的单元测试
- 测试旧数据兼容性
- 错误日志记录详细信息

---

## 成功标准

### 量化指标
- ✅ 空检查从 147 个减少到 <20 个（-86%）
- ✅ 所有 ViewMode 魔法数字改为枚举（6 个文件）
- ✅ EventType 字符串比较改为枚举
- ✅ 平台判断集中到适配器（移除业务代码中的 kIsWeb）

### 质量指标
- ✅ 编译器能检查所有枚举分支
- ✅ 新增枚举值时有编译错误提示
- ✅ 代码可读性提升（enum vs magic number）
- ✅ 测试覆盖率不降低

### 架构指标
- ✅ 业务逻辑无平台判断
- ✅ 快速失败而非防御性编程
- ✅ 类型安全保证（enum vs string/int）

---

## 预期收益

### 代码质量
- **可读性**: 枚举比魔法数字语义清晰 100%
- **类型安全**: 编译器检查减少运行时错误
- **维护性**: 添加新枚举值，编译器会提示所有需要处理的地方

### 性能
- **减少运行时检查**: 147 个 null 检查 → 20 个
- **更早发现错误**: 初始化时崩溃而非运行时

### 团队效率
- **新人友好**: 枚举 = 自文档化
- **重构友好**: 修改枚举自动影响所有用法
- **测试简化**: 减少边界情况测试

---

## 时间估算

- **步骤 1（空检查）**: 4 小时
  - 分析空检查：1 小时
  - 重构初始化：2 小时
  - 测试验证：1 小时

- **步骤 2（枚举）**: 5 小时
  - 定义枚举：1 小时
  - 更新模型和序列化：2 小时
  - 更新所有使用点：2 小时

- **步骤 3（平台适配器）**: 4 小时
  - 设计接口：1 小时
  - 实现适配器：2 小时
  - 迁移使用点：1 小时

- **步骤 4（序列化工具）**: 3 小时
  - 创建工具类：1 小时
  - 更新 Models：1 小时
  - 测试验证：1 小时

**总计**: 16 小时（2 个工作日）

---

## 下一步

完成 Phase 2 后，进入 **Phase 3: 统一数据格式**。

Phase 2 建立了类型安全和清晰的结构：
- 枚举替代魔法值
- 快速失败替代防御式编程
- 平台差异被隔离

**核心思想**: "让不正确的状态无法表示" - 通过类型系统而非运行时检查来保证正确性。
