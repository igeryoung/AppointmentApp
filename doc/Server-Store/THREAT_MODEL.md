# Server-Store Architecture - 威胁模型

> **作者**: Linus Torvalds
> **日期**: 2025-10-23
> **方法**: STRIDE威胁建模

---

## 🎯 系统概览

### 新架构数据流

```
┌──────────────┐                    ┌──────────────┐
│   Client     │                    │    Server    │
│  (Flutter)   │ ──── HTTPS ───────>│  (Dart/Shelf)│
│  SQLite      │                    │  PostgreSQL  │
│  (缓存)      │ <──── JSON ────────│  (真相源)    │
└──────────────┘                    └──────────────┘
      │                                    │
      │ Cache Only                         │ Full Data
      │ ~50MB                              │ ~1GB+
      │                                    │
      ▼                                    ▼
[LRU淘汰]                           [Book Backup]
```

**关键变化**:
1. **Client → Cache only** (之前：完整数据)
2. **Server → Single source of truth** (之前：sync中的一方)
3. **无冲突解决** (之前：复杂的版本合并)

---

## 🚨 资产分类

| 资产 | 价值 | 在新架构中的位置 |
|------|------|-----------------|
| **患者医疗数据** | 极高 | Server (主) + Client (cache) |
| **Device Token** | 高 | Server DB + Client local |
| **数据库凭证** | 极高 | Server环境变量 |
| **缓存数据** | 中 | Client SQLite (可重建) |
| **Book备份** | 极高 | Server文件系统 |

---

## 🔍 STRIDE威胁分析

### S - Spoofing (身份假冒)

#### ✅ 威胁 S-1: Device Token劫持 → 改进

**旧架构风险**:
```
每个设备存储完整数据
→ 窃取Token = 窃取所有数据
```

**新架构缓解**:
```
Token仅授权fetch缓存数据
→ 窃取Token ≠ 窃取全量数据（需多次请求）
→ Rate limiting可检测异常
```

**残留风险**: Token仍永不过期
**缓解**: 参考 [security/P1_HIGH/05_token_expiration.md](../security/P1_HIGH/05_token_expiration.md)

---

#### ✅ 威胁 S-2: Server假冒 → 改进

**新架构风险**:
```
Client完全依赖Server
→ 中间人可返回伪造数据
```

**缓解措施**:
1. **强制HTTPS** (P0-02)
2. **Certificate Pinning** (推荐)
   ```dart
   final client = http.Client();
   client.badCertificateCallback = (cert, host, port) {
     return cert.sha256 == expectedCertHash;  // 固定证书
   };
   ```
3. **Response签名验证** (可选)

**严重性**: 高 → 中 (HTTPS强制后)

---

### T - Tampering (数据篡改)

#### ✅ 威胁 T-1: Cache数据篡改 → 新威胁

**新架构风险**:
```
Client cache可被本地恶意App篡改
→ 用户看到错误的医疗数据
```

**缓解措施**:
1. **Cache完整性校验**
   ```dart
   class CachedNote {
     final String data;
     final String checksum;  // SHA256(data + secret)

     bool verify() => sha256(data + secret) == checksum;
   }
   ```

2. **定期重新验证**
   ```dart
   // 每次打开App时校验cache
   if (!await cacheManager.verifyIntegrity()) {
     await cacheManager.clearAll();  // 清空可疑cache
     showWarning('Cache corrupted, reloading from server');
   }
   ```

**严重性**: 中 (Cache可重建)
**状态**: ⚠️ 需要实现

---

#### ✅ 威胁 T-2: 并发写入冲突 → 消除

**旧架构风险**:
```
多设备同时修改同一Note
→ 冲突解决复杂
→ 可能丢失数据
```

**新架构消除**:
```
Server是唯一写入点
→ 数据库事务保证原子性
→ 乐观锁检测并发
```

```dart
// Server端乐观锁
Future<Note> updateNote(Note note) async {
  final current = await db.query('SELECT version FROM notes WHERE id = ?', [note.id]);

  if (current.version != note.version) {
    throw ConflictException('Note was modified by another request');
  }

  await db.execute('''
    UPDATE notes
    SET strokes_data = ?, version = version + 1
    WHERE id = ? AND version = ?
  ''', [note.data, note.id, note.version]);
}
```

