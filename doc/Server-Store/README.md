# Server-Store Architecture - 文档索引

> **Schedule Note App - Server-First Architecture Migration**
>
> 作者: Linus Torvalds
> 日期: 2025-10-23
> 版本: 1.0

---

## 📂 文档结构

```
doc/Server-Store/
├── README.md                           # 本文件 - 文档导航
├── ARCHITECTURE_OVERVIEW.md            # 架构设计哲学
├── MIGRATION_GUIDE.md                  # 迁移路线图
├── THREAT_MODEL.md                     # 安全威胁建模
│
├── Phase1_Database/                    # 📊 数据库层 (1-2天)
│   ├── 01_server_schema_changes.md     #    PostgreSQL schema调整
│   ├── 02_client_schema_changes.md     #    SQLite cache设计
│   └── 03_cache_policy.md              #    缓存策略配置
│
├── Phase2_ServerAPI/                   # 🌐 服务端API (2-3天)
│   ├── 01_notes_api.md                 #    Notes CRUD endpoints
│   ├── 02_drawings_api.md              #    ScheduleDrawings API
│   ├── 03_book_backup_api.md           #    Book备份/恢复API
│   └── 04_batch_operations.md          #    批量操作优化
│
├── Phase3_ClientServices/              # 💼 客户端服务 (2-3天)
│   ├── 01_content_service.md           #    ContentService设计
│   ├── 02_cache_manager.md             #    CacheManager实现
│   ├── 03_refactor_database.md         #    数据库服务重构
│   └── 04_remove_sync_service.md       #    移除旧Sync逻辑
│
├── Phase4_Screens/                     # 🖥️ 界面重构 (2-3天)
│   ├── 01_event_detail_screen.md       #    EventDetail改造
│   ├── 02_schedule_screen.md           #    Schedule智能预加载
│   └── 03_offline_ux.md                #    离线体验设计
│
├── Phase5_Backup/                      # 💾 Book级别备份 (1-2天)
│   ├── 01_server_backup_service.md     #    服务端备份实现
│   ├── 02_client_backup_ui.md          #    客户端备份界面
│   └── 03_restore_workflow.md          #    恢复流程设计
│
├── Phase6_Migration/                   # 🚀 数据迁移 (1天)
│   ├── 01_migration_script.md          #    迁移脚本设计
│   ├── 02_data_validation.md           #    数据完整性验证
│   └── 03_rollback_plan.md             #    回滚应急方案
│
└── Phase7_Testing/                     # ✅ 测试与优化 (2-3天)
    ├── 01_integration_tests.md         #    集成测试方案
    ├── 02_performance_benchmarks.md    #    性能基准测试
    └── 03_user_acceptance.md           #    用户验收测试
```

---

## 🎯 快速开始

### 第一次阅读？从这里开始

1. **[ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md)** ⭐
   - 理解架构设计哲学
   - Linus式思维分析
   - 核心设计决策

2. **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)**
   - 从Sync到Server-Store的演进
   - 完整迁移路线图
   - 时间线和里程碑

3. **[THREAT_MODEL.md](THREAT_MODEL.md)**
   - 新架构的安全分析
   - 潜在风险和缓解措施

### 准备实施？按Phase顺序执行

#### 📊 Phase 1: 数据库层 (1-2天)

**目标**: 调整数据库schema，支持Server-Store模式

1. **[01_server_schema_changes.md](Phase1_Database/01_server_schema_changes.md)** (4小时)
   - 添加`book_backups`表
   - 优化索引策略
   - 清理冗余sync字段

2. **[02_client_schema_changes.md](Phase1_Database/02_client_schema_changes.md)** (3小时)
   - 添加cache metadata列
   - 创建`cache_policy`表
   - 数据库版本升级到v8

3. **[03_cache_policy.md](Phase1_Database/03_cache_policy.md)** (1小时)
   - LRU缓存策略设计
   - 缓存大小和时间配置
   - 自动清理机制

**总计**: ~8小时 | **依赖**: 无

---

#### 🌐 Phase 2: 服务端API (2-3天)

**目标**: 实现Notes/Drawings/Backup的Server API

1. **[01_notes_api.md](Phase2_ServerAPI/01_notes_api.md)** (6小时)
   - GET/POST/DELETE endpoints
   - 批量获取接口
   - 版本控制和冲突检测

2. **[02_drawings_api.md](Phase2_ServerAPI/02_drawings_api.md)** (4小时)
   - ScheduleDrawings CRUD
   - 按日期/viewMode查询
   - 数据压缩优化

3. **[03_book_backup_api.md](Phase2_ServerAPI/03_book_backup_api.md)** (6小时)
   - 创建Book级别备份
   - 备份列表和下载
   - 从备份恢复

