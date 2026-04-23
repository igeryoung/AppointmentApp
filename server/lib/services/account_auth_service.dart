import '../database/connection.dart';

class AuthenticatedSession {
  final String deviceId;
  final String deviceToken;
  final String accountId;
  final String username;
  final String accountRole;

  const AuthenticatedSession({
    required this.deviceId,
    required this.deviceToken,
    required this.accountId,
    required this.username,
    required this.accountRole,
  });

  bool get canWrite => accountRole == AccountAuthService.roleWrite;
  bool get isReadOnly => accountRole == AccountAuthService.roleRead;
}

class AccountAuthService {
  static const roleRead = 'read';
  static const roleWrite = 'write';

  final DatabaseConnection db;

  AccountAuthService(this.db);

  Map<String, dynamic>? _first(dynamic data) {
    if (data is List && data.isNotEmpty) {
      final row = data.first;
      if (row is Map<String, dynamic>) return row;
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String normalizeRole(dynamic value, {String fallback = roleRead}) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == roleRead) return roleRead;
    if (normalized == roleWrite) return roleWrite;
    return fallback;
  }

  Future<AuthenticatedSession?> authenticateDevice(
    String deviceId,
    String deviceToken,
  ) async {
    final deviceRows = await db.client
        .from('devices')
        .select('id, device_token, is_active, account_id')
        .eq('id', deviceId)
        .limit(1);
    final device = _first(deviceRows);
    if (device == null) return null;
    if (device['is_active'] != true) return null;
    if ((device['device_token'] ?? '').toString() != deviceToken) return null;

    final accountId = device['account_id']?.toString() ?? '';
    if (accountId.isEmpty) return null;

    final accountRows = await db.client
        .from('accounts')
        .select('id, username, account_role, is_active')
        .eq('id', accountId)
        .limit(1);
    final account = _first(accountRows);
    if (account == null || account['is_active'] != true) return null;

    return AuthenticatedSession(
      deviceId: deviceId,
      deviceToken: deviceToken,
      accountId: accountId,
      username: account['username']?.toString() ?? '',
      accountRole: normalizeRole(account['account_role']),
    );
  }

  Future<bool> verifyDeviceAccess(String deviceId, String token) async {
    try {
      return await authenticateDevice(deviceId, token) != null;
    } catch (_) {
      return false;
    }
  }

  Future<String> getAccountRoleForDevice(String deviceId) async {
    try {
      final deviceRows = await db.client
          .from('devices')
          .select('account_id')
          .eq('id', deviceId)
          .limit(1);
      final device = _first(deviceRows);
      final accountId = device?['account_id']?.toString() ?? '';
      if (accountId.isEmpty) return roleRead;

      final accountRows = await db.client
          .from('accounts')
          .select('account_role, is_active')
          .eq('id', accountId)
          .limit(1);
      final account = _first(accountRows);
      if (account == null || account['is_active'] != true) return roleRead;
      return normalizeRole(account['account_role']);
    } catch (_) {
      return roleRead;
    }
  }

  Future<bool> canDeviceWrite(String deviceId) async {
    return await getAccountRoleForDevice(deviceId) == roleWrite;
  }

  Future<String?> accountIdForDevice(String deviceId) async {
    final rows = await db.client
        .from('devices')
        .select('account_id, is_active')
        .eq('id', deviceId)
        .limit(1);
    final row = _first(rows);
    if (row == null || row['is_active'] != true) return null;
    final accountId = row['account_id']?.toString() ?? '';
    return accountId.isEmpty ? null : accountId;
  }

  Future<bool> verifyBookAccess(
    String deviceId,
    String bookUuid, {
    bool requireWrite = false,
  }) async {
    final accountId = await accountIdForDevice(deviceId);
    if (accountId == null) return false;

    final bookRows = await db.client
        .from('books')
        .select('book_uuid, owner_account_id, is_deleted')
        .eq('book_uuid', bookUuid)
        .eq('is_deleted', false)
        .limit(1);
    final book = _first(bookRows);
    if (book == null) return false;

    final role = await getAccountRoleForDevice(deviceId);
    if (role == roleWrite) return true;
    if (requireWrite) return false;

    if (book['owner_account_id']?.toString() == accountId) return true;

    final accessRows = await db.client
        .from('account_book_access')
        .select('book_uuid')
        .eq('book_uuid', bookUuid)
        .eq('account_id', accountId)
        .limit(1);
    return _first(accessRows) != null;
  }

  Future<void> grantBookAccessToDevice({
    required String bookUuid,
    required String deviceId,
  }) async {
    final accountId = await accountIdForDevice(deviceId);
    if (accountId == null) {
      throw Exception('Target device is not linked to an active account');
    }
    await grantBookAccessToAccount(bookUuid: bookUuid, accountId: accountId);
  }

  Future<void> grantBookAccessToAccount({
    required String bookUuid,
    required String accountId,
  }) async {
    await db.client.from('account_book_access').upsert({
      'book_uuid': bookUuid,
      'account_id': accountId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'book_uuid,account_id');
  }

  Future<Set<String>> accessibleBookUuidsForDevice(String deviceId) async {
    final accountId = await accountIdForDevice(deviceId);
    if (accountId == null) return <String>{};

    final role = await getAccountRoleForDevice(deviceId);
    if (role == roleWrite) {
      final allRows = await db.client
          .from('books')
          .select('book_uuid')
          .eq('is_deleted', false);
      return _rows(allRows)
          .map((row) => row['book_uuid']?.toString() ?? '')
          .where((uuid) => uuid.isNotEmpty)
          .toSet();
    }

    final ownedRows = await db.client
        .from('books')
        .select('book_uuid')
        .eq('owner_account_id', accountId)
        .eq('is_deleted', false);
    final accessRows = await db.client
        .from('account_book_access')
        .select('book_uuid')
        .eq('account_id', accountId);

    final result = <String>{};
    for (final row in _rows(ownedRows)) {
      final uuid = row['book_uuid']?.toString();
      if (uuid != null && uuid.isNotEmpty) result.add(uuid);
    }
    for (final row in _rows(accessRows)) {
      final uuid = row['book_uuid']?.toString();
      if (uuid != null && uuid.isNotEmpty) result.add(uuid);
    }
    return result;
  }
}
