# Phase 6: 简化 Repository 层

## Linus 的视角

> "Abstraction is good. Over-abstraction is the root of all evil."

Repository Pattern 理论上很美好：
- 抽象数据访问
- 便于切换实现
- 便于测试

**但在实践中**：
- 你只有 1 个实现（SQLite）
- 你从不切换实现
- 你的测试也不 mock repositories

**这就是为理论付出实践代价的典型例子。**

---

## 当前问题分析

### 问题：5 层调用栈只为查询数据库

**典型调用链**：
```
ScheduleScreen
    ↓
ScheduleCubit.loadEvents()
    ↓
EventRepository.getByDateRange()
    ↓
EventRepositoryImpl._getDatabaseFn()
    ↓
PRDDatabaseService.query()
    ↓
SQLite
```

**5 层调用，但实际只需要 2 层**：
```
ScheduleCubit
    ↓
DatabaseService.getEvents()
    ↓
SQLite
```

### 具体问题

#### 问题 1: Repository Pattern 无实际价值

**分析 4 个 Repositories**：
- BookRepository: 只有 1 个实现（BookRepositoryImpl）
- EventRepository: 只有 1 个实现（EventRepositoryImpl）
- NoteRepository: 只有 1 个实现（NoteRepositoryImpl）
- DrawingRepository: 只有 1 个实现（DrawingRepositoryImpl）

**测试现状**：
- 检查 `test/` 目录：只有 1 个 Repository 测试（book_repository_test.dart）
- 其他测试都直接测 Cubit 或 Service
- 没有一个地方 mock Repository

**结论**：Repository 层是**纯粹的样板代码**，无任何价值。

#### 问题 2: 800 行重复代码

Phase 1 已经提取了泛型基类（如果执行），但即使有基类，仍有问题：
- 4 个接口定义（interface）
- 4 个实现类（impl）
- 每个 CRUD 操作定义两次（接口 + 实现）

**如果直接使用 DatabaseService**：
- 不需要接口定义
- 不需要实现类
- 直接调用数据库方法

#### 问题 3: 增加调试难度

**场景**：查询事件时出错
- **有 Repository**：断点要打在 5 个地方（Screen → Cubit → Repo interface → Repo impl → DB service）
- **无 Repository**：断点打 2 个地方（Cubit → DB service）

**堆栈跟踪**：
- **有 Repository**：10+ 行堆栈
- **无 Repository**：3-4 行堆栈

#### 问题 4: 命名混乱

**同一个操作有 3 个名字**：
```dart
// Cubit 层
eventRepository.getByDateRange(startDate, endDate);

// Repository 层
_getDatabaseService().query('events', where: ...);

// 实际 SQL
SELECT * FROM events WHERE start_time >= ? AND end_time <= ?
```

**为什么不直接**：
```dart
db.getEventsByDateRange(startDate, endDate);
```

---

## 重构目标

### 目标 1: 删除 Repository 层
- 删除所有 Repository 接口和实现
- Cubit 直接调用 DatabaseService
- 简化调用链：5 层 → 2 层

### 目标 2: 增强 DatabaseService
- 添加领域特定的查询方法
- 例如：`getEventsByDateRange()`, `getArchivedBooks()`
- 方法名直接反映业务意图

### 目标 3: 简化依赖注入
- 不需要注册 4 个 Repositories
- 只注册 1 个 DatabaseService
- Cubit 构造函数简化

### 目标 4: 提升可测试性
- Mock DatabaseService（1 个）而非 4 个 Repositories
- 测试更直接（Cubit → DB）
- 减少测试样板代码

---

## 重构方法

### 步骤 1: 评估影响范围（第 1 天上午）

#### 1.1 扫描 Repository 使用情况
- 搜索所有调用 Repository 的地方
- 列出每个 Repository 的方法使用统计
- 确认是否有特殊逻辑（不只是简单 CRUD）

