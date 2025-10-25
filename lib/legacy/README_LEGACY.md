# Legacy Code Directory

## ⚠️ 注意：此目录包含旧版实现代码

此目录包含项目早期的实现版本，**当前应用并未使用这些代码**。保留这些文件仅供参考或将来可能的功能恢复。

## 🚫 不要使用这些文件

- **当前活跃代码路径**: `BookListScreen` → `ScheduleScreen` → `EventDetailScreen`
- **当前活跃数据层**: `PRDDatabaseService` (位于 `lib/services/`)
- **当前活跃模型**: `Book`, `Event`, `Note` (位于 `lib/models/`)

## 📁 Legacy 文件说明

### Screens (UI层)
- `calendar_screen.dart` - 旧版日历视图（已被 ScheduleScreen 替代）
- `appointment_detail_screen.dart` - 旧版预约详情（已被 EventDetailScreen 替代）

### Providers (状态管理)
- `book_provider.dart` - 旧版 Book 状态管理
- `appointment_provider.dart` - 旧版 Appointment 状态管理

**注意**: 当前应用不使用 Provider 模式，直接在 Screen 层调用数据库服务。

### Services (业务逻辑层)
- `book_service.dart` - Book 业务逻辑封装
- `appointment_service.dart` - Appointment 业务逻辑封装
- `database_service.dart` - ⚠️ **数据库 Schema 错误** - 查询 `appointments` 表但实际只创建了 `events` 表
- `web_database_service.dart` - Web 平台数据库实现

**注意**: 当前应用直接使用 `PRDDatabaseService`，不经过 Service 抽象层。

### Models (数据模型)
- `appointment.dart` - 旧版 Appointment 模型（已被 Event + Note 模型替代）

## 🐛 已知问题

### DatabaseService 的致命 Bug
```dart
// database_service.dart 创建的表：
CREATE TABLE events (...)
CREATE TABLE notes (...)

// 但是查询时使用的表名：
await db.query('appointments', ...)  // ❌ 这个表不存在！
```

如果尝试使用 `DatabaseService`，会导致运行时错误："no such table: appointments"

## 🗑️ 为什么不直接删除？

保留这些文件是为了：
1. **代码历史参考** - 了解项目演进过程
2. **设计思路参考** - Service 层和 Provider 模式的实现示例
3. **功能恢复选项** - 如果将来需要某些功能，可以从这里提取

## 🔄 如果需要清理

如果确认永远不需要这些代码，可以安全删除整个 `lib/legacy/` 目录：

```bash
rm -rf lib/legacy
```

## 📚 相关文档

- 当前架构说明: 见根目录 `README.md`
- PRD 文档: `doc/appointmentApp_PRD.md`
- 测试文档: `test/README.md`

---

**最后更新**: 2025-10-17
**维护状态**: ⚠️ 不维护（Legacy Code）
