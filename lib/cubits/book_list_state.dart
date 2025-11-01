import 'package:equatable/equatable.dart';
import '../models/book.dart';

/// Base state for BookListCubit
abstract class BookListState extends Equatable {
  const BookListState();

  @override
  List<Object?> get props => [];
}

/// Initial state - before any data is loaded
class BookListInitial extends BookListState {
  const BookListInitial();
}

/// Loading state - data is being fetched
class BookListLoading extends BookListState {
  const BookListLoading();
}

/// Loaded state - data is available
class BookListLoaded extends BookListState {
  final List<Book> books;

  const BookListLoaded(this.books);

  @override
  List<Object?> get props => [books];

  /// Create a copy with updated books list
  BookListLoaded copyWith({List<Book>? books}) {
    return BookListLoaded(books ?? this.books);
  }
}

/// Error state - an error occurred
class BookListError extends BookListState {
  final String message;

  const BookListError(this.message);

  @override
  List<Object?> get props => [message];
}
