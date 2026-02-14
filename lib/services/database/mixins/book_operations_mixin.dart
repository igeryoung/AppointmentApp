import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../models/book.dart';

/// Mixin providing Book CRUD operations for PRDDatabaseService
mixin BookOperationsMixin {
  /// Subclasses must provide database access
  Future<Database> get database;

  // ===================
  // Book Operations
  // ===================

  Future<List<Book>> getAllBooks({bool includeArchived = false}) async {
    final db = await database;
    final whereClause = includeArchived ? '' : 'WHERE archived_at IS NULL';
    final maps = await db.rawQuery('''
      SELECT * FROM books $whereClause ORDER BY created_at DESC
    ''');
    return maps.map((map) => Book.fromMap(map)).toList();
  }

  Future<Book?> getBookByUuid(String uuid) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'book_uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  Future<Book> createBook(String name) async {
    // Note: This method is deprecated for production use
    // Books should be created via BookRepositoryImpl which calls POST /api/books
    // This is kept for backward compatibility and testing only
    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    final db = await database;
    final now = DateTime.now();
    final bookUuid = const Uuid().v4();

    await db.insert('books', {
      'book_uuid': bookUuid,
      'name': name.trim(),
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
    });

    return Book(uuid: bookUuid, name: name.trim(), createdAt: now);
  }

  Future<Book> updateBook(Book book) async {
    if (book.name.trim().isEmpty)
      throw ArgumentError('Book name cannot be empty');

    final db = await database;
    final updatedRows = await db.update(
      'books',
      {'name': book.name.trim()},
      where: 'book_uuid = ?',
      whereArgs: [book.uuid],
    );

    if (updatedRows == 0) throw Exception('Book not found');
    return book.copyWith(name: book.name.trim());
  }

  Future<void> archiveBook(String uuid) async {
    final db = await database;
    final now = DateTime.now();
    final updatedRows = await db.update(
      'books',
      {'archived_at': now.millisecondsSinceEpoch ~/ 1000},
      where: 'book_uuid = ? AND archived_at IS NULL',
      whereArgs: [uuid],
    );
    if (updatedRows == 0) throw Exception('Book not found or already archived');
  }

  Future<void> deleteBook(String uuid) async {
    final db = await database;
    final deletedRows = await db.delete(
      'books',
      where: 'book_uuid = ?',
      whereArgs: [uuid],
    );
    if (deletedRows == 0) throw Exception('Book not found');
  }

  Future<int> getEventCountByBook(String bookUuid) async {
    final db = await database;
    final result = await db.query(
      'events',
      columns: ['COUNT(*) as count'],
      where: 'book_uuid = ?',
      whereArgs: [bookUuid],
    );
    return result.first['count'] as int;
  }

  Future<List<String>> getAllRecordNumbers(String bookUuid) async {
    final db = await database;
    final result = await db.query(
      'events',
      columns: ['DISTINCT record_number'],
      where:
          'book_uuid = ? AND record_number IS NOT NULL AND record_number != ""',
      whereArgs: [bookUuid],
      orderBy: 'record_number ASC',
    );
    return result.map((row) => row['record_number'] as String).toList();
  }
}
