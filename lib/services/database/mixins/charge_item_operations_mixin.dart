import 'package:sqflite/sqflite.dart';
import '../../../models/charge_item.dart';

/// Mixin for charge item operations - charge items linked to records (person-level)
/// with optional event association for filtering
mixin ChargeItemOperationsMixin {
  Future<Database> get database;

  /// Get all charge items for a record (person-level)
  Future<List<ChargeItem>> getChargeItemsByRecordUuid(String recordUuid) async {
    final db = await database;
    final results = await db.query(
      'charge_items',
      where: 'record_uuid = ? AND is_deleted = 0',
      whereArgs: [recordUuid],
      orderBy: 'created_at ASC',
    );

    return results.map((map) => ChargeItem.fromMap(map)).toList();
  }

  /// Get charge items for a specific event
  Future<List<ChargeItem>> getChargeItemsByEventId(String eventId) async {
    final db = await database;
    final results = await db.query(
      'charge_items',
      where: 'event_id = ? AND is_deleted = 0',
      whereArgs: [eventId],
      orderBy: 'created_at ASC',
    );

    return results.map((map) => ChargeItem.fromMap(map)).toList();
  }

  /// Get charge items for a record, optionally filtered by event
  /// If eventId is null, returns all items for the record
  /// If eventId is provided, returns only items associated with that event
  Future<List<ChargeItem>> getChargeItemsByRecordAndEvent(
    String recordUuid, {
    String? eventId,
  }) async {
    final db = await database;

    if (eventId == null) {
      // Return all items for the record
      return getChargeItemsByRecordUuid(recordUuid);
    }

    // Return only items associated with this specific event
    final results = await db.query(
      'charge_items',
      where: 'record_uuid = ? AND event_id = ? AND is_deleted = 0',
      whereArgs: [recordUuid, eventId],
      orderBy: 'created_at ASC',
    );

    return results.map((map) => ChargeItem.fromMap(map)).toList();
  }

  /// Get all charge items for a record (for total calculation)
  /// Alias for getChargeItemsByRecordUuid
  Future<List<ChargeItem>> getAllChargeItemsForRecord(String recordUuid) async {
    return getChargeItemsByRecordUuid(recordUuid);
  }

  /// Get a single charge item by ID
  Future<ChargeItem?> getChargeItemById(String id) async {
    final db = await database;
    final results = await db.query(
      'charge_items',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return ChargeItem.fromMap(results.first);
  }

  /// Create or update a charge item
  /// Returns the saved item
  Future<ChargeItem> saveChargeItem(ChargeItem item) async {
    final db = await database;
    final now = DateTime.now();

    // Check if item exists
    final existing = await getChargeItemById(item.id);

    ChargeItem result;
    if (existing == null) {
      // Insert new item
      final newItem = item.copyWith(
        createdAt: now,
        updatedAt: now,
        isDirty: true,
        version: 1,
      );

      await db.insert(
        'charge_items',
        newItem.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      result = newItem;

      // Update has_charge_items flag for all events of this record
      await updateEventsHasChargeItemsFlag(recordUuid: item.recordUuid);
    } else {
      // Update existing item
      final updatedItem = item.copyWith(
        updatedAt: now,
        isDirty: true,
        version: existing.version + 1,
      );

      await db.update(
        'charge_items',
        updatedItem.toMap(),
        where: 'id = ?',
        whereArgs: [item.id],
      );

      result = updatedItem;
    }

    return result;
  }

  /// Update the received amount of a charge item
  Future<void> updateChargeItemReceivedAmount({
    required String id,
    required int receivedAmount,
  }) async {
    final db = await database;
    final now = DateTime.now();

    await db.update(
      'charge_items',
      {
        'received_amount': receivedAmount,
        'updated_at': now.millisecondsSinceEpoch ~/ 1000,
        'is_dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft delete a charge item
  Future<void> deleteChargeItem(String id) async {
    final db = await database;

    // First, get the item to know which record it belongs to
    final item = await getChargeItemById(id);
    if (item == null) return; // Item doesn't exist

    // Soft delete the item
    final now = DateTime.now();
    await db.update(
      'charge_items',
      {
        'is_deleted': 1,
        'updated_at': now.millisecondsSinceEpoch ~/ 1000,
        'is_dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    // Update has_charge_items flag for all events of this record
    await updateEventsHasChargeItemsFlag(recordUuid: item.recordUuid);
  }

  /// Check if a charge item with the same name already exists for this record
  /// Used to prevent duplicates
  Future<bool> chargeItemExists({
    required String recordUuid,
    String? eventId,
    required String itemName,
    String? excludeId, // Exclude this ID when checking (for updates)
  }) async {
    final db = await database;

    String where = 'record_uuid = ? AND item_name = ? AND is_deleted = 0';
    List<dynamic> whereArgs = [recordUuid, itemName];

    if (eventId != null) {
      where += ' AND event_id = ?';
      whereArgs.add(eventId);
    }

    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }

    final results = await db.query(
      'charge_items',
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );

    return results.isNotEmpty;
  }

  /// Get total price and received amount for a record
  Future<Map<String, int>> getChargeItemsTotal(String recordUuid) async {
    final items = await getChargeItemsByRecordUuid(recordUuid);

    int totalPrice = 0;
    int totalReceived = 0;

    for (final item in items) {
      totalPrice += item.itemPrice;
      totalReceived += item.receivedAmount;
    }

    return {
      'total': totalPrice,
      'received': totalReceived,
    };
  }

  /// Get all dirty (unsynced) charge items
  /// Used for background sync
  Future<List<ChargeItem>> getDirtyChargeItems() async {
    final db = await database;
    final results = await db.query(
      'charge_items',
      where: 'is_dirty = 1',
      orderBy: 'updated_at ASC',
    );

    return results.map((map) => ChargeItem.fromMap(map)).toList();
  }

  /// Mark a charge item as synced (clear dirty flag)
  Future<void> markChargeItemSynced(String id, DateTime syncedAt) async {
    final db = await database;
    await db.update(
      'charge_items',
      {
        'is_dirty': 0,
        'synced_at': syncedAt.millisecondsSinceEpoch ~/ 1000,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a charge item as dirty (needs sync)
  Future<void> markChargeItemDirty(String id) async {
    final db = await database;
    await db.update(
      'charge_items',
      {'is_dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update has_charge_items flag for all events matching the record_uuid
  /// Should be called after adding or deleting charge items
  Future<void> updateEventsHasChargeItemsFlag({
    required String recordUuid,
  }) async {
    final db = await database;

    // Check if any charge items exist for this record
    final chargeItems = await getChargeItemsByRecordUuid(recordUuid);
    final hasChargeItems = chargeItems.isNotEmpty;

    // Update all events for this record to set has_charge_items flag
    await db.update(
      'events',
      {'has_charge_items': hasChargeItems ? 1 : 0},
      where: 'record_uuid = ?',
      whereArgs: [recordUuid],
    );
  }

  /// Apply server charge item change to local database
  Future<void> applyServerChargeItemChange(Map<String, dynamic> data) async {
    final db = await database;
    final id = data['id']?.toString();
    if (id == null) {
      throw ArgumentError('Missing id for charge_items');
    }

    final isDeleted = data['is_deleted'] == true || data['isDeleted'] == true;

    // Check if item exists locally
    final existing = await getChargeItemById(id);

    if (isDeleted) {
      // Soft delete locally
      if (existing != null) {
        await db.update(
          'charge_items',
          {
            'is_deleted': 1,
            'synced_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'is_dirty': 0,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        // Update has_charge_items flag
        await updateEventsHasChargeItemsFlag(recordUuid: existing.recordUuid);
      }
      return;
    }

    final chargeItem = ChargeItem.fromMap(data);
    final itemData = chargeItem.copyWith(
      isDirty: false,
      syncedAt: DateTime.now(),
    ).toMap();

    if (existing == null) {
      // Insert new item
      await db.insert('charge_items', itemData);
    } else {
      // Update existing item
      await db.update(
        'charge_items',
        itemData,
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    // Update has_charge_items flag
    await updateEventsHasChargeItemsFlag(recordUuid: chargeItem.recordUuid);
  }
}
