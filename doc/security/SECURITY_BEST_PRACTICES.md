# Schedule Note App - 安全最佳实践

> **面向**: 开发团队
> **目的**: 编写安全代码的实用指南
> **风格**: Linus 式 - 简单、直接、实用

---

## 🎯 核心原则

### 1. 默认拒绝（Deny by Default）

**❌ 错误**：先开放，再限制
```dart
// 默认允许所有来源
final allowedOrigins = config.allowedOrigins ?? ['*'];
```

**✅ 正确**：先拒绝，明确允许
```dart
// 默认拒绝，必须明确指定
final allowedOrigins = config.allowedOrigins;
if (allowedOrigins.isEmpty) {
  throw Exception('ALLOWED_ORIGINS must be set');
}
```

---

### 2. 最小权限（Least Privilege）

**❌ 错误**：数据库用户有所有权限
```sql
GRANT ALL PRIVILEGES ON DATABASE schedule_note TO app_user;
```

**✅ 正确**：只给必需权限
```sql
GRANT SELECT, INSERT, UPDATE ON books, events, notes TO app_user;
-- 不给 DROP、CREATE 权限
```

---

### 3. 纵深防御（Defense in Depth）

不要依赖单一安全措施。多层保护：

```
传输层：HTTPS（P0-02）
    ↓
认证层：Token 验证 + 过期（P1-05）
    ↓
授权层：设备所有权检查（P2-12）
    ↓
验证层：输入验证（P2-09）
    ↓
数据层：加密存储（P1-06）
```

即使一层被突破，其他层仍能保护。

---

## 🔒 编码规范

### 永远不要硬编码秘密

**❌ 禁止**：
```dart
const API_KEY = 'sk-1234567890abcdef';
const DB_PASSWORD = 'postgres';
const ENCRYPTION_KEY = 'my_secret_key';
```

**✅ 应该**：
```dart
final apiKey = Platform.environment['API_KEY'] ??
                (throw Exception('API_KEY not set'));
final dbPassword = Platform.environment['DB_PASSWORD'] ??
                   (throw Exception('DB_PASSWORD not set'));
final encryptionKey = await _secureStorage.read(key: 'encryption_key');
```

**检查方法**：
```bash
# 搜索可疑的硬编码
grep -r "password.*=" lib/
grep -r "key.*=" lib/
grep -r "secret.*=" lib/
```

---

### 永远验证用户输入

**❌ 危险**：
```dart
Future<Book> getBook(int id) async {
  return await db.query('SELECT * FROM books WHERE id = $id');
}
```

**✅ 安全**：
```dart
Future<Book> getBook(int id) async {
  // 1. 验证类型和范围
  if (id <= 0 || id > MAX_INT) {
    throw ArgumentError('Invalid book ID');
  }

  // 2. 使用参数化查询
  return await db.query(
    'SELECT * FROM books WHERE id = @id',
    parameters: {'id': id},
  );
}
```

**验证清单**：
- [ ] 类型正确？
- [ ] 范围合理？
- [ ] 长度限制？
- [ ] 格式有效？
- [ ] 非空检查？

---

### 永远使用参数化查询

**❌ SQL 注入漏洞**：
```dart
await db.query('SELECT * FROM $tableName WHERE user_id = $userId');
```

**✅ 参数化查询**：
```dart
// 表名用白名单
final validTable = _validateTableName(tableName);

// 值用参数
await db.query(
  'SELECT * FROM $validTable WHERE user_id = @userId',
  parameters: {'userId': userId},
);
```

**规则**：
- 表名/列名：白名单验证
- 值：参数化查询
- 永远不直接拼接用户输入

---

### 安全的错误处理

**❌ 泄露内部信息**：
```dart
try {
  await connectDatabase();
} catch (e) {
  return Response.internalServerError(
    body: 'Database connection failed: $e',  // 暴露数据库路径、端口等
  );
}
```

**✅ 通用错误消息**：
```dart
try {
  await connectDatabase();
} catch (e) {
  // 详细日志仅记录服务端
  logger.error('Database connection failed', error: e, stackTrace: stackTrace);

  // 返回通用错误
  return Response.internalServerError(
    body: jsonEncode({'error': 'Service temporarily unavailable'}),
  );
}
```

---

### HTTPS 强制执行

**❌ 可选 HTTPS**：
```dart
final url = userConfig.serverUrl;  // 可能是 http://
await http.get(Uri.parse(url));
```

**✅ 强制 HTTPS**：
```dart
final url = userConfig.serverUrl;

// 生产环境必须 HTTPS
if (!url.startsWith('https://') && !kDebugMode) {
  throw Exception('Only HTTPS URLs are allowed in production');
}

// 开发环境警告
if (!url.startsWith('https://') && kDebugMode) {
  debugPrint('⚠️  Using HTTP in development mode');
}

await http.get(Uri.parse(url));
```

---

## 🧪 安全测试

### 单元测试必须包含安全测试

