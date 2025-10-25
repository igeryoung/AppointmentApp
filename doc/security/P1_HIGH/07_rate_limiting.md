# P1-07: 无请求速率限制

> **优先级**: 🟠 P1 - High  
> **状态**: ⏸️ 待修复  
> **估计时间**: 2小时  
> **影响范围**: 服务端

---

## 📋 问题

**当前**: 所有 API 端点无速率限制，可无限调用

**风险**:
- 暴力破解 Device Token
- DDoS 攻击耗尽资源
- 数据库连接池耗尽

## ✅ 修复方案

### 使用 `shelf_rate_limiter`

```yaml
# server/pubspec.yaml
dependencies:
  shelf_rate_limiter: ^0.1.0
```

```dart
// server/main.dart
import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';

void main() async {
  // 全局速率限制：每IP 100请求/分钟
  final rateLimiter = RateLimiter(
    maxRequests: 100,
    windowSize: Duration(minutes: 1),
    keyExtractor: (request) => request.headers['x-forwarded-for'] ?? 
                               request.connectionInfo?.remoteAddress.address ?? 
                               'unknown',
  );

  final handler = Pipeline()
      .addMiddleware(rateLimiter.middleware())
      .addMiddleware(logRequests())
      // ... 其他中间件 ...
      .addHandler(app);
}
```

### 分级限速

```dart
// 不同端点不同限制
final authRateLimiter = RateLimiter(
  maxRequests: 5,  // 认证端点：5次/分钟
  windowSize: Duration(minutes: 1),
);

final syncRateLimiter = RateLimiter(
  maxRequests: 30,  // 同步端点：30次/分钟
  windowSize: Duration(minutes: 1),
);

// 应用到特定路由
router.post('/api/devices/register', 
  (req) => authRateLimiter.check(req, _registerDevice));
router.post('/api/sync/full', 
  (req) => syncRateLimiter.check(req, _fullSync));
```

### 按设备限速

```dart
// 使用 Device ID 而不是 IP
final deviceRateLimiter = RateLimiter(
  keyExtractor: (request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body);
    return json['deviceId'] ?? 'unknown';
  },
);
```

## 🧪 测试

1. **超限被拒绝**: 连续请求101次，第101次返回 429
2. **窗口重置**: 等待1分钟后，可以再次请求
3. **不同IP独立**: IP A超限不影响IP B

## 📊 配置

```bash
# .env
RATE_LIMIT_MAX_REQUESTS=100
RATE_LIMIT_WINDOW_MINUTES=1
AUTH_RATE_LIMIT_MAX_REQUESTS=5
```

**状态**: ⏸️ 待实现
