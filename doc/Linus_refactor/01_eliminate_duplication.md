# Phase 1: 消除代码重复

## Linus 的视角

> "Copy-paste is the root of all evil in code maintenance."

代码重复不仅仅是"多了几行代码"的问题，而是**维护噩梦的开始**：
- 修复一个 bug 需要改 3 个地方
- 改漏一处就引入新 bug
- 每个重复都是技术债务的利息

**最糟糕的是**：重复代码说明你没有找到正确的抽象。

---

## 当前问题

### 问题 1: 时间选择器逻辑重复 3 次

**位置**：
- `schedule_screen.dart` 第 996-1042 行（46 行）
- `event_detail_screen.dart` 第 774-791 行（17 行）
- `event_detail_screen.dart` 第 804-822 行（17 行）

**模式**：
```
1. 调用 showDatePicker()
2. 如果取消，返回 null
3. 调用 showTimePicker()
4. 如果取消，返回 null
5. 组合日期和时间成 DateTime
```

**问题**：
- 3 处代码完全相同
- 修改一处（如添加日期范围限制）必须改 3 次
- 已发生过：schedule_screen 的修复没同步到 event_detail_screen

**影响**：80 行 → 应该是 10 行的可复用函数

---

### 问题 2: 数据库服务初始化重复 5 次

**位置**：
- `schedule_screen.dart:88-90`
- `event_detail_screen.dart:50-52`
- `book_list_screen.dart:32-34`
- `book_list_screen_bloc.dart:45-47`
- （可能还有更多）

**模式**：
```dart
IDatabaseService get _dbService => kIsWeb
    ? WebPRDDatabaseService()
    : PRDDatabaseService();
```

**问题**：
- 平台判断散布在 5+ 个文件
- 每个屏幕都要知道平台差异
- 违反"关注点分离"原则
- 如果增加新平台（如 Desktop 特殊处理），需要改 5+ 处

**影响**：15 行重复代码 + 架构混乱

---

### 问题 3: Repository CRUD 模式重复 4 次

**位置**：
- `book_repository_impl.dart` (103 行)
- `event_repository_impl.dart` (244 行)
- `note_repository_impl.dart` (222 行)
- `drawing_repository_impl.dart` (254 行)

**模式**（每个 Repository 都有）：
```
- getById(id) → query + fromMap
- getAll() → query + map + toList
- insert(entity) → toMap + db.insert
- update(entity) → toMap + db.update
- delete(id) → db.delete
```

**问题**：
- 95% 的代码完全相同
- 只有表名和 Entity 类型不同
- 总共 ~800 行代码，实际需要 ~200 行（用泛型）

**影响**：600 行可删除的重复代码

---

### 问题 4: 错误处理模式重复

**位置**：多个 Repository 和 Service

**模式**：
```
try {
  // 数据库操作
  debugPrint('操作成功');
} catch (e) {
  debugPrint('错误: $e');
  rethrow;
}
```

**问题**：
- 每个方法都要写相同的 try-catch
- debugPrint 应该用日志系统
- 错误处理策略不一致

**影响**：约 50 行重复的错误处理代码

---

## 重构目标

### 目标 1: 提取时间选择器工具函数
- 创建 `DateTimePickerUtils.pickDateTime()`
- 3 处调用点改为使用工具函数
- 删除 70+ 行重复代码

### 目标 2: 集中化数据库服务获取
- 在 `service_locator.dart` 注册单例
- 所有屏幕使用 `getIt<IDatabaseService>()`
- 删除 15 行平台判断代码

### 目标 3: 创建泛型 Repository 基类
- 实现 `BaseRepository<T, ID>`
- 4 个具体 Repository 继承基类
- 只需实现特殊逻辑（如复杂查询）
- 删除 600 行样板代码

### 目标 4: 统一错误处理
- 创建 `DatabaseErrorHandler`
- 在 Database Service 层统一处理
- 删除分散的 try-catch 块

---

## 重构方法

### 步骤 1: 提取时间选择器（第 1 天上午）

