import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/cache_policy.dart';
import 'package:schedule_note_app/services/prd_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('CachePolicy Database Tests', () {
    late PRDDatabaseService db;

    setUp(() async {
      // Reset singleton before each test
      PRDDatabaseService.resetInstance();
      db = PRDDatabaseService();
      // Trigger database initialization
      await db.database;
    });

    tearDown(() async {
      await db.close();
      PRDDatabaseService.resetInstance();
    });

    test('getCachePolicy returns default policy after v8 migration', () async {
      final policy = await db.getCachePolicy();

      expect(policy.maxCacheSizeMb, 50);
      expect(policy.cacheDurationDays, 7);
      expect(policy.autoCleanup, true);
    });

    test('updateCachePolicy modifies values', () async {
      final customPolicy = CachePolicy(
        maxCacheSizeMb: 100,
        cacheDurationDays: 14,
        autoCleanup: false,
      );

      await db.updateCachePolicy(customPolicy);

      final retrieved = await db.getCachePolicy();

      expect(retrieved.maxCacheSizeMb, 100);
      expect(retrieved.cacheDurationDays, 14);
      expect(retrieved.autoCleanup, false);
    });

    test('updateCachePolicy persists lastCleanupAt', () async {
      final now = DateTime.now();
      final policy = CachePolicy(
        maxCacheSizeMb: 50,
        cacheDurationDays: 7,
        autoCleanup: true,
        lastCleanupAt: now,
      );

      await db.updateCachePolicy(policy);

      final retrieved = await db.getCachePolicy();

      // Compare with second precision (database stores seconds)
      expect(retrieved.lastCleanupAt, isNotNull);
      expect(
        retrieved.lastCleanupAt!.millisecondsSinceEpoch ~/ 1000,
        now.millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('multiple updates work correctly', () async {
      final policy1 = CachePolicy.aggressive();
      await db.updateCachePolicy(policy1);

      final retrieved1 = await db.getCachePolicy();
      expect(retrieved1.maxCacheSizeMb, 20);

      final policy2 = CachePolicy.relaxed();
      await db.updateCachePolicy(policy2);

      final retrieved2 = await db.getCachePolicy();
      expect(retrieved2.maxCacheSizeMb, 100);
    });

    test('cache_policy table only has one row', () async {
      await db.updateCachePolicy(CachePolicy.aggressive());
      await db.updateCachePolicy(CachePolicy.relaxed());

      final database = await db.database;
      final result = await database.rawQuery('SELECT COUNT(*) FROM cache_policy');
      final count = result.first.values.first as int;

      expect(count, 1); // Should always be 1 row
    });

    test('factory constructors can be saved and retrieved', () async {
      final factories = [
        CachePolicy.defaultPolicy(),
        CachePolicy.aggressive(),
        CachePolicy.relaxed(),
      ];

      for (final policy in factories) {
        await db.updateCachePolicy(policy);
        final retrieved = await db.getCachePolicy();

        expect(retrieved.maxCacheSizeMb, policy.maxCacheSizeMb);
        expect(retrieved.cacheDurationDays, policy.cacheDurationDays);
        expect(retrieved.autoCleanup, policy.autoCleanup);
      }
    });

    test('copyWith results can be saved', () async {
      final original = await db.getCachePolicy();
      final modified = original.copyWith(maxCacheSizeMb: 200);

      await db.updateCachePolicy(modified);

      final retrieved = await db.getCachePolicy();
      expect(retrieved.maxCacheSizeMb, 200);
      expect(retrieved.cacheDurationDays, original.cacheDurationDays);
    });
  });
}
