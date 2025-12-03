import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../models/cache_policy.dart';

/// Mixin providing Cache Policy operations for PRDDatabaseService
mixin CachePolicyOperationsMixin {
  /// Subclasses must provide database access
  Future<Database> get database;

  // ===================
  // Cache Policy Operations
  // ===================

  /// Get cache policy configuration (single-row table, id=1)
  Future<CachePolicy> getCachePolicy() async {
    final db = await database;
    final maps = await db.query('cache_policy', where: 'id = 1', limit: 1);

    if (maps.isEmpty) {
      // Fallback to default if not found (shouldn't happen after v8 migration)
      return CachePolicy.defaultPolicy();
    }

    return CachePolicy.fromMap(maps.first);
  }

  /// Update cache policy configuration
  Future<void> updateCachePolicy(CachePolicy policy) async {
    final db = await database;
    final updatedRows = await db.update(
      'cache_policy',
      policy.toMap(),
      where: 'id = 1',
    );

    if (updatedRows == 0) {
      // If update failed, insert (shouldn't happen after v8 migration)
      await db.insert('cache_policy', policy.toMap());
    }

  }
}
