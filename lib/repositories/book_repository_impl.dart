import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import 'book_repository.dart';

/// Implementation of BookRepository using SQLite
class BookRepositoryImpl implements IBookRepository {
  final Future<Database> Function() _getDatabaseFn;

  BookRepositoryImpl(this._getDatabaseFn);

  @override
  Future<List<Book>> getAll({bool includeArchived = false}) async {
    final db = await _getDatabaseFn();
    final whereClause = includeArchived ? '' : 'WHERE archived_at IS NULL';
    final maps = await db.rawQuery('''
      SELECT * FROM books $whereClause ORDER BY created_at DESC
    ''');
    return maps.map((map) => Book.fromMap(map)).toList();
  }

  @override
  Future<Book?> getById(int id) async {
    final db = await _getDatabaseFn();
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  @override
  Future<Book> create(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    final db = await _getDatabaseFn();
    final now = DateTime.now();
    final bookUuid = const Uuid().v4();

    final id = await db.insert('books', {
      'name': name.trim(),
      'book_uuid': bookUuid,
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
    });

    return Book(id: id, uuid: bookUuid, name: name.trim(), createdAt: now);
  }

  @override
  Future<Book> update(Book book) async {
    if (book.id == null) throw ArgumentError('Book ID cannot be null');
    if (book.name.trim().isEmpty) throw ArgumentError('Book name cannot be empty');

    final db = await _getDatabaseFn();
    final updatedRows = await db.update(
      'books',
      {'name': book.name.trim()},
      where: 'id = ?',
      whereArgs: [book.id],
    );

    if (updatedRows == 0) throw Exception('Book not found');
    return book.copyWith(name: book.name.trim());
  }

  @override
  Future<void> delete(int id) async {
    final db = await _getDatabaseFn();
    final deletedRows = await db.delete('books', where: 'id = ?', whereArgs: [id]);
    if (deletedRows == 0) throw Exception('Book not found');
  }

  /// Archive a book (soft delete)
  @override
  Future<void> archive(int id) async {
    final db = await _getDatabaseFn();
    final now = DateTime.now();
    final updatedRows = await db.update(
      'books',
      {'archived_at': now.millisecondsSinceEpoch ~/ 1000},
      where: 'id = ? AND archived_at IS NULL',
      whereArgs: [id],
    );
    if (updatedRows == 0) throw Exception('Book not found or already archived');
  }

  @override
  Future<void> reorder(List<Book> books) async {
    final db = await _getDatabaseFn();
    final batch = db.batch();

    for (var i = 0; i < books.length; i++) {
      final book = books[i];
      if (book.id != null) {
        // Note: Book model doesn't have an 'order' field currently
        // This is a placeholder for future implementation
        // For now, ordering is handled by created_at DESC in getAll()
      }
    }

    await batch.commit(noResult: true);
  }
}
