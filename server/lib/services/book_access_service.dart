import '../database/connection.dart';

class BookAccessService {
  static const String accessRead = 'read';
  static const String accessWrite = 'write';
  static const String accessOwner = 'owner';
  static const String accessPulled = 'pulled';

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

  String normalizeAccessType(dynamic value, {String fallback = accessRead}) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == accessOwner) return accessOwner;
    if (normalized == accessWrite) return accessWrite;
    if (normalized == accessRead || normalized == accessPulled) {
      return accessRead;
    }
    return fallback;
  }

  bool isWriteAccessType(String accessType) {
    final normalized = normalizeAccessType(accessType);
    return normalized == accessOwner || normalized == accessWrite;
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

    if (bookRow['device_id']?.toString() == deviceId) {
      return true;
    }

    final accessRows = await db.client
        .from('book_device_access')
        .select('access_type')
        .eq('book_uuid', bookUuid)
        .eq('device_id', deviceId)
        .limit(1);
    final accessRow = _first(accessRows);
    if (accessRow == null) return false;

    if (!requireWrite) return true;
    final rawAccessType = accessRow['access_type']?.toString() ?? accessRead;
    if (isWriteAccessType(rawAccessType)) {
      return true;
    }

    // Pulled access is implicit and should follow the device role.
    // Explicit read access remains read-only until the owner upgrades it.
    if (rawAccessType.trim().toLowerCase() == accessPulled) {
      return _deviceHasWriteRole(deviceId);
    }

    return false;
  }

  Future<void> grantBookAccess({
    required String bookUuid,
    required String deviceId,
    required String accessType,
  }) async {
    final normalized = normalizeAccessType(accessType, fallback: accessRead);
    await db.client.from('book_device_access').upsert({
      'book_uuid': bookUuid,
      'device_id': deviceId,
      'access_type': normalized,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'book_uuid,device_id');
  }
}
