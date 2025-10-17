import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/book.dart';
import '../models/appointment.dart';

/// Web平台内存数据库服务 - 用于演示
class WebDatabaseService {
  static WebDatabaseService? _instance;

  // 内存存储
  final List<Book> _books = [];
  final List<Appointment> _appointments = [];
  int _nextBookId = 1;
  int _nextAppointmentId = 1;

  WebDatabaseService._internal();

  factory WebDatabaseService() {
    _instance ??= WebDatabaseService._internal();
    return _instance!;
  }

  /// 重置单例实例（测试用）
  static void resetInstance() {
    _instance = null;
  }

  // ====================
  // Book CRUD 操作
  // ====================

  /// 获取所有books
  Future<List<Book>> getAllBooks() async {
    await Future.delayed(const Duration(milliseconds: 10)); // 模拟数据库延迟
    return List.from(_books.reversed); // 最新的在前
  }

  /// 根据ID获取book
  Future<Book?> getBookById(int id) async {
    await Future.delayed(const Duration(milliseconds: 5));
    try {
      return _books.firstWhere((book) => book.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 创建新book
  Future<Book> createBook(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    await Future.delayed(const Duration(milliseconds: 10));

    final book = Book(
      id: _nextBookId++,
      name: name.trim(),
      createdAt: DateTime.now(),
    );

    _books.add(book);
    return book;
  }

  /// 更新book
  Future<Book> updateBook(Book book) async {
    if (book.id == null) {
      throw ArgumentError('Book ID cannot be null for update');
    }
    if (book.name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    await Future.delayed(const Duration(milliseconds: 10));

    final index = _books.indexWhere((b) => b.id == book.id);
    if (index == -1) {
      throw Exception('Book with id ${book.id} not found');
    }

    final updatedBook = book.copyWith(name: book.name.trim());
    _books[index] = updatedBook;
    return updatedBook;
  }

  /// 删除book（会级联删除所有相关appointments）
  Future<void> deleteBook(int id) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final bookIndex = _books.indexWhere((b) => b.id == id);
    if (bookIndex == -1) {
      throw Exception('Book with id $id not found');
    }

    _books.removeAt(bookIndex);
    // 级联删除相关appointments
    _appointments.removeWhere((a) => a.bookId == id);
  }

  // ====================
  // Appointment CRUD 操作
  // ====================

  /// 获取指定book在指定日期的所有appointments
  Future<List<Appointment>> getAppointmentsByBookAndDate(
    int bookId,
    DateTime date,
  ) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _appointments
        .where((a) =>
            a.bookId == bookId &&
            a.startTime.isAfter(startOfDay.subtract(const Duration(milliseconds: 1))) &&
            a.startTime.isBefore(endOfDay))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// 根据ID获取appointment
  Future<Appointment?> getAppointmentById(int id) async {
    await Future.delayed(const Duration(milliseconds: 5));
    try {
      return _appointments.firstWhere((a) => a.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 创建新appointment
  Future<Appointment> createAppointment(Appointment appointment) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final now = DateTime.now();
    final newAppointment = appointment.copyWith(
      id: _nextAppointmentId++,
      createdAt: now,
      updatedAt: now,
    );

    _appointments.add(newAppointment);
    return newAppointment;
  }

  /// 更新appointment
  Future<Appointment> updateAppointment(Appointment appointment) async {
    if (appointment.id == null) {
      throw ArgumentError('Appointment ID cannot be null for update');
    }

    await Future.delayed(const Duration(milliseconds: 10));

    final index = _appointments.indexWhere((a) => a.id == appointment.id);
    if (index == -1) {
      throw Exception('Appointment with id ${appointment.id} not found');
    }

    final updatedAppointment = appointment.copyWith(updatedAt: DateTime.now());
    _appointments[index] = updatedAppointment;
    return updatedAppointment;
  }

  /// 删除appointment
  Future<void> deleteAppointment(int id) async {
    await Future.delayed(const Duration(milliseconds: 10));

    final appointmentIndex = _appointments.indexWhere((a) => a.id == id);
    if (appointmentIndex == -1) {
      throw Exception('Appointment with id $id not found');
    }

    _appointments.removeAt(appointmentIndex);
  }

  /// 获取指定book的appointment总数
  Future<int> getAppointmentCountByBook(int bookId) async {
    await Future.delayed(const Duration(milliseconds: 5));
    return _appointments.where((a) => a.bookId == bookId).length;
  }

  // ====================
  // 数据库维护操作
  // ====================

  /// 清空所有数据（测试用）
  Future<void> clearAllData() async {
    await Future.delayed(const Duration(milliseconds: 5));
    _appointments.clear();
    _books.clear();
    _nextBookId = 1;
    _nextAppointmentId = 1;
  }

  /// 获取数据库版本
  Future<int> getDatabaseVersion() async {
    return 1;
  }
}