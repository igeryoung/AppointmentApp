import '../models/book.dart';

/// Repository interface for Book entity operations
/// Defines the contract for book data access
abstract class IBookRepository {
  /// Retrieve all books ordered by their order field
  /// [includeArchived] - if true, includes archived books
  Future<List<Book>> getAll({bool includeArchived = false});

  /// Retrieve a single book by its UUID
  /// Returns null if book not found
  Future<Book?> getByUuid(String uuid);

  /// Create a new book
  /// Returns the created book with server-generated UUID
  /// Requires server connection (fails if offline)
  Future<Book> create(String name);

  /// Update an existing book
  /// Returns the updated book
  Future<Book> update(Book book);

  /// Delete a book by its UUID
  /// Cascade deletes all associated events
  Future<void> delete(String uuid);

  /// Archive a book (soft delete)
  /// Throws exception if book not found or already archived
  Future<void> archive(String uuid);

  /// Reorder books by updating their order field
  Future<void> reorder(List<Book> books);
}
