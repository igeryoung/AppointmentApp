import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../services/api_client.dart';
import '../services/database/prd_database_service.dart';
import 'book_repository.dart';
import 'base_repository.dart';

/// Implementation of BookRepository using SQLite as local cache,
/// with server as source of truth.
class BookRepositoryImpl extends BaseRepository<Book, int>
    implements IBookRepository {
  final ApiClient? _apiClient;
  final PRDDatabaseService? _dbService;

  BookRepositoryImpl(
    Future<Database> Function() getDatabaseFn, {
    ApiClient? apiClient,
    PRDDatabaseService? dbService,
  }) : _apiClient = apiClient,
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
    return query(where: 'archived_at IS NULL', orderBy: 'created_at DESC');
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

  Future<DeviceCredentials> _requireCredentials(String action) async {
    if (_dbService == null) {
      throw Exception(
        'Database service not configured. $action requires device credentials.',
      );
    }
    final credentials = await _dbService.getDeviceCredentials();
    if (credentials == null) {
      throw Exception(
        'Device not registered. Please register device before $action.',
      );
    }
    return credentials;
  }

  dynamic _pick(Map<String, dynamic> map, String camel, String snake) {
    if (map.containsKey(camel)) return map[camel];
    return map[snake];
  }

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

  int _toSeconds(dynamic value) =>
      _parseServerTimestamp(value).millisecondsSinceEpoch ~/ 1000;
  int? _toSecondsOrNull(dynamic value) =>
      value == null ? null : _toSeconds(value);

  @override
  Future<Book> create(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    if (_apiClient == null) {
      throw Exception(
        'API client not configured. Book creation requires server connection.',
      );
    }

    final credentials = await _requireCredentials('creating books');
    final now = DateTime.now().toUtc();

    try {
      final response = await _apiClient.createBook(
        name: trimmedName,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
      final serverUuid =
          (response['uuid'] ?? response['bookUuid'] ?? response['book_uuid'])
              as String;

      await insert({
        'book_uuid': serverUuid,
        'name': trimmedName,
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
      });

      return Book(uuid: serverUuid, name: trimmedName, createdAt: now);
    } catch (e) {
      throw Exception('Failed to create book: Server connection required. $e');
    }
  }

  @override
  Future<Book> update(Book book) async {
    final trimmedName = book.name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Book name cannot be empty');

    final db = await getDatabaseFn();
    final existingRows = await db.query(
      'books',
      columns: ['book_uuid', 'version'],
      where: 'book_uuid = ?',
      whereArgs: [book.uuid],
      limit: 1,
    );
    if (existingRows.isEmpty) throw Exception('Book not found');

    final rawVersion = existingRows.first['version'];
    final currentVersion = rawVersion is int
        ? rawVersion
        : int.tryParse(rawVersion?.toString() ?? '') ?? 1;
    final nextVersion = currentVersion + 1;

    if (_apiClient != null) {
      final credentials = await _requireCredentials('updating books');
      await _apiClient.updateBook(
        bookUuid: book.uuid,
        name: trimmedName,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
    }

    final updatedRows = await db.update(
      'books',
      {'name': trimmedName, 'version': nextVersion, 'is_dirty': 0},
      where: 'book_uuid = ?',
      whereArgs: [book.uuid],
    );

    if (updatedRows == 0) throw Exception('Book not found');
    return book.copyWith(name: trimmedName);
  }

  @override
  Future<void> delete(String uuid) async {
    // Device-level delete: remove only local copy.
    // Server copy stays available for future import.

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
    if (_apiClient != null) {
      final credentials = await _requireCredentials('archiving books');
      await _apiClient.archiveBook(
        bookUuid: uuid,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );
    }

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
    // Ordering handled by BookOrderService (SharedPreferences).
  }

  @override
  Future<List<Map<String, dynamic>>> listServerBooks({
    String? searchQuery,
  }) async {
    if (_apiClient == null) {
      throw Exception(
        'API client not configured. Server operations require configuration.',
      );
    }
    final credentials = await _requireCredentials('accessing server books');

    return _apiClient.listServerBooks(
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
      searchQuery: searchQuery,
    );
  }

  @override
  Future<void> pullBookFromServer(String bookUuid) async {
    if (_apiClient == null) {
      throw Exception(
        'API client not configured. Book pull requires server connection.',
      );
    }
    final credentials = await _requireCredentials('pulling books');

    final existingBook = await getByUuid(bookUuid);
    if (existingBook != null) {
      throw Exception(
        'Book already exists locally. Cannot pull book that already exists.',
      );
    }

    try {
      final bookData = await _apiClient.pullBook(
        bookUuid: bookUuid,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      );

      final db = await getDatabaseFn();
      final events =
          (bookData['events'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final notes =
          (bookData['notes'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final drawings =
          (bookData['drawings'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];

      await db.transaction((txn) async {
        final bookMap = bookData['book'] as Map<String, dynamic>;
        await txn.insert('books', {
          'book_uuid': _pick(bookMap, 'bookUuid', 'book_uuid'),
          'name': bookMap['name'],
          'created_at': _toSeconds(_pick(bookMap, 'createdAt', 'created_at')),
          'archived_at': null,
          'version': bookMap['version'] ?? 1,
          'is_dirty': 0,
        });

        for (final event in events) {
          final recordUuid = (_pick(event, 'recordUuid', 'record_uuid') ?? '')
              .toString();
          if (recordUuid.isEmpty) {
            continue;
          }

          await txn.insert('records', {
            'record_uuid': recordUuid,
            'record_number':
                (_pick(event, 'recordNumber', 'record_number') ?? '')
                    .toString(),
            'name':
                (_pick(event, 'name', 'name') ?? _pick(event, 'title', 'title'))
                    ?.toString(),
            'phone': _pick(event, 'phone', 'phone')?.toString(),
            'version': 1,
            'is_dirty': 0,
            'is_deleted': 0,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);

          final eventTypesValue = _pick(event, 'eventTypes', 'event_types');
          final eventTypes = eventTypesValue is List
              ? jsonEncode(eventTypesValue)
              : (eventTypesValue?.toString() ?? '[]');

          await txn.insert('events', {
            'id': _pick(event, 'id', 'id'),
            'book_uuid': _pick(event, 'bookUuid', 'book_uuid') ?? bookUuid,
            'record_uuid': recordUuid,
            'title': _pick(event, 'title', 'title')?.toString() ?? '',
            'record_number':
                (_pick(event, 'recordNumber', 'record_number') ?? '')
                    .toString(),
            'event_types': eventTypes,
            'has_charge_items':
                _pick(event, 'hasChargeItems', 'has_charge_items') == true
                ? 1
                : 0,
            'start_time': _toSeconds(_pick(event, 'startTime', 'start_time')),
            'end_time': _toSecondsOrNull(_pick(event, 'endTime', 'end_time')),
            'created_at': _toSeconds(_pick(event, 'createdAt', 'created_at')),
            'updated_at':
                _toSecondsOrNull(_pick(event, 'updatedAt', 'updated_at')) ??
                _toSeconds(_pick(event, 'createdAt', 'created_at')),
            'is_removed': _pick(event, 'isRemoved', 'is_removed') == true
                ? 1
                : 0,
            'removal_reason': _pick(event, 'removalReason', 'removal_reason'),
            'original_event_id': _pick(
              event,
              'originalEventId',
              'original_event_id',
            ),
            'new_event_id': _pick(event, 'newEventId', 'new_event_id'),
            'is_checked': _pick(event, 'isChecked', 'is_checked') == true
                ? 1
                : 0,
            'has_note': _pick(event, 'hasNote', 'has_note') == true ? 1 : 0,
            'version': _pick(event, 'version', 'version') ?? 1,
            'is_dirty': 0,
          });
        }

        for (final note in notes) {
          final createdAt = _toSeconds(_pick(note, 'createdAt', 'created_at'));
          final updatedAt =
              _toSecondsOrNull(_pick(note, 'updatedAt', 'updated_at')) ??
              createdAt;
          await txn.insert('notes', {
            'record_uuid': _pick(note, 'recordUuid', 'record_uuid'),
            'pages_data': _pick(note, 'pagesData', 'pages_data'),
            'created_at': createdAt,
            'updated_at': updatedAt,
            'version': _pick(note, 'version', 'version') ?? 1,
            'is_dirty': 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (final drawing in drawings) {
          await txn.insert('schedule_drawings', {
            'book_uuid': _pick(drawing, 'bookUuid', 'book_uuid') ?? bookUuid,
            'date': _toSeconds(_pick(drawing, 'date', 'date')),
            'view_mode': _pick(drawing, 'viewMode', 'view_mode') ?? 0,
            'strokes_data': _pick(drawing, 'strokesData', 'strokes_data'),
            'created_at': _toSeconds(_pick(drawing, 'createdAt', 'created_at')),
            'updated_at':
                _toSecondsOrNull(_pick(drawing, 'updatedAt', 'updated_at')) ??
                _toSeconds(_pick(drawing, 'createdAt', 'created_at')),
            'version': _pick(drawing, 'version', 'version') ?? 1,
            'is_dirty': 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    } catch (e) {
      throw Exception('Failed to pull book from server: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> getServerBookInfo(String bookUuid) async {
    if (_apiClient == null) {
      throw Exception(
        'API client not configured. Server operations require configuration.',
      );
    }
    final credentials = await _requireCredentials('accessing server books');

    try {
      return await _apiClient.getServerBookInfo(
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
