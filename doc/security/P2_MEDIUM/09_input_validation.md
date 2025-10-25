# P2-09: 缺少输入验证

> **优先级**: 🟡 P2 - Medium  
> **状态**: ⏸️ 待修复  
> **估计时间**: 3小时  

---

## 📋 问题

多处 API 端点参数未验证：
- `bookId`, `backupId` 无范围检查
- `backupName` 无长度限制
- JSON 数据无结构验证

## ✅ 修复

### 统一验证中间件

```dart
class RequestValidator {
  static void validateBookId(int? id) {
    if (id == null || id <= 0) {
      throw ValidationException('Invalid book ID');
    }
  }

  static void validateBackupName(String? name) {
    if (name == null || name.isEmpty) {
      throw ValidationException('Backup name required');
    }
    if (name.length > 255) {
      throw ValidationException('Backup name too long');
    }
  }

  static void validateDeviceId(String? id) {
    if (id == null || !RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw ValidationException('Invalid device ID format');
    }
  }
}
```

**状态**: ⏸️ 待实现
