# Schedule Note App - 安全分析报告

> **分析人**: Linus Torvalds
> **日期**: 2025-10-20
> **应用类型**: 医疗预约管理系统（包含手写笔记功能）
> **数据敏感度**: 高（医疗数据，受 HIPAA/GDPR 保护）

---

## 🎯 核心判断

### ❌ **当前状态：不适合生产环境**

这不是"理论上的风险"。这是**真实的、可被利用的漏洞**：
1. 硬编码密码 + 开放 CORS = 任何人都能访问数据库
2. 无 HTTPS 强制 = 医疗数据明文传输（违法）
3. Token 永不过期 = 设备丢失等于永久数据泄露

### ✅ **可修复性：简单**

好消息是这些问题都有直接的解决方案，不需要重构架构。

---

## 📊 问题统计

| 优先级 | 数量 | 必须修复时间 | 状态 |
|--------|------|--------------|------|
| 🔴 P0 - Critical | 4 | 立即（1天内） | ⏸️ 0/4 |
| 🟠 P1 - High | 4 | 7天内 | ⏸️ 0/4 |
| 🟡 P2 - Medium | 4 | 30天内 | ⏸️ 0/4 |
| **总计** | **12** | - | **0/12** |

---

## 🔴 P0 - 立即修复（阻断性安全问题）

### 1. 硬编码的数据库凭证
- **文件**: `server/lib/config/database_config.dart:28`
- **问题**: `password: 'postgres'` 明文硬编码
- **风险**: 代码泄露 = 数据库完全暴露
- **详细 Spec**: [P0_CRITICAL/01_hardcoded_credentials.md](P0_CRITICAL/01_hardcoded_credentials.md)

### 2. 无 HTTPS 强制执行
- **文件**: `server/main.dart`, 客户端所有网络调用
- **问题**: 允许 HTTP 连接，医疗数据明文传输
- **风险**: 违反医疗数据保护法规，中间人攻击
- **详细 Spec**: [P0_CRITICAL/02_https_enforcement.md](P0_CRITICAL/02_https_enforcement.md)

### 3. 完全开放的 CORS
- **文件**: `server/main.dart:123`
- **问题**: `Access-Control-Allow-Origin: *`
- **风险**: 任何网站都能调用 API，窃取用户数据
- **详细 Spec**: [P0_CRITICAL/03_cors_vulnerability.md](P0_CRITICAL/03_cors_vulnerability.md)

### 4. SQL 注入风险
- **文件**: `server/lib/services/sync_service.dart:62`
- **问题**: 动态拼接表名，未验证
- **风险**: 执行任意 SQL 命令，完全控制数据库
- **详细 Spec**: [P0_CRITICAL/04_sql_injection_risk.md](P0_CRITICAL/04_sql_injection_risk.md)

---

## 🟠 P1 - 高优先级（7天内）

### 5. Token 永不过期
- **文件**: `server/lib/routes/device_routes.dart`
- **问题**: Token 生成后永久有效
- **风险**: 设备丢失 = 永久数据访问权限
- **详细 Spec**: [P1_HIGH/05_token_expiration.md](P1_HIGH/05_token_expiration.md)

### 6. 医疗数据无加密存储
- **文件**: 所有数据库表
- **问题**: SQLite 和 PostgreSQL 数据明文存储
- **风险**: 数据库文件泄露 = 所有数据暴露
- **详细 Spec**: [P1_HIGH/06_data_encryption.md](P1_HIGH/06_data_encryption.md)

### 7. 无请求速率限制
- **文件**: 所有 API 端点
- **问题**: 无限制调用 API
- **风险**: 暴力破解、DDoS、资源耗尽
- **详细 Spec**: [P1_HIGH/07_rate_limiting.md](P1_HIGH/07_rate_limiting.md)

### 8. 弱 Token 生成算法
- **文件**: `server/lib/routes/device_routes.dart:143`
- **问题**: 使用可预测的输入生成 Token
- **风险**: Token 可被预测或暴力破解
- **详细 Spec**: [P1_HIGH/08_weak_token_generation.md](P1_HIGH/08_weak_token_generation.md)

---

## 🟡 P2 - 中优先级（30天内）

### 9. 缺少输入验证
- **文件**: 多处 API 端点
- **问题**: 参数未验证范围、长度、格式
- **详细 Spec**: [P2_MEDIUM/09_input_validation.md](P2_MEDIUM/09_input_validation.md)

### 10. 设备认证过于简单
- **文件**: 所有 `_verifyDevice` 函数
- **问题**: 仅检查 Token，无额外验证
- **详细 Spec**: [P2_MEDIUM/10_device_authentication.md](P2_MEDIUM/10_device_authentication.md)

### 11. Backup 数据完整性未验证
- **文件**: `lib/services/book_backup_service.dart:183`
- **问题**: 恢复时不验证数据完整性
- **详细 Spec**: [P2_MEDIUM/11_backup_integrity.md](P2_MEDIUM/11_backup_integrity.md)

