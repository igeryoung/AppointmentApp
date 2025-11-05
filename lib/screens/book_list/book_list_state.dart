import '../../models/book.dart';

/// Immutable state for BookListScreen
/// Holds all data needed to render the UI
class BookListState {
  final List<Book> books;
  final bool isLoading;
  final String? errorMessage;

  const BookListState({
    required this.books,
    required this.isLoading,
    this.errorMessage,
  });

  /// Initial state with empty books and loading
  factory BookListState.initial() => const BookListState(
        books: [],
        isLoading: true,
      );

  /// Create a copy with updated fields
  BookListState copyWith({
    List<Book>? books,
    bool? isLoading,
    String? errorMessage,
  }) {
    return BookListState(
      books: books ?? this.books,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  /// Clear error message
  BookListState clearError() {
    return BookListState(
      books: books,
      isLoading: isLoading,
      errorMessage: null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BookListState &&
        other.books == books &&
        other.isLoading == isLoading &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(books, isLoading, errorMessage);
}