**严重性**: 高 → 低 (架构级消除)

---

### R - Repudiation (否认性)

#### ✅ 威胁 R-1: 操作无法追溯 → 持平

**新架构影响**:
```
Client不再有本地日志
→ 所有操作都通过Server
→ Server日志是唯一来源
```

**缓解措施**:
```sql
-- Server端审计表
CREATE TABLE audit_log (
  id SERIAL PRIMARY KEY,
  device_id UUID NOT NULL,
  operation VARCHAR(50),  -- 'create', 'update', 'delete'
  table_name VARCHAR(50),
  record_id INTEGER,
  old_value JSONB,        -- 变更前
  new_value JSONB,        -- 变更后
  timestamp TIMESTAMP DEFAULT NOW()
);
```

**严重性**: 中 (与旧架构相同)
**优先级**: P2

---

### I - Information Disclosure (信息泄露)

#### ✅ 威胁 I-1: Cache数据泄露 → 新威胁

**新架构风险**:
```
Client cache未加密
→ 手机被盗 = cache数据泄露
```

**缓解措施**:
1. **SQLite加密** (推荐)
   ```yaml
   # pubspec.yaml
   dependencies:
     sqflite_sqlcipher: ^2.0.0  # 加密版SQLite
   ```

   ```dart
   final db = await openDatabase(
     path,
     password: await _getDeviceKey(),  // 从Keychain获取
   );
   ```

2. **敏感字段加密**
   ```dart
   // 仅加密strokes_data
   final encrypted = encrypt(note.strokesData, key: deviceKey);
   await db.insert('notes_cache', {'strokes_data': encrypted});
   ```

**严重性**: 中
**状态**: ⚠️ 推荐实现
**参考**: [security/P1_HIGH/06_data_encryption.md](../security/P1_HIGH/06_data_encryption.md)

---

#### ✅ 威胁 I-2: 批量数据窃取 → 改进

**旧架构风险**:
```
窃取Token → 一次性下载所有数据
```

**新架构改进**:
```
窃取Token → 需要逐个请求notes
→ Rate limiting检测异常
→ 审计日志记录大量请求
```

**缓解措施**:
```dart
// Server端rate limiting
class RateLimiter {
  // 每设备每分钟最多100个请求
  final maxRequestsPerMinute = 100;

  Future<bool> allowRequest(String deviceId) async {
    final count = await redis.increment('rate:$deviceId');
    if (count == 1) {
      await redis.expire('rate:$deviceId', 60);
    }
    return count <= maxRequestsPerMinute;
  }
}
```

**严重性**: 高 → 中
**参考**: [security/P1_HIGH/07_rate_limiting.md](../security/P1_HIGH/07_rate_limiting.md)

---

#### ⚠️ 威胁 I-3: Server日志泄露敏感信息 → 新威胁

**新架构风险**:
```
所有请求经过Server
→ Server日志可能包含医疗数据
→ 日志系统安全性要求提高
```

**缓解措施**:
```dart
// 避免记录敏感数据
logger.info('Note updated: eventId=$eventId');  // ✅ Good
logger.debug('Note data: ${note.strokesData}'); // ❌ Bad

// 使用脱敏
logger.debug('Note updated: ${note.id}, size=${note.data.length}');
```

**严重性**: 中
**状态**: ⚠️ 需要代码审查

---

### D - Denial of Service (拒绝服务)

#### ✅ 威胁 D-1: Cache清理攻击 → 新威胁

**新架构风险**:
```
恶意触发cache清理
→ 用户需要重新下载所有数据
→ 网络流量暴增
```

**缓解措施**:
1. **清理限流**
   ```dart
   class CacheManager {
     DateTime? _lastCleanup;

     Future<void> cleanup() async {
       if (_lastCleanup != null &&
           DateTime.now().difference(_lastCleanup!) < Duration(hours: 1)) {
         throw Exception('Cleanup too frequent');
       }
       _lastCleanup = DateTime.now();
       // ... 执行清理
     }
   }
   ```

2. **用户确认**
   ```dart
   // UI层要求用户确认
   if (await showConfirmDialog('Clear cache?')) {
     await cacheManager.clearAll();
   }
   ```

**严重性**: 低
**状态**: ✅ 可通过UI设计缓解

---