### 12. 同步冲突解决无授权检查
- **文件**: `server/lib/services/sync_service.dart:221`
- **问题**: 任何设备都可以解决任意冲突
- **详细 Spec**: [P2_MEDIUM/12_conflict_authorization.md](P2_MEDIUM/12_conflict_authorization.md)

---

## 🧠 Linus 式根因分析

### 数据结构问题

```
当前认证模型（过于简单）：
Device ─── has ──→ Token (永久有效)
   ↓
任何数据（无所有权概念）
```

**问题**：
1. 没有"所有权"层：任何设备都能修改任何数据
2. 没有"时间"维度：Token 没有过期时间
3. 没有"范围"限制：Token 有完全权限

**应该是**：
```
Device ─── has ──→ Token (带过期时间)
   ↓                  ↓
  owns            限定范围
   ↓                  ↓
特定 Books ←──────────┘
```

### 复杂度可消除

以下"配置"不应该硬编码，应该是运行时参数：

| 硬编码项 | 应该从哪里来 | 为什么 |
|---------|-------------|--------|
| 数据库密码 | 环境变量 | 安全基本原则 |
| CORS 域名 | 配置文件 | 不同环境不同 |
| 服务端口 | 命令行参数 | 部署灵活性 |
| Token 有效期 | 常量配置 | 业务策略可变 |

这些都是**可以立即消除的特殊情况**。

### 最大风险点

```
风险 = 概率 × 影响

P0#1: 硬编码密码
  概率: 高（代码在 Git 中，任何人都能看到）
  影响: 极高（完全控制数据库）
  优先级: 最高

P0#2: 无 HTTPS
  概率: 中（需要网络访问）
  影响: 极高（违法 + 数据泄露）
  优先级: 最高

P0#3: 开放 CORS
  概率: 高（任何网站都能利用）
  影响: 高（窃取用户数据）
  优先级: 最高
```

---

## ✅ 修复策略

### 阶段 1：P0 修复（1天）

**目标**：消除阻断性安全问题，使应用可以安全测试

1. ✅ 环境变量化所有敏感配置
2. ✅ 强制 HTTPS（服务端拒绝 HTTP）
3. ✅ 限制 CORS 到特定域名
4. ✅ 表名白名单验证

**不破坏向后兼容性**：
- 开发环境仍可用 HTTP（通过环境变量控制）
- 现有 Token 继续有效（先不强制过期）

### 阶段 2：P1 修复（7天）

**目标**：添加纵深防御层，符合医疗数据保护标准

1. Token 过期机制 + 刷新流程
2. 敏感字段加密（手写笔记、患者名）
3. API 速率限制（防暴力破解）
4. 强化 Token 生成（CSPRNG）

**向后兼容**：
- 旧 Token 自动迁移（服务端添加过期时间）
- 未加密数据逐步迁移（后台任务）

### 阶段 3：P2 修复（30天）

**目标**：完善安全体系，添加审计和监控

1. 统一输入验证
2. 设备指纹验证
3. Backup 完整性检查
4. 权限检查细化

---

## 📝 实施检查清单

### 修复前准备
- [ ] 创建安全分支 `security/p0-fixes`
- [ ] 备份生产数据库（如果有）
- [ ] 准备回滚计划

### P0 修复验证
- [ ] 无法用硬编码密码连接数据库
- [ ] HTTP 请求被拒绝
- [ ] 非白名单域名无法调用 API
- [ ] 无法注入 SQL 语句

### P1 修复验证
- [ ] 旧 Token 在设定时间后失效
- [ ] 数据库中敏感字段已加密
- [ ] 超速请求被限流
- [ ] Token 无法被预测

### 文档更新
- [ ] 更新部署文档（环境变量说明）
- [ ] 更新 API 文档（HTTPS 要求）
- [ ] 更新开发者指南（安全最佳实践）

---

## 🔗 相关文档

- [威胁建模](THREAT_MODEL.md) - 详细的攻击场景分析
- [安全最佳实践](SECURITY_BEST_PRACTICES.md) - 开发安全代码指南
- [P0 修复指南](P0_CRITICAL/) - 立即修复问题详细说明
- [P1 修复指南](P1_HIGH/) - 高优先级问题详细说明
- [P2 修复指南](P2_MEDIUM/) - 中优先级问题详细说明

---

## 📞 联系与反馈

如果在修复过程中遇到问题：
1. 检查对应的详细 Spec 文档
2. 查看测试计划是否覆盖场景
3. 记录修复过程中的发现（更新 Spec）

**记住**：安全不是一次性任务，是持续过程。每次修改都要问：
- 这会引入新的安全问题吗？
- 这会破坏现有的安全措施吗？
- 这需要更新安全文档吗？

---

**最后的 Linus 风格总结**：

这些问题都是**真实的**、**可修复的**、**必须修复的**。不要拖延。不要说"等有时间再说"。医疗数据泄露不会等你有时间。

从 P0 开始，一个一个修，一个一个测，一个一个 commit。简单、直接、有效。
