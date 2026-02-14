import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../database/connection.dart';
import '../services/book_pull_service.dart';
import '../services/note_service.dart';

/// Canonical book routes.
///
/// Endpoints:
/// - POST   /api/books
/// - GET    /api/books
/// - GET    /api/books/<bookUuid>
/// - PATCH  /api/books/<bookUuid>
/// - POST   /api/books/<bookUuid>/archive
/// - DELETE /api/books/<bookUuid>
/// - GET    /api/books/<bookUuid>/bundle
class BookRoutes {
  final DatabaseConnection db;
  late final BookPullService _pullService;
  late final NoteService _noteService;

  BookRoutes(this.db) {
    _pullService = BookPullService(db);
    _noteService = NoteService(db);
  }

  Router get router {
    final router = Router();
    router.post('/', _createBook);
    router.get('/', _listBooks);
    router.get('/<bookUuid>', _getBook);
    router.patch('/<bookUuid>', _updateBook);
    router.post('/<bookUuid>/archive', _archiveBook);
    router.delete('/<bookUuid>', _deleteBook);
    router.get('/<bookUuid>/bundle', _getBookBundle);
    return router;
  }

  Future<Map<String, String>?> _auth(Request request) async {
    final deviceId = request.headers['x-device-id'];
    final deviceToken = request.headers['x-device-token'];
    if (deviceId == null || deviceToken == null) {
      return null;
    }
    final valid = await _noteService.verifyDeviceAccess(deviceId, deviceToken);
    if (!valid) return null;
    return {'deviceId': deviceId, 'deviceToken': deviceToken};
  }

