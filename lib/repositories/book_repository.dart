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

  /// List all books available on server with optional search
  /// Returns metadata about books stored on the server
  /// [searchQuery] - optional filter by book name (case-insensitive)
  Future<List<Map<String, dynamic>>> listServerBooks({String? searchQuery});

  /// Pull complete book data from server to local device
  /// Includes book + events + notes + drawings by default.
  /// When [lightImport] is true, only imports book metadata.
  /// Throws if book already exists locally or doesn't exist on server
  /// [bookUuid] - UUID of the book to pull from server
  Future<void> pullBookFromServer(String bookUuid, {bool lightImport = false});

  /// Get book metadata from server without pulling the full data
  /// Useful for checking if a book exists on server or getting version info
  /// [bookUuid] - UUID of the book to check
  Future<Map<String, dynamic>?> getServerBookInfo(String bookUuid);
}
