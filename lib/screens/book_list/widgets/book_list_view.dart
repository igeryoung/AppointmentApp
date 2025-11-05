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
  final void Function(Book) onArchive;
  final void Function(Book) onDelete;
  final void Function(Book)? onUploadToServer;

  const BookListView({
    super.key,
    required this.books,
    required this.onRefresh,
    required this.onReorder,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
    required this.onDelete,
    this.onUploadToServer,
  });

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const EmptyState();
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ReorderableListView.builder(
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
            onArchive: () => onArchive(book),
            onDelete: () => onDelete(book),
            onUploadToServer:
                onUploadToServer == null ? null : () => onUploadToServer!(book),
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
          shadowColor: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      child: child,
    );
  }
}
