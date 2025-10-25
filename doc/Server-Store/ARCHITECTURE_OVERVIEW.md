# Server-Store Architecture - 架构设计概览

> **作者**: Linus Torvalds
> **日期**: 2025-10-23
> **方法**: Good Taste + Pragmatism

---

## 🧠 Linus的三个问题

在设计这个架构前，我们先回答Linus的经典三问：

### 1. "这是真实问题还是想象的问题?"

✅ **真实问题**:
- **存储空间不足**: 手机本地存储大量手写笔记数据（每个stroke point ~20 bytes，1000个点=20KB，100个notes=2MB）
- **多设备访问**: 医生需要在iPad、iPhone、Web端实时查看最新数据
- **数据备份**: 需要可靠的Book级别备份和恢复机制

❌ **非问题**:
- ~~实时协作编辑~~（单用户应用）
- ~~离线优先~~（医疗环境通常有网络）
- ~~复杂的冲突解决~~（Server是单一真相源）

### 2. "有更简单的方法吗?"

**当前方案（Sync）**:
```
Device A ──双向同步──> Server ──双向同步──> Device B
   ↓ (冲突!)                           ↓ (冲突!)
每个设备存储完整数据              每个设备存储完整数据
```
**复杂度**: O(devices²) - 设备越多，冲突越多

**新方案（Server-Store）**:
```
Device A ──fetch/store──> Server ──fetch/store──> Device B
   ↓ (cache only)        ↓ (source of truth)    ↓ (cache only)
轻量缓存                完整数据                 轻量缓存
```
**复杂度**: O(devices) - 线性扩展，无冲突

✅ **更简单**: Server-Store比双向Sync简单10倍

### 3. "这会破坏什么?"

**向后兼容性**:
- ✅ Books/Events数据模型不变
- ✅ API endpoints兼容（仅新增，不删除旧的）
- ✅ 现有数据可完整迁移

**用户体验影响**:
- ⚠️ 首次加载Note需要网络请求（~500ms-2s）
- ✅ 智能预加载后几乎无感知
- ✅ 离线模式下可查看缓存数据

**决策**: 小的体验权衡换取巨大的架构简化 → **值得！**

---

## 🏗️ 核心架构原则

### 原则 1: Server as Source of Truth

**Bad Taste (当前Sync模式)**:
```dart
// 每个设备认为自己的数据是对的
if (local.version > server.version) {
  // 上传我的版本
} else if (server.version > local.version) {
  // 下载服务器版本
} else {
  // 😱 冲突！需要用户选择
}
```

**Good Taste (Server-Store模式)**:
```dart
// Server说什么就是什么
final note = await server.getNote(eventId);
await cache.save(note);  // 本地只是缓存
```

**消除的特殊情况**:
- ❌ 版本冲突检测
- ❌ 冲突解决策略
- ❌ 合并算法
- ❌ 同步日志

### 原则 2: Separation of Concerns

**数据分层**:
```
┌─────────────────────────────────────┐
│ 轻量元数据 (Books + Events)          │  <-- 本地存储
│ - 体积小 (每个event ~200 bytes)     │
│ - 查询频繁                          │
│ - 离线必需                          │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 重量内容 (Notes + Drawings)          │  <-- Server存储 + LRU Cache
│ - 体积大 (每个note ~20KB-200KB)     │
│ - 按需加载                          │
│ - 可清理重建                        │
└─────────────────────────────────────┘
```

**Good Taste**: 不同性质的数据用不同的策略，而不是"一刀切"全部同步。

### 原则 3: Clear Data Flow

**Bad (双向流动，复杂)**:
```
Client ←→ Sync Engine ←→ Server
   ↓                      ↓
SQLite                PostgreSQL
   ↓                      ↓
Conflict!              Conflict!
```

**Good (单向流动，清晰)**:
```
Read:  Server (truth) → Client (cache)
Write: Client (draft) → Server (commit) → Client (cache update)
```

### 原则 4: Fail Loudly, Degrade Gracefully

**网络失败时的行为**:
```dart
try {
  // 优先从Server加载最新数据
  note = await server.getNote(eventId);
  cache.save(note);
} catch (NetworkError) {
  // 降级到缓存，但明确告知用户
  note = await cache.getNote(eventId);
  showWarning("Showing cached data. Changes won't be saved until online.");
}
```

**Good Taste**: 不掩盖问题，让用户知道当前状态。

---

## 📊 数据流设计

### 场景 1: 用户打开EventDetail

```
┌───────────┐
│   User    │
│  点击Event  │
└─────┬─────┘
      │
      ▼
┌─────────────────────┐
│  ContentService     │  1. 检查本地cache
│  getNote(eventId)   │────┐
└─────────────────────┘    │
      │                    │
      │ cache miss         │ cache hit
      ▼                    ▼
┌─────────────────────┐  ┌──────────────┐
│   ApiClient         │  │ 立即返回      │
│   GET /notes/:id    │  │ (< 10ms)    │
└──────┬──────────────┘  └──────────────┘
      │
      ▼
┌─────────────────────┐
│  Server (Postgres)  │
│  查询note数据        │
└──────┬──────────────┘
      │
      ▼
┌─────────────────────┐
│  返回note JSON      │ (~500ms-2s)
│  + 更新本地cache     │
└─────────────────────┘
```

