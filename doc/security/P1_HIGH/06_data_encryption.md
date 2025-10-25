# P1-06: 医疗数据无加密存储

> **优先级**: 🟠 P1 - High  
> **状态**: ⏸️ 待修复  
> **估计时间**: 4小时  
> **影响范围**: 客户端 + 服务端

---

## 📋 问题

**当前**: 所有数据（患者姓名、病历号、手写笔记）明文存储在数据库中

**风险**:
- 数据库备份泄露 = 所有患者信息暴露
- 磁盘被盗 = 完整医疗记录可读
- 违反 HIPAA/GDPR 加密要求

## ✅ 修复方案

### 选项 A: 应用层加密（推荐）

**加密敏感字段**: `name`, `record_number`, `strokes_data`

```dart
// lib/services/encryption_service.dart
import 'package:encrypt/encrypt.dart';

class EncryptionService {
  late final Encrypter _encrypter;
  late final IV _iv;

  EncryptionService() {
    // 从安全存储读取密钥（Keychain/KeyStore）
    final key = Key.fromSecureRandom(32);  // AES-256
    _encrypter = Encrypter(AES(key));
    _iv = IV.fromSecureRandom(16);
  }

  String encrypt(String plaintext) {
    return _encrypter.encrypt(plaintext, iv: _iv).base64;
  }

  String decrypt(String ciphertext) {
    return _encrypter.decrypt64(ciphertext, iv: _iv);
  }
}
```

**修改数据模型**:

```dart
// lib/models/event.dart
class Event {
  // ... 现有字段 ...

  // 存储时加密
  static Event fromMap(Map<String, dynamic> map, EncryptionService? encryption) {
    return Event(
      id: map['id'],
      name: encryption?.decrypt(map['name']) ?? map['name'],
      recordNumber: encryption?.decrypt(map['record_number']) ?? map['record_number'],
      // ...
    );
  }

  Map<String, dynamic> toMap(EncryptionService? encryption) {
    return {
      'id': id,
      'name': encryption?.encrypt(name) ?? name,
      'record_number': encryption?.encrypt(recordNumber) ?? recordNumber,
      // ...
    };
  }
}
```

### 选项 B: 数据库级加密

**SQLite**: 使用 `sqlcipher`

```yaml
# pubspec.yaml
dependencies:
  sqflite_sqlcipher: ^2.2.0  # 替换 sqflite
```

```dart
// 初始化加密数据库
final db = await openDatabase(
  path,
  password: userProvidedPassword,  // 用户设置的密码
  // ...
);
```

**PostgreSQL**: 启用透明数据加密（TDE）

```sql
-- 使用 pgcrypto 扩展
CREATE EXTENSION pgcrypto;

-- 创建加密列
ALTER TABLE events ADD COLUMN name_encrypted BYTEA;
UPDATE events SET name_encrypted = pgp_sym_encrypt(name, 'encryption_key');
```

### 推荐：混合方案

- **客户端**: SQLite 使用 SQLCipher（全盘加密）
- **服务端**: PostgreSQL TDE（全盘加密）
- **传输层**: HTTPS（已在 P0-02 修复）

这样实现**三层加密**：存储加密 + 传输加密 + 应用加密

## 🧪 测试

1. **加密后不可读**: 直接读取数据库文件，数据为乱码
2. **正确解密**: 应用正常读取和显示数据
3. **性能影响**: 加密/解密延迟 < 10ms
4. **密钥轮换**: 支持更换加密密钥

## 📊 配置

```bash
# .env
ENABLE_ENCRYPTION=true
# 从安全存储读取，不要硬编码
```

**状态**: ⏸️ 待实现