  Response _json(int statusCode, Map<String, dynamic> body) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }

  bool _toBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  List<String> _toEventTypes(dynamic value) {
    if (value == null) return const ['other'];
    if (value is List) {
      final cleaned = value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      return cleaned.isEmpty ? const ['other'] : cleaned;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const ['other'];
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {
        return <String>[trimmed];
      }
      return <String>[trimmed];
    }
    return <String>[value.toString()];
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.isUtc ? value : value.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt() * 1000,
        isUtc: true,
      );
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final asInt = int.tryParse(text);
    if (asInt != null) {
      return DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return parsed.isUtc ? parsed : parsed.toUtc();
  }

  Map<String, dynamic> _bookResponse(Map<String, dynamic> row) {
    return {
      'bookUuid': row['book_uuid'],
      'name': row['name'],
      'deviceId': row['device_id'],
      'createdAt': (row['created_at'] as DateTime).toUtc().toIso8601String(),
      'updatedAt': (row['updated_at'] as DateTime).toUtc().toIso8601String(),
      'archivedAt': row['archived_at'] != null
          ? (row['archived_at'] as DateTime).toUtc().toIso8601String()
          : null,
      'version': row['version'],
      'isDeleted': row['is_deleted'] == true,
    };
  }

  Map<String, dynamic> _eventResponse(Map<String, dynamic> row) {
    final eventTypes = _toEventTypes(row['event_types']);
    return {
      'id': row['id'].toString(),
      'bookUuid': row['book_uuid'].toString(),
      'recordUuid': row['record_uuid'].toString(),
      'title': row['title'].toString(),
      'eventTypes': eventTypes,
      'hasChargeItems': row['has_charge_items'] == true,
      'isChecked': row['is_checked'] == true,
      'hasNote': row['has_note'] == true,
      'startTime': (row['start_time'] as DateTime).toUtc().toIso8601String(),
      'endTime': row['end_time'] != null
          ? (row['end_time'] as DateTime).toUtc().toIso8601String()
          : null,
      'createdAt': (row['created_at'] as DateTime).toUtc().toIso8601String(),
      'updatedAt': (row['updated_at'] as DateTime).toUtc().toIso8601String(),
      'isRemoved': row['is_removed'] == true,
      'removalReason': row['removal_reason'],
      'originalEventId': row['original_event_id']?.toString(),
      'newEventId': row['new_event_id']?.toString(),
      'version': row['version'],
      'isDeleted': row['is_deleted'] == true,
      'recordName': row['record_name'],
      'recordNumber': row['record_number'],
      'recordPhone': row['record_phone'],
    };
  }

  Future<Response> _createBook(Request request) async {
    try {
      final auth = await _auth(request);
      if (auth == null) {
        return _json(401, {
          'success': false,
          'message': 'Invalid device credentials',
        });
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final name = (json['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        return _json(400, {
          'success': false,
          'message': 'Book name is required',
        });
      }

      final row = await db.querySingle(
        '''
        INSERT INTO books (book_uuid, device_id, name, created_at, updated_at, synced_at, version, is_deleted)
        VALUES (uuid_generate_v4(), @deviceId, @name, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false)
        RETURNING book_uuid, device_id, name, created_at, updated_at, archived_at, version, is_deleted
        ''',
        parameters: {'deviceId': auth['deviceId'], 'name': name},
      );

      if (row == null) {
        return _json(500, {
          'success': false,
          'message': 'Failed to create book',
        });
      }

      await db.query(
        '''
        INSERT INTO book_device_access (book_uuid, device_id, access_type, created_at)
        VALUES (@bookUuid, @deviceId, 'owner', CURRENT_TIMESTAMP)
        ON CONFLICT (book_uuid, device_id) DO NOTHING
        ''',
        parameters: {
          'bookUuid': row['book_uuid'],
          'deviceId': auth['deviceId'],
        },
      );

      return _json(200, {'success': true, 'book': _bookResponse(row)});
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to create book: $e',
      });
    }
  }

  Future<Response> _listBooks(Request request) async {
    try {
      final auth = await _auth(request);
      if (auth == null) {
        return _json(401, {
          'success': false,
          'message': 'Invalid device credentials',
        });
      }

      final search = request.url.queryParameters['search'];
      final includeArchived = _toBool(
        request.url.queryParameters['includeArchived'],
      );
      final rows = await _pullService.listBooksForDevice(
        auth['deviceId']!,
        searchQuery: search,
      );

      final books = rows
          .where((row) {
            final isDeleted = row['is_deleted'] == true;
            if (isDeleted) return false;
            if (includeArchived) return true;
            return row['archived_at'] == null;
          })
          .map((row) {
            return {
              'bookUuid': row['book_uuid'],
              'name': row['name'],
              'deviceId': row['device_id'],
              'createdAt': row['created_at'],
              'updatedAt': row['updated_at'],
              'archivedAt': row['archived_at'],
              'version': row['version'],
            };
          })
          .toList();

      return _json(200, {
        'success': true,
        'books': books,
        'count': books.length,
      });
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to list books: $e',
      });
    }
  }

  Future<Response> _getBook(Request request, String bookUuid) async {
    try {
      final auth = await _auth(request);
      if (auth == null) {
        return _json(401, {
          'success': false,
          'message': 'Invalid device credentials',
        });
      }

      final canAccess = await _noteService.verifyBookOwnership(
        auth['deviceId']!,
        bookUuid,
      );
      if (!canAccess) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }

      final book = await _pullService.getBookMetadata(
        bookUuid,
        auth['deviceId']!,
      );
      return _json(200, {
        'success': true,
        'book': {
          'bookUuid': book['book_uuid'],
          'name': book['name'],
          'createdAt': book['created_at'],
          'updatedAt': book['updated_at'],
          'archivedAt': book['archived_at'],
          'version': book['version'],
          'isDeleted': book['is_deleted'],
        },
      });
    } catch (e) {
      if (e.toString().contains('Book not found')) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }
      return _json(500, {
        'success': false,
        'message': 'Failed to get book: $e',
      });
    }
  }

  Future<Response> _updateBook(Request request, String bookUuid) async {
    try {
      final auth = await _auth(request);
      if (auth == null) {
        return _json(401, {
          'success': false,
          'message': 'Invalid device credentials',
        });
      }

      final canAccess = await _noteService.verifyBookOwnership(
        auth['deviceId']!,
        bookUuid,
      );
      if (!canAccess) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final name = (json['name'] as String?)?.trim();
      if (name == null || name.isEmpty) {
        return _json(400, {
          'success': false,
          'message': 'Book name is required',
        });
      }

      final row = await db.querySingle(
        '''
        UPDATE books
        SET
          name = @name,
          updated_at = CURRENT_TIMESTAMP,
          synced_at = CURRENT_TIMESTAMP,
          version = version + 1
        WHERE book_uuid = @bookUuid
          AND is_deleted = false
        RETURNING book_uuid, device_id, name, created_at, updated_at, archived_at, version, is_deleted
        ''',
        parameters: {'bookUuid': bookUuid, 'name': name},
      );

      if (row == null) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }

      return _json(200, {'success': true, 'book': _bookResponse(row)});
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to update book: $e',
      });
    }
  }

  Future<Response> _archiveBook(Request request, String bookUuid) async {
    try {
      final auth = await _auth(request);
      if (auth == null) {
        return _json(401, {
          'success': false,
          'message': 'Invalid device credentials',
        });
      }

      final canAccess = await _noteService.verifyBookOwnership(
        auth['deviceId']!,
        bookUuid,
      );
      if (!canAccess) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }

      final row = await db.querySingle(
        '''
        UPDATE books
        SET
          archived_at = CURRENT_TIMESTAMP,
          updated_at = CURRENT_TIMESTAMP,
          synced_at = CURRENT_TIMESTAMP,
          version = version + 1
        WHERE book_uuid = @bookUuid
          AND is_deleted = false
          AND archived_at IS NULL
        RETURNING book_uuid, device_id, name, created_at, updated_at, archived_at, version, is_deleted
        ''',
        parameters: {'bookUuid': bookUuid},
      );

      if (row == null) {
        return _json(404, {
          'success': false,
          'message': 'Book not found or already archived',
        });
      }

      return _json(200, {'success': true, 'book': _bookResponse(row)});
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to archive book: $e',
      });
    }
  }

  Future<Response> _deleteBook(Request request, String bookUuid) async {
    try {
      final auth = await _auth(request);
      if (auth == null) {
        return _json(401, {
          'success': false,
          'message': 'Invalid device credentials',
        });
      }

      final canAccess = await _noteService.verifyBookOwnership(
        auth['deviceId']!,
        bookUuid,
      );
      if (!canAccess) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }

      final row = await db.querySingle(
        '''
        UPDATE books
        SET
          is_deleted = true,
          updated_at = CURRENT_TIMESTAMP,
          synced_at = CURRENT_TIMESTAMP,
          version = version + 1
        WHERE book_uuid = @bookUuid
          AND is_deleted = false
        RETURNING book_uuid, device_id, name, created_at, updated_at, archived_at, version, is_deleted
        ''',
        parameters: {'bookUuid': bookUuid},
      );

      if (row == null) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }

      return _json(200, {'success': true});
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to delete book: $e',
      });
    }
  }

  Future<Response> _getBookBundle(Request request, String bookUuid) async {
    try {
      final auth = await _auth(request);
      if (auth == null) {
        return _json(401, {
          'success': false,
          'message': 'Invalid device credentials',
        });
      }

      final canAccess = await _noteService.verifyBookOwnership(
        auth['deviceId']!,
        bookUuid,
      );
      if (!canAccess) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }

      final bundle = await _pullService.getCompleteBookData(
        bookUuid,
        auth['deviceId']!,
      );
      final book = bundle['book'] as Map<String, dynamic>;
      final eventsRaw = (bundle['events'] as List).cast<Map<String, dynamic>>();
      final notesRaw = (bundle['notes'] as List).cast<Map<String, dynamic>>();
      final drawingsRaw = (bundle['drawings'] as List)
          .cast<Map<String, dynamic>>();

      final events = eventsRaw.map((e) {
        return {
          'id': e['id'],
          'bookUuid': e['book_uuid'],
          'recordUuid': e['record_uuid'],
          'title': e['title'],
          'name': e['name'],
          'recordNumber': e['record_number'],
          'phone': e['phone'],
          'eventType': e['event_type'],
          'eventTypes': _toEventTypes(e['event_types']),
          'hasChargeItems': e['has_charge_items'] == true,
          'isChecked': e['is_checked'] == true,
          'hasNote': e['has_note'] == true,
          'startTime': e['start_time'],
          'endTime': e['end_time'],
          'createdAt': e['created_at'],
          'updatedAt': e['updated_at'],
          'isRemoved': e['is_removed'] == true,
          'removalReason': e['removal_reason'],
          'originalEventId': e['original_event_id'],
          'newEventId': e['new_event_id'],
          'version': e['version'],
          'isDeleted': e['is_deleted'] == true,
        };
      }).toList();

      final notes = notesRaw.map((n) {
        return {
          'id': n['id'],
          'recordUuid': n['record_uuid'],
          'pagesData': n['pages_data'],
          'createdAt': n['created_at'],
          'updatedAt': n['updated_at'],
          'version': n['version'],
          'isDeleted': n['is_deleted'] == true,
        };
      }).toList();

      final drawings = drawingsRaw.map((d) {
        return {
          'id': d['id'],
          'bookUuid': d['book_uuid'],
          'date': d['date'],
          'viewMode': d['view_mode'],
          'strokesData': d['strokes_data'],
          'createdAt': d['created_at'],
          'updatedAt': d['updated_at'],
          'version': d['version'],
          'isDeleted': d['is_deleted'] == true,
        };
      }).toList();

      return _json(200, {
        'success': true,
        'bundle': {
          'book': {
            'bookUuid': book['book_uuid'],
            'name': book['name'],
            'createdAt': book['created_at'],
            'updatedAt': book['updated_at'],
            'archivedAt': book['archived_at'],
            'version': book['version'],
            'isDeleted': book['is_deleted'],
          },
          'events': events,
          'notes': notes,
          'drawings': drawings,
        },
      });
    } catch (e) {
      if (e.toString().contains('Book not found')) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }
      return _json(500, {
        'success': false,
        'message': 'Failed to load book bundle: $e',
      });
    }
  }

  // Event write endpoints are mounted in EventRoutes, but this utility is kept
  // for future extension where book and event endpoints are merged.
  Map<String, dynamic> eventRowToResponse(Map<String, dynamic> row) {
    return _eventResponse(row);
  }

  Future<Map<String, dynamic>> ensureRecordExists({
    required String recordUuid,
    String? recordNumber,
    String? name,
    String? phone,
  }) async {
    final row = await db.querySingle(
      '''
      INSERT INTO records (record_uuid, record_number, name, phone, created_at, updated_at, synced_at, version, is_deleted)
      VALUES (@recordUuid, @recordNumber, @name, @phone, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, false)
      ON CONFLICT (record_uuid) DO UPDATE
      SET
        record_number = COALESCE(NULLIF(@recordNumber, ''), records.record_number),
        name = COALESCE(@name, records.name),
        phone = COALESCE(@phone, records.phone),
        updated_at = CURRENT_TIMESTAMP,
        synced_at = CURRENT_TIMESTAMP
      RETURNING record_uuid, record_number, name, phone
      ''',
      parameters: {
        'recordUuid': recordUuid,
        'recordNumber': recordNumber ?? '',
        'name': name,
        'phone': phone,
      },
    );
    return row ??
        {
          'record_uuid': recordUuid,
          'record_number': recordNumber ?? '',
          'name': name,
          'phone': phone,
        };
  }

  DateTime? parseTimestamp(dynamic value) => _parseTimestamp(value);
  List<String> normalizeEventTypes(dynamic value) => _toEventTypes(value);
}
