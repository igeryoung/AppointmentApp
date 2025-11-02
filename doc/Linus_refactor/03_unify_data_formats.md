# Phase 3: 统一数据格式

## Linus 的视角

> "Every abstraction costs you something. Multiple data formats cost you everything."

数据格式不一致是技术债务的最糟糕形式：
- **每次读写都付转换税** - 性能开销
- **容易出错** - 忘记处理一种格式就是 bug
- **难以测试** - 需要测试所有格式组合
- **代码混乱** - 业务逻辑被格式判断污染

**最关键的是**：数据格式不一致说明系统在演进过程中缺乏规划，每次都在"打补丁"而不是"做正确的事"。

---

## 当前问题分析

### 问题 1: 双命名约定（snake_case + camelCase）

**位置**：
- `note.dart` 第 72-96 行
- `schedule_drawing.dart` 第 61-86 行
- 所有 Model 的 fromMap 方法

**模式**：
```dart
// 处理两种字段名
final strokesDataRaw = map['strokesData'] ?? map['strokes_data'];
final eventIdRaw = map['eventId'] ?? map['event_id'];
final createdAtRaw = map['createdAt'] ?? map['created_at'];
```

**问题分析**：
- **本地数据库使用 snake_case**（SQLite 约定）
- **服务器 API 使用 camelCase**（JSON 约定）
- **fromMap 需要同时支持两种**
- **每个字段都要写两次名字**

**为什么会这样**：
- 早期本地数据库独立设计（用 snake_case）
- 后期添加服务器同步（用 camelCase）
- 没有做数据迁移，而是"兼容两种"

**代价**：
- 每个 Model 的 fromMap 增加 50% 代码
- 性能：每个字段查找两次
- 维护：修改字段名要改 4 个地方（本地读写 + 服务器读写）

---

### 问题 2: 双时间戳格式

**位置**：
- `note.dart` parseTimestamp 方法
- `schedule_drawing.dart` parseTimestamp 方法
- `event.dart` 日期处理

**模式**：
```dart
static DateTime? parseTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is String) return DateTime.parse(value); // ISO 8601
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000); // Unix seconds
  }
  return null;
}
```

**问题分析**：
- **本地数据库**: Unix timestamp (整数秒)
- **服务器 API**: ISO 8601 字符串
- **内存对象**: DateTime 对象

**代价**：
- 三种格式互相转换
- 每次序列化/反序列化都要判断类型
- 时区问题（Unix timestamp 是 UTC，ISO 8601 可能带时区）
- 精度问题（秒 vs 毫秒 vs 微秒）

---

### 问题 3: JSON 编码混乱（字符串 vs 对象）

**位置**：
- `note.dart` strokes 字段
- `schedule_drawing.dart` strokes 字段

**模式**：
```dart
if (strokesDataRaw is String) {
  // 已经是 JSON 字符串，需要解码
  final strokesJson = jsonDecode(strokesDataRaw) as List;
  strokes = strokesJson.map((s) => Stroke.fromJson(s)).toList();
} else if (strokesDataRaw is List) {
  // 已经是对象列表，直接用
  strokes = (strokesDataRaw as List).map((s) => Stroke.fromJson(s)).toList();
}
```

**问题分析**：
- **数据库存储**: JSON 字符串（TEXT 类型）
- **内存传递**: Dart 对象（List<Stroke>）
- **fromMap 不确定输入是哪种**

**为什么会这样**：
- SQLite 不支持 JSON 类型（只能存 TEXT）
- 有时 fromMap 输入是 `db.query()` 结果（字符串）
- 有时 fromMap 输入是 `jsonDecode()` 结果（对象）
- 两个路径都要支持

**代价**：
- 每次都要运行时类型检查
- 代码重复（Note 和 ScheduleDrawing 都有相同逻辑）
- 潜在 bug：忘记处理一种类型

---

### 问题 4: 数据库迁移缺失

**现状**：
- 没有版本化的数据库迁移机制
- 所有兼容性都在代码中处理（双格式支持）
- 旧数据永远不会"升级"到新格式

**问题**：
- **技术债务永久化** - 兼容代码永远无法删除
- **性能永久损失** - 每次都要检查格式
- **复杂度累积** - 每次格式变更都增加兼容逻辑

