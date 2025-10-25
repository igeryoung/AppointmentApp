# P2-12: 同步冲突解决无授权检查

> **优先级**: 🟡 P2 - Medium  
> **状态**: ⏸️ 待修复  
> **估计时间**: 1小时  

---

## 📋 问题

任何设备都可以解决任意冲突，无所有权检查

## ✅ 修复

### 检查设备所有权

```dart
Future<void> resolveConflict(ConflictResolutionRequest request) async {
  // 检查设备是否拥有该记录
  final record = await db.querySingle('''
    SELECT device_id FROM ${request.tableName}
    WHERE id = @recordId
  ''', parameters: {'recordId': request.recordId});

  if (record == null) {
    throw Exception('Record not found');
  }

  if (record['device_id'] != request.deviceId) {
    throw Exception('Not authorized to resolve this conflict');
  }

  // 继续处理冲突解决...
}
```

**状态**: ⏸️ 待实现
