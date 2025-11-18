import 'package:sqflite/sqflite.dart';
import '../../../models/person_charge_item.dart';

/// Mixin for person charge item operations - shared charge items across events
mixin PersonChargeItemOperationsMixin {
  Future<Database> get database;

  /// Get all charge items for a person (name + record number)
  Future<List<PersonChargeItem>> getPersonChargeItems({
    required String personNameNormalized,
    required String recordNumberNormalized,
  }) async {
    final db = await database;
    final results = await db.query(
      'person_charge_items',
      where: 'person_name_normalized = ? AND record_number_normalized = ?',
      whereArgs: [personNameNormalized, recordNumberNormalized],
      orderBy: 'created_at ASC',
    );

    return results.map((map) => PersonChargeItem.fromMap(map)).toList();
  }

  /// Get a single charge item by ID
  Future<PersonChargeItem?> getPersonChargeItemById(int id) async {
    final db = await database;
    final results = await db.query(
      'person_charge_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return PersonChargeItem.fromMap(results.first);
  }

  /// Create or update a person charge item
  /// Returns the saved item with ID populated
  Future<PersonChargeItem> savePersonChargeItem(PersonChargeItem item) async {
    final db = await database;
    final now = DateTime.now();

    if (item.id == null) {
      // Insert new item
      final id = await db.insert(
        'person_charge_items',
        {
          'person_name_normalized': item.personNameNormalized,
          'record_number_normalized': item.recordNumberNormalized,
          'item_name': item.itemName,
          'cost': item.cost,
          'is_paid': item.isPaid ? 1 : 0,
          'created_at': now.millisecondsSinceEpoch ~/ 1000,
          'updated_at': now.millisecondsSinceEpoch ~/ 1000,
          'version': 1,
          'is_dirty': 1, // Mark as dirty for sync
        },
        conflictAlgorithm: ConflictAlgorithm.fail,
      );

      return item.copyWith(
        id: id,
        createdAt: now,
        updatedAt: now,
        isDirty: true,
      );
    } else {
      // Update existing item
      await db.update(
        'person_charge_items',
        {
          'item_name': item.itemName,
          'cost': item.cost,
          'is_paid': item.isPaid ? 1 : 0,
          'updated_at': now.millisecondsSinceEpoch ~/ 1000,
          'version': item.version + 1,
          'is_dirty': 1, // Mark as dirty for sync
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );

      return item.copyWith(
        updatedAt: now,
        version: item.version + 1,
        isDirty: true,
      );
    }
  }

  /// Update only the paid status of a charge item
  /// This is optimized for the common case of toggling paid status
  Future<void> updatePersonChargeItemPaidStatus({
    required int id,
    required bool isPaid,
  }) async {
    final db = await database;
    final now = DateTime.now();

    await db.update(
      'person_charge_items',
      {
        'is_paid': isPaid ? 1 : 0,
        'updated_at': now.millisecondsSinceEpoch ~/ 1000,
        'is_dirty': 1, // Mark as dirty for sync
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a charge item
  /// This will remove it from all events for this person
  Future<void> deletePersonChargeItem(int id) async {
    final db = await database;
    await db.delete(
      'person_charge_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Check if a charge item with the same name already exists for this person
  /// Used to prevent duplicates
  Future<bool> personChargeItemExists({
    required String personNameNormalized,
    required String recordNumberNormalized,
    required String itemName,
    int? excludeId, // Exclude this ID when checking (for updates)
  }) async {
    final db = await database;

    String where = 'person_name_normalized = ? AND record_number_normalized = ? AND item_name = ?';
    List<dynamic> whereArgs = [personNameNormalized, recordNumberNormalized, itemName];

    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }

    final results = await db.query(
      'person_charge_items',
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );

    return results.isNotEmpty;
  }

  /// Get total cost and paid amount for a person
  Future<Map<String, int>> getPersonChargeItemsTotal({
    required String personNameNormalized,
    required String recordNumberNormalized,
  }) async {
    final items = await getPersonChargeItems(
      personNameNormalized: personNameNormalized,
      recordNumberNormalized: recordNumberNormalized,
    );

    int totalCost = 0;
    int paidAmount = 0;

    for (final item in items) {
      totalCost += item.cost;
      if (item.isPaid) {
        paidAmount += item.cost;
      }
    }

    return {
      'total': totalCost,
      'paid': paidAmount,
    };
  }

  /// Get all dirty (unsynced) charge items
  /// Used for background sync
  Future<List<PersonChargeItem>> getDirtyPersonChargeItems() async {
    final db = await database;
    final results = await db.query(
      'person_charge_items',
      where: 'is_dirty = 1',
      orderBy: 'updated_at ASC',
    );

    return results.map((map) => PersonChargeItem.fromMap(map)).toList();
  }

  /// Mark a charge item as synced (clear dirty flag)
  Future<void> markPersonChargeItemSynced(int id) async {
    final db = await database;
    await db.update(
      'person_charge_items',
      {'is_dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a charge item as dirty (needs sync)
  Future<void> markPersonChargeItemDirty(int id) async {
    final db = await database;
    await db.update(
      'person_charge_items',
      {'is_dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
