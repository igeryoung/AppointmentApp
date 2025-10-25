# 安全文档索引

> **Schedule Note App - 完整安全分析与修复指南**
>
> 作者: Linus Torvalds
> 日期: 2025-10-20

---

## 📂 文档结构

```
doc/security/
├── README.md                          # 本文件 - 文档导航
├── SECURITY_ANALYSIS.md               # 主报告 - 从这里开始
├── THREAT_MODEL.md                    # 威胁建模分析
├── SECURITY_BEST_PRACTICES.md         # 开发安全指南
│
├── P0_CRITICAL/                       # 🔴 立即修复（1天内）
│   ├── 01_hardcoded_credentials.md    #    硬编码数据库密码
│   ├── 02_https_enforcement.md        #    无 HTTPS 强制执行
│   ├── 03_cors_vulnerability.md       #    CORS 完全开放
│   └── 04_sql_injection_risk.md       #    SQL 注入风险
│
├── P1_HIGH/                           # 🟠 高优先级（7天内）
│   ├── 05_token_expiration.md         #    Token 永不过期
│   ├── 06_data_encryption.md          #    数据未加密存储
│   ├── 07_rate_limiting.md            #    无请求速率限制
│   └── 08_weak_token_generation.md    #    弱 Token 生成算法
│
└── P2_MEDIUM/                         # 🟡 中优先级（30天内）
    ├── 09_input_validation.md         #    输入验证缺失
    ├── 10_device_authentication.md    #    设备认证简单
    ├── 11_backup_integrity.md         #    Backup 无完整性验证
    └── 12_conflict_authorization.md   #    冲突解决无授权
```

---

## 🎯 快速开始

### 第一次阅读？从这里开始

1. **[SECURITY_ANALYSIS.md](SECURITY_ANALYSIS.md)** ⭐
   - 总览所有安全问题
   - 了解优先级和影响
   - 查看修复进度

2. **[THREAT_MODEL.md](THREAT_MODEL.md)**
   - 理解攻击场景
   - 了解风险评估方法

3. **[SECURITY_BEST_PRACTICES.md](SECURITY_BEST_PRACTICES.md)**
   - 学习安全编码规范
   - 避免常见陷阱

### 准备修复？按优先级顺序

#### 🔴 第1天：修复 P0（阻断性问题）

必须全部完成才能进入下一阶段：

1. **[01_hardcoded_credentials.md](P0_CRITICAL/01_hardcoded_credentials.md)** (30分钟)
   - 环境变量化数据库密码
   - 创建 `.env.example`
   - 测试无密码时拒绝启动

2. **[02_https_enforcement.md](P0_CRITICAL/02_https_enforcement.md)** (1小时)
   - 获取 SSL 证书
   - 服务端强制 HTTPS
   - 客户端验证证书

3. **[03_cors_vulnerability.md](P0_CRITICAL/03_cors_vulnerability.md)** (20分钟)
   - 域名白名单配置
   - 替换 `Access-Control-Allow-Origin: *`

4. **[04_sql_injection_risk.md](P0_CRITICAL/04_sql_injection_risk.md)** (30分钟)
   - 表名白名单验证
   - 搜索所有 SQL 拼接点

**总计**: ~2.5小时 | **收益**: 消除最严重漏洞

---

#### 🟠 第2-7天：修复 P1（高优先级）

可以分批完成，但建议按顺序：

1. **[05_token_expiration.md](P1_HIGH/05_token_expiration.md)** (2小时)
   - 添加 Token 过期机制
   - 实现自动刷新

2. **[07_rate_limiting.md](P1_HIGH/07_rate_limiting.md)** (2小时)
   - 添加 API 速率限制
   - 防止暴力攻击

3. **[08_weak_token_generation.md](P1_HIGH/08_weak_token_generation.md)** (30分钟)
   - 使用密码学安全随机数

4. **[06_data_encryption.md](P1_HIGH/06_data_encryption.md)** (4小时)
   - 数据库加密（最耗时）
   - 可选：仅加密敏感字段

**总计**: ~8.5小时 | **收益**: 符合医疗数据保护标准

---

#### 🟡 第8-30天：修复 P2（中优先级）

改进和完善：