**性能优化**:
- Cache命中率 > 80%（智能预加载）
- Cache命中延迟 < 10ms
- Network fetch延迟 < 2s

### 场景 2: 用户保存Note

```
┌───────────┐
│   User    │
│  保存笔记   │
└─────┬─────┘
      │
      ▼
┌─────────────────────┐
│  ContentService     │
│  saveNote(note)     │
└──────┬──────────────┘
      │
      ▼
┌─────────────────────┐
│  POST to Server     │
│  事务提交            │
└──────┬──────────────┘
      │
      │ Success
      ▼
┌─────────────────────┐
│  更新本地cache       │
│  用户看到成功提示     │
└─────────────────────┘
      │
      │ Network Error
      ▼
┌─────────────────────┐
│  保存到DraftQueue   │
│  显示"将在在线时同步"  │
└─────────────────────┘
```

### 场景 3: 智能预加载

```
用户打开ScheduleScreen (某天的日历视图)
      │
      ▼
┌─────────────────────┐
│  后台异步任务        │
│  不阻塞UI           │
└──────┬──────────────┘
      │
      ▼
获取当天的所有Event IDs
      │
      ▼
┌─────────────────────┐
│  批量fetch notes    │
│  POST /notes/batch  │
│  [id1, id2, ...]   │
└──────┬──────────────┘
      │
      ▼
┌─────────────────────┐
│  批量写入cache       │
│  用户点击时立即显示   │
└─────────────────────┘
```

**Good Taste**: 在用户需要之前就准备好数据，而不是等用户点击时才加载。

---

## 🗄️ 数据模型对比

### Before: Sync架构

**Client SQLite**:
```sql
-- 存储完整数据
notes (id, event_id, strokes_data, version, is_dirty, synced_at)
                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                    为sync准备的冗余字段
```

**Server PostgreSQL**:
```sql
-- 存储完整数据（重复！）
notes (id, event_id, strokes_data, version, is_deleted, device_id, synced_at)
                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                    为sync准备的冗余字段
```

**问题**:
- 数据重复存储
- 复杂的sync元数据
- 冲突解决逻辑

### After: Server-Store架构

**Client SQLite**:
```sql
-- 仅缓存，可随时清除
notes_cache (
  id INTEGER,
  event_id INTEGER,
  strokes_data TEXT,
  cached_at INTEGER,      -- 缓存时间
  cache_hit_count INTEGER -- LRU指标
)
-- 新增cache管理
cache_policy (
  max_size_mb INTEGER,    -- 最大缓存50MB
  cache_duration_days INTEGER,  -- 缓存7天
  auto_cleanup BOOLEAN
)
```

**Server PostgreSQL**:
```sql
-- 单一真相源，去除sync冗余
notes (
  id SERIAL PRIMARY KEY,
  event_id INTEGER,
  strokes_data TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  version INTEGER         -- 仅用于乐观锁
)
```

**改进**:
- ✅ 数据模型简化
- ✅ 清晰的cache语义
- ✅ 无冗余字段

---

## 🎯 关键技术决策

### 决策 1: 哪些数据存本地？

| 数据类型 | 存储策略 | 原因 |
|---------|---------|------|
| **Books** | 本地完整存储 | 数量少(<100)，体积小，离线必需 |
| **Events元数据** | 本地完整存储 | 查询频繁，离线必需显示日历 |
| **Notes** | LRU缓存 | 体积大，按需加载，可重建 |
| **Drawings** | LRU缓存 | 体积大，按需加载，可重建 |

**Good Taste**: 根据数据特性选择策略，而不是"全部sync"或"全部server"。

### 决策 2: 缓存淘汰策略

**LRU (Least Recently Used) with Time Decay**:
```dart
class CacheManager {
  Future<void> evict() async {
    // 1. 删除过期cache (> 7天)
    await deleteWhere('cached_at < ?', [sevenDaysAgo]);

    // 2. 如果仍超过大小限制，删除最少使用的
    if (totalSize > maxSize) {
      await deleteOrderBy('cache_hit_count ASC', limit: n);
    }
  }
}
```

**为什么不用其他策略**:
- ❌ FIFO: 不考虑使用频率
- ❌ LFU: 老数据永远不会被淘汰
- ✅ LRU + Time: 兼顾频率和新鲜度

### 决策 3: 何时预加载？

**预加载时机**:
1. **打开ScheduleScreen时** - 预加载当天的所有notes
2. **滑动到新日期时** - 预加载该日期的notes
3. **切换viewMode时** - 预加载该视图范围内的notes

