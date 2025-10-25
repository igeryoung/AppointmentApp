import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/cache_policy.dart';

void main() {
  group('CachePolicy Model Tests', () {
    test('toMap and fromMap round-trip preserves all fields', () {
      final now = DateTime.now();
      final policy = CachePolicy(
        maxCacheSizeMb: 75,
        cacheDurationDays: 10,
        autoCleanup: false,
        lastCleanupAt: now,
      );

      final map = policy.toMap();
      final restored = CachePolicy.fromMap(map);

      expect(restored.maxCacheSizeMb, policy.maxCacheSizeMb);
      expect(restored.cacheDurationDays, policy.cacheDurationDays);
      expect(restored.autoCleanup, policy.autoCleanup);
      // DateTime comparison with second precision (database stores seconds)
      expect(restored.lastCleanupAt, isNotNull);
      expect(policy.lastCleanupAt, isNotNull);
      expect(
        restored.lastCleanupAt!.millisecondsSinceEpoch ~/ 1000,
        policy.lastCleanupAt!.millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('toMap and fromMap handles null lastCleanupAt', () {
      final policy = CachePolicy(
        maxCacheSizeMb: 50,
        cacheDurationDays: 7,
        autoCleanup: true,
        lastCleanupAt: null,
      );

      final map = policy.toMap();
      final restored = CachePolicy.fromMap(map);

      expect(restored.lastCleanupAt, isNull);
    });

    test('defaultPolicy returns correct values', () {
      final policy = CachePolicy.defaultPolicy();

      expect(policy.maxCacheSizeMb, 50);
      expect(policy.cacheDurationDays, 7);
      expect(policy.autoCleanup, true);
      expect(policy.lastCleanupAt, isNull);
    });

    test('aggressive policy returns smaller values', () {
      final policy = CachePolicy.aggressive();

      expect(policy.maxCacheSizeMb, 20);
      expect(policy.cacheDurationDays, 3);
      expect(policy.autoCleanup, true);
    });

    test('relaxed policy returns larger values', () {
      final policy = CachePolicy.relaxed();

      expect(policy.maxCacheSizeMb, 100);
      expect(policy.cacheDurationDays, 14);
      expect(policy.autoCleanup, true);
    });

    test('copyWith preserves unchanged fields', () {
      final original = CachePolicy(
        maxCacheSizeMb: 50,
        cacheDurationDays: 7,
        autoCleanup: true,
        lastCleanupAt: DateTime(2025, 10, 24),
      );

      final modified = original.copyWith(maxCacheSizeMb: 100);

      expect(modified.maxCacheSizeMb, 100);
      expect(modified.cacheDurationDays, 7); // Unchanged
      expect(modified.autoCleanup, true); // Unchanged
      expect(modified.lastCleanupAt, original.lastCleanupAt); // Unchanged
    });

    test('copyWith can modify all fields', () {
      final original = CachePolicy.defaultPolicy();
      final newDate = DateTime(2025, 10, 24);

      final modified = original.copyWith(
        maxCacheSizeMb: 200,
        cacheDurationDays: 30,
        autoCleanup: false,
        lastCleanupAt: newDate,
      );

      expect(modified.maxCacheSizeMb, 200);
      expect(modified.cacheDurationDays, 30);
      expect(modified.autoCleanup, false);
      expect(modified.lastCleanupAt, newDate);
    });

    test('toString contains all important information', () {
      final policy = CachePolicy(
        maxCacheSizeMb: 50,
        cacheDurationDays: 7,
        autoCleanup: true,
      );

      final str = policy.toString();

      expect(str, contains('50MB'));
      expect(str, contains('7days'));
      expect(str, contains('autoCleanup: true'));
    });

    test('equality works correctly', () {
      final policy1 = CachePolicy(
        maxCacheSizeMb: 50,
        cacheDurationDays: 7,
        autoCleanup: true,
      );

      final policy2 = CachePolicy(
        maxCacheSizeMb: 50,
        cacheDurationDays: 7,
        autoCleanup: true,
      );

      final policy3 = CachePolicy(
        maxCacheSizeMb: 100,
        cacheDurationDays: 7,
        autoCleanup: true,
      );

      expect(policy1, equals(policy2));
      expect(policy1, isNot(equals(policy3)));
    });

    test('hashCode is consistent', () {
      final policy1 = CachePolicy(
        maxCacheSizeMb: 50,
        cacheDurationDays: 7,
        autoCleanup: true,
      );

      final policy2 = CachePolicy(
        maxCacheSizeMb: 50,
        cacheDurationDays: 7,
        autoCleanup: true,
      );

      expect(policy1.hashCode, equals(policy2.hashCode));
    });

    test('toMap converts autoCleanup boolean to int correctly', () {
      final policyTrue = CachePolicy(
        maxCacheSizeMb: 50,
        cacheDurationDays: 7,
        autoCleanup: true,
      );

      final policyFalse = policyTrue.copyWith(autoCleanup: false);

      expect(policyTrue.toMap()['auto_cleanup'], 1);
      expect(policyFalse.toMap()['auto_cleanup'], 0);
    });

    test('toMap always sets id to 1 for single-row table', () {
      final policy = CachePolicy.defaultPolicy();
      final map = policy.toMap();

      expect(map['id'], 1);
    });
  });
}
