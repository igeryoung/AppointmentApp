import '../../../models/book.dart';
import '../../../services/book_order_service.dart';

/// Adapter for book ordering operations
/// Wraps BookOrderService for easier testing
class BookOrderAdapter {
  final BookOrderService _orderService;

  BookOrderAdapter(this._orderService);

  /// Create with default service
  factory BookOrderAdapter.fromGetIt() {
    return BookOrderAdapter(BookOrderService());
  }

  /// Load saved book order from SharedPreferences
  Future<List<String>> loadOrder() async {
    return await _orderService.loadBookOrder();
  }

  /// Apply saved order to a list of books
  /// Handles missing books gracefully
  List<Book> applyOrder(List<Book> books, List<String> savedOrder) {
    return _orderService.applyOrder(books, savedOrder);
  }

  /// Save current book order to SharedPreferences
  Future<void> saveCurrentOrder(List<Book> books) async {
    return await _orderService.saveCurrentOrder(books);
  }
}