#### ✅ 威胁 D-2: 批量请求DOS → 持平

**新架构影响**:
```
Client不再能离线工作
→ 所有操作依赖Server
→ Server可用性更关键
```

**缓解措施**:
1. **Rate limiting** (同 I-2)
2. **Connection pooling**
   ```dart
   // 限制同时请求数
   final semaphore = Semaphore(maxConcurrent: 5);

   Future<Note> getNote(int id) async {
     await semaphore.acquire();
     try {
       return await _api.getNote(id);
     } finally {
       semaphore.release();
     }
   }
   ```

**严重性**: 中 → 中
**参考**: [security/P1_HIGH/07_rate_limiting.md](../security/P1_HIGH/07_rate_limiting.md)

---

### E - Elevation of Privilege (权限提升)

#### ✅ 威胁 E-1: 跨Book数据访问 → 持平

**新架构影响**:
```
权限检查完全在Server端
→ 必须确保每个API都检查device_id
```

**缓解措施**:
```dart
// Server端统一权限检查中间件
Future<Response> authorizeBook(Request req, int bookId) async {
  final deviceId = req.headers['X-Device-Id'];
  final token = req.headers['Authorization'];

  // 验证Token
  if (!await validateToken(deviceId, token)) {
    return Response.forbidden('Invalid token');
  }

  // 验证Book所有权
  final book = await db.getBook(bookId);
  if (book.deviceId != deviceId) {
    return Response.forbidden('Access denied');
  }

  return null;  // 继续处理
}
```

**严重性**: 高
**状态**: ⚠️ 需要代码审查确认
**参考**: [security/P2_MEDIUM/12_conflict_authorization.md](../security/P2_MEDIUM/12_conflict_authorization.md)

---

#### ⚠️ 威胁 E-2: Cache权限绕过 → 新威胁

**新架构风险**:
```
恶意App直接读取SQLite cache
→ 绕过应用级权限检查
```

**缓解措施**:
1. **文件系统权限**
   ```dart
   // iOS: 使用App Sandbox
   // Android: 使用Internal Storage
   final dbPath = await getDatabasesPath();  // 自动受保护
   ```

2. **Cache加密** (同 I-1)

**严重性**: 低 (需要root权限)
**状态**: ✅ OS级保护已足够

---

## 🎯 攻击场景分析

### 场景 1: 窃取Device Token后的攻击

**攻击步骤**:
```
1. 攻击者通过中间人攻击获取Token
2. 使用Token请求API
3. 尝试下载所有Book数据
```

**防御层**:
```
┌─────────────────────────────────┐
│ Layer 1: HTTPS Only (P0-02)    │ ← 阻止Token窃取
├─────────────────────────────────┤
│ Layer 2: Rate Limiting (P1-07) │ ← 检测异常请求
├─────────────────────────────────┤
│ Layer 3: Audit Log             │ ← 记录可疑行为
├─────────────────────────────────┤
│ Layer 4: Token Expiration      │ ← 限制时间窗口
└─────────────────────────────────┘
```

**新架构优势**:
- ✅ 无法一次性dump全部数据（需逐个请求）
- ✅ Rate limiting可快速检测
- ✅ 攻击成本提高

---

### 场景 2: 手机被盗的数据泄露

**攻击步骤**:
```
1. 盗取手机
2. 提取SQLite数据库文件
3. 读取cache中的医疗数据
```

**防御层**:
```
┌─────────────────────────────────┐
│ Layer 1: OS文件保护             │ ← 需要解锁手机
├─────────────────────────────────┤
│ Layer 2: SQLite加密 (推荐)      │ ← 加密cache
├─────────────────────────────────┤
│ Layer 3: 有限数据量             │ ← 仅7天cache
└─────────────────────────────────┘
```

**新架构优势**:
- ✅ Cache仅包含部分数据（~7天）
- ✅ 不包含历史数据
- ⚠️ 仍需加密cache

---

### 场景 3: Server被攻破

**攻击步骤**:
```
1. 攻击者获取Server访问权限
2. 直接读取PostgreSQL数据库
3. 窃取所有患者数据
```