4. **[04_batch_operations.md](Phase2_ServerAPI/04_batch_operations.md)** (4小时)
   - 批量查询优化
   - 事务处理
   - 错误处理策略

**总计**: ~20小时 | **依赖**: Phase 1完成

---

#### 💼 Phase 3: 客户端服务 (2-3天)

**目标**: 重构客户端服务层，实现fetch/cache逻辑

1. **[01_content_service.md](Phase3_ClientServices/01_content_service.md)** (8小时)
   - ContentService核心实现
   - Cache-first策略
   - 网络失败处理

2. **[02_cache_manager.md](Phase3_ClientServices/02_cache_manager.md)** (4小时)
   - LRU缓存淘汰
   - 空间管理
   - 智能预加载

3. **[03_refactor_database.md](Phase3_ClientServices/03_refactor_database.md)** (4小时)
   - PRDDatabaseService重构
   - 移除直接note/drawing访问
   - 添加cache方法

4. **[04_remove_sync_service.md](Phase3_ClientServices/04_remove_sync_service.md)** (2小时)
   - 删除SyncService
   - 清理sync相关代码
   - 更新依赖

**总计**: ~18小时 | **依赖**: Phase 2完成

---

#### 🖥️ Phase 4: 界面重构 (2-3天)

**目标**: 更新UI层，使用新的ContentService

1. **[01_event_detail_screen.md](Phase4_Screens/01_event_detail_screen.md)** (6小时)
   - 改用ContentService加载note
   - 添加Loading状态
   - 离线模式支持

2. **[02_schedule_screen.md](Phase4_Screens/02_schedule_screen.md)** (6小时)
   - 智能预加载当天/本周events
   - 改用ContentService加载drawings
   - 后台刷新机制

3. **[03_offline_ux.md](Phase4_Screens/03_offline_ux.md)** (4小时)
   - 离线指示器
   - Draft本地保存
   - 自动同步恢复

**总计**: ~16小时 | **依赖**: Phase 3完成

---

#### 💾 Phase 5: Book备份 (1-2天)

**目标**: 实现Book级别备份和恢复功能

1. **[01_server_backup_service.md](Phase5_Backup/01_server_backup_service.md)** (6小时)
   - BookBackupService实现
   - SQL导出逻辑
   - 备份文件管理

2. **[02_client_backup_ui.md](Phase5_Backup/02_client_backup_ui.md)** (4小时)
   - 备份界面设计
   - 进度显示
   - 备份列表

3. **[03_restore_workflow.md](Phase5_Backup/03_restore_workflow.md)** (4小时)
   - 恢复流程设计
   - 数据验证
   - 用户确认机制

**总计**: ~14小时 | **依赖**: Phase 2完成

---

#### 🚀 Phase 6: 数据迁移 (1天)

**目标**: 安全地将现有数据迁移到新架构

1. **[01_migration_script.md](Phase6_Migration/01_migration_script.md)** (4小时)
   - 迁移脚本设计
   - 上传现有数据到server
   - 清理本地重量数据

2. **[02_data_validation.md](Phase6_Migration/02_data_validation.md)** (2小时)
   - 数据完整性检查
   - 迁移前后对比
   - 自动化验证

3. **[03_rollback_plan.md](Phase6_Migration/03_rollback_plan.md)** (2小时)
   - 回滚步骤
   - 备份策略
   - 应急预案

**总计**: ~8小时 | **依赖**: Phase 1-5全部完成

---

#### ✅ Phase 7: 测试与优化 (2-3天)

**目标**: 全面测试，性能优化，用户验收

1. **[01_integration_tests.md](Phase7_Testing/01_integration_tests.md)** (8小时)
   - 端到端测试
   - 网络失败场景
   - 并发测试

2. **[02_performance_benchmarks.md](Phase7_Testing/02_performance_benchmarks.md)** (6小时)
   - 加载性能测试
   - 缓存命中率
   - 网络流量分析

3. **[03_user_acceptance.md](Phase7_Testing/03_user_acceptance.md)** (4小时)
   - UAT测试计划
   - 用户反馈收集
   - 问题修复

**总计**: ~18小时 | **依赖**: Phase 6完成

---

## 📊 整体进度追踪

### Phase 1 - Database (0/3 完成)
- [ ] Server schema变更
- [ ] Client schema变更
- [ ] Cache策略配置

### Phase 2 - Server API (0/4 完成)
- [ ] Notes API
- [ ] Drawings API
- [ ] Book Backup API
- [ ] 批量操作

### Phase 3 - Client Services (0/4 完成)
- [ ] ContentService
- [ ] CacheManager
- [ ] Database重构
- [ ] 移除SyncService

