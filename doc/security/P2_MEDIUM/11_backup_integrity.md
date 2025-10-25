# P2-11: Backup 数据完整性未验证

> **优先级**: 🟡 P2 - Medium  
> **状态**: ⏸️ 待修复  
> **估计时间**: 2小时  

---

## 📋 问题

恢复 Backup 时不验证数据完整性，可能导入恶意数据

## ✅ 修复

### 添加 Checksum

```dart
// 上传时计算checksum
String _calculateChecksum(Map<String, dynamic> data) {
  final json = jsonEncode(data);
  return sha256.convert(utf8.encode(json)).toString();
}

await db.query('''
  INSERT INTO book_backups (device_id, backup_data, checksum)
  VALUES (@deviceId, @data, @checksum)
''');

// 下载时验证checksum
final backupData = jsonDecode(response['backup_data']);
final expectedChecksum = response['checksum'];
final actualChecksum = _calculateChecksum(backupData);

if (actualChecksum != expectedChecksum) {
  throw Exception('Backup data corrupted');
}
```

**状态**: ⏸️ 待实现
