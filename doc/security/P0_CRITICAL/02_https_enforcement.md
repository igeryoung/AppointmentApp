# P0-02: HTTPS 强制执行

> **优先级**: 🔴 P0 - Critical
> **状态**: ⏸️ 待修复
> **估计时间**: 1小时
> **影响范围**: 服务端 + 客户端

---

## 📋 问题描述

### 当前状态

**服务端**：接受任何 HTTP 连接
```dart
// server/main.dart:130
final server = await shelf_io.serve(
  handler,
  serverConfig.host,  // 绑定所有接口
  serverConfig.port,  // 端口 8080（HTTP）
);
// ❌ 没有 HTTPS，没有证书，没有任何加密
```

**客户端**：使用 HTTP URL
```dart
// lib/services/server_config_service.dart:54
Future<String> getServerUrlOrDefault({String defaultUrl = 'http://localhost:8080'}) {
  // ❌ 默认 HTTP，不是 HTTPS
}
```

### 为什么这是问题

1. **医疗数据明文传输**
   - 患者姓名、病历号、预约信息全部明文
   - 手写笔记（可能包含诊断）明文传输
   - 违反 HIPAA、GDPR 等医疗数据保护法规

2. **认证 Token 可被窃取**
   - Device Token 在网络中明文传输
   - 中间人攻击可窃取 Token
   - 攻击者获得完全访问权限

3. **中间人攻击**
   - Wi-Fi 热点可截获所有流量
   - ISP 可读取所有数据
   - 公司代理可记录所有请求

### 真实风险场景

```
场景 1：公共 Wi-Fi
- 医生在咖啡店使用公共 Wi-Fi
- 黑客运行抓包工具（Wireshark）
- 捕获所有患者数据和 Device Token
- 使用 Token 访问完整数据库

场景 2：医院网络
- 医院 IT 部门监控网络流量
- 所有预约数据被记录
- 员工可查看任何医生的患者信息
- 违反患者隐私权

场景 3：移动网络
- 电信运营商记录 HTTP 流量
- 数据被用于广告定向
- 患者医疗信息泄露给第三方
```

---

## 🧠 Linus 式根因分析

### 数据结构问题

**当前**：没有"传输层"概念
```
Client ──HTTP (明文)──> Server
   ↓
医疗数据裸奔
```

**应该**：传输层必须加密
```
Client ──TLS 加密──> Server
   ↓
医疗数据加密管道
```

### 复杂度分析

这不是"可选的安全功能"，这是**基础要求**。就像你不会建一个没有门的房子。

**消除特殊情况**：
- ❌ 生产环境用 HTTPS，开发环境用 HTTP
- ✅ 所有环境强制 HTTPS（开发环境用自签名证书）

**为什么有人用 HTTP？**
- "HTTPS 太复杂" → ❌ Let's Encrypt 免费证书，5分钟配置
- "开发环境不需要" → ❌ 开发环境泄露数据一样违法
- "性能开销大" → ❌ TLS 1.3 开销可忽略

---

## ✅ 修复方案

### 阶段 1：服务端强制 HTTPS（生产环境）

#### 1.1 获取 SSL 证书

**选项 A：Let's Encrypt（推荐，免费）**
```bash
# 使用 certbot
sudo certbot certonly --standalone -d your-domain.com

# 证书位置
/etc/letsencrypt/live/your-domain.com/fullchain.pem
/etc/letsencrypt/live/your-domain.com/privkey.pem
```

**选项 B：自签名证书（仅开发环境）**
```bash
# 生成自签名证书
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes \
  -subj "/CN=localhost"
```

#### 1.2 修改服务端代码

**文件**：`server/lib/config/database_config.dart`（新增 SSL 配置）

```dart
class ServerConfig {
  final String host;
  final int port;
  final bool isDevelopment;
  final bool enableSSL;  // 🆕 新增
  final String? certPath;  // 🆕 证书路径
  final String? keyPath;   // 🆕 私钥路径

  const ServerConfig({
    required this.host,
    required this.port,
    this.isDevelopment = true,
    this.enableSSL = false,
    this.certPath,
    this.keyPath,
  });

  factory ServerConfig.production() {
    final enableSSL = Platform.environment['ENABLE_SSL'] != 'false';  // 默认启用
    return ServerConfig(
      host: Platform.environment['SERVER_HOST'] ?? '0.0.0.0',
      port: int.parse(Platform.environment['SERVER_PORT'] ?? '443'),  // HTTPS 默认端口
      isDevelopment: false,
      enableSSL: enableSSL,
      certPath: Platform.environment['SSL_CERT_PATH'],
      keyPath: Platform.environment['SSL_KEY_PATH'],
    );
  }
}
```

**文件**：`server/main.dart`

