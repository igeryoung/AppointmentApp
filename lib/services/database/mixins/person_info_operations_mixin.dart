import 'package:sqflite/sqflite.dart';

/// Mixin for person info operations - stores person-level data like phone numbers
mixin PersonInfoOperationsMixin {
  Future<Database> get database;

  /// Get person info (phone number) for a person
  Future<String?> getPersonPhone({
    required String personNameNormalized,
    required String recordNumberNormalized,
  }) async {
    final db = await database;
    final results = await db.query(
      'person_info',
      where: 'person_name_normalized = ? AND record_number_normalized = ?',
      whereArgs: [personNameNormalized, recordNumberNormalized],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return results.first['phone'] as String?;
  }

  /// Set or update person phone number
  /// Returns the phone number that was saved
  Future<String?> setPersonPhone({
    required String personNameNormalized,
    required String recordNumberNormalized,
    required String? phone,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // If phone is empty, delete the record if it exists
    if (phone == null || phone.trim().isEmpty) {
      await db.delete(
        'person_info',
        where: 'person_name_normalized = ? AND record_number_normalized = ?',
        whereArgs: [personNameNormalized, recordNumberNormalized],
      );
      return null;
    }

    // Try to update first
    final updateCount = await db.update(
      'person_info',
      {
        'phone': phone.trim(),
        'updated_at': now,
      },
      where: 'person_name_normalized = ? AND record_number_normalized = ?',
      whereArgs: [personNameNormalized, recordNumberNormalized],
    );

    // If no rows were updated, insert new record
    if (updateCount == 0) {
      await db.insert(
        'person_info',
        {
          'person_name_normalized': personNameNormalized,
          'record_number_normalized': recordNumberNormalized,
          'phone': phone.trim(),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    return phone.trim();
  }

  /// Check if person info exists
  Future<bool> personInfoExists({
    required String personNameNormalized,
    required String recordNumberNormalized,
  }) async {
    final db = await database;
    final results = await db.query(
      'person_info',
      where: 'person_name_normalized = ? AND record_number_normalized = ?',
      whereArgs: [personNameNormalized, recordNumberNormalized],
      limit: 1,
    );

    return results.isNotEmpty;
  }
}
