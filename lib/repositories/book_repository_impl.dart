import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import '../models/book.dart';
import '../services/api_client.dart';
import '../services/database/prd_database_service.dart';
import 'book_repository.dart';
import 'base_repository.dart';

/// Implementation of BookRepository using SQLite
class BookRepositoryImpl extends BaseRepository<Book, int> implements IBookRepository {
  final ApiClient? _apiClient;
  final PRDDatabaseService? _dbService;

  BookRepositoryImpl(
    Future<Database> Function() getDatabaseFn, {
    ApiClient? apiClient,
    PRDDatabaseService? dbService,
  })  : _apiClient = apiClient,
        _dbService = dbService,
        super(getDatabaseFn);

  @override
  String get tableName => 'books';

  @override
  Book fromMap(Map<String, dynamic> map) => Book.fromMap(map);

  @override
  Map<String, dynamic> toMap(Book entity) => entity.toMap();

  @override
  Future<List<Book>> getAll({bool includeArchived = false}) async {
    if (includeArchived) {
      return queryAll(orderBy: 'created_at DESC');
    }
    // Use custom query for non-archived books
    return query(
      where: 'archived_at IS NULL',
      orderBy: 'created_at DESC',
    );
  }

  @override
  Future<Book?> getByUuid(String uuid) async {
    final results = await query(
      where: 'book_uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  @override
  Future<Book> create(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    // Step 1: Call server API to create book and get UUID
    if (_apiClient == null || _dbService == null) {
      throw Exception('API client or database service not configured. Book creation requires server connection.');
    }

    final credentials = await _dbService!.getDeviceCredentials();
    if (credentials == null) {
      throw Exception('Device not registered. Please register device before creating books.');
    }

    final now = DateTime.now();

    try {
      // Call /api/create-books endpoint
      final response = await _apiClient!.createBook(
        name: name.trim(),
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      final serverUuid = response['uuid'] as String;

      debugPrint('✅ Book created on server with UUID: $serverUuid');

      // Step 2: Create book locally with server-provided UUID
      await insert({
        'book_uuid': serverUuid,
        'name': name.trim(),
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
      });

      return Book(
        uuid: serverUuid,
        name: name.trim(),
        createdAt: now,
      );
    } catch (e) {
      debugPrint('❌ Failed to create book: $e');
      throw Exception('Failed to create book: Server connection required. $e');
    }
  }

  @override
  Future<Book> update(Book book) async {
    if (book.name.trim().isEmpty) throw ArgumentError('Book name cannot be empty');

    final db = await getDatabaseFn();
    final updatedRows = await db.update(
      'books',
      {'name': book.name.trim()},
      where: 'book_uuid = ?',
      whereArgs: [book.uuid],
    );

    if (updatedRows == 0) throw Exception('Book not found');
    return book.copyWith(name: book.name.trim());
  }

  @override
  Future<void> delete(String uuid) async {
    final db = await getDatabaseFn();
    final deletedRows = await db.delete(
      'books',
      where: 'book_uuid = ?',
      whereArgs: [uuid],
    );
    if (deletedRows == 0) throw Exception('Book not found');
  }

  /// Archive a book (soft delete)
  @override
  Future<void> archive(String uuid) async {
    final db = await getDatabaseFn();
    final now = DateTime.now();
    final updatedRows = await db.update(
      'books',
      {'archived_at': now.millisecondsSinceEpoch ~/ 1000},
      where: 'book_uuid = ? AND archived_at IS NULL',
      whereArgs: [uuid],
    );
    if (updatedRows == 0) throw Exception('Book not found or already archived');
  }

  @override
  Future<void> reorder(List<Book> books) async {
    // Note: Book model doesn't have an 'order' field currently
    // This is a placeholder for future implementation
    // For now, ordering is handled by created_at DESC in getAll()
    // and by BookOrderService which uses SharedPreferences
    debugPrint('⚠️ Book.reorder() called but not implemented - use BookOrderService instead');
  }
}