**应该怎么做**：
- 定义迁移脚本（schema_v1 → schema_v2）
- 应用启动时检查版本，自动升级
- 升级完成后，删除旧格式兼容代码

---

## 重构目标

### 目标 1: 统一字段命名为 camelCase
- 本地数据库也使用 camelCase
- 删除所有 snake_case 兼容代码
- 写一次性迁移脚本

### 目标 2: 统一时间戳格式为 ISO 8601 字符串
- 所有存储都用 ISO 8601
- 删除 Unix timestamp 兼容代码
- 保持时区信息

### 目标 3: 统一 JSON 存储约定
- 数据库存储 JSON 字符串（TEXT）
- fromMap 输入总是已解码的 Map
- 在数据库层做编码/解码

### 目标 4: 建立数据库迁移机制
- 实现 schema version 管理
- 写迁移脚本升级旧数据
- 应用启动时自动执行

---

## 重构方法

### 步骤 1: 设计统一格式（第 1 天上午）

#### 1.1 制定格式标准

**字段命名**：
- 统一使用 camelCase
- 理由：Dart/Flutter 生态标准，JSON API 标准
- 数据库也用 camelCase（SQLite 支持，只是不常见）

**时间戳**：
- 统一使用 ISO 8601 字符串（UTC）
- 格式：`2025-01-15T10:30:00.000Z`
- 理由：
  - 人类可读（调试友好）
  - 保留时区信息
  - JSON 标准
  - 可排序（字符串排序 = 时间排序）

**JSON 嵌套**：
- 数据库存储：JSON 字符串（TEXT）
- 代码传递：Dart 对象
- fromMap 输入：总是 Map（调用者负责解码）
- toMap 输出：Map（调用者负责编码）

#### 1.2 评估影响范围
- 扫描所有使用 snake_case 字段的代码
- 确认所有时间戳读写位置
- 列出需要迁移的数据库表和字段

#### 1.3 制定迁移策略
- **Phase A**: 代码支持双格式（已经完成）
- **Phase B**: 写数据迁移脚本
- **Phase C**: 执行迁移，更新数据
- **Phase D**: 删除旧格式兼容代码

---

### 步骤 2: 实现数据库迁移机制（第 1 天下午）

#### 2.1 添加 schema_version 表
```sql
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);
```

#### 2.2 实现 MigrationManager
- 文件位置：`lib/services/migration_manager.dart`
- 功能：
  - 检查当前数据库版本
  - 查找需要执行的迁移脚本
  - 按顺序执行迁移
  - 更新版本号
  - 事务保护（迁移失败回滚）

#### 2.3 定义迁移接口
```dart
abstract class Migration {
  int get version;
  String get description;
  Future<void> migrate(Database db);
  Future<void> rollback(Database db); // 如果可能
}
```

#### 2.4 集成到数据库初始化
- PRDDatabaseService.onOpen 时调用 MigrationManager
- 测试环境支持重置到特定版本

---

### 步骤 3: 编写字段名迁移脚本（第 2 天上午）

#### 3.1 Migration_001: Books 表字段名
```sql
-- 迁移策略：
-- 1. 添加新字段（camelCase）
-- 2. 复制旧字段数据到新字段
-- 3. 删除旧字段（DROP COLUMN 在 SQLite 需要重建表）
```

**涉及表**：
- books: created_at → createdAt, archived_at → archivedAt
- events: 多个字段
- notes: 多个字段
- schedule_drawings: 多个字段

**SQLite 限制**：
- 不支持直接 RENAME COLUMN（旧版本）
- 需要创建新表，复制数据，删除旧表，重命名新表

#### 3.2 实现 Migration_001
- 对每个表：
  1. CREATE TABLE new_table (新 schema)
  2. INSERT INTO new_table SELECT ... FROM old_table
  3. DROP TABLE old_table
  4. ALTER TABLE new_table RENAME TO old_table
- 在事务中执行
- 保留所有索引和约束

#### 3.3 测试迁移
- 准备测试数据库（旧格式）
- 运行迁移
- 验证数据完整性
- 测试回滚（如果支持）

---

### 步骤 4: 编写时间戳迁移脚本（第 2 天下午）