#### 1.2 识别需要保留的逻辑
- **复杂查询**：如果 Repository 有复杂的多表 JOIN
- **数据转换**：如果 Repository 做了特殊的数据映射
- **缓存逻辑**：如果 Repository 内有缓存

**预期结果**：95% 是简单 CRUD，5% 有特殊逻辑（需要移到 Service 层）

#### 1.3 设计迁移策略
- **策略 A（激进）**：完全删除 Repository，Cubit 直接调 DB
- **策略 B（保守）**：保留 Repository 作为 DB Service 的薄包装
- **推荐**：策略 A（我们不需要这层抽象）

---

### 步骤 2: 增强 DatabaseService（第 1 天下午）

#### 2.1 添加领域方法到 IDatabaseService

**当前**：只有通用的 CRUD
```dart
abstract class IDatabaseService {
  Future<List<Map<String, dynamic>>> query(String table, {where, orderBy});
  Future<int> insert(String table, Map<String, dynamic> values);
  // ...
}
```

**增强**：添加业务方法
```dart
abstract class IDatabaseService {
  // 通用 CRUD（保留）
  Future<List<Map>> query(...);
  Future<int> insert(...);

  // 领域方法（新增）
  // Books
  Future<List<Book>> getAllBooks();
  Future<List<Book>> getArchivedBooks();
  Future<Book?> getBookById(int id);

  // Events
  Future<List<Event>> getEventsByDateRange(int bookId, DateTime start, DateTime end);
  Future<List<Event>> getEventsByBook(int bookId);
  Future<Event?> getEventById(int id);

  // Notes
  Future<Note?> getNoteByEventId(int eventId);
  Future<void> saveNote(Note note);

  // Drawings
  Future<ScheduleDrawing?> getDrawing({required int bookId, required DateTime date, required ViewMode viewMode});
  Future<void> saveDrawing(ScheduleDrawing drawing);
}
```

#### 2.2 实现领域方法

**原则**：
- 方法名反映业务意图（getEventsByDateRange 而非 query）
- 返回领域对象（Event）而非 Map
- 内部调用通用 CRUD + fromMap 转换

**示例**：
```dart
class PRDDatabaseService implements IDatabaseService {
  Future<List<Event>> getEventsByDateRange(
    int bookId,
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final maps = await db.query(
      'events',
      where: 'book_id = ? AND start_time >= ? AND end_time <= ?',
      whereArgs: [bookId, start.toIso8601String(), end.toIso8601String()],
      orderBy: 'start_time ASC',
    );
    return maps.map((map) => Event.fromMap(map)).toList();
  }
}
```

#### 2.3 Web 实现同步更新
- WebPRDDatabaseService 也实现相同的领域方法
- 保持接口一致性

---

### 步骤 3: 迁移 Cubit 使用（第 2 天）

#### 3.1 更新 ScheduleCubit

**旧代码**：
```dart
class ScheduleCubit extends Cubit<ScheduleState> {
  final EventRepository _eventRepository;

  ScheduleCubit(this._eventRepository);

  Future<void> loadEvents(DateTime start, DateTime end) async {
    final events = await _eventRepository.getByDateRange(start, end);
    emit(state.copyWith(events: events));
  }
}
```

**新代码**：
```dart
class ScheduleCubit extends Cubit<ScheduleState> {
  final IDatabaseService _db;

  ScheduleCubit(this._db);

  Future<void> loadEvents(DateTime start, DateTime end) async {
    final events = await _db.getEventsByDateRange(
      state.bookId,
      start,
      end,
    );
    emit(state.copyWith(events: events));
  }
}
```

#### 3.2 更新 BookListCubit
- 替换 BookRepository → IDatabaseService
- 调用 `_db.getAllBooks()`, `_db.getArchivedBooks()`

#### 3.3 更新 EventDetailCubit
- 替换 EventRepository, NoteRepository → IDatabaseService
- 调用 `_db.getEventById()`, `_db.getNoteByEventId()`

#### 3.4 更新其他 Services
- ContentService（如果还在用）
- SyncCoordinator
- 任何使用 Repository 的地方