#### 1.1 创建工具类
- 文件位置：`lib/utils/datetime_picker_utils.dart`
- 创建静态方法 `pickDateTime()`
- 支持初始值、日期范围限制
- 返回 `Future<DateTime?>`

#### 1.2 替换第一处调用
- 在 `schedule_screen.dart:996` 替换为工具函数
- 运行测试确保行为一致
- 手工测试时间选择功能

#### 1.3 替换剩余调用
- `event_detail_screen.dart` 两处
- 运行完整测试套件
- 删除原有的重复代码

#### 1.4 增强工具函数
- 添加文档注释
- 添加单元测试（测试取消、正常选择）
- 考虑添加 `pickDateTimeRange()` 以备将来使用

---

### 步骤 2: 集中化数据库服务（第 1 天下午）

#### 2.1 注册全局单例
- 在 `service_locator.dart` 添加：
  ```
  getIt.registerLazySingleton<IDatabaseService>(
    () => kIsWeb ? WebPRDDatabaseService() : PRDDatabaseService()
  );
  ```

#### 2.2 更新第一个屏幕
- `book_list_screen.dart`: 删除 getter，改用 `getIt<IDatabaseService>()`
- 确保应用启动和数据加载正常
- 测试 Web 和 Mobile 平台

#### 2.3 更新剩余屏幕
- `schedule_screen.dart`
- `event_detail_screen.dart`
- `book_list_screen_bloc.dart`
- 每改一个，运行测试

#### 2.4 验证
- 在 Web 和 Mobile 上运行应用
- 确认数据库操作正常
- 删除所有本地的平台判断代码

---

### 步骤 3: 创建泛型 Repository（第 2 天）

#### 3.1 设计基类接口
- 定义 `BaseRepository<T, ID>` 抽象类
- 包含标准 CRUD 方法：
  - `Future<T?> getById(ID id)`
  - `Future<List<T>> getAll()`
  - `Future<ID> insert(T entity)`
  - `Future<void> update(T entity)`
  - `Future<void> delete(ID id)`
- 需要子类实现：
  - `String get tableName`
  - `T fromMap(Map<String, dynamic> map)`
  - `Map<String, dynamic> toMap(T entity)`

#### 3.2 实现基类
- 文件位置：`lib/repositories/base_repository.dart`
- 实现所有标准 CRUD 操作
- 使用模板方法模式（调用抽象方法 fromMap/toMap）
- 添加事务支持方法（如果需要）

#### 3.3 重构第一个 Repository
- 选择 `BookRepository`（最简单）
- 改为继承 `BaseRepository<Book, int>`
- 只保留特殊查询（如 getArchivedBooks）
- 删除所有标准 CRUD 代码
- 运行 `book_repository_test.dart`

#### 3.4 重构剩余 Repositories
- `EventRepository`
- `NoteRepository`
- `DrawingRepository`
- 每改一个运行对应测试
- 确保所有集成测试通过

#### 3.5 清理
- 删除重复的代码
- 更新文档注释
- 统一命名约定

---

### 步骤 4: 统一错误处理（第 2 天下午，可选）

**注意**：这一步可以延后到 Phase 6（简化 Repository 层）

#### 4.1 在 DatabaseService 层添加统一处理
- 捕获常见数据库错误
- 转换为业务异常（如 `RecordNotFoundException`）
- 添加适当的日志

#### 4.2 移除 Repository 层的 try-catch
- Repository 不需要捕获异常
- 让异常向上传播到 Cubit/Service 层

#### 4.3 在 Cubit 层处理用户可见错误
- 捕获业务异常
- 转换为用户友好的错误消息
- 发射错误状态

---

## 测试要求

### 单元测试

#### 时间选择器工具
- **测试用例**：
  - 用户选择完整日期和时间
  - 用户在日期选择器点取消
  - 用户在时间选择器点取消
  - 传入初始值正确显示
  - 日期范围限制有效

#### 泛型 Repository
- **测试每个 Repository**：
  - CRUD 操作正常工作
  - 特殊查询方法正常
  - 错误处理正确
- **测试基类**：
  - 所有标准操作
  - 事务支持（如果实现）

### 集成测试