#### 4.1 Migration_002: Unix timestamp → ISO 8601
```sql
-- 对每个时间戳字段：
UPDATE events SET createdAt = datetime(createdAtOld, 'unixepoch')
WHERE createdAt IS NOT NULL;
```

**注意**：
- SQLite 的 datetime() 函数自动转换
- 输出格式是 ISO 8601（无时区标记，默认 UTC）
- 可以在一个 UPDATE 语句中处理多个字段

#### 4.2 验证时区正确性
- 确认所有 Unix timestamps 是 UTC
- 转换后的 ISO 字符串也是 UTC
- 应用代码正确处理 UTC 时间

#### 4.3 测试边界情况
- NULL 值
- 未来日期
- 过去日期（1970 之前，如果有）
- 精度保持（毫秒）

---

### 步骤 5: 更新代码删除兼容逻辑（第 3 天）

#### 5.1 更新 Model 的 fromMap 方法
- 删除 `map['field'] ?? map['field_name']` 模式
- 只使用 camelCase 字段名
- 删除 parseTimestamp 多格式支持，只解析 ISO 字符串

#### 5.2 更新 toMap 方法
- 确保输出 camelCase
- 时间戳输出 ISO 8601 字符串

#### 5.3 更新所有查询代码
- Repository 的 WHERE 子句使用新字段名
- 排序字段使用新字段名

#### 5.4 删除 SerializationUtils（Phase 2 的临时工具）
- 不再需要双格式支持
- 所有代码假设统一格式

---

### 步骤 6: 服务器 API 同步检查（第 3 天下午）

#### 6.1 确认服务器已使用 camelCase
- 检查服务器 API 响应格式
- 如果服务器也需要改，先改服务器

#### 6.2 验证同步功能
- 测试本地 → 服务器同步
- 测试服务器 → 本地同步
- 确认字段映射正确

#### 6.3 处理版本兼容
- 如果服务器支持多版本客户端
- 添加 API 版本号
- 客户端发送期望的格式

---

## 测试要求

### 迁移测试（最关键）

#### 准备测试数据
- **测试数据库 1**: 旧格式，完整数据
  - 多个 books（包括已归档）
  - 多个 events（不同时间范围）
  - 多个 notes（包括大量笔画）
  - 多个 drawings

#### 迁移执行测试
- **测试场景**：
  - 从版本 0 迁移到最新版本
  - 中途失败回滚（模拟错误）
  - 部分迁移后重启应用
  - 重复执行迁移（幂等性）

#### 数据完整性验证
- **验证点**：
  - 记录数量不变
  - 字段值完全一致
  - 时间戳转换正确（比较 before/after）
  - 外键关系保持
  - 索引重建成功

### 单元测试

#### Model 序列化
- **测试用例**：
  - camelCase 字段正确读取
  - ISO 8601 时间戳正确解析
  - 缺少字段抛出异常（不再兼容旧格式）
  - toMap → fromMap 往返一致

#### MigrationManager
- **测试用例**：
  - 检测当前版本
  - 找到待执行迁移
  - 按顺序执行
  - 事务回滚
  - 更新版本号

### 集成测试

#### 端到端数据流
- **测试场景**：
  - 创建新 book（使用新格式）
  - 加载旧数据（已迁移）
  - 同步到服务器
  - 从服务器同步
  - 确认所有操作正常

#### 跨平台测试
- **测试场景**：
  - Web 和 Mobile 使用相同迁移
  - 迁移后的数据在两个平台都能读取

### 性能测试

#### 迁移性能
- **测试数据**：
  - 1000 个 events
  - 500 个 notes（每个 100 笔画）
  - 100 个 drawings
- **测量指标**：
  - 迁移总时间（应该 <10 秒）
  - 内存使用
  - 应用启动时间增量

#### 运行时性能对比
- **测量点**：
  - 查询性能（before/after 迁移）
  - 插入性能
  - 序列化/反序列化性能
- **期望**：迁移后性能提升（删除格式判断）

---

## 风险与缓解

### 风险 1: 数据迁移失败导致数据丢失（严重）
**症状**：迁移脚本有 bug，破坏数据
**影响**：用户数据永久丢失
**缓解**：
- **自动备份**：迁移前自动备份数据库文件
- **事务保护**：整个迁移在一个事务中
- **验证步骤**：迁移后检查数据完整性
- **回滚机制**：失败时恢复备份
- **充分测试**：用真实数据量测试

