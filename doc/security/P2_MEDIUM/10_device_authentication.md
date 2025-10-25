# P2-10: 设备认证过于简单

> **优先级**: 🟡 P2 - Medium  
> **状态**: ⏸️ 待修复  
> **估计时间**: 4小时  

---

## 📋 问题

`_verifyDevice` 仅检查 Token 是否匹配，无二次验证

## ✅ 修复

### 添加设备指纹

```dart
class DeviceFingerprint {
  final String platform;
  final String osVersion;
  final String appVersion;
  
  String hash() {
    return sha256.convert(utf8.encode('$platform:$osVersion:$appVersion')).toString();
  }
}

// 注册时保存指纹
await db.query('''
  INSERT INTO devices (id, device_token, device_fingerprint)
  VALUES (@id, @token, @fingerprint)
''');

// 验证时检查指纹
Future<bool> _verifyDevice(String deviceId, String token, String fingerprint) async {
  final row = await db.querySingle('SELECT * FROM devices WHERE id = @id');
  return row['device_token'] == token && 
         row['device_fingerprint'] == fingerprint;
}
```

**状态**: ⏸️ 待实现
