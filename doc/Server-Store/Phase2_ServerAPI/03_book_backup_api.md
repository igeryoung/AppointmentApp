# Phase 2-03: Book Backup API

> **优先级**: P2 - Phase 2
> **状态**: ✅ 已完成
> **实际时间**: 5小时
> **完成日期**: 2025-10-24
> **依赖**: Phase 1-01完成

---

## 📋 任务描述

### 目标

完善Book级别备份API（server已有基础实现，需优化）：
1. 创建Book备份（导出为SQL或JSON）
2. 获取备份列表
3. 从备份恢复
4. 下载备份文件

### 当前状态

**已有实现** (server/lib/routes/book_backup_routes.dart):
- ✅ `/api/books/upload` - 上传备份
- ✅ `/api/books/restore/<backupId>` - 恢复备份
- ⚠️ 当前是JSON格式存储在PostgreSQL中

**需要改进**:
- 改为文件存储（避免大JSON拖慢数据库）
- 添加备份压缩
- 支持增量备份（Phase 2可选）

---

## 🧠 Linus式根因分析

### 数据结构问题

**当前方案（JSON in DB）**:
```sql
book_backups (
  backup_data JSONB  -- 存储完整Book数据
)
问题: 100MB的Book会占用100MB JSONB，影响查询性能
```

**改进方案（File-based）**:
```sql
book_backups (
  backup_path TEXT,           -- 文件路径
  backup_size_bytes BIGINT    -- 文件大小
)
实际数据: /var/scheduleNote/backups/book_1_2025-10-23.sql.gz
```

**Good Taste**:
- ✅ 数据库存元数据，文件系统存大块数据
- ✅ 分离关注点：metadata vs payload

---

## ✅ 实施方案

### API设计

```
POST   /api/books/{bookId}/backup
  → 创建备份，返回backupId

GET    /api/books/{bookId}/backups
  → 列出该Book的所有备份

GET    /api/backups/{backupId}/download
  → 下载备份文件（streaming）

POST   /api/backups/{backupId}/restore
  Body: { deviceId, deviceToken }
  → 从备份恢复数据
```

### 备份格式

**SQL格式** (推荐):
```sql
-- Book metadata
INSERT INTO books (...) VALUES (...);

-- Events
INSERT INTO events (...) VALUES (...);

-- Notes
INSERT INTO notes (...) VALUES (...);

-- Drawings
INSERT INTO schedule_drawings (...) VALUES (...);
```

**压缩**: gzip压缩SQL文件（减少50-70%）

### 核心逻辑

1. **创建备份**:
   - 查询Book的所有关联数据
   - 生成SQL INSERT语句
   - 压缩并保存到文件
   - 在`book_backups`表记录元数据

2. **恢复备份**:
   - 验证权限
   - 在事务中执行：
     - 删除旧数据
     - 执行备份SQL
   - 全部成功或全部回滚

3. **文件管理**:
   - 路径: `{BACKUP_DIR}/book_{bookId}_{timestamp}.sql.gz`
   - 自动清理: 保留最近10个备份

---

## 🧪 测试计划

### 功能测试

1. **创建备份**: 备份Book #1（包含10个events, 5个notes）
2. **列出备份**: 获取Book #1的备份列表
3. **下载备份**: 下载备份文件，验证完整性
4. **恢复备份**: 恢复到新Book，验证数据一致性
5. **错误处理**: Book不存在、权限不足、磁盘空间不足

### 性能测试

- 100个events的Book备份 < 5秒
- 备份文件大小 < 原数据的30%（压缩后）

---

## 📦 向后兼容性

**迁移策略**:
- 保留旧的JSON格式备份（只读）
- 新备份使用文件格式
- Phase 6清理旧格式备份

---

## ✅ 验收标准

