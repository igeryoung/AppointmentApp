import 'package:flutter/foundation.dart';
import '../models/book.dart';
import '../services/book_service.dart';

/// Book状态管理Provider
class BookProvider extends ChangeNotifier {
  final BookService _bookService = BookService();

  List<Book> _books = [];
  Book? _currentBook;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<Book> get books => _books;
  Book? get currentBook => _currentBook;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 加载所有books
  Future<void> loadBooks() async {
    _setLoading(true);
    _clearError();

    try {
      _books = await _bookService.getBooks();
      notifyListeners();
    } catch (e) {
      _setError('加载预约册失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// 创建新book
  Future<bool> createBook(String name) async {
    _clearError();

    try {
      final newBook = await _bookService.createBook(name);
      _books.insert(0, newBook); // 新建的放在最前面
      notifyListeners();
      return true;
    } catch (e) {
      _setError('创建预约册失败: $e');
      return false;
    }
  }

  /// 更新book名称
  Future<bool> updateBookName(int id, String newName) async {
    _clearError();

    try {
      final updatedBook = await _bookService.updateBookName(id, newName);

      // 更新本地列表
      final index = _books.indexWhere((book) => book.id == id);
      if (index != -1) {
        _books[index] = updatedBook;
      }

      // 如果当前选中的book被更新了，也要更新
      if (_currentBook?.id == id) {
        _currentBook = updatedBook;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _setError('更新预约册失败: $e');
      return false;
    }
  }

  /// 删除book
  Future<bool> deleteBook(int id) async {
    _clearError();

    try {
      await _bookService.deleteBook(id);

      // 从本地列表中移除
      _books.removeWhere((book) => book.id == id);

      // 如果删除的是当前选中的book，清空选择
      if (_currentBook?.id == id) {
        _currentBook = null;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _setError('删除预约册失败: $e');
      return false;
    }
  }

  /// 设置当前选中的book
  void setCurrentBook(Book book) {
    _currentBook = book;
    notifyListeners();
  }

  /// 清空当前选中的book
  void clearCurrentBook() {
    _currentBook = null;
    notifyListeners();
  }

  /// 验证book名称
  Future<ValidationResult> validateBookName(String name, {int? excludeId}) async {
    try {
      return await _bookService.validateBookName(name, excludeId: excludeId);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        errorMessage: '验证失败: $e',
      );
    }
  }

  /// 获取book统计信息
  Future<BookStatistics?> getBookStatistics(int id) async {
    try {
      return await _bookService.getBookStatistics(id);
    } catch (e) {
      _setError('获取统计信息失败: $e');
      return null;
    }
  }

  /// 设置加载状态
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// 设置错误信息
  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// 清空错误信息
  void _clearError() {
    _errorMessage = null;
    if (_errorMessage != null) {
      notifyListeners();
    }
  }

  /// 刷新books列表
  Future<void> refresh() async {
    await loadBooks();
  }
}