### 风险 2: SQLite 版本差异（中等）
**症状**：不同设备 SQLite 版本不同，语法不兼容
**影响**：迁移在某些设备失败
**缓解**：
- 使用最基础的 SQL 语法
- 避免新特性（如 RENAME COLUMN）
- 测试多个 SQLite 版本
- 准备多种迁移策略

### 风险 3: 时区转换错误（中等）
**症状**：时间戳转换后时区错误，显示时间不对
**影响**：用户看到错误的时间
**缓解**：
- 明确约定所有存储都是 UTC
- 只在显示时转换到本地时区
- 写详细的时区处理测试
- 手工验证关键时间戳

### 风险 4: 服务器同步冲突（中等）
**症状**：客户端新格式与服务器旧格式不兼容
**影响**：同步失败，数据不一致
**缓解**：
- 先更新服务器支持新格式
- 客户端迁移时检查服务器版本
- 添加格式转换层（如果必要）
- 分阶段发布（先服务器后客户端）

### 风险 5: 用户在迁移期间操作（低风险）
**症状**：迁移过程中用户修改数据
**影响**：部分数据可能丢失
**缓解**：
- 迁移期间显示加载界面
- 阻止用户交互
- 迁移通常很快（<10 秒）

---

## 成功标准

### 功能标准
- ✅ 所有旧数据成功迁移到新格式
- ✅ 新创建的数据使用新格式
- ✅ 代码中删除所有旧格式兼容逻辑
- ✅ 数据库 schema version 正确管理

### 数据完整性标准
- ✅ 迁移前后记录数量一致
- ✅ 迁移前后字段值一致
- ✅ 时间戳转换精度保持（±1 秒内）
- ✅ 外键关系完整

### 性能标准
- ✅ 迁移时间 <10 秒（1000 条记录）
- ✅ 序列化速度提升 ≥20%（删除格式判断）
- ✅ 代码大小减少（删除兼容逻辑）

### 代码质量标准
- ✅ 删除 SerializationUtils 临时工具
- ✅ Model 代码简化 50%（fromMap 方法）
- ✅ 无 TODO 标记关于格式兼容

---

## 预期收益

### 即时收益
- **代码简化**: fromMap/toMap 方法减少 50% 代码
- **性能提升**: 序列化快 20-30%（无类型判断）
- **维护性**: 修改字段只需改一个地方

### 长期收益
- **技术债务清除**: 永久删除双格式支持代码
- **可扩展性**: 未来格式变更有迁移机制
- **数据一致性**: 所有地方使用相同格式

### 团队收益
- **新人友好**: 只需学习一种格式
- **调试友好**: ISO 时间戳人类可读
- **信心建立**: 成功迁移证明技术能力

---

## 回滚计划

### 如果迁移失败

#### 立即回滚（应用启动时检测）
1. 检测到迁移失败标志
2. 恢复自动备份的数据库
3. 记录错误日志
4. 禁用迁移，使用兼容模式
5. 提示用户联系支持

#### 热修复发布
1. 修复迁移 bug
2. 发布新版本
3. 用户重新尝试迁移

#### 最坏情况（无法自动修复）
1. 提供数据导出工具
2. 手工修复数据
3. 重新导入

---

## 时间估算

- **步骤 1（设计）**: 3 小时
- **步骤 2（迁移机制）**: 5 小时
- **步骤 3（字段名迁移）**: 6 小时
- **步骤 4（时间戳迁移）**: 4 小时
- **步骤 5（代码更新）**: 4 小时
- **步骤 6（服务器同步）**: 2 小时

**总计**: 24 小时（3 个工作日）

**缓冲**: +1 天用于测试和修复边界情况

---

## 下一步

完成 Phase 3 后，进入 **Phase 4: 修复数据所有权**。

Phase 3 清除了数据格式的技术债务：
- 单一标准格式
- 可维护的迁移机制
- 为后续重构打下数据基础

**核心教训**: "技术债务要尽早还，拖得越久利息越高。" 双格式支持每天都在浪费 CPU 周期和开发时间。
