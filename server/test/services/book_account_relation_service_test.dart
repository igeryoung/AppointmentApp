import 'package:schedule_note_server/services/book_account_relation_service.dart';
import 'package:test/test.dart';

void main() {
  group('BookAccountRelationService', () {
    test('create, pull, and local delete update account book access', () async {
      final store = _FakeBookAccountRelationStore(
        deviceAccounts: {
          'owner-device': 'owner-account',
          'reader-device': 'reader-account',
        },
      );
      final service = BookAccountRelationService(store);

      await service.recordCreatedBook(
        accountId: 'owner-account',
        bookUuid: 'book-001',
      );

      expect(
        await service.accessedBookUuids('owner-account'),
        contains('book-001'),
      );
      expect(await service.accessedBookUuids('reader-account'), isEmpty);

      final pulled = await service.recordPulledBook(
        deviceId: 'reader-device',
        bookUuid: 'book-001',
      );

      expect(pulled, isTrue);
      expect(
        await service.accessedBookUuids('reader-account'),
        contains('book-001'),
      );
      expect(store.upsertCount('reader-account', 'book-001'), 1);

      await service.recordPulledBook(
        deviceId: 'reader-device',
        bookUuid: 'book-001',
      );

      expect(
        store.upsertCount('reader-account', 'book-001'),
        1,
        reason: 'Pulling an already-related book must be idempotent.',
      );

      await service.removeOwnBookAccess(
        accountId: 'reader-account',
        bookUuid: 'book-001',
      );

      expect(await service.accessedBookUuids('reader-account'), isEmpty);
      expect(
        await service.accessedBookUuids('owner-account'),
        contains('book-001'),
        reason: 'Deleting one local book removes only that account relation.',
      );
    });

    test(
      'pull does not create access when the device has no account',
      () async {
        final store = _FakeBookAccountRelationStore();
        final service = BookAccountRelationService(store);

        final pulled = await service.recordPulledBook(
          deviceId: 'orphan-device',
          bookUuid: 'book-001',
        );

        expect(pulled, isFalse);
        expect(store.allAccess, isEmpty);
      },
    );
  });
}

class _FakeBookAccountRelationStore implements BookAccountRelationStore {
  final Map<String, String> deviceAccounts;
  final Set<_RelationKey> _access = <_RelationKey>{};
  final Map<_RelationKey, int> _upsertCounts = <_RelationKey, int>{};

  _FakeBookAccountRelationStore({Map<String, String>? deviceAccounts})
    : deviceAccounts = deviceAccounts ?? const {};

  Set<_RelationKey> get allAccess => Set<_RelationKey>.of(_access);

  int upsertCount(String accountId, String bookUuid) {
    return _upsertCounts[_RelationKey(accountId, bookUuid)] ?? 0;
  }

  @override
  Future<String?> accountIdForDevice(String deviceId) async {
    return deviceAccounts[deviceId];
  }

  @override
  Future<bool> hasAccess({
    required String accountId,
    required String bookUuid,
  }) async {
    return _access.contains(_RelationKey(accountId, bookUuid));
  }

  @override
  Future<List<String>> listAccessedBookUuids(String accountId) async {
    return _access
        .where((key) => key.accountId == accountId)
        .map((key) => key.bookUuid)
        .toList();
  }

  @override
  Future<void> removeAccess({
    required String accountId,
    required String bookUuid,
  }) async {
    _access.remove(_RelationKey(accountId, bookUuid));
  }

  @override
  Future<void> upsertAccess({
    required String accountId,
    required String bookUuid,
  }) async {
    final key = _RelationKey(accountId, bookUuid);
    _access.add(key);
    _upsertCounts[key] = (_upsertCounts[key] ?? 0) + 1;
  }
}

class _RelationKey {
  final String accountId;
  final String bookUuid;

  const _RelationKey(this.accountId, this.bookUuid);

  @override
  bool operator ==(Object other) {
    return other is _RelationKey &&
        other.accountId == accountId &&
        other.bookUuid == bookUuid;
  }

  @override
  int get hashCode => Object.hash(accountId, bookUuid);
}