---

### 步骤 4: 更新依赖注入（第 2 天下午）

#### 4.1 从 service_locator 删除 Repositories
```dart
// 删除这些
getIt.registerLazySingleton<BookRepository>(...);
getIt.registerLazySingleton<EventRepository>(...);
getIt.registerLazySingleton<NoteRepository>(...);
getIt.registerLazySingleton<DrawingRepository>(...);
```

#### 4.2 Cubit 注册简化
```dart
// 旧代码
getIt.registerFactory<ScheduleCubit>(
  () => ScheduleCubit(
    getIt<EventRepository>(),
  ),
);

// 新代码
getIt.registerFactory<ScheduleCubit>(
  () => ScheduleCubit(
    getIt<IDatabaseService>(),
  ),
);
```

---

### 步骤 5: 删除 Repository 文件（第 3 天上午）

#### 5.1 删除接口文件
- `lib/repositories/book_repository.dart`
- `lib/repositories/event_repository.dart`
- `lib/repositories/note_repository.dart`
- `lib/repositories/drawing_repository.dart`
- `lib/repositories/device_repository.dart`

#### 5.2 删除实现文件
- `lib/repositories/book_repository_impl.dart`
- `lib/repositories/event_repository_impl.dart`
- `lib/repositories/note_repository_impl.dart`
- `lib/repositories/drawing_repository_impl.dart`
- `lib/repositories/device_repository_impl.dart`

#### 5.3 删除测试文件（如果有）
- `test/repositories/book_repository_test.dart`
- 等等...

#### 5.4 删除 base_repository.dart（如果 Phase 1 创建了）

---

### 步骤 6: 更新测试（第 3 天下午）

#### 6.1 Cubit 测试更新

**旧代码**：Mock 4 个 Repositories
```dart
class MockEventRepository extends Mock implements EventRepository {}
class MockNoteRepository extends Mock implements NoteRepository {}

setUp() {
  eventRepo = MockEventRepository();
  noteRepo = MockNoteRepository();
  cubit = ScheduleCubit(eventRepo, noteRepo);
}
```

**新代码**：只 Mock 1 个 DatabaseService
```dart
class MockDatabaseService extends Mock implements IDatabaseService {}

setUp() {
  db = MockDatabaseService();
  cubit = ScheduleCubit(db);
}
```

#### 6.2 更新测试断言
```dart
// 旧代码
when(eventRepo.getByDateRange(any, any))
    .thenAnswer((_) async => mockEvents);

// 新代码
when(db.getEventsByDateRange(any, any, any))
    .thenAnswer((_) async => mockEvents);
```

#### 6.3 添加 DatabaseService 集成测试
- 测试新增的领域方法
- 确保查询逻辑正确
- 测试数据转换（Map → Domain object）

---

## 替代方案：保守方案（如果激进方案风险太高）

### 方案 B: 保留 Repository 作为薄包装

如果团队不接受完全删除 Repository：

#### B.1 Repository 变成 DB Service 的代理
```dart
class EventRepositoryImpl implements EventRepository {
  final IDatabaseService _db;

  EventRepositoryImpl(this._db);

  @override
  Future<List<Event>> getByDateRange(DateTime start, DateTime end) {
    return _db.getEventsByDateRange(start, end);  // 直接转发
  }
}
```

#### B.2 优点
- 保留现有调用代码
- 可以逐步迁移

#### B.3 缺点
- 仍然是额外的一层
- 没有实质性简化

**推荐**：不要用方案 B，直接删除更干净。

---

## 测试要求

### 单元测试

#### DatabaseService 领域方法
- **测试用例**（每个新方法）：
  - 正常查询返回正确数据
  - 空结果返回空列表
  - 错误数据抛出异常
  - 数据转换正确（Map → Domain）

#### Cubit 测试更新
- **测试用例**：
  - Mock DatabaseService 而非 Repository
  - 验证正确的 DB 方法被调用
  - 状态更新正确

