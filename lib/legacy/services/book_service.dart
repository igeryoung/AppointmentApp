import '../models/book.dart';
import 'database_service.dart';

/// Book业务服务 - 处理Book相关的业务逻辑
class BookService {
  final DatabaseService _databaseService = DatabaseService();

  /// 获取所有books
  Future<List<Book>> getBooks() async {
    try {
      return await _databaseService.getAllBooks();
    } catch (e) {
      throw BookServiceException('获取预约册列表失败: $e');
    }
  }

  /// 根据ID获取book
  Future<Book?> getBookById(int id) async {
    try {
      return await _databaseService.getBookById(id);
    } catch (e) {
      throw BookServiceException('获取预约册失败: $e');
    }
  }

  /// 创建新book
  Future<Book> createBook(String name) async {
    // 业务验证
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw BookServiceException('预约册名称不能为空');
    }

    if (trimmedName.length > 50) {
      throw BookServiceException('预约册名称不能超过50个字符');
    }

    // 检查名称是否重复
    final existingBooks = await _databaseService.getAllBooks();
    final isDuplicate = existingBooks.any(
      (book) => book.name.toLowerCase() == trimmedName.toLowerCase(),
    );

    if (isDuplicate) {
      throw BookServiceException('预约册名称已存在');
    }

    try {
      return await _databaseService.createBook(trimmedName);
    } catch (e) {
      throw BookServiceException('创建预约册失败: $e');
    }
  }

  /// 更新book名称
  Future<Book> updateBookName(int id, String newName) async {
    // 业务验证
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      throw BookServiceException('预约册名称不能为空');
    }

    if (trimmedName.length > 50) {
      throw BookServiceException('预约册名称不能超过50个字符');
    }

    // 获取现有book
    final existingBook = await _databaseService.getBookById(id);
    if (existingBook == null) {
      throw BookServiceException('预约册不存在');
    }

    // 检查新名称是否与其他book重复
    final allBooks = await _databaseService.getAllBooks();
    final isDuplicate = allBooks.any(
      (book) => book.id != id &&
                book.name.toLowerCase() == trimmedName.toLowerCase(),
    );

    if (isDuplicate) {
      throw BookServiceException('预约册名称已存在');
    }

    try {
      final updatedBook = existingBook.copyWith(name: trimmedName);
      return await _databaseService.updateBook(updatedBook);
    } catch (e) {
      throw BookServiceException('更新预约册失败: $e');
    }
  }

  /// 删除book
  /// 注意：这会删除book下的所有appointments
  Future<void> deleteBook(int id) async {
    // 检查book是否存在
    final existingBook = await _databaseService.getBookById(id);
    if (existingBook == null) {
      throw BookServiceException('预约册不存在');
    }

    // 检查是否有appointments
    final appointmentCount = await _databaseService.getAppointmentCountByBook(id);
    if (appointmentCount > 0) {
      // 可以选择抛出异常或者确认删除
      // 这里我们允许删除，但在UI层应该有确认提示
    }

    try {
      await _databaseService.deleteBook(id);
    } catch (e) {
      throw BookServiceException('删除预约册失败: $e');
    }
  }

  /// 获取book的统计信息
  Future<BookStatistics> getBookStatistics(int id) async {
    try {
      final book = await _databaseService.getBookById(id);
      if (book == null) {
        throw BookServiceException('预约册不存在');
      }

      final appointmentCount = await _databaseService.getAppointmentCountByBook(id);

      return BookStatistics(
        book: book,
        totalAppointments: appointmentCount,
      );
    } catch (e) {
      if (e is BookServiceException) rethrow;
      throw BookServiceException('获取预约册统计信息失败: $e');
    }
  }

  /// 验证book名称（不创建，仅验证）
  Future<ValidationResult> validateBookName(String name, {int? excludeId}) async {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      return ValidationResult(
        isValid: false,
        errorMessage: '预约册名称不能为空',
      );
    }

    if (trimmedName.length > 50) {
      return ValidationResult(
        isValid: false,
        errorMessage: '预约册名称不能超过50个字符',
      );
    }

    // 检查重复
    try {
      final existingBooks = await _databaseService.getAllBooks();
      final isDuplicate = existingBooks.any(
        (book) => book.id != excludeId &&
                  book.name.toLowerCase() == trimmedName.toLowerCase(),
      );

      if (isDuplicate) {
        return ValidationResult(
          isValid: false,
          errorMessage: '预约册名称已存在',
        );
      }

      return ValidationResult(isValid: true);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        errorMessage: '验证失败: $e',
      );
    }
  }
}

/// Book业务异常
class BookServiceException implements Exception {
  final String message;
  BookServiceException(this.message);

  @override
  String toString() => 'BookServiceException: $message';
}

/// Book统计信息
class BookStatistics {
  final Book book;
  final int totalAppointments;

  const BookStatistics({
    required this.book,
    required this.totalAppointments,
  });

  @override
  String toString() {
    return 'BookStatistics(book: ${book.name}, totalAppointments: $totalAppointments)';
  }
}

/// 验证结果
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult({
    required this.isValid,
    this.errorMessage,
  });

  @override
  String toString() {
    return 'ValidationResult(isValid: $isValid, errorMessage: $errorMessage)';
  }
}