```dart
group('Security Tests', () {
  test('拒绝 SQL 注入尝试', () {
    expect(
      () => getBook("1; DROP TABLE users--"),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('拒绝超长输入', () {
    final longName = 'A' * 10000;
    expect(
      () => createBook(longName),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('拒绝无效 Token', () async {
    final response = await apiClient.sync(
      deviceId: 'valid-id',
      deviceToken: 'invalid-token',
    );
    expect(response.statusCode, equals(401));
  });
});
```

### 手动渗透测试清单

- [ ] SQL 注入：尝试注入特殊字符
- [ ] XSS：在输入中加 `<script>` 标签
- [ ] CSRF：从其他域发起请求
- [ ] 认证绕过：尝试无 Token 访问
- [ ] 权限提升：尝试访问其他用户数据
- [ ] 速率限制：连续发送1000次请求

---

## 📝 代码审查安全检查清单

### 新增 API 端点

- [ ] 需要认证吗？
- [ ] 检查设备所有权吗？
- [ ] 输入全部验证吗？
- [ ] 使用参数化查询吗？
- [ ] 有速率限制吗？
- [ ] 错误不泄露信息吗？

### 新增数据库操作

- [ ] 使用参数化查询？
- [ ] 表名来自白名单？
- [ ] 有权限检查？
- [ ] 记录审计日志？

### 新增文件操作

- [ ] 验证文件路径？
- [ ] 限制文件大小？
- [ ] 检查文件类型？
- [ ] 防止路径遍历（`../`）？

---

## 🚫 常见陷阱

### 陷阱 1："开发环境不需要安全"

**❌ 错误想法**：
> "反正是本地测试，用 HTTP 就行"

**✅ 正确做法**：
- 开发环境也用 HTTPS（自签名证书）
- 开发数据库也用强密码
- 开发环境泄露一样违法

---

### 陷阱 2："性能优先于安全"

**❌ 错误想法**：
> "加密会影响性能，先不加"

**✅ 正确做法**：
- 现代加密开销极小（< 1ms）
- 数据泄露代价远超性能损失
- 先安全，再优化

---

### 陷阱 3："等发现问题再修"

**❌ 错误想法**：
> "暂时没人攻击，以后再说"

**✅ 正确做法**：
- 安全问题修复成本指数增长
- 开发时修复：1小时
- 生产后修复：1周 + 用户信任损失

---

## 🔄 持续安全

### 依赖更新

```bash
# 每月检查一次
flutter pub outdated
dart pub outdated

# 检查安全漏洞
dart pub audit  # Dart 2.18+
```

### 密钥轮换

| 密钥类型 | 轮换频率 | 责任人 |
|---------|---------|--------|
| 数据库密码 | 90天 | DevOps |
| API Token | 30天 | 自动 |
| 加密密钥 | 1年 | 安全团队 |

### 审计日志审查

每周检查：
```sql
-- 失败的认证尝试
SELECT * FROM sync_log
WHERE status = 'failed'
  AND created_at > NOW() - INTERVAL '7 days';

-- 异常大量请求
SELECT device_id, COUNT(*)
FROM sync_log
WHERE created_at > NOW() - INTERVAL '1 day'
GROUP BY device_id
HAVING COUNT(*) > 1000;
```

---

## 📚 推荐资源

### 阅读清单

1. **OWASP Top 10** - 最常见的 Web 漏洞
2. **CWE Top 25** - 最危险的软件错误
3. **NIST Cybersecurity Framework** - 系统性安全框架

### 工具

```bash
# 静态代码分析
dart analyze --fatal-infos

# 依赖漏洞扫描
dart pub audit

# Secrets 扫描
git secrets --scan  # 防止提交密码
```

---

## ✅ 安全开发工作流

```
1. 需求阶段
   └─> 识别敏感数据
   └─> 确定认证/授权需求

2. 设计阶段
   └─> 威胁建模（STRIDE）
   └─> 设计安全控制

3. 开发阶段
   └─> 遵循安全编码规范
   └─> 代码自审查

4. 测试阶段
   └─> 单元测试（安全用例）
   └─> 手动渗透测试

5. 部署阶段
   └─> 环境变量检查
   └─> 安全配置验证

6. 运维阶段
   └─> 日志监控
   └─> 定期安全审计
```

---

## 🎓 总结

### Linus 式安全三原则

1. **简单 > 复杂**
   - 不要设计复杂的安全系统
   - 用简单、久经考验的方法
   - HTTPS > 自己发明的加密

2. **默认安全 > 可选安全**
   - 生产环境无 HTTPS？拒绝启动
   - 无环境变量？拒绝启动
   - 不要给开发者"跳过安全"的选项

3. **早修复 > 晚修复**
   - 发现问题立即修
   - 不要"等有时间"
   - 安全债务比技术债务更危险

---

**记住**：安全不是一个功能，是一种思维方式。每写一行代码，问自己："这能被恶意利用吗？"
