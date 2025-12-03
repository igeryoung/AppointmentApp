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

    final now = DateTime.now().toUtc();

    try {
      // Call /api/create-books endpoint
      final response = await _apiClient!.createBook(
        name: name.trim(),
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      final serverUuid = response['uuid'] as String;


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
    final now = DateTime.now().toUtc();
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
      final bookData = await _apiClient!.pullBook(
        bookUuid: bookUuid,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      DateTime _parseServerTimestamp(dynamic value) {
        if (value == null) {
          throw ArgumentError('Server timestamp is null');
        }

        if (value is int) {
          return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
        }

        if (value is String) {
          final parsed = DateTime.parse(value);
          if (parsed.isUtc) return parsed;
          return DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          );
        }

        if (value is DateTime) {
          if (value.isUtc) return value;
          return DateTime.utc(
            value.year,
            value.month,
            value.day,
            value.hour,
            value.minute,
            value.second,
            value.millisecond,
            value.microsecond,
          );
        }

        throw ArgumentError('Unsupported timestamp type: ${value.runtimeType}');
      }

      int _toSeconds(dynamic value) => _parseServerTimestamp(value).millisecondsSinceEpoch ~/ 1000;
      int? _toSecondsOrNull(dynamic value) => value == null ? null : _toSeconds(value);

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
          'created_at': _toSeconds(bookMap['created_at']),
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
            'has_charge_items': event['has_charge_items'] == true ? 1 : 0,
            'start_time': _toSeconds(event['start_time']),
            'end_time': _toSecondsOrNull(event['end_time']),
            'created_at': _toSeconds(event['created_at']),
            'updated_at': event['updated_at'] != null
                ? _toSeconds(event['updated_at'])
                : _toSeconds(event['created_at']),
            'is_removed': event['is_removed'] == true ? 1 : 0,
            'removal_reason': event['removal_reason'],
            'original_event_id': event['original_event_id'],
            'new_event_id': event['new_event_id'],
            'is_checked': event['is_checked'] == true ? 1 : 0,
            'has_note': event['has_note'] == true ? 1 : 0,
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
            'created_at': _toSeconds(note['created_at']),
            'updated_at': note['updated_at'] != null
                ? _toSeconds(note['updated_at'])
                : _toSeconds(note['created_at']),
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
            'date': _toSeconds(drawing['date']),
            'view_mode': drawing['view_mode'],
            'strokes_data': drawing['strokes_data'],
            'created_at': _toSeconds(drawing['created_at']),
            'updated_at': drawing['updated_at'] != null
                ? _toSeconds(drawing['updated_at'])
                : _toSeconds(drawing['created_at']),
            'version': drawing['version'],
            'is_dirty': 0,
          });
        }
      });

    } catch (e) {
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
      rethrow;
    }
  }
}