- [x] 文件备份正常工作 ✅ (SQL + gzip)
- [x] 备份列表API正常 ✅ (GET /api/books/{bookId}/backups)
- [x] 恢复功能正常（事务保证） ✅ (全部成功或全部回滚)
- [x] 文件压缩率 > 50% ✅ (实测89.1%压缩率！)
- [x] 权限验证通过 ✅ (deviceId + deviceToken)
- [x] 性能达标 ✅ (备份<1s, 恢复<1s)
- [x] 自动清理保留最新10个备份 ✅
- [x] 所有测试通过 ✅ (40/40 tests passed)

### 实测性能
- **压缩率**: 89.1% (7919 bytes → 867 bytes)
- **备份时间**: < 1秒 (10 events + 5 notes + 2 drawings)
- **恢复时间**: < 1秒 (完整数据恢复)
- **数据完整性**: 100% (所有数据正确恢复)

---

## 🔗 相关任务

- **依赖**: [Phase 1-01: Server Schema](../Phase1_Database/01_server_schema_changes.md)
- **下一步**: [Phase 5-01: Server Backup Service](../Phase5_Backup/01_server_backup_service.md)

---

## 📝 实施总结

### 已实现功能

**文件备份系统**:
- ✅ `BookBackupService.createFileBackup()` - SQL生成 + gzip压缩
- ✅ `BookBackupService.restoreFromFileBackup()` - 事务性恢复
- ✅ `BookBackupService.cleanupOldBackups()` - 保留最新10个
- ✅ `BookBackupService.getBackupFilePath()` - 流式下载支持

**新API端点** (文件备份):
- ✅ `POST /api/books/{bookId}/backup` - 创建备份
- ✅ `GET /api/books/{bookId}/backups` - 列出备份
- ✅ `GET /api/backups/{backupId}/download` - 下载备份文件（流式传输）
- ✅ `POST /api/backups/{backupId}/restore` - 恢复备份
- ✅ `DELETE /api/backups/{backupId}` - 删除备份

**Legacy API** (向后兼容):
- ✅ `POST /api/books/upload` - JSON格式上传（标记为deprecated）
- ✅ `GET /api/books/list` - 列出备份（标记为deprecated）
- ✅ 恢复接口自动检测并支持两种格式

**测试覆盖**:
- ✅ `test_book_backup_api.sh` - 40个测试全部通过
- ✅ 功能测试：创建、列出、下载、恢复、删除
- ✅ 性能测试：备份/恢复时间、压缩率
- ✅ 错误处理：无效ID、权限验证、数据完整性
- ✅ 边界测试：自动清理、并发备份

**数据库改动**:
- ✅ `migrations/004_server_store_optimization.sql` - 添加file-based字段
- ✅ `backup_data` 改为nullable（支持文件备份）
- ✅ 新增索引优化文件备份查询

**文件**:
- `server/lib/services/book_backup_service.dart` - 新增500+行实现
- `server/lib/routes/book_backup_routes.dart` - 完全重构
- `server/main.dart` - 路由挂载更新
- `server/openapi.yaml` - API文档更新
- `server/test_book_backup_api.sh` - 综合测试脚本

### 关键设计决策

1. **文件格式**: SQL而非JSON
   - 更易inspection和手动修复
   - 可以直接在psql中执行
   - gzip压缩率更高（89% vs 预期50%）

2. **存储策略**: 文件系统 + 数据库元数据
   - 避免大JSONB拖慢数据库
   - 文件可独立备份/迁移
   - 元数据查询仍然快速

3. **向后兼容**: 保留旧API
   - 标记为deprecated但继续工作
   - 恢复接口自动检测格式
   - Phase 6再清理legacy代码

4. **自动清理**: 保留最新10个备份
   - 每次备份后自动触发
   - 防止磁盘空间耗尽
   - 可配置数量（默认10）

### 下一步工作

- [ ] 客户端集成（Flutter）
- [ ] 增量备份支持（Phase 5）
- [ ] 备份加密（安全性增强）
- [ ] 云存储集成（S3/GCS）

---

**Linus说**: "Use the right tool for the job. Databases for metadata, filesystems for large blobs."

**实施总结**: 文件备份系统完全按照Linus的"good taste"设计：简单、可测试、实际可用。89.1%的压缩率远超预期，性能优异，所有测试通过。✅
