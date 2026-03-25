import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../database/connection.dart';
import '../services/book_access_service.dart';
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
  late final BookAccessService _bookAccessService;

  BookRoutes(this.db) {
    _pullService = BookPullService(db);
    _noteService = NoteService(db);
    _bookAccessService = BookAccessService(db);
  }

  Router get router {
    final router = Router();
    router.post('/', _createBook);
    router.get('/', _listBooks);
    router.get('/<bookUuid>', _getBook);
    router.patch('/<bookUuid>', _updateBook);
    router.post('/<bookUuid>/archive', _archiveBook);
    router.delete('/<bookUuid>', _deleteBook);
    router.post('/<bookUuid>/access', _grantBookAccess);
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
    final role = await _noteService.getDeviceRole(deviceId);
    return {
      'deviceId': deviceId,
      'deviceToken': deviceToken,
      'deviceRole': role,
    };
  }

  Response _json(int statusCode, Map<String, dynamic> body) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }

  bool _isReadOnlyRole(String? role) => role == NoteService.roleRead;

  Future<bool> _hasWriteAccess({
    required String deviceId,
    required String bookUuid,
  }) async {
    return _bookAccessService.verifyBookAccess(
      deviceId,
      bookUuid,
      requireWrite: true,
    );
  }

  Future<void> _ensureMembership({
    required String deviceId,
    required String bookUuid,
  }) async {
    final existing = await db.client
        .from('book_device_access')
        .select('book_uuid')
        .eq('book_uuid', bookUuid)
        .eq('device_id', deviceId)
        .limit(1);
    if (_first(existing) != null) return;
    await _bookAccessService.grantBookAccess(
      bookUuid: bookUuid,
      deviceId: deviceId,
    );
  }

  Map<String, dynamic>? _first(dynamic data) {
    if (data is List && data.isNotEmpty) {
      final row = data.first;
      if (row is Map<String, dynamic>) return row;
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    return null;
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

  String? _toIsoUtc(dynamic value) {
    final parsed = _parseTimestamp(value);
    return parsed?.toIso8601String();
  }

  String _hashBookPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  String _readBookPasswordFromHeader(Request request) {
    return request.headers['x-book-password']?.trim() ?? '';
  }

  Future<Map<String, dynamic>?> _loadBookPasswordRow(String bookUuid) async {
    final rows = await db.client
        .from('books')
        .select('book_uuid, book_password_hash, is_deleted')
        .eq('book_uuid', bookUuid)
        .limit(1);
    return _first(rows);
  }

  Future<Response?> _requireValidBookPassword(
    Request request,
    String bookUuid,
  ) async {
    final book = await _loadBookPasswordRow(bookUuid);
    if (book == null || book['is_deleted'] == true) {
      return _json(404, {'success': false, 'message': 'Book not found'});
    }

    final storedHash = (book['book_password_hash'] ?? '').toString().trim();
    if (storedHash.isEmpty) {
      // Backward compatibility for old books created before password rollout.
      return null;
    }

    final providedPassword = _readBookPasswordFromHeader(request);
    if (providedPassword.isEmpty ||
        _hashBookPassword(providedPassword) != storedHash) {
      return _json(403, {
        'success': false,
        'message': 'Invalid book password',
        'error': 'INVALID_BOOK_PASSWORD',
      });
    }

    return null;
  }

  Map<String, dynamic> _bookResponse(Map<String, dynamic> row) {
    return {
      'bookUuid': row['book_uuid'],
      'name': row['name'],
      'deviceId': row['device_id'],
      'createdAt': _toIsoUtc(row['created_at']),
      'updatedAt': _toIsoUtc(row['updated_at']),
      'archivedAt': _toIsoUtc(row['archived_at']),
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
      'startTime': _toIsoUtc(row['start_time']),
      'endTime': _toIsoUtc(row['end_time']),
      'createdAt': _toIsoUtc(row['created_at']),
      'updatedAt': _toIsoUtc(row['updated_at']),
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
      if (_isReadOnlyRole(auth['deviceRole'])) {
        return _json(403, {
          'success': false,
          'message': 'Read-only device cannot create books',
          'error': 'READ_ONLY_DEVICE',
        });
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final name = (json['name'] as String?)?.trim() ?? '';
      final password =
          ((json['bookPassword'] ?? json['password']) as String?)?.trim() ?? '';
      if (name.isEmpty) {
        return _json(400, {
          'success': false,
          'message': 'Book name is required',
        });
      }
      if (password.isEmpty) {
        return _json(400, {
          'success': false,
          'message': 'Book password is required',
        });
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final inserted = await db.client
          .from('books')
          .insert({
            'device_id': auth['deviceId'],
            'name': name,
            'book_password_hash': _hashBookPassword(password),
            'created_at': now,
            'updated_at': now,
            'synced_at': now,
            'version': 1,
            'is_deleted': false,
          })
          .select(
            'book_uuid, device_id, name, created_at, updated_at, archived_at, version, is_deleted',
          )
          .limit(1);
      final row = _first(inserted);

      if (row == null) {
        return _json(500, {
          'success': false,
          'message': 'Failed to create book',
        });
      }

      await _bookAccessService.grantBookAccess(
        bookUuid: row['book_uuid'].toString(),
        deviceId: auth['deviceId']!,
      );

      return _json(200, {'success': true, 'book': _bookResponse(row)});
    } catch (e) {
      final errorText = e.toString().toLowerCase();
      if (errorText.contains('book_password_hash') &&
          errorText.contains('column')) {
        return _json(500, {
          'success': false,
          'message':
              'Database migration required: missing books.book_password_hash column',
          'error': 'DB_MIGRATION_REQUIRED',
        });
      }
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

      final passwordValidation = await _requireValidBookPassword(
        request,
        bookUuid,
      );
      if (passwordValidation != null) {
        return passwordValidation;
      }

      final canAccess = await _noteService.verifyBookOwnership(
        auth['deviceId']!,
        bookUuid,
      );
      if (!canAccess) {
        await _ensureMembership(
          deviceId: auth['deviceId']!,
          bookUuid: bookUuid,
        );
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
      final canAccess = await _hasWriteAccess(
        deviceId: auth['deviceId']!,
        bookUuid: bookUuid,
      );
      if (!canAccess) {
        return _json(403, {
          'success': false,
          'message': 'Book is not writable for this device',
          'error': 'READ_ONLY_BOOK',
        });
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

      final currentRows = await db.client
          .from('books')
          .select('version')
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .limit(1);
      final current = _first(currentRows);
      if (current == null) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }
      final rowList = await db.client
          .from('books')
          .update({
            'name': name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'version': ((current['version'] as num?)?.toInt() ?? 1) + 1,
          })
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .select(
            'book_uuid, device_id, name, created_at, updated_at, archived_at, version, is_deleted',
          )
          .limit(1);
      final row = _first(rowList);

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
      final canAccess = await _hasWriteAccess(
        deviceId: auth['deviceId']!,
        bookUuid: bookUuid,
      );
      if (!canAccess) {
        return _json(403, {
          'success': false,
          'message': 'Book is not writable for this device',
          'error': 'READ_ONLY_BOOK',
        });
      }

      final currentRows = await db.client
          .from('books')
          .select('version, archived_at')
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .limit(1);
      final current = _first(currentRows);
      if (current == null || current['archived_at'] != null) {
        return _json(404, {
          'success': false,
          'message': 'Book not found or already archived',
        });
      }
      final rowList = await db.client
          .from('books')
          .update({
            'archived_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'version': ((current['version'] as num?)?.toInt() ?? 1) + 1,
          })
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .select(
            'book_uuid, device_id, name, created_at, updated_at, archived_at, version, is_deleted',
          )
          .limit(1);
      final row = _first(rowList);

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
      final canAccess = await _hasWriteAccess(
        deviceId: auth['deviceId']!,
        bookUuid: bookUuid,
      );
      if (!canAccess) {
        return _json(403, {
          'success': false,
          'message': 'Book is not writable for this device',
          'error': 'READ_ONLY_BOOK',
        });
      }

      final currentRows = await db.client
          .from('books')
          .select('version')
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .limit(1);
      final current = _first(currentRows);
      if (current == null) {
        return _json(404, {'success': false, 'message': 'Book not found'});
      }
      final rowList = await db.client
          .from('books')
          .update({
            'is_deleted': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'version': ((current['version'] as num?)?.toInt() ?? 1) + 1,
          })
          .eq('book_uuid', bookUuid)
          .eq('is_deleted', false)
          .select('book_uuid')
          .limit(1);
      final row = _first(rowList);

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

      final passwordValidation = await _requireValidBookPassword(
        request,
        bookUuid,
      );
      if (passwordValidation != null) {
        return passwordValidation;
      }

      final canAccess = await _noteService.verifyBookOwnership(
        auth['deviceId']!,
        bookUuid,
      );
      if (!canAccess) {
        await _ensureMembership(
          deviceId: auth['deviceId']!,
          bookUuid: bookUuid,
        );
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
      final chargeItemsRaw = (bundle['charge_items'] as List? ?? const [])
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

      final chargeItems = chargeItemsRaw.map((c) {
        return {
          'id': c['id'],
          'recordUuid': c['record_uuid'],
          'eventId': c['event_id'],
          'itemName': c['item_name'],
          'itemPrice': c['item_price'],
          'receivedAmount': c['received_amount'],
          'paidItems': jsonDecode((c['paid_items_json'] ?? '[]').toString()),
          'createdAt': c['created_at'],
          'updatedAt': c['updated_at'],
          'version': c['version'],
          'isDeleted': c['is_deleted'] == true,
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
          'chargeItems': chargeItems,
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

  Future<Response> _grantBookAccess(Request request, String bookUuid) async {
    try {
      final auth = await _auth(request);
      if (auth == null) {
        return _json(401, {
          'success': false,
          'message': 'Invalid device credentials',
        });
      }

      final hasWriteAccess = await _hasWriteAccess(
        deviceId: auth['deviceId']!,
        bookUuid: bookUuid,
      );
      if (!hasWriteAccess) {
        return _json(403, {
          'success': false,
          'message': 'Book is not writable for this device',
          'error': 'READ_ONLY_BOOK',
        });
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final targetDeviceId = (json['targetDeviceId'] as String?)?.trim() ?? '';
      if (targetDeviceId.isEmpty) {
        return _json(400, {
          'success': false,
          'message': 'targetDeviceId is required',
        });
      }

      final targetRows = await db.client
          .from('devices')
          .select('id')
          .eq('id', targetDeviceId)
          .eq('is_active', true)
          .limit(1);
      if (_first(targetRows) == null) {
        return _json(404, {
          'success': false,
          'message': 'Target device not found',
        });
      }

      await _bookAccessService.grantBookAccess(
        bookUuid: bookUuid,
        deviceId: targetDeviceId,
      );

      return _json(200, {
        'success': true,
        'bookUuid': bookUuid,
        'targetDeviceId': targetDeviceId,
        'membershipGranted': true,
      });
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to grant book access: $e',
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
    final existingRows = await db.client
        .from('records')
        .select('record_uuid, record_number, name, phone')
        .eq('record_uuid', recordUuid)
        .limit(1);
    final existing = _first(existingRows);
    if (existing == null) {
      final insertedRows = await db.client
          .from('records')
          .insert({
            'record_uuid': recordUuid,
            'record_number': recordNumber ?? '',
            'name': name,
            'phone': phone,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'version': 1,
            'is_deleted': false,
          })
          .select('record_uuid, record_number, name, phone')
          .limit(1);
      return _first(insertedRows) ??
          {
            'record_uuid': recordUuid,
            'record_number': recordNumber ?? '',
            'name': name,
            'phone': phone,
          };
    }

    final mergedRecordNumber = (recordNumber ?? '').trim().isNotEmpty
        ? recordNumber
        : existing['record_number'];
    final mergedName = name ?? existing['name'];
    final mergedPhone = phone ?? existing['phone'];
    final updatedRows = await db.client
        .from('records')
        .update({
          'record_number': mergedRecordNumber,
          'name': mergedName,
          'phone': mergedPhone,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'synced_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('record_uuid', recordUuid)
        .select('record_uuid, record_number, name, phone')
        .limit(1);
    return _first(updatedRows) ??
        {
          'record_uuid': recordUuid,
          'record_number': mergedRecordNumber,
          'name': mergedName,
          'phone': mergedPhone,
        };
  }

  DateTime? parseTimestamp(dynamic value) => _parseTimestamp(value);
  List<String> normalizeEventTypes(dynamic value) => _toEventTypes(value);
}
