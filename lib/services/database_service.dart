import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book.dart';
import '../models/appointment.dart';
import 'web_database_service.dart';

/// 数据库服务 - 单例模式，处理所有SQLite操作
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;
  static WebDatabaseService? _webDatabase;

  DatabaseService._internal();

  factory DatabaseService() {
    _instance ??= DatabaseService._internal();
    return _instance!;
  }

  /// 获取Web数据库实例
  WebDatabaseService get _webDb {
    _webDatabase ??= WebDatabaseService();
    return _webDatabase!;
  }

  /// 获取数据库实例，懒加载
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    // 在测试环境中使用随机数据库名称避免冲突
    final dbName = _isTestEnvironment()
        ? 'schedule_note_test_${DateTime.now().millisecondsSinceEpoch}.db'
        : 'schedule_note.db';
    final path = join(databasesPath, dbName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createTables,
      onConfigure: _onConfigure,
    );
  }

  /// 检查是否在测试环境中
  bool _isTestEnvironment() {
    // 在测试环境中，通常会有这个环境变量
    return const bool.fromEnvironment('dart.vm.product') == false &&
           const bool.fromEnvironment('flutter.testing') == true;
  }

  /// 配置数据库选项
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// 创建数据库表 - PRD compliant schema: Book → Event → Note
  Future<void> _createTables(Database db, int version) async {
    // 创建books表 - Top-level container
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        archived_at INTEGER
      )
    ''');

    // 创建events表 - Individual appointment entries
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        record_number TEXT NOT NULL,
        event_type TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    // 创建notes表 - Handwriting-only notes linked to events
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id INTEGER NOT NULL UNIQUE,
        strokes_data TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE
      )
    ''');

    // 创建索引 - Optimized for PRD requirements
    await db.execute('''
      CREATE INDEX idx_events_book_time
      ON events(book_id, start_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_events_book_date
      ON events(book_id, date(start_time, 'unixepoch'))
    ''');

    await db.execute('''
      CREATE INDEX idx_notes_event
      ON notes(event_id)
    ''');
  }

  /// 关闭数据库连接
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// 重置单例实例（测试用）
  static void resetInstance() {
    _instance = null;
    _database = null;
  }

  // ====================
  // Book CRUD 操作
  // ====================

  /// 获取所有books
  Future<List<Book>> getAllBooks() async {
    if (kIsWeb) {
      return await _webDb.getAllBooks();
    }

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'books',
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) => Book.fromMap(maps[i]));
  }

  /// 根据ID获取book
  Future<Book?> getBookById(int id) async {
    if (kIsWeb) {
      return await _webDb.getBookById(id);
    }

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'books',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  /// 创建新book
  Future<Book> createBook(String name) async {
    if (kIsWeb) {
      return await _webDb.createBook(name);
    }

    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    final db = await database;
    final now = DateTime.now();
    final id = await db.insert('books', {
      'name': name.trim(),
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
    });

    return Book(
      id: id,
      name: name.trim(),
      createdAt: now,
    );
  }

  /// 更新book
  Future<Book> updateBook(Book book) async {
    if (kIsWeb) {
      return await _webDb.updateBook(book);
    }

    if (book.id == null) {
      throw ArgumentError('Book ID cannot be null for update');
    }
    if (book.name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    final db = await database;
    final updatedRows = await db.update(
      'books',
      {'name': book.name.trim()},
      where: 'id = ?',
      whereArgs: [book.id],
    );

    if (updatedRows == 0) {
      throw Exception('Book with id ${book.id} not found');
    }

    return book.copyWith(name: book.name.trim());
  }

  /// 删除book（会级联删除所有相关appointments）
  Future<void> deleteBook(int id) async {
    if (kIsWeb) {
      return await _webDb.deleteBook(id);
    }

    final db = await database;
    final deletedRows = await db.delete(
      'books',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (deletedRows == 0) {
      throw Exception('Book with id $id not found');
    }
  }

  // ====================
  // Appointment CRUD 操作
  // ====================

  /// 获取指定book在指定日期的所有appointments
  Future<List<Appointment>> getAppointmentsByBookAndDate(
    int bookId,
    DateTime date,
  ) async {
    if (kIsWeb) {
      return await _webDb.getAppointmentsByBookAndDate(bookId, date);
    }

    final db = await database;

    // 计算一天的开始和结束时间戳
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final startTimestamp = startOfDay.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = endOfDay.millisecondsSinceEpoch ~/ 1000;

    final List<Map<String, dynamic>> maps = await db.query(
      'appointments',
      where: 'book_id = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [bookId, startTimestamp, endTimestamp],
      orderBy: 'start_time ASC',
    );

    return List.generate(maps.length, (i) => Appointment.fromMap(maps[i]));
  }

  /// 根据ID获取appointment
  Future<Appointment?> getAppointmentById(int id) async {
    if (kIsWeb) {
      return await _webDb.getAppointmentById(id);
    }

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Appointment.fromMap(maps.first);
  }

  /// 创建新appointment
  Future<Appointment> createAppointment(Appointment appointment) async {
    if (kIsWeb) {
      return await _webDb.createAppointment(appointment);
    }

    final db = await database;
    final now = DateTime.now();

    final appointmentToCreate = appointment.copyWith(
      createdAt: now,
      updatedAt: now,
    );

    final id = await db.insert('appointments', appointmentToCreate.toMap());

    return appointmentToCreate.copyWith(id: id);
  }

  /// 更新appointment
  Future<Appointment> updateAppointment(Appointment appointment) async {
    if (kIsWeb) {
      return await _webDb.updateAppointment(appointment);
    }

    if (appointment.id == null) {
      throw ArgumentError('Appointment ID cannot be null for update');
    }

    final db = await database;
    final now = DateTime.now();

    final updatedAppointment = appointment.copyWith(updatedAt: now);
    final updateData = updatedAppointment.toMap();
    updateData.remove('id'); // 移除ID，不更新主键

    final updatedRows = await db.update(
      'appointments',
      updateData,
      where: 'id = ?',
      whereArgs: [appointment.id],
    );

    if (updatedRows == 0) {
      throw Exception('Appointment with id ${appointment.id} not found');
    }

    return updatedAppointment;
  }

  /// 删除appointment
  Future<void> deleteAppointment(int id) async {
    if (kIsWeb) {
      return await _webDb.deleteAppointment(id);
    }

    final db = await database;
    final deletedRows = await db.delete(
      'appointments',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (deletedRows == 0) {
      throw Exception('Appointment with id $id not found');
    }
  }

  /// 获取指定book的appointment总数
  Future<int> getAppointmentCountByBook(int bookId) async {
    if (kIsWeb) {
      return await _webDb.getAppointmentCountByBook(bookId);
    }

    final db = await database;
    final result = await db.query(
      'appointments',
      columns: ['COUNT(*) as count'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );

    return result.first['count'] as int;
  }

  // ====================
  // 数据库维护操作
  // ====================

  /// 清空所有数据（测试用）
  Future<void> clearAllData() async {
    if (kIsWeb) {
      return await _webDb.clearAllData();
    }

    final db = await database;
    await db.delete('appointments');
    await db.delete('books');
  }

  /// 获取数据库版本
  Future<int> getDatabaseVersion() async {
    final db = await database;
    return await db.getVersion();
  }
}