import 'package:sqflite/sqflite.dart';

/// Base repository providing common database operation helpers.
/// Eliminates duplicate database query patterns across repository implementations.
///
/// This class provides protected helper methods that subclasses can use,
/// but does NOT override interface methods to allow flexibility in signatures.
///
/// Type parameters:
/// - [T]: The entity type (e.g., Book, Event)
/// - [ID]: The ID type (typically int)
abstract class BaseRepository<T, ID> {
  final Future<Database> Function() getDatabaseFn;

  BaseRepository(this.getDatabaseFn);

  /// The table name in the database
  String get tableName;

  /// Convert a database map to an entity
  T fromMap(Map<String, dynamic> map);

  /// Convert an entity to a database map
  Map<String, dynamic> toMap(T entity);

  /// Helper: Get an entity by its ID
  Future<T?> getById(ID id) async {
    final db = await getDatabaseFn();
    final maps = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return fromMap(maps.first);
  }

  /// Helper: Delete an entity by its ID
  Future<void> deleteById(ID id) async {
    final db = await getDatabaseFn();
    final deletedRows = await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (deletedRows == 0) {
      throw Exception('${tableName.substring(0, tableName.length - 1)} not found');
    }
  }

  /// Helper: Insert a new entity
  Future<ID> insert(Map<String, dynamic> data) async {
    final db = await getDatabaseFn();
    final id = await db.insert(tableName, data);
    return id as ID;
  }

  /// Helper: Update an entity with custom data
  Future<int> updateById(ID id, Map<String, dynamic> data) async {
    final db = await getDatabaseFn();
    return await db.update(
      tableName,
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Helper: Execute a query with custom where clause
  Future<List<T>> query({
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await getDatabaseFn();
    final maps = await db.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  /// Helper: Get all entities with optional ordering
  Future<List<T>> queryAll({String? orderBy}) async {
    final db = await getDatabaseFn();
    final maps = await db.query(tableName, orderBy: orderBy);
    return maps.map((map) => fromMap(map)).toList();
  }

  /// Helper: Execute a raw query
  Future<List<T>> rawQuery(String sql, [List<dynamic>? arguments]) async {
    final db = await getDatabaseFn();
    final maps = await db.rawQuery(sql, arguments);
    return maps.map((map) => fromMap(map)).toList();
  }
}
