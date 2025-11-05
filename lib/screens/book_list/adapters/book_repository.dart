import '../../../models/book.dart';
import '../../../services/database_service_interface.dart';
import '../../../services/service_locator.dart';

/// Repository for book CRUD operations
/// Wraps IDatabaseService for easier testing and mocking
class BookRepository {
  final IDatabaseService _dbService;

  BookRepository(this._dbService);

  /// Create from service locator
  factory BookRepository.fromGetIt() {
    return BookRepository(getIt<IDatabaseService>());
  }

  /// Get all books
  Future<List<Book>> getAll() async {
    return await _dbService.getAllBooks();
  }

  /// Create a new book
  Future<void> create(String name) async {
    await _dbService.createBook(name);
  }

  /// Update an existing book
  Future<void> update(Book book) async {
    await _dbService.updateBook(book);
  }

  /// Archive a book
  Future<void> archive(int bookId) async {
    return await _dbService.archiveBook(bookId);
  }

  /// Delete a book
  Future<void> delete(int bookId) async {
    return await _dbService.deleteBook(bookId);
  }

  /// Get a single book by ID
  Future<Book?> getById(int bookId) async {
    final books = await getAll();
    try {
      return books.firstWhere((book) => book.id == bookId);
    } catch (e) {
      return null;
    }
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
}