#### 数据库服务单例
- **测试场景**：
  - 应用启动时正确初始化
  - Web 平台使用 WebPRDDatabaseService
  - Mobile 平台使用 PRDDatabaseService
  - 多次调用 getIt 返回同一实例

#### 时间选择流程
- **测试场景**：
  - 从日程屏幕创建新事件，选择时间
  - 从详情屏幕修改事件时间
  - 时区处理正确（如果适用）

### 行为验证测试

#### Before/After 对比
- **验证点**：
  - 时间选择行为完全一致
  - 数据库查询结果相同
  - Repository 操作返回值相同
  - 错误处理行为一致

### 手工测试清单

- [ ] 创建新事件，选择日期时间
- [ ] 修改现有事件的时间
- [ ] 取消时间选择（日期和时间两个点）
- [ ] 在 Web 浏览器测试所有功能
- [ ] 在 iOS/Android 测试所有功能
- [ ] 检查控制台无重复的 debugPrint

---

## 风险与缓解

### 风险 1: 时间选择器行为不一致（低风险）
**症状**：某些地方的时间选择行为改变
**影响**：用户操作不流畅
**缓解**：
- 详细的单元测试
- 手工测试所有调用点
- 使用参数化支持不同配置

### 风险 2: 数据库服务单例初始化时机（中风险）
**症状**：应用启动时数据库未就绪
**影响**：应用崩溃或数据加载失败
**缓解**：
- 确保在 main() 中调用 setupServiceLocator()
- 添加初始化检查
- 测试应用冷启动流程

### 风险 3: 泛型 Repository 缺少灵活性（低风险）
**症状**：特殊查询难以实现
**影响**：需要绕过基类直接操作
**缓解**：
- 基类提供 protected 方法访问数据库
- 支持自定义查询方法
- 不强制所有操作都用基类

### 风险 4: 破坏现有测试（低风险）
**症状**：现有单元测试失败
**影响**：需要更新测试代码
**缓解**：
- 逐个 Repository 迁移
- 每步运行完整测试套件
- 保留旧代码直到新代码稳定

---

## 成功标准

### 量化指标
- ✅ 删除 70+ 行时间选择器重复代码
- ✅ 删除 15 行数据库服务平台判断代码
- ✅ 删除 600 行 Repository 样板代码
- ✅ 总计删除约 **700 行重复代码**

### 质量指标
- ✅ 所有现有测试通过
- ✅ 新增单元测试覆盖工具函数和基类
- ✅ 集成测试通过（跨平台）
- ✅ 代码审查无重大问题

### 可维护性指标
- ✅ 修改时间选择逻辑只需改 1 处
- ✅ 修改 CRUD 逻辑只需改基类
- ✅ 添加新 Repository 只需 <50 行代码

---

## 预期收益

### 立即收益
- **代码行数**: -700 行（-12%）
- **维护成本**: 减少 70%（修复 bug 从改 3 处变成改 1 处）
- **开发速度**: 新 Repository 开发时间减少 80%

### 长期收益
- **一致性**: 所有相似操作行为统一
- **测试覆盖**: 测试基类 = 测试所有 Repository
- **重构友好**: 改基类自动影响所有子类

---

## 时间估算

- **步骤 1（时间选择器）**: 3 小时
  - 创建工具函数: 1 小时
  - 替换调用点: 1 小时
  - 测试验证: 1 小时

- **步骤 2（数据库服务）**: 2 小时
  - 注册单例: 0.5 小时
  - 更新屏幕: 1 小时
  - 跨平台测试: 0.5 小时

- **步骤 3（泛型 Repository）**: 8 小时
  - 设计和实现基类: 3 小时
  - 重构 4 个 Repositories: 4 小时
  - 测试和验证: 1 小时

- **步骤 4（错误处理）**: 3 小时（可选）

**总计**: 13-16 小时（2 个工作日）

---

## 下一步

完成 Phase 1 后，进入 **Phase 2: 集中化特殊情况**。

Phase 1 为后续重构打下基础：
- 代码更简洁
- 测试覆盖更好
- 团队建立了重构的信心

**关键教训**："不要重复自己"（DRY）不仅仅是减少代码量，更是建立正确的抽象。