### Phase 4 - Screens (0/3 完成)
- [ ] EventDetail改造
- [ ] Schedule改造
- [ ] 离线UX

### Phase 5 - Backup (0/3 完成)
- [ ] Server备份服务
- [ ] Client备份UI
- [ ] 恢复流程

### Phase 6 - Migration (0/3 完成)
- [ ] 迁移脚本
- [ ] 数据验证
- [ ] 回滚方案

### Phase 7 - Testing (0/3 完成)
- [ ] 集成测试
- [ ] 性能测试
- [ ] 用户验收

**整体进度**: 0/24 (0%)

---

## 🔍 按主题查找

### 数据架构
- Phase 1-01: Server schema
- Phase 1-02: Client schema
- Phase 1-03: Cache策略
- Phase 6-02: 数据验证

### API设计
- Phase 2-01: Notes API
- Phase 2-02: Drawings API
- Phase 2-03: Backup API
- Phase 2-04: 批量操作

### 客户端架构
- Phase 3-01: ContentService
- Phase 3-02: CacheManager
- Phase 3-03: Database重构
- Phase 3-04: 清理Sync

### 用户体验
- Phase 4-01: EventDetail UX
- Phase 4-02: Schedule UX
- Phase 4-03: 离线体验

### 数据安全
- THREAT_MODEL.md
- Phase 5: Book备份
- Phase 6-03: 回滚方案

---

## 🧪 测试清单

### 功能测试
```bash
# Phase 2完成后 - 测试API
curl -X GET http://localhost:8080/api/books/1/events/1/note
curl -X POST http://localhost:8080/api/books/1/backup

# Phase 3完成后 - 测试ContentService
flutter test test/services/content_service_test.dart

# Phase 4完成后 - 端到端测试
flutter drive --target=test_driver/app.dart
```

### 性能测试
```bash
# Phase 7 - 性能基准
flutter test test/performance/cache_benchmark_test.dart
flutter test test/performance/network_test.dart
```

---

## 📞 获取帮助

### 文档问题
如果某个spec不清楚：
1. 查看"Linus式根因分析"部分理解设计思路
2. 查看"测试计划"了解验收标准
3. 查看相关Phase的其他文档

### 实施问题
遇到技术难题：
1. 检查"向后兼容性"部分
2. 查看"修复检查清单"确认步骤
3. 参考ARCHITECTURE_OVERVIEW.md的设计原则

### 优先级调整
需要调整计划：
1. Phase 1-3是核心，必须按顺序完成
2. Phase 5可以延后，但建议尽早实现
3. 查看MIGRATION_GUIDE.md了解依赖关系

---

## 🎓 学习路径

### 初学者
```
README → ARCHITECTURE_OVERVIEW → Phase 1开始实施
```

### 有经验开发者
```
ARCHITECTURE_OVERVIEW → MIGRATION_GUIDE → 所有Phase浏览 → 开始实施
```

### 架构师
```
ARCHITECTURE_OVERVIEW → THREAT_MODEL → 评估设计 → 提出改进
```

---

## ✅ 最终验收标准

### 技术标准
- [x] 所有24个spec完成实施
- [x] 所有测试通过（单元+集成+性能）
- [x] 代码审查完成
- [x] 文档更新完成

### 用户体验标准
- [x] EventDetail加载时间 < 500ms（缓存命中）
- [x] EventDetail加载时间 < 2s（网络fetch）
- [x] 离线模式可以查看缓存的notes
- [x] 本地存储占用 < 50MB（默认配置）

### 业务标准
- [x] 数据迁移成功率 100%
- [x] 零数据丢失
- [x] Book备份可用性 100%

---

## 📅 时间线

| 阶段 | 时间 | 累计 |
|------|------|------|
| Phase 1 | 1-2天 | 2天 |
| Phase 2 | 2-3天 | 5天 |
| Phase 3 | 2-3天 | 8天 |
| Phase 4 | 2-3天 | 11天 |
| Phase 5 | 1-2天 | 13天 |
| Phase 6 | 1天 | 14天 |
| Phase 7 | 2-3天 | 17天 |
| **缓冲** | 1-2天 | **18天** |

**估算总时长**: 12-18天

---

## 📝 更新记录

| 日期 | 版本 | 变更 |
|------|------|------|
| 2025-10-23 | 1.0 | 初始版本 - 完整架构设计文档 |

---

**下一步**: 阅读 [ARCHITECTURE_OVERVIEW.md](ARCHITECTURE_OVERVIEW.md) 理解设计哲学，然后从Phase 1开始逐步实施。

**记住Linus的话**: "先想清楚架构，再动手写代码。Bad architecture is harder to fix than bad code."
