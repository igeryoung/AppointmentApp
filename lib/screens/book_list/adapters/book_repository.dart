import '../../../models/book.dart';
import '../../../repositories/book_repository.dart';
import '../../../services/service_locator.dart';

/// Adapter for book CRUD operations
/// Wraps IBookRepository from service locator
class BookRepository {
  final IBookRepository _repo;

  BookRepository(this._repo);

  /// Create from service locator
  factory BookRepository.fromGetIt() {
    return BookRepository(getIt<IBookRepository>());
  }

  /// Get all books
  Future<List<Book>> getAll() async {
    return await _repo.getAll();
  }

  /// Create a new book
  Future<void> create(String name) async {
    await _repo.create(name);
  }

  /// Update an existing book
  Future<void> update(Book book) async {
    await _repo.update(book);
  }

  /// Archive a book
  Future<void> archive(String bookUuid) async {
    return await _repo.archive(bookUuid);
  }

  /// Delete a book
  Future<void> delete(String bookUuid) async {
    return await _repo.delete(bookUuid);
  }

  /// Get a single book by UUID
  Future<Book?> getByUuid(String bookUuid) async {
    return await _repo.getByUuid(bookUuid);
  }

  /// Get a book by name
  Future<Book?> getByName(String name) async {
    final books = await getAll();
    try {
      return books.firstWhere((book) => book.name == name);
    } catch (e) {
      return null;
    }
  }

  /// List books available on server
  Future<List<Map<String, dynamic>>> listServerBooks({
    String? searchQuery,
  }) async {
    return await _repo.listServerBooks(searchQuery: searchQuery);
  }

  /// Pull a server book bundle into local cache
  Future<void> pullBookFromServer(
    String bookUuid, {
    bool lightImport = false,
  }) async {
    await _repo.pullBookFromServer(bookUuid, lightImport: lightImport);
  }
}
