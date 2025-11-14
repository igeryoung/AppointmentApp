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

  Future<Book?> getBookById(int id) async {
    final db = await database;
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  Future<Book> createBook(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    final db = await database;
    final now = DateTime.now();
    final bookUuid = const Uuid().v4();

    final id = await db.insert('books', {
      'name': name.trim(),
      'book_uuid': bookUuid,
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
    });

    return Book(id: id, uuid: bookUuid, name: name.trim(), createdAt: now);
  }

  Future<Book> updateBook(Book book) async {
    if (book.id == null) throw ArgumentError('Book ID cannot be null');
    if (book.name.trim().isEmpty) throw ArgumentError('Book name cannot be empty');

    final db = await database;
    final updatedRows = await db.update(
      'books',
      {'name': book.name.trim()},
      where: 'id = ?',
      whereArgs: [book.id],
    );

    if (updatedRows == 0) throw Exception('Book not found');
    return book.copyWith(name: book.name.trim());
  }

  Future<void> archiveBook(int id) async {
    final db = await database;
    final now = DateTime.now();
    final updatedRows = await db.update(
      'books',
      {'archived_at': now.millisecondsSinceEpoch ~/ 1000},
      where: 'id = ? AND archived_at IS NULL',
      whereArgs: [id],
    );
    if (updatedRows == 0) throw Exception('Book not found or already archived');
  }

  Future<void> deleteBook(int id) async {
    final db = await database;
    final deletedRows = await db.delete('books', where: 'id = ?', whereArgs: [id]);
    if (deletedRows == 0) throw Exception('Book not found');
  }

  Future<int> getEventCountByBook(int bookId) async {
    final db = await database;
    final result = await db.query(
      'events',
      columns: ['COUNT(*) as count'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    return result.first['count'] as int;
  }

  Future<List<String>> getAllRecordNumbers(int bookId) async {
    final db = await database;
    final result = await db.query(
      'events',
      columns: ['DISTINCT record_number'],
      where: 'book_id = ? AND record_number IS NOT NULL AND record_number != ""',
      whereArgs: [bookId],
      orderBy: 'record_number ASC',
    );
    return result
        .map((row) => row['record_number'] as String)
        .toList();
  }
}