**防御层**:
```
┌─────────────────────────────────┐
│ Layer 1: Server安全加固         │ ← 防火墙、最小权限
├─────────────────────────────────┤
│ Layer 2: 数据库加密 (P1-06)     │ ← TDE加密
├─────────────────────────────────┤
│ Layer 3: 审计日志               │ ← 检测异常访问
├─────────────────────────────────┤
│ Layer 4: Book备份完整性         │ ← 快速恢复
└─────────────────────────────────┘
```

**新架构影响**:
- ⚠️ 风险集中在Server（单点故障）
- ✅ 更易于实施防护措施
- ✅ 专业运维团队管理

---

## 📊 风险矩阵对比

### 旧架构 (Sync)

```
影响 ↑
高 │ I-1(数据泄露) │ S-1(Token劫持)│
   │ T-1(并发冲突) │               │
中 │ E-1(权限提升) │ R-1(不可追溯) │
   │               │               │
低 │               │ D-1(DOS攻击)  │
   └───────────────┴───────────────┴──> 可能性
      低            中            高
```

### 新架构 (Server-Store)

```
影响 ↑
高 │               │ E-1(权限检查) │
   │               │               │
中 │ I-1(Cache泄露)│ I-2(批量窃取) │
   │ T-1(Cache篡改)│ D-2(DOS攻击)  │
低 │ D-1(Cache清理)│ R-1(不可追溯) │
   └───────────────┴───────────────┴──> 可能性
      低            中            高
```

**改进总结**:
- ✅ 消除高风险并发冲突 (T-1)
- ✅ Token劫持影响降低 (S-1: 高→中)
- ⚠️ 新增Cache相关风险 (I-1, T-1, D-1)
- ⚠️ Server单点依赖增加

---

## ✅ 安全增强建议

### 优先级 P1 (必须实现)

1. **HTTPS强制执行** (P0-02)
   ```dart
   if (apiClient.baseUrl.startsWith('http://')) {
     throw Exception('HTTPS required in production');
   }
   ```

2. **Rate Limiting** (P1-07)
   ```dart
   final limiter = RateLimiter(maxPerMinute: 100);
   ```

3. **Token过期机制** (P1-05)
   ```sql
   ALTER TABLE devices ADD COLUMN token_expires_at TIMESTAMP;
   ```

### 优先级 P2 (强烈推荐)

4. **Cache加密** (I-1缓解)
   ```yaml
   dependencies:
     sqflite_sqlcipher: ^2.0.0
   ```

5. **Cache完整性校验** (T-1缓解)
   ```dart
   if (!cacheManager.verifyIntegrity()) {
     await cacheManager.clearAll();
   }
   ```

6. **Server数据加密** (P1-06)
   ```sql
   -- PostgreSQL TDE
   ALTER TABLE notes ENCRYPT USING aes256;
   ```

### 优先级 P3 (可选增强)

7. **Certificate Pinning**
8. **响应签名验证**
9. **设备指纹增强**

---

## 🔄 持续安全评估

### 每次功能更新检查

| 更新类型 | 检查内容 |
|---------|---------|
| **新增API** | E-1权限检查, I-2数据泄露, D-2 DOS |
| **Cache逻辑变更** | I-1加密, T-1完整性, D-1清理 |
| **认证变更** | S-1假冒, S-2 Token |
| **数据模型变更** | T-2并发, R-1审计 |

### 定期安全审计

- [ ] **每季度**: 渗透测试
- [ ] **每半年**: 威胁模型更新
- [ ] **每年**: 外部安全审计

---

## 📝 总结

### 新架构安全优势

✅ **消除复杂性**
- 无sync冲突解决 → 减少安全漏洞
- 单一数据源 → 简化权限管理
- 清晰数据流 → 易于审计

✅ **攻击面减小**
- Client仅cache → 泄露影响有限
- 逐个请求 → 批量窃取困难
- Rate limiting → DOS难度增加

### 新架构安全挑战

⚠️ **Server单点依赖**
- 可用性更关键
- 需要专业运维
- 备份/恢复重要性提升

⚠️ **Cache安全**
- 需要加密保护
- 完整性验证
- 定期清理策略

### 最终建议

**实施顺序**:
1. Phase 1-7基础实施
2. 安全P1项目（HTTPS, Rate Limiting, Token过期）
3. 安全P2项目（Cache加密, 数据加密）
4. 持续监控和审计

**记住**: "Security is not a feature, it's a process. Build it in from the start."