```dart
import 'dart:io';

void main(List<String> args) async {
  // ... 现有代码 ...

  final serverConfig = isDevelopment
      ? ServerConfig.development()
      : ServerConfig.production();

  // 🆕 HTTPS 支持
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_errorHandler())
      .addMiddleware(_httpsRedirectMiddleware(serverConfig))  // 🆕 HTTP 重定向到 HTTPS
      .addMiddleware(corsHeaders(headers: {
        'Access-Control-Allow-Origin': '*',  // TODO: P0-03 将修复此问题
      }))
      .addHandler(app);

  HttpServer server;
  if (serverConfig.enableSSL) {
    // HTTPS 模式
    final context = SecurityContext()
      ..useCertificateChain(serverConfig.certPath!)
      ..usePrivateKey(serverConfig.keyPath!);

    server = await HttpServer.bindSecure(
      serverConfig.host,
      serverConfig.port,
      context,
    );

    print('✅ HTTPS enabled');
  } else {
    // HTTP 模式（仅开发环境）
    if (!serverConfig.isDevelopment) {
      print('⚠️  WARNING: Running production server without HTTPS!');
      print('   This is INSECURE and violates medical data protection laws.');
      print('   Set ENABLE_SSL=true and provide SSL_CERT_PATH and SSL_KEY_PATH.');
      exit(1);  // 🔴 生产环境拒绝启动
    }

    server = await HttpServer.bind(serverConfig.host, serverConfig.port);
    print('⚠️  HTTP mode (development only)');
  }

  serveRequests(server, handler);

  print('✅ Server listening on ${server.address.host}:${server.port}');
  // ... 现有代码 ...
}

// 🆕 HTTP 重定向中间件
Middleware _httpsRedirectMiddleware(ServerConfig config) {
  return (Handler handler) {
    return (Request request) async {
      // 如果启用了 SSL 但请求是 HTTP，重定向到 HTTPS
      if (config.enableSSL && request.url.scheme == 'http') {
        final httpsUrl = request.requestedUri.replace(scheme: 'https');
        return Response.movedPermanently(httpsUrl.toString());
      }
      return handler(request);
    };
  };
}
```

### 阶段 2：客户端强制 HTTPS

#### 2.1 修改默认 URL

**文件**：`lib/services/server_config_service.dart`

```dart
Future<String> getServerUrlOrDefault({
  String defaultUrl = 'https://localhost:8443'  // 🔴 改为 HTTPS
}) async {
  final url = await getServerUrl();

  // 🆕 验证 URL 必须是 HTTPS（生产环境）
  if (url != null && !url.startsWith('https://')) {
    if (!kDebugMode) {
      throw Exception('Production app requires HTTPS URL, got: $url');
    }
    debugPrint('⚠️  WARNING: Using HTTP URL in debug mode: $url');
  }

  return url ?? defaultUrl;
}
```

#### 2.2 添加证书固定（Certificate Pinning）

**文件**：`lib/services/api_client.dart`

```dart
import 'dart:io';

class ApiClient {
  final String baseUrl;
  final Duration timeout;
  late final http.Client _client;  // 🆕 持久化 HTTP 客户端

  ApiClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
  }) {
    _client = _createHttpClient();

    // 🆕 验证 URL
    if (!baseUrl.startsWith('https://') && !kDebugMode) {
      throw ArgumentError('Production API client requires HTTPS URL');
    }
  }

  // 🆕 创建支持证书验证的 HTTP 客户端
  http.Client _createHttpClient() {
    final client = HttpClient();

    // 开发环境：允许自签名证书
    if (kDebugMode) {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        debugPrint('⚠️  Accepting self-signed certificate for $host (DEBUG MODE)');
        return true;
      };
    } else {
      // 生产环境：严格证书验证
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        debugPrint('❌ Invalid certificate for $host');
        return false;
      };
    }

    return IOClient(client);
  }

  // 修改所有 HTTP 请求使用 _client
  Future<DeviceRegisterResponse> registerDevice({
    required String deviceName,
    String? platform,
  }) async {
    try {
      final request = DeviceRegisterRequest(
        deviceName: deviceName,
        platform: platform,
      );

      final response = await _client  // 🔴 使用 _client 而不是 http
          .post(
            Uri.parse('$baseUrl/api/devices/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout);

      // ... 现有代码 ...
    } catch (e) {
      // ... 现有代码 ...
    }
  }

  // ... 其他方法类似修改 ...
}
```

### 阶段 3：环境配置

**文件**：`.env.example`（更新）

```bash
# Server Configuration
SERVER_HOST=0.0.0.0
SERVER_PORT=443  # HTTPS 默认端口

# SSL Configuration (Production)
ENABLE_SSL=true
SSL_CERT_PATH=/etc/letsencrypt/live/your-domain.com/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/your-domain.com/privkey.pem

# Development (HTTP for local testing)
# ENABLE_SSL=false
# SERVER_PORT=8080
```

