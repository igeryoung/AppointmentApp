import 'package:flutter/material.dart';
import '../../../models/book.dart';
import 'book_card.dart';
import 'empty_state.dart';

/// Pure UI widget for displaying the list of books
/// Handles list rendering, empty state, and reordering
class BookListView extends StatelessWidget {
  final List<Book> books;
  final Future<void> Function() onRefresh;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;
  final void Function(Book) onTap;
  final void Function(Book) onRename;
  final void Function(Book) onDelete;
  final bool isReadOnlyDevice;

  const BookListView({
    super.key,
    required this.books,
    required this.onRefresh,
    required this.onReorder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.isReadOnlyDevice = false,
  });

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const EmptyState();
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: isReadOnlyDevice
          ? ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: books.length,
              itemBuilder: (context, index) {
                final book = books[index];
                return BookCard(
                  key: ValueKey(book.uuid),
                  book: book,
                  onTap: () => onTap(book),
                  onRename: () => onRename(book),
                  onDelete: () => onDelete(book),
                  isReadOnlyDevice: true,
                );
              },
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: books.length,
              onReorder: onReorder,
              proxyDecorator: _proxyDecorator,
              itemBuilder: (context, index) {
                final book = books[index];
                return BookCard(
                  key: ValueKey(book.uuid),
                  book: book,
                  onTap: () => onTap(book),
                  onRename: () => onRename(book),
                  onDelete: () => onDelete(book),
                  isReadOnlyDevice: false,
                );
              },
            ),
    );
  }

  /// Customize the appearance of the dragged item
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Material(
          elevation: 8.0,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      child: child,
    );
  }
}
