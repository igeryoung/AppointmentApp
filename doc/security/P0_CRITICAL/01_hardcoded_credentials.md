# P0-01: 硬编码的数据库凭证

> **优先级**: 🔴 P0 - Critical
> **状态**: ⏸️ 待修复
> **估计时间**: 30分钟
> **影响范围**: 服务端配置

---

## 📋 问题描述

### 当前状态

**文件**: `server/lib/config/database_config.dart:22-30`

```dart
factory DatabaseConfig.development() {
  return const DatabaseConfig(
    host: 'localhost',
    port: 5433,
    database: 'schedule_note_dev',
    username: 'postgres',
    password: 'postgres',  // 🔴 硬编码明文密码
    maxConnections: 5,
  );
}
```

### 为什么这是问题

1. **代码泄露 = 数据库完全暴露**
   - 代码在 Git 仓库中，任何有访问权限的人都能看到
   - 如果仓库公开或被泄露，密码立即暴露

2. **无法按环境区分**
   - 开发、测试、生产环境使用相同密码
   - 一个环境泄露影响所有环境

3. **无法轮换密码**
   - 修改密码需要修改代码
   - 需要重新部署应用

### 真实风险场景

```
场景 1：恶意员工
- 离职员工仍知道数据库密码
- 可以从家中连接数据库
- 窃取或删除所有患者数据

场景 2：代码泄露
- GitHub 仓库意外公开
- 黑客使用密码连接数据库
- 下载所有医疗数据出售

场景 3：供应链攻击
- 依赖包被污染
- 恶意代码读取配置文件
- 发送数据库凭证到攻击者服务器
```

---

## 🧠 Linus 式根因分析

### 数据结构问题

**当前**：配置是"代码的一部分"
```
Code ──包含──> Config (密码)
  ↓
部署时硬编码
```

**应该**：配置是"运行时参数"
```
Code ──读取──> Environment ──提供──> Config
  ↓                                     ↑
部署时                               运行时设置
```

### 复杂度分析

这不是"需要复杂配置系统"的问题。这是"不要把秘密写在代码里"的基本原则。

**消除特殊情况**：
- ❌ 开发环境用这个密码，生产环境用那个密码
- ✅ 所有环境都从环境变量读取

---

## ✅ 修复方案

### 方案：环境变量化

**原则**：
1. 代码中**零**硬编码秘密
2. 使用操作系统环境变量
3. 提供合理的默认值（仅用于本地开发）

### 修改代码

**文件**: `server/lib/config/database_config.dart`

```dart
factory DatabaseConfig.development() {
  return DatabaseConfig(
    host: _getEnv('DB_HOST', 'localhost'),
    port: int.parse(_getEnv('DB_PORT', '5433')),
    database: _getEnv('DB_NAME', 'schedule_note_dev'),
    username: _getEnv('DB_USER', 'postgres'),
    password: _requireEnv('DB_PASSWORD'),  // 🔴 必须提供，无默认值
    maxConnections: int.parse(_getEnv('DB_MAX_CONNECTIONS', '5')),
  );
}

// 新增：必须提供的环境变量
static String _requireEnv(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) {
    throw Exception('Required environment variable $key is not set');
  }
  return value;
}

// 现有方法保持不变
static String _getEnv(String key, String defaultValue) {
  return Platform.environment[key] ?? defaultValue;
}
```

**关键点**：
- `DB_PASSWORD` **必须**从环境变量读取，无默认值
- 其他参数可以有默认值（方便本地开发）
- 启动时如果缺少 `DB_PASSWORD`，直接报错退出

### 更新启动脚本

**文件**: `server/README.md` 新增环境变量说明

```bash
# 开发环境
export DB_HOST=localhost
export DB_PORT=5433
export DB_NAME=schedule_note_dev
export DB_USER=postgres
export DB_PASSWORD=your_dev_password_here

# 启动服务
dart run main.dart --dev
```

**文件**: `.env.example`（新建）

```bash
# Database Configuration
DB_HOST=localhost
DB_PORT=5433
DB_NAME=schedule_note_dev
DB_USER=postgres
DB_PASSWORD=change_me_in_production

# Server Configuration
SERVER_HOST=0.0.0.0
SERVER_PORT=8080
```

