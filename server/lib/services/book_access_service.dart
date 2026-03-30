import '../database/connection.dart';

class BookAccessService {
  final DatabaseConnection db;

  BookAccessService(this.db);

  Map<String, dynamic>? _first(dynamic data) {
    if (data is List && data.isNotEmpty) {
      final row = data.first;
      if (row is Map<String, dynamic>) return row;
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  Future<bool> _deviceHasWriteRole(String deviceId) async {
    final deviceRows = await db.client
        .from('devices')
        .select('device_role')
        .eq('id', deviceId)
        .limit(1);
    final deviceRow = _first(deviceRows);
    if (deviceRow == null) return false;
    final role = (deviceRow['device_role'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return role == 'write';
  }

  Future<bool> verifyBookAccess(
    String deviceId,
    String bookUuid, {
    bool requireWrite = false,
  }) async {
    final existingBook = await db.client
        .from('books')
        .select('book_uuid, device_id')
        .eq('book_uuid', bookUuid)
        .eq('is_deleted', false)
        .limit(1);
    final bookRow = _first(existingBook);
    if (bookRow == null) return false;

    final hasWriteRole = await _deviceHasWriteRole(deviceId);
    if (hasWriteRole) {
      return true;
    }

    if (requireWrite) {
      return false;
    }

    if (bookRow['device_id']?.toString() == deviceId) {
      return true;
    }

    final accessRows = await db.client
        .from('book_device_access')
        .select('book_uuid')
        .eq('book_uuid', bookUuid)
        .eq('device_id', deviceId)
        .limit(1);
    final accessRow = _first(accessRows);
    if (accessRow == null) return false;

    return true;
  }

  Future<void> grantBookAccess({
    required String bookUuid,
    required String deviceId,
  }) async {
    await db.client.from('book_device_access').upsert({
      'book_uuid': bookUuid,
      'device_id': deviceId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'book_uuid,device_id');
  }
}
