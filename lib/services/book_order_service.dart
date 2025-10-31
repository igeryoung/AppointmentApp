import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';

/// Service to manage custom book ordering stored locally
class BookOrderService {
  static const String _orderKey = 'book_order';

  /// Save the book order (list of book UUIDs) to SharedPreferences
  Future<void> saveBookOrder(List<String> bookUuids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, bookUuids);
  }

  /// Load the saved book order from SharedPreferences
  Future<List<String>> loadBookOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_orderKey) ?? [];
  }

  /// Apply custom order to a list of books
  /// Books not in the saved order will be added to the top (new books)
  List<Book> applyOrder(List<Book> books, List<String> savedOrder) {
    if (savedOrder.isEmpty) {
      return books; // Return original order if no custom order saved
    }

    // Create map for quick lookup of saved order indices
    final orderMap = {for (int i = 0; i < savedOrder.length; i++) savedOrder[i]: i};

    // Separate books into two groups:
    // 1. Books that exist in the saved order
    // 2. New books (not in saved order) - these go to the top
    final newBooks = <Book>[];
    final orderedBooks = <Book>[];

    for (var book in books) {
      if (orderMap.containsKey(book.uuid)) {
        orderedBooks.add(book);
      } else {
        newBooks.add(book);
      }
    }

    // Sort ordered books according to saved order
    orderedBooks.sort((a, b) {
      final indexA = orderMap[a.uuid] ?? 0;
      final indexB = orderMap[b.uuid] ?? 0;
      return indexA.compareTo(indexB);
    });

    // New books at the top, then ordered books
    return [...newBooks, ...orderedBooks];
  }

  /// Get current order from a list of books and save it
  Future<void> saveCurrentOrder(List<Book> books) async {
    final uuids = books.map((book) => book.uuid).toList();
    await saveBookOrder(uuids);
  }
}
