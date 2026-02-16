import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../models/record.dart';

/// Record database operations
mixin RecordOperationsMixin {
  Future<Database> get database;
  static const _uuid = Uuid();

  Future<Record> createRecord({
    required String recordNumber,
    String? name,
    String? phone,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final recordUuid = _uuid.v4();

    final record = Record(
      recordUuid: recordUuid,
      recordNumber: recordNumber,
      name: name,
      phone: phone,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('records', {...record.toMap(), 'is_dirty': 1});
    return record;
  }

  Future<Record?> getRecordByUuid(String recordUuid) async {
    final db = await database;
    final results = await db.query(
      'records',
      where: 'record_uuid = ? AND is_deleted = 0',
      whereArgs: [recordUuid],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Record.fromMap(results.first);
  }

  Future<Record?> getRecordByRecordNumber(String recordNumber) async {
    if (recordNumber.isEmpty) return null;
    final db = await database;
    final results = await db.query(
      'records',
      where: 'record_number = ? AND is_deleted = 0',
      whereArgs: [recordNumber],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Record.fromMap(results.first);
  }

  /// Find record by BOTH name AND record_number
  /// Returns null if either is empty or no match found
  Future<Record?> getRecordByNameAndRecordNumber(
    String name,
    String recordNumber,
  ) async {
    if (recordNumber.isEmpty || name.isEmpty) return null;
    final db = await database;
    final results = await db.query(
      'records',
      where: 'name = ? AND record_number = ? AND is_deleted = 0',
      whereArgs: [name, recordNumber],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Record.fromMap(results.first);
  }

  /// Get existing record or create new one
  /// - Non-empty recordNumber: prefer record_number match first (server treats it as canonical identity)
  /// - Non-empty recordNumber + non-empty name: keep local compatibility by still allowing name updates
  /// - Empty recordNumber or no match: create new standalone record
  Future<Record> getOrCreateRecord({
    required String recordNumber,
    String? name,
    String? phone,
    bool updateExisting = true,
  }) async {
    final normalizedName = name?.trim();
    final hasName = normalizedName != null && normalizedName.isNotEmpty;

    if (recordNumber.isNotEmpty) {
      final existing = await getRecordByRecordNumber(recordNumber);
      if (existing != null) {
        final shouldUpdateName =
            updateExisting && hasName && normalizedName != existing.name;
        final shouldUpdatePhone =
            updateExisting && phone != null && phone != existing.phone;

        if (shouldUpdateName || shouldUpdatePhone) {
          return await updateRecord(
            recordUuid: existing.recordUuid!,
            name: shouldUpdateName ? normalizedName : null,
            phone: shouldUpdatePhone ? phone : null,
          );
        }
        return existing;
      }
    }

    return await createRecord(
      recordNumber: recordNumber,
      name: hasName ? normalizedName : name,
      phone: phone,
    );
  }

  Future<Record> updateRecord({
    required String recordUuid,
    String? name,
    String? phone,
    String? recordNumber,
  }) async {
    final db = await database;
    final existing = await getRecordByUuid(recordUuid);
    if (existing == null) throw Exception('Record not found: $recordUuid');

    final now = DateTime.now().toUtc();
    final updates = <String, dynamic>{
      'updated_at': now.millisecondsSinceEpoch ~/ 1000,
      'is_dirty': 1,
    };
    if (name != null) updates['name'] = name;
    if (phone != null) updates['phone'] = phone;
    if (recordNumber != null) updates['record_number'] = recordNumber;

    await db.update(
      'records',
      updates,
      where: 'record_uuid = ?',
      whereArgs: [recordUuid],
    );

    return existing.copyWith(
      name: name ?? existing.name,
      phone: phone ?? existing.phone,
      recordNumber: recordNumber ?? existing.recordNumber,
      updatedAt: now,
    );
  }

  Future<void> deleteRecord(String recordUuid) async {
    final db = await database;
    await db.update(
      'records',
      {
        'is_deleted': 1,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        'is_dirty': 1,
      },
      where: 'record_uuid = ?',
      whereArgs: [recordUuid],
    );
  }

  Future<List<Record>> getAllRecords() async {
    final db = await database;
    final results = await db.query(
      'records',
      where: 'is_deleted = 0',
      orderBy: 'name ASC',
    );
    return results.map((map) => Record.fromMap(map)).toList();
  }

  Future<List<Record>> searchRecords(String query) async {
    if (query.isEmpty) return [];
    final db = await database;
    final pattern = '%$query%';
    final results = await db.query(
      'records',
      where: '(name LIKE ? OR record_number LIKE ?) AND is_deleted = 0',
      whereArgs: [pattern, pattern],
      orderBy: 'name ASC',
      limit: 50,
    );
    return results.map((map) => Record.fromMap(map)).toList();
  }

  Future<List<Record>> getDirtyRecords() async {
    final db = await database;
    final results = await db.query('records', where: 'is_dirty = 1');
    return results.map((map) => Record.fromMap(map)).toList();
  }

  Future<void> markRecordsSynced(List<String> recordUuids) async {
    if (recordUuids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(recordUuids.length, '?').join(',');
    await db.execute(
      'UPDATE records SET is_dirty = 0 WHERE record_uuid IN ($placeholders)',
      recordUuids,
    );
  }
}