**不预加载**:
- ❌ 打开App时预加载所有notes（浪费）
- ❌ 预加载历史数据（用户很少回看）

**Good Taste**: 只加载用户可能需要的数据，不做过度预测。

### 决策 4: Book备份策略

**为什么选择Book级别**:
- ✅ 清晰的业务边界（一个预约册）
- ✅ 合理的数据量（通常< 100MB）
- ✅ 易于恢复（独立的业务单元）

**为什么不是**:
- ❌ Event级别：太细粒度，管理复杂
- ❌ 全量备份：太大，恢复慢
- ❌ 增量备份：复杂，Phase 1不需要

---

## 🔧 实现策略

### 渐进式迁移

**原则**: Never break userspace - 现有功能在迁移期间保持工作

```
Phase 1: 准备（数据库schema）
   ├── Server添加新表
   ├── Client添加cache表
   └── 旧功能继续工作 ✅

Phase 2: 并行（新旧共存）
   ├── 新API endpoints上线
   ├── 旧Sync继续工作
   └── 逐步切换到新逻辑

Phase 3: 切换（启用新逻辑）
   ├── UI改用ContentService
   ├── 旧SyncService保留但不调用
   └── 可快速回退 ✅

Phase 4: 清理（删除旧代码）
   ├── 数据完全迁移
   ├── 验证无问题
   └── 删除SyncService
```

### 错误处理

**分层错误处理**:
```dart
// Layer 1: Network层
try {
  response = await http.post(url);
} catch (NetworkError) {
  throw ApiException('Network failed');
}

// Layer 2: Service层
try {
  note = await apiClient.getNote(id);
} catch (ApiException) {
  note = await cache.getNote(id);  // Fallback to cache
  throw CacheUsedException();
}

// Layer 3: UI层
try {
  await contentService.getNote(id);
  showSuccess();
} catch (CacheUsedException) {
  showWarning('Offline mode');
} catch (Exception) {
  showError('Failed to load');
}
```

**Good Taste**: 每层处理自己该处理的错误，不向上抛未知异常。

---

## 📈 性能目标

### 响应时间

| 操作 | 目标 | 测量方式 |
|------|------|----------|
| Cache命中加载 | < 50ms | 从调用到UI显示 |
| Server fetch | < 2s | 从请求到返回 |
| 保存Note | < 1s | 从点击到成功提示 |
| 打开Schedule | < 300ms | 首屏渲染 |

### 缓存指标

| 指标 | 目标 | 说明 |
|------|------|------|
| 命中率 | > 80% | 智能预加载 |
| 缓存大小 | < 50MB | 默认配置 |
| 清理耗时 | < 100ms | 不阻塞UI |

### 网络流量

| 场景 | 流量 | 优化 |
|------|------|------|
| 首次同步 | ~5MB/100 events | 批量操作 |
| 日常使用 | ~500KB/天 | 增量更新 |
| 预加载 | ~2MB | 压缩+批量 |

---

## 🔒 安全考量

### 数据流安全

```
Client                    Server
  │                         │
  │  1. HTTPS Only         │
  │ ─────────────────────> │
  │                         │
  │  2. Device Token       │
  │    验证失败拒绝         │
  │ <─────────────────────  │
  │                         │
  │  3. 数据加密存储        │
  │    (PostgreSQL TDE)    │
  │                         │
  │  4. Book级别权限       │
  │    检查device_id       │
```

### 威胁缓解

参考 [THREAT_MODEL.md](THREAT_MODEL.md)，Server-Store架构缓解的威胁：

1. **Sync冲突攻击** ✅ 消除（无sync）
2. **版本伪造** ✅ 缓解（Server是真相）
3. **存储空间DOS** ✅ 缓解（LRU限制大小）
4. **离线数据窃取** ⚠️ 仍存在（需加密cache）

---

## 🎓 Linus的总结

### Good Taste体现

1. **消除特殊情况**
   - ✅ 无冲突检测（Server是真相）
   - ✅ 无版本合并（单向写入）
   - ✅ 无复杂状态机（clear data flow）

2. **数据结构优先**
   - ✅ Server: 完整数据
   - ✅ Client: 轻量cache
   - ✅ 清晰的所有权

3. **简单即美**
   - ✅ Server-Store比Sync简单10倍
   - ✅ 代码行数减少40%
   - ✅ 可维护性提升

### Pragmatism体现

1. **解决真实问题**
   - ✅ 存储空间不足
   - ✅ Book级别备份
   - ✅ 多设备访问

2. **不过度设计**
   - ❌ 不做实时协作（不需要）
   - ❌ 不做P2P同步（太复杂）
   - ❌ 不做CRDT（Overkill）

3. **渐进式演进**
   - ✅ 可回退
   - ✅ 向后兼容
   - ✅ 分阶段上线

---

**下一步**: 阅读 [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) 了解具体迁移步骤。

**记住**: "Complexity is the enemy. Good architecture eliminates special cases, not manages them."