### 集成测试

#### 端到端数据流
- **测试场景**：
  - 从 UI 触发数据加载
  - Cubit 调用 DatabaseService
  - 数据正确显示
- **验证点**：
  - 调用链简化（2 层）
  - 数据完整性
  - 性能没有降低

### 回归测试

#### 所有现有功能
- **测试清单**：
  - 加载 books
  - 加载 events
  - 创建/更新/删除操作
  - 搜索和过滤
  - 同步功能
- **验证**：所有功能行为不变

---

## 风险与缓解

### 风险 1: 遗漏 Repository 调用点（中风险）
**症状**：某些地方还在用 Repository，编译失败
**影响**：重构不完整
**缓解**：
- 编译器会捕获（类型错误）
- 全局搜索 "Repository" 确认都删除了
- 逐步迁移，每个 Cubit 测试后再继续

### 风险 2: 测试需要大量更新（中风险）
**症状**：所有 Mock Repository 的测试都要改
**影响**：工作量大
**缓解**：
- 自动化替换（sed/awk）
- 测试模式统一，改一个参考其他
- 这是一次性工作

### 风险 3: 团队反对删除抽象层（低风险，高影响）
**症状**：团队认为"应该保留 Repository 以备将来"
**影响**：重构被否决
**缓解**：
- 数据说话：Repository 从未被 mock
- YAGNI 原则："You Aren't Gonna Need It"
- 如果真需要，将来再加（比维护无用代码容易）
- 妥协方案：先用方案 B（薄包装），后续再删

### 风险 4: DatabaseService 变得臃肿（低风险）
**症状**：添加太多领域方法，DatabaseService 变成巨类
**影响**：单个文件过大
**缓解**：
- 使用 extension methods 分组
- 或者按领域拆分（BookQueries, EventQueries）
- 但保持接口统一（都实现 IDatabaseService）

---

## 成功标准

### 代码简化标准
- ✅ 删除 800+ 行 Repository 代码
- ✅ 调用链从 5 层减少到 2 层
- ✅ service_locator 减少 4 个注册

### 功能完整性标准
- ✅ 所有 CRUD 操作正常
- ✅ 所有业务逻辑不变
- ✅ 所有测试通过

### 可维护性标准
- ✅ 新增查询方法更直接（在 DatabaseService）
- ✅ 调试堆栈更短
- ✅ 测试 mock 更简单（1 个而非 4 个）

---

## 预期收益

### 即时收益
- **代码行数**: -800 行（Repository 层）
- **调用层级**: 5 层 → 2 层（-60%）
- **依赖注册**: -4 个 Repository

### 开发效率
- **添加查询**: 直接在 DatabaseService 添加方法
- **调试时间**: 堆栈更短，更快定位问题
- **测试编写**: Mock 1 个对象而非 4 个

### 架构清晰度
- **YAGNI**: 删除"为将来准备"的无用抽象
- **直接性**: Cubit → DB，没有中间层
- **诚实性**: 代码反映真实情况（只有 1 个 DB 实现）

---

## 时间估算

- **步骤 1（评估）**: 2 小时
- **步骤 2（增强 DB Service）**: 6 小时
- **步骤 3（迁移 Cubit）**: 6 小时
- **步骤 4（更新 DI）**: 2 小时
- **步骤 5（删除文件）**: 1 小时
- **步骤 6（更新测试）**: 7 小时

**总计**: 24 小时（3 个工作日）

---

## 下一步

完成 Phase 6 后，进入 **Phase 7: 删除 deprecated 代码**。

Phase 6 简化了数据访问层：
- 删除无用抽象
- 调用链清晰
- 代码更少，更易维护

**核心教训**: "抽象是有成本的。如果一个抽象层只有 1 个实现，从未被 mock，从未被替换，那它就是无用的样板代码。删掉它。"

**YAGNI**: You Aren't Gonna Need It. 不要为"将来可能"而设计，解决当下的问题。
