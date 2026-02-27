import '../../models/book.dart';

/// Immutable state for BookListScreen
/// Holds all data needed to render the UI
class BookListState {
  final List<Book> books;
  final bool isLoading;
  final bool isReadOnlyDevice;
  final String? errorMessage;

  const BookListState({
    required this.books,
    required this.isLoading,
    required this.isReadOnlyDevice,
    this.errorMessage,
  });

  /// Initial state with empty books and loading
  factory BookListState.initial() =>
      const BookListState(books: [], isLoading: true, isReadOnlyDevice: false);

  /// Create a copy with updated fields
  BookListState copyWith({
    List<Book>? books,
    bool? isLoading,
    bool? isReadOnlyDevice,
    String? errorMessage,
  }) {
    return BookListState(
      books: books ?? this.books,
      isLoading: isLoading ?? this.isLoading,
      isReadOnlyDevice: isReadOnlyDevice ?? this.isReadOnlyDevice,
      errorMessage: errorMessage,
    );
  }

  /// Clear error message
  BookListState clearError() {
    return BookListState(
      books: books,
      isLoading: isLoading,
      isReadOnlyDevice: isReadOnlyDevice,
      errorMessage: null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BookListState &&
        other.books == books &&
        other.isLoading == isLoading &&
        other.isReadOnlyDevice == isReadOnlyDevice &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode =>
      Object.hash(books, isLoading, isReadOnlyDevice, errorMessage);
}
