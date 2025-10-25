# P1-05: Token 永不过期

> **优先级**: 🟠 P1 - High  
> **状态**: ⏸️ 待修复  
> **估计时间**: 2小时  
> **影响范围**: 服务端认证 + 客户端

---

## 📋 问题

**当前**: Token 生成后永久有效，从不过期

**风险**:
- 设备丢失 = 永久数据访问权限
- Token 泄露无法撤销
- 离职员工仍可访问

## ✅ 修复方案

### 1. 数据库添加过期时间

```sql
-- migrations/004_token_expiration.sql
ALTER TABLE devices ADD COLUMN token_expires_at TIMESTAMP;
ALTER TABLE devices ADD COLUMN refresh_token VARCHAR(512);

-- 为现有 Token 设置过期时间（30天后）
UPDATE devices 
SET token_expires_at = CURRENT_TIMESTAMP + INTERVAL '30 days'
WHERE token_expires_at IS NULL;
```

### 2. Token 验证检查过期

```dart
// server/lib/routes/device_routes.dart
Future<bool> _verifyDeviceToken(String deviceId, String token) async {
  final row = await db.querySingle(
    '''
    SELECT device_token, token_expires_at FROM devices 
    WHERE id = @id AND is_active = true
    ''',
    parameters: {'id': deviceId},
  );

  if (row == null) return false;
  
  // 检查 Token 是否过期
  final expiresAt = row['token_expires_at'] as DateTime;
  if (DateTime.now().isAfter(expiresAt)) {
    return false;  // Token 已过期
  }
  
  return row['device_token'] == token;
}
```

### 3. Token 刷新机制

```dart
// 新增 API: /api/devices/refresh-token
Future<Response> _refreshToken(Request request) async {
  final body = jsonDecode(await request.readAsString());
  final deviceId = body['deviceId'];
  final refreshToken = body['refreshToken'];
  
  // 验证 Refresh Token
  final device = await _getDevice(deviceId);
  if (device == null || device.refreshToken != refreshToken) {
    return Response.forbidden('Invalid refresh token');
  }
  
  // 生成新的 Access Token（30天）和 Refresh Token（90天）
  final newToken = _generateToken(deviceId);
  final newRefreshToken = _generateToken('$deviceId:refresh');
  
  await db.query('''
    UPDATE devices 
    SET device_token = @token,
        token_expires_at = CURRENT_TIMESTAMP + INTERVAL '30 days',
        refresh_token = @refreshToken
    WHERE id = @id
  ''', parameters: {
    'token': newToken,
    'refreshToken': newRefreshToken,
    'id': deviceId,
  });
  
  return Response.ok(jsonEncode({
    'deviceToken': newToken,
    'refreshToken': newRefreshToken,
    'expiresAt': DateTime.now().add(Duration(days: 30)).toIso8601String(),
  }));
}
```

### 4. 客户端自动刷新

```dart
// lib/services/sync_service.dart
Future<SyncResult> syncAll() async {
  try {
    return await _performSync();
  } on ApiException catch (e) {
    if (e.statusCode == 401) {
      // Token 过期，尝试刷新
      await _refreshToken();
      return await _performSync();  // 重试
    }
    rethrow;
  }
}

Future<void> _refreshToken() async {
  final deviceInfo = await getDeviceInfo();
  final response = await apiClient.refreshToken(
    deviceId: deviceInfo.deviceId,
    refreshToken: deviceInfo.refreshToken,
  );
  
  // 保存新 Token
  await _saveDeviceInfo(deviceInfo.copyWith(
    deviceToken: response.deviceToken,
    refreshToken: response.refreshToken,
  ));
}
```

## 🧪 测试

1. **过期 Token 被拒绝**: 手动设置过期时间为过去，验证请求失败
2. **未过期 Token 正常工作**: 验证新生成的 Token 可以使用30天
3. **刷新 Token 成功**: 使用 Refresh Token 获取新的 Access Token
4. **客户端自动刷新**: Token 过期时自动刷新后继续工作

## 📊 配置

```bash
# .env
TOKEN_EXPIRY_DAYS=30  # Access Token 有效期
REFRESH_TOKEN_EXPIRY_DAYS=90  # Refresh Token 有效期
```

**状态**: ⏸️ 待实现
