import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import 'book_repository.dart';
import 'base_repository.dart';

/// Implementation of BookRepository using SQLite
class BookRepositoryImpl extends BaseRepository<Book, int> implements IBookRepository {
  BookRepositoryImpl(Future<Database> Function() getDatabaseFn) : super(getDatabaseFn);

  @override
  String get tableName => 'books';

  @override
  Book fromMap(Map<String, dynamic> map) => Book.fromMap(map);

  @override
  Map<String, dynamic> toMap(Book entity) => entity.toMap();

  @override
  Future<List<Book>> getAll({bool includeArchived = false}) async {
    if (includeArchived) {
      return queryAll(orderBy: 'created_at DESC');
    }
    // Use custom query for non-archived books
    return query(
      where: 'archived_at IS NULL',
      orderBy: 'created_at DESC',
    );
  }

  @override
  Future<Book?> getById(int id) => super.getById(id);

  @override
  Future<Book> create(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    final now = DateTime.now();
    final bookUuid = const Uuid().v4();

    final id = await insert({
      'name': name.trim(),
      'book_uuid': bookUuid,
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
      'is_dirty': 1, // Mark as dirty - needs backup
    });

    return Book(id: id, uuid: bookUuid, name: name.trim(), createdAt: now, isDirty: true);
  }

  @override
  Future<Book> update(Book book) async {
    if (book.id == null) throw ArgumentError('Book ID cannot be null');
    if (book.name.trim().isEmpty) throw ArgumentError('Book name cannot be empty');

    final updatedRows = await updateById(
      book.id!,
      {'name': book.name.trim()},
    );

    if (updatedRows == 0) throw Exception('Book not found');
    return book.copyWith(name: book.name.trim());
  }

  @override
  Future<void> delete(int id) => deleteById(id);

  /// Archive a book (soft delete)
  @override
  Future<void> archive(int id) async {
    final db = await getDatabaseFn();
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
    final db = await getDatabaseFn();
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

  /// Clear dirty flag for a book (called after successful backup)
  Future<void> clearDirtyFlag(int bookId) async {
    final db = await getDatabaseFn();
    final updatedRows = await db.update(
      'books',
      {'is_dirty': 0},
      where: 'id = ?',
      whereArgs: [bookId],
    );
    if (updatedRows == 0) {
      throw Exception('Book not found');
    }
  }

  /// Check if a book needs backup (is dirty)
  Future<bool> isBookDirty(int bookId) async {
    final db = await getDatabaseFn();
    final result = await db.query(
      'books',
      columns: ['is_dirty'],
      where: 'id = ?',
      whereArgs: [bookId],
    );
    if (result.isEmpty) {
      throw Exception('Book not found');
    }
    return (result.first['is_dirty'] as int) == 1;
  }
}
