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

  @override
  Future<List<Map<String, dynamic>>> listServerBooks({String? searchQuery}) async {
    if (_apiClient == null || _dbService == null) {
      throw Exception('API client or database service not configured. Server operations require configuration.');
    }

    final credentials = await _dbService!.getDeviceCredentials();
    if (credentials == null) {
      throw Exception('Device not registered. Please register device before accessing server books.');
    }

    try {
      return await _apiClient!.listServerBooks(
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
        searchQuery: searchQuery,
      );
    } catch (e) {
      debugPrint('❌ Failed to list server books: $e');
      rethrow;
    }
  }

  @override
  Future<void> pullBookFromServer(String bookUuid) async {
    if (_apiClient == null || _dbService == null) {
      throw Exception('API client or database service not configured. Book pull requires server connection.');
    }

    final credentials = await _dbService!.getDeviceCredentials();
    if (credentials == null) {
      throw Exception('Device not registered. Please register device before pulling books.');
    }

    // Check if book already exists locally
    final existingBook = await getByUuid(bookUuid);
    if (existingBook != null) {
      throw Exception('Book already exists locally. Cannot pull book that already exists.');
    }

    try {
      // Pull complete book data from server
      debugPrint('📥 Pulling book from server: $bookUuid');
      final bookData = await _apiClient!.pullBook(
        bookUuid: bookUuid,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      final db = await getDatabaseFn();

      // Extract counts for logging
      final events = bookData['events'] as List;
      final notes = bookData['notes'] as List;
      final drawings = bookData['drawings'] as List;

      // Use transaction to ensure atomicity
      await db.transaction((txn) async {
        // 1. Insert book
        final bookMap = bookData['book'] as Map<String, dynamic>;
        await txn.insert('books', {
          'book_uuid': bookMap['book_uuid'],
          'name': bookMap['name'],
          'created_at': DateTime.parse(bookMap['created_at'] as String).millisecondsSinceEpoch ~/ 1000,
          'archived_at': null,  // Clear archived status when pulling from server
          'version': bookMap['version'],
          'is_dirty': 0,
        });

        // 2. Insert events
        for (final eventMap in events) {
          final event = eventMap as Map<String, dynamic>;
          await txn.insert('events', {
            'id': event['id'],
            'book_uuid': event['book_uuid'],
            'name': event['name'],
            'record_number': event['record_number'],
            'phone': event['phone'],
            'event_type': event['event_type'],
            'event_types': event['event_types'] ?? '[]',
            'has_charge_items': event['has_charge_items'] ?? 0,
            'start_time': DateTime.parse(event['start_time'] as String).millisecondsSinceEpoch ~/ 1000,
            'end_time': event['end_time'] != null
                ? DateTime.parse(event['end_time'] as String).millisecondsSinceEpoch ~/ 1000
                : null,
            'created_at': DateTime.parse(event['created_at'] as String).millisecondsSinceEpoch ~/ 1000,
            'updated_at': event['updated_at'] != null
                ? DateTime.parse(event['updated_at'] as String).millisecondsSinceEpoch ~/ 1000
                : DateTime.parse(event['created_at'] as String).millisecondsSinceEpoch ~/ 1000,
            'is_removed': event['is_removed'] == true ? 1 : 0,
            'removal_reason': event['removal_reason'],
            'original_event_id': event['original_event_id'],
            'new_event_id': event['new_event_id'],
            'is_checked': event['is_checked'] ?? 0,
            'has_note': event['has_note'] ?? 0,
            'version': event['version'],
            'is_dirty': 0,
          });
        }

        // 3. Insert notes
        for (final noteMap in notes) {
          final note = noteMap as Map<String, dynamic>;
          await txn.insert('notes', {
            'id': note['id'],
            'event_id': note['event_id'],
            'strokes_data': note['strokes_data'],
            'pages_data': note['pages_data'],
            'created_at': DateTime.parse(note['created_at'] as String).millisecondsSinceEpoch ~/ 1000,
            'updated_at': note['updated_at'] != null
                ? DateTime.parse(note['updated_at'] as String).millisecondsSinceEpoch ~/ 1000
                : DateTime.parse(note['created_at'] as String).millisecondsSinceEpoch ~/ 1000,
            'version': note['version'],
            'is_dirty': 0,
          });
        }

        // 4. Insert schedule drawings
        for (final drawingMap in drawings) {
          final drawing = drawingMap as Map<String, dynamic>;
          await txn.insert('schedule_drawings', {
            'id': drawing['id'],
            'book_uuid': drawing['book_uuid'],
            'date': DateTime.parse(drawing['date'] as String).millisecondsSinceEpoch ~/ 1000,
            'view_mode': drawing['view_mode'],
            'strokes_data': drawing['strokes_data'],
            'created_at': DateTime.parse(drawing['created_at'] as String).millisecondsSinceEpoch ~/ 1000,
            'updated_at': drawing['updated_at'] != null
                ? DateTime.parse(drawing['updated_at'] as String).millisecondsSinceEpoch ~/ 1000
                : DateTime.parse(drawing['created_at'] as String).millisecondsSinceEpoch ~/ 1000,
            'version': drawing['version'],
            'is_dirty': 0,
          });
        }
      });

      debugPrint('✅ Book pulled successfully: $bookUuid');
      debugPrint('   - Events: ${events.length}');
      debugPrint('   - Notes: ${notes.length}');
      debugPrint('   - Drawings: ${drawings.length}');
    } catch (e) {
      debugPrint('❌ Failed to pull book from server: $e');
      throw Exception('Failed to pull book from server: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> getServerBookInfo(String bookUuid) async {
    if (_apiClient == null || _dbService == null) {
      throw Exception('API client or database service not configured. Server operations require configuration.');
    }

    final credentials = await _dbService!.getDeviceCredentials();
    if (credentials == null) {
      throw Exception('Device not registered. Please register device before accessing server books.');
    }

    try {
      return await _apiClient!.getServerBookInfo(
        bookUuid: bookUuid,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
    } catch (e) {
      if (e is ApiException && e.statusCode == 404) {
        return null;
      }
      debugPrint('❌ Failed to get server book info: $e');
      rethrow;
    }
  }
}
