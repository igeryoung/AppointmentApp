import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/book.dart';
import '../repositories/book_repository.dart';
import '../services/book_order_service.dart';
import 'book_list_state.dart';

/// BookListCubit - Manages book list state and operations
///
/// Responsibilities:
/// - Load books from repository
/// - Create new books
/// - Update book details (rename)
/// - Archive books
/// - Delete books
/// - Reorder books and persist order
///
/// Target: <150 lines
class BookListCubit extends Cubit<BookListState> {
  final IBookRepository _bookRepository;
  final BookOrderService _bookOrderService;

  BookListCubit(
    this._bookRepository,
    this._bookOrderService,
  ) : super(const BookListInitial());

  // ===================
  // Load Operations
  // ===================

  /// Load all books with custom order applied
  Future<void> loadBooks() async {
    emit(const BookListLoading());

    try {
      // Fetch books from repository
      final books = await _bookRepository.getAll(includeArchived: false);

      // Apply custom order from SharedPreferences
      final savedOrder = await _bookOrderService.loadBookOrder();
      final orderedBooks = _bookOrderService.applyOrder(books, savedOrder);

      emit(BookListLoaded(orderedBooks));
      debugPrint('✅ BookListCubit: Loaded ${orderedBooks.length} books');
    } catch (e) {
      debugPrint('❌ BookListCubit: Failed to load books: $e');
      emit(BookListError('Failed to load books: $e'));
    }
  }

  // ===================
  // Create Operations
  // ===================

  /// Create a new book
  /// Returns the created book on success
  Future<Book?> createBook(String name) async {
    if (name.trim().isEmpty) {
      emit(const BookListError('Book name cannot be empty'));
      return null;
    }

    try {
      // Create book in repository
      final newBook = await _bookRepository.create(name.trim());

      // Reload books to update UI
      await loadBooks();

      debugPrint('✅ BookListCubit: Created book "${newBook.name}" (uuid: ${newBook.uuid})');
      return newBook;
    } catch (e) {
      debugPrint('❌ BookListCubit: Failed to create book: $e');
      emit(BookListError('Failed to create book: $e'));
      return null;
    }
  }

  // ===================
  // Update Operations
  // ===================

  /// Update book details (rename)
  Future<void> updateBook(Book book, {String? newName}) async {

    if (newName != null && newName.trim().isEmpty) {
      emit(const BookListError('Book name cannot be empty'));
      return;
    }

    try {
      // Update book in repository
      final updatedBook = book.copyWith(
        name: newName?.trim() ?? book.name,
      );
      await _bookRepository.update(updatedBook);

      // Reload books to update UI
      await loadBooks();

      debugPrint('✅ BookListCubit: Updated book "${updatedBook.name}"');
    } catch (e) {
      debugPrint('❌ BookListCubit: Failed to update book: $e');
      emit(BookListError('Failed to update book: $e'));
    }
  }

  // ===================
  // Archive Operations
  // ===================

  /// Archive a book
  Future<void> archiveBook(String bookUuid) async {
    try {
      await _bookRepository.archive(bookUuid);

      // Reload books to update UI
      await loadBooks();

      debugPrint('✅ BookListCubit: Archived book (uuid: $bookUuid)');
    } catch (e) {
      debugPrint('❌ BookListCubit: Failed to archive book: $e');
      emit(BookListError('Failed to archive book: $e'));
    }
  }

  // ===================
  // Delete Operations
  // ===================

  /// Delete a book permanently
  Future<void> deleteBook(String bookUuid) async {
    try {
      await _bookRepository.delete(bookUuid);

      // Reload books to update UI
      await loadBooks();

      debugPrint('✅ BookListCubit: Deleted book (id: $bookId)');
    } catch (e) {
      debugPrint('❌ BookListCubit: Failed to delete book: $e');
      emit(BookListError('Failed to delete book: $e'));
    }
  }

  // ===================
  // Reorder Operations
  // ===================

  /// Reorder books in the list
  /// Updates UI immediately and persists order to SharedPreferences
  Future<void> reorderBooks(int oldIndex, int newIndex) async {
    final currentState = state;
    if (currentState is! BookListLoaded) {
      debugPrint('⚠️ BookListCubit: Cannot reorder - state is not BookListLoaded');
      return;
    }

    // Adjust newIndex if moving down the list
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    // Create new list with reordered books
    final books = List<Book>.from(currentState.books);
    final book = books.removeAt(oldIndex);
    books.insert(newIndex, book);

    // Update UI immediately (optimistic update)
    emit(BookListLoaded(books));

    // Persist the new order
    try {
      await _bookOrderService.saveCurrentOrder(books);
      debugPrint('✅ BookListCubit: Reordered books ($oldIndex → $newIndex)');
    } catch (e) {
      debugPrint('❌ BookListCubit: Failed to save book order: $e');
      // Don't emit error - UI already updated, order just won't persist
    }
  }
}