1. **[09_input_validation.md](P2_MEDIUM/09_input_validation.md)** (3小时)
2. **[10_device_authentication.md](P2_MEDIUM/10_device_authentication.md)** (4小时)
3. **[11_backup_integrity.md](P2_MEDIUM/11_backup_integrity.md)** (2小时)
4. **[12_conflict_authorization.md](P2_MEDIUM/12_conflict_authorization.md)** (1小时)

**总计**: ~10小时

---

## 📊 修复进度追踪

### P0 - Critical (0/4 完成)

- [ ] 硬编码凭证
- [ ] HTTPS 强制执行
- [ ] CORS 漏洞
- [ ] SQL 注入

### P1 - High (0/4 完成)

- [ ] Token 过期
- [ ] 数据加密
- [ ] 速率限制
- [ ] Token 生成算法

### P2 - Medium (0/4 完成)

- [ ] 输入验证
- [ ] 设备认证
- [ ] Backup 完整性
- [ ] 冲突授权

**整体进度**: 0/12 (0%)

---

## 🔍 按问题类型查找

### 认证 / 授权

- P1-05: Token 过期机制
- P1-08: 安全 Token 生成
- P2-10: 设备指纹验证
- P2-12: 冲突解决授权

### 数据保护

- P0-01: 密码管理
- P1-06: 数据加密
- P2-11: Backup 完整性

### 网络安全

- P0-02: HTTPS 强制
- P0-03: CORS 配置
- P1-07: 速率限制

### 注入攻击

- P0-04: SQL 注入防护
- P2-09: 输入验证

---

## 🧪 测试清单

每个修复后必须验证：

### P0 验证

```bash
# 1. 无密码拒绝启动
unset DB_PASSWORD && dart run main.dart
# 预期：报错退出

# 2. HTTP 被拒绝
curl http://your-server/api/health
# 预期：重定向到 HTTPS 或拒绝

# 3. 未授权来源被拒绝
curl -H "Origin: https://evil.com" https://your-server/api/health
# 预期：无 CORS 头

# 4. SQL 注入失败
# 见各详细 spec 的测试部分
```

### 集成测试

```bash
# 运行完整测试套件
flutter test
dart test server/

# 检查无安全告警
dart analyze --fatal-warnings
```

---

## 📞 获取帮助

### 文档问题

如果某个 spec 不清楚：
1. 查看对应文件中的"测试计划"部分
2. 查看"真实风险场景"了解影响
3. 查看"Linus 式根因分析"理解问题本质

### 实施问题

如果修复过程中遇到问题：
1. 检查"向后兼容性"部分
2. 查看"修复检查清单"确认步骤
3. 参考 [SECURITY_BEST_PRACTICES.md](SECURITY_BEST_PRACTICES.md)

### 优先级调整

如果需要调整优先级：
1. 查看 [THREAT_MODEL.md](THREAT_MODEL.md) 中的风险评估
2. 评估您的实际部署环境
3. 至少完成所有 P0 问题

---

## 🎓 学习资源

### 推荐阅读顺序

1. **初学者**
   ```
   SECURITY_ANALYSIS.md → P0 详细 specs → 开始修复
   ```

2. **有经验开发者**
   ```
   THREAT_MODEL.md → SECURITY_BEST_PRACTICES.md → 所有 specs
   ```

3. **安全专家**
   ```
   THREAT_MODEL.md → 评估是否有遗漏 → 补充威胁
   ```

---

## ✅ 验收标准

### P0 完成标准

修复后系统应满足：

- [x] 代码中无硬编码密码
- [x] 生产环境强制 HTTPS
- [x] CORS 仅允许白名单域名
- [x] 所有 SQL 查询参数化或白名单

### 最终目标

- [x] 所有 12 个问题修复完成
- [x] 所有测试通过
- [x] 代码审查完成
- [x] 部署文档更新
- [x] 团队安全培训完成

---

## 📅 更新记录

| 日期 | 版本 | 变更 |
|------|------|------|
| 2025-10-20 | 1.0 | 初始版本 - 完整安全分析 |

---

**下一步**：阅读 [SECURITY_ANALYSIS.md](SECURITY_ANALYSIS.md) 了解全局情况，然后开始修复 P0-01。

**记住 Linus 的话**：这些不是"可选的改进"，是**必须修复的漏洞**。从 P0 开始，一个一个修，一个一个测，一个一个 commit。
