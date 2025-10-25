# P1-08: 弱 Token 生成算法

> **优先级**: 🟠 P1 - High  
> **状态**: ⏸️ 待修复  
> **估计时间**: 30分钟  
> **影响范围**: 服务端认证

---

## 📋 问题

**当前**: 使用可预测的输入生成 Token

```dart
// server/lib/routes/device_routes.dart:143
String _generateToken(String deviceId) {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final random = _uuid.v4();  // UUID v4 是伪随机
  final content = '$deviceId:$timestamp:$random';
  final bytes = utf8.encode(content);
  final digest = sha256.convert(bytes);
  return digest.toString();
}
```

**问题**:
- `timestamp` 可预测（当前时间附近）
- UUID v4 不是密码学安全的随机数
- 攻击者可以暴力破解

## ✅ 修复方案

### 使用密码学安全随机数（CSPRNG）

```dart
import 'dart:math';
import 'package:crypto/crypto.dart';

String _generateToken(String deviceId) {
  // 使用密码学安全的随机数生成器
  final random = Random.secure();
  final randomBytes = List<int>.generate(32, (_) => random.nextInt(256));
  
  // 组合设备ID和随机数
  final content = '$deviceId:${base64Encode(randomBytes)}';
  final bytes = utf8.encode(content);
  
  // 使用 SHA-256 哈希
  final digest = sha256.convert(bytes);
  return digest.toString();
}
```

### 更好：使用专用 Token 生成库

```yaml
# pubspec.yaml
dependencies:
  nanoid: ^1.0.0  # 生成密码学安全的 ID
```

```dart
import 'package:nanoid/nanoid.dart';

String _generateToken(String deviceId) {
  // 生成 256位密码学安全的 Token
  final token = nanoid(alphabet: '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', length: 64);
  
  // 可选：结合设备ID进行HMAC签名
  final hmac = Hmac(sha256, utf8.encode(serverSecret));
  final signature = hmac.convert(utf8.encode('$deviceId:$token'));
  
  return '$token.$signature';
}
```

## 🧪 测试

1. **唯一性**: 生成1000万个 Token，无重复
2. **不可预测**: 无法从已知 Token 推测下一个
3. **足够长**: 至少 256位熵

## 📊 比较

| 方法 | 熵 | 安全性 | 性能 |
|------|-----|--------|------|
| 当前（时间戳+UUID） | ~128位 | 弱 | 快 |
| Random.secure() | 256位 | 强 | 快 |
| nanoid(64) | 384位 | 很强 | 快 |
| HMAC签名 | 512位 | 最强 | 中 |

**推荐**: `nanoid` + HMAC 签名（P1-05实现后）

**状态**: ⏸️ 待实现
