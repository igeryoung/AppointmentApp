import '../database/connection.dart';

abstract class BookAccountRelationStore {
  Future<String?> accountIdForDevice(String deviceId);

  Future<bool> hasAccess({required String accountId, required String bookUuid});

  Future<List<String>> listAccessedBookUuids(String accountId);

  Future<void> upsertAccess({
    required String accountId,
    required String bookUuid,
  });

  Future<void> removeAccess({
    required String accountId,
    required String bookUuid,
  });
}

class SupabaseBookAccountRelationStore implements BookAccountRelationStore {
  final DatabaseConnection db;

  SupabaseBookAccountRelationStore(this.db);

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

  @override
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

  @override
  Future<bool> hasAccess({
    required String accountId,
    required String bookUuid,
  }) async {
    final rows = await db.client
        .from('account_book_access')
        .select('book_uuid')
        .eq('book_uuid', bookUuid)
        .eq('account_id', accountId)
        .limit(1);
    return _first(rows) != null;
  }

  @override
  Future<List<String>> listAccessedBookUuids(String accountId) async {
    final rows = await db.client
        .from('account_book_access')
        .select('book_uuid')
        .eq('account_id', accountId);
    return _rows(rows)
        .map((row) => row['book_uuid']?.toString() ?? '')
        .where((uuid) => uuid.isNotEmpty)
        .toList();
  }

  @override
  Future<void> upsertAccess({
    required String accountId,
    required String bookUuid,
  }) async {
    await db.client.from('account_book_access').upsert({
      'book_uuid': bookUuid,
      'account_id': accountId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'book_uuid,account_id');
  }

  @override
  Future<void> removeAccess({
    required String accountId,
    required String bookUuid,
  }) async {
    await db.client
        .from('account_book_access')
        .delete()
        .eq('account_id', accountId)
        .eq('book_uuid', bookUuid);
  }
}

class BookAccountRelationService {
  final BookAccountRelationStore _store;

  BookAccountRelationService(this._store);

  Future<void> recordCreatedBook({
    required String accountId,
    required String bookUuid,
  }) async {
    await _store.upsertAccess(accountId: accountId, bookUuid: bookUuid);
  }

  Future<bool> recordPulledBook({
    required String deviceId,
    required String bookUuid,
  }) async {
    final accountId = await _store.accountIdForDevice(deviceId);
    if (accountId == null) return false;
    final existing = await _store.hasAccess(
      accountId: accountId,
      bookUuid: bookUuid,
    );
    if (!existing) {
      await _store.upsertAccess(accountId: accountId, bookUuid: bookUuid);
    }
    return true;
  }

  Future<List<String>> accessedBookUuids(String accountId) {
    return _store.listAccessedBookUuids(accountId);
  }

  Future<void> removeOwnBookAccess({
    required String accountId,
    required String bookUuid,
  }) async {
    await _store.removeAccess(accountId: accountId, bookUuid: bookUuid);
  }
}