**文件**: `.gitignore`（确保包含）

```
.env
.env.local
*.env
```

### Docker 部署

**文件**: `server/Dockerfile`（如果使用 Docker）

```dockerfile
# 不在 Dockerfile 中设置密码
# 在 docker-compose.yml 或运行时传入

ENV DB_HOST=db
ENV DB_PORT=5432
# DB_PASSWORD 通过 docker run -e 传入
```

---

## 🧪 测试计划

### 测试 1：无密码时拒绝启动

```bash
# 清除环境变量
unset DB_PASSWORD

# 尝试启动服务
dart run main.dart --dev

# 预期结果：
# ❌ Exception: Required environment variable DB_PASSWORD is not set
# 服务拒绝启动
```

### 测试 2：错误密码无法连接

```bash
export DB_PASSWORD=wrong_password
dart run main.dart --dev

# 预期结果：
# ❌ Database connection failed. Please check your configuration.
# 服务优雅退出
```

### 测试 3：正确密码正常运行

```bash
export DB_PASSWORD=postgres  # 实际密码
dart run main.dart --dev

# 预期结果：
# ✅ Database connection established
# ✅ Server listening on 0.0.0.0:8080
```

### 测试 4：代码中无明文密码

```bash
# 搜索代码中的密码
grep -r "password.*postgres" server/lib/

# 预期结果：
# 无匹配（所有密码都来自环境变量）
```

---

## 📦 向后兼容性

### 现有部署

如果已有运行的服务器：

1. **添加环境变量**（不要先改代码）
   ```bash
   # 在服务器上设置环境变量
   echo 'export DB_PASSWORD=current_password' >> ~/.bashrc
   source ~/.bashrc
   ```

2. **更新代码**
   ```bash
   git pull
   # 代码会从环境变量读取密码
   ```

3. **重启服务**
   ```bash
   # 服务重启时使用环境变量中的密码
   ./restart_server.sh
   ```

### 现有客户端

客户端**不受影响**：
- 客户端只连接服务器 API
- 客户端不知道数据库密码
- 无需更新客户端

---

## ✅ 验收标准

- [ ] 代码中无任何硬编码的数据库密码
- [ ] `.env.example` 文件已创建并提交
- [ ] `.env` 文件已加入 `.gitignore`
- [ ] 缺少 `DB_PASSWORD` 时服务拒绝启动
- [ ] README 更新了环境变量设置说明
- [ ] 所有测试通过

---

## 📝 修复检查清单

### 修改前
- [ ] 记录当前所有环境的数据库密码
- [ ] 确认 `.gitignore` 包含 `.env`
- [ ] 备份当前配置

### 修改代码
- [ ] 修改 `DatabaseConfig.development()`
- [ ] 修改 `DatabaseConfig.production()`
- [ ] 添加 `_requireEnv()` 方法
- [ ] 创建 `.env.example`

### 测试验证
- [ ] 无密码时拒绝启动
- [ ] 错误密码无法连接
- [ ] 正确密码正常运行
- [ ] 代码中搜索不到明文密码

### 文档更新
- [ ] 更新 `server/README.md`
- [ ] 更新部署文档
- [ ] 通知团队环境变量设置方法

### 部署
- [ ] 在开发环境设置环境变量
- [ ] 在测试环境设置环境变量
- [ ] 在生产环境设置环境变量
- [ ] 重启所有环境验证

---

## 🔗 相关问题

- [P0-02: HTTPS 强制执行](02_https_enforcement.md) - 传输层加密
- [P1-06: 数据加密存储](../P1_HIGH/06_data_encryption.md) - 存储层加密
- [安全最佳实践](../SECURITY_BEST_PRACTICES.md) - 秘密管理

---

## 📊 状态追踪

| 阶段 | 状态 | 完成时间 | 负责人 |
|------|------|----------|--------|
| 问题确认 | ✅ | 2025-10-20 | Linus |
| 方案设计 | ✅ | 2025-10-20 | Linus |
| 代码修改 | ⏸️ | - | - |
| 测试验证 | ⏸️ | - | - |
| 部署上线 | ⏸️ | - | - |

---

**Linus 说**：这是最基本的安全原则。不要把密码写在代码里。就这么简单。30分钟就能修好。