---

## 🧪 测试计划

### 测试 1：生产环境拒绝 HTTP

```bash
# 设置生产环境但不启用 SSL
export ENABLE_SSL=false
dart run main.dart  # 不加 --dev

# 预期结果：
# ⚠️  WARNING: Running production server without HTTPS!
# ❌ 进程退出，代码 1
```

### 测试 2：HTTPS 正常运行

```bash
# 配置 SSL
export ENABLE_SSL=true
export SSL_CERT_PATH=./cert.pem
export SSL_KEY_PATH=./key.pem
dart run main.dart

# 预期结果：
# ✅ HTTPS enabled
# ✅ Server listening on 0.0.0.0:443
```

### 测试 3：客户端拒绝 HTTP（生产环境）

```dart
// 模拟生产环境
void testProductionHttpRejection() {
  // 设置 kDebugMode = false (release build)
  final apiClient = ApiClient(
    baseUrl: 'http://example.com',  // HTTP URL
  );

  // 预期结果：
  // ❌ ArgumentError: Production API client requires HTTPS URL
}
```

### 测试 4：证书验证

```bash
# 使用无效证书
curl https://localhost:443 --insecure

# 预期结果：
# ⚠️  客户端拒绝连接（生产环境）
# ✅ 开发环境接受自签名证书
```

---

## 📦 向后兼容性

### 现有客户端

**问题**：现有客户端使用 HTTP URL

**解决方案**：
1. **服务端同时支持 HTTP 和 HTTPS（过渡期）**
   ```bash
   # HTTP 端口重定向到 HTTPS
   # 使用 Nginx 或 Apache 反向代理
   ```

2. **客户端自动升级 URL**
   ```dart
   // 自动将 http:// 转换为 https://
   String _upgradeToHttps(String url) {
     if (url.startsWith('http://') && !kDebugMode) {
       return url.replaceFirst('http://', 'https://');
     }
     return url;
   }
   ```

3. **发送通知提醒用户更新**
   - 检测到 HTTP URL 时显示警告
   - 引导用户更新服务器地址

### 开发环境

开发环境继续支持 HTTP（通过 `--dev` 参数）：
```bash
# 开发模式（HTTP）
dart run main.dart --dev

# 生产模式（HTTPS 必须）
dart run main.dart
```

---

## ✅ 验收标准

- [ ] 生产环境无 SSL 时拒绝启动
- [ ] HTTPS 连接正常工作
- [ ] HTTP 请求自动重定向到 HTTPS
- [ ] 客户端拒绝 HTTP URL（生产环境）
- [ ] 证书验证正常工作
- [ ] 开发环境可使用自签名证书
- [ ] README 更新了 SSL 配置说明

---

## 📝 修复检查清单

### 准备工作
- [ ] 获取 SSL 证书（Let's Encrypt 或购买）
- [ ] 配置 DNS 指向服务器
- [ ] 备份当前服务器配置

### 服务端修改
- [ ] 添加 SSL 配置到 `ServerConfig`
- [ ] 修改 `main.dart` 支持 HTTPS
- [ ] 添加 HTTP 重定向中间件
- [ ] 生产环境拒绝 HTTP 启动

### 客户端修改
- [ ] 修改默认 URL 为 HTTPS
- [ ] 添加 URL 验证
- [ ] 实现证书验证
- [ ] 处理自签名证书（开发环境）

### 测试验证
- [ ] 生产环境无 SSL 时拒绝启动
- [ ] HTTPS 连接成功
- [ ] HTTP 自动重定向
- [ ] 证书验证工作正常

### 部署
- [ ] 更新服务器环境变量
- [ ] 配置 SSL 证书路径
- [ ] 重启服务验证
- [ ] 测试客户端连接

---

## 🔗 相关问题

- [P0-01: 硬编码凭证](01_hardcoded_credentials.md) - 密码安全
- [P1-06: 数据加密存储](../P1_HIGH/06_data_encryption.md) - 存储加密
- [P2-10: 设备认证增强](../P2_MEDIUM/10_device_authentication.md) - 认证安全

---

## 📊 状态追踪

| 阶段 | 状态 | 完成时间 | 负责人 |
|------|------|----------|--------|
| 问题确认 | ✅ | 2025-10-20 | Linus |
| 方案设计 | ✅ | 2025-10-20 | Linus |
| 证书准备 | ⏸️ | - | - |
| 服务端修改 | ⏸️ | - | - |
| 客户端修改 | ⏸️ | - | - |
| 测试验证 | ⏸️ | - | - |
| 部署上线 | ⏸️ | - | - |

---

**Linus 说**：医疗数据不加密传输就是犯罪。不要找借口。上 Let's Encrypt，5分钟搞定。就这么简单。
