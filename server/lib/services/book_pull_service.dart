import 'dart:convert';

import '../database/connection.dart';
import 'account_auth_service.dart';
import 'book_access_service.dart';

/// Service for pulling books from server to local device.
class BookPullService {
  final DatabaseConnection db;
  late final BookAccessService _bookAccessService;
  late final AccountAuthService _accountAuth;

  BookPullService(this.db) {
    _bookAccessService = BookAccessService(db);
    _accountAuth = AccountAuthService(db);
  }

  DateTime _asUtc(dynamic value) {
    if (value is DateTime) return value.isUtc ? value : value.toUtc();
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null)
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return parsed.isUtc ? parsed : parsed.toUtc();
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Map<String, dynamic>? _first(dynamic data) {
    final rows = _rows(data);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  int _toInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? defaultValue;
  }

  Future<Map<String, bool>> _unpaidChargeFlagsByRecordUuids(
    Iterable<String> recordUuids,
  ) async {
    final uniqueRecordUuids = recordUuids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final flags = {for (final id in uniqueRecordUuids) id: false};
    if (uniqueRecordUuids.isEmpty) return flags;

    final rows = await db.client
        .from('charge_items')
        .select('record_uuid, item_price, received_amount')
        .inFilter('record_uuid', uniqueRecordUuids)
        .eq('is_deleted', false);

    for (final row in _rows(rows)) {
      final recordUuid = row['record_uuid']?.toString() ?? '';
      if (recordUuid.isEmpty || flags[recordUuid] == true) continue;
      final itemPrice = _toInt(row['item_price']);
      final receivedAmount = _toInt(row['received_amount']);
      if (receivedAmount < itemPrice) {
        flags[recordUuid] = true;
      }
    }

    return flags;
  }

  String _normalizeEventTypes(dynamic value) {
    if (value == null) return '[]';
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? '[]' : trimmed;
    }
    try {
      return jsonEncode(value);
    } catch (_) {
      return '[]';
    }
  }

  String _primaryEventType(String eventTypes) {
    try {
      final decoded = jsonDecode(eventTypes);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.first.toString();
      }
    } catch (_) {}
    return 'other';
  }

  Future<List<Map<String, dynamic>>> listBooksForDevice(
    String deviceId, {
    String? searchQuery,
  }) async {
    final accessibleBookUuids = await _accountAuth.accessibleBookUuidsForDevice(
      deviceId,
    );
    if (accessibleBookUuids.isEmpty) return const [];
    var query = db.client
        .from('books')
        .select(
          'book_uuid, name, created_at, updated_at, archived_at, version, is_deleted, device_id, owner_account_id',
        );

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      query = query.ilike('name', '%${searchQuery.trim()}%');
    }

    final results = await query
        .inFilter('book_uuid', accessibleBookUuids.toList())
        .order('created_at', ascending: false);

    return _rows(results).map((row) {
      return {
        'book_uuid': row['book_uuid'] as String,
        'name': row['name'] as String,
        'created_at': _asUtc(row['created_at']).toIso8601String(),
        'updated_at': _asUtc(row['updated_at']).toIso8601String(),
        'archived_at': row['archived_at'] != null
            ? _asUtc(row['archived_at']).toIso8601String()
            : null,
        'version': (row['version'] as num?)?.toInt() ?? 1,
        'is_deleted': _toBool(row['is_deleted']),
        'device_id': row['device_id'] as String?,
        'owner_account_id': row['owner_account_id'] as String?,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> getCompleteBookData(
    String bookUuid,
    String deviceId,
  ) async {
    final bookRows = await db.client
        .from('books')
        .select(
          'book_uuid, name, created_at, updated_at, archived_at, version, is_deleted',
        )
        .eq('book_uuid', bookUuid)
        .limit(1);
    final book = _first(bookRows);
    if (book == null) {
      throw Exception('Book not found: $bookUuid');
    }

    final eventRowsRaw = await db.client
        .from('events')
        .select(
          'id, book_uuid, record_uuid, title, event_types, has_charge_items, is_checked, has_note, '
          'start_time, end_time, created_at, updated_at, is_removed, removal_reason, '
          'original_event_id, new_event_id, version, is_deleted',
        )
        .eq('book_uuid', bookUuid)
        .order('start_time', ascending: true);
    final eventRows = _rows(eventRowsRaw);

    final recordUuids = eventRows
        .map((e) => (e['record_uuid'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final unpaidChargeFlagsByRecordUuid = await _unpaidChargeFlagsByRecordUuids(
      recordUuids,
    );

    final recordsById = <String, Map<String, dynamic>>{};
    if (recordUuids.isNotEmpty) {
      final recordsRaw = await db.client
          .from('records')
          .select('record_uuid, name, record_number, phone')
          .inFilter('record_uuid', recordUuids);
      for (final row in _rows(recordsRaw)) {
        recordsById[row['record_uuid'].toString()] = row;
      }
    }

    final events = eventRows.map((row) {
      final recordUuid = row['record_uuid'].toString();
      final record = recordsById[recordUuid];
      final eventTypes = _normalizeEventTypes(row['event_types']);
      return {
        'id': row['id'] as String,
        'book_uuid': row['book_uuid'] as String,
        'record_uuid': recordUuid,
        'title': row['title'] as String,
        'name': (record?['name'] as String?) ?? (row['title'] as String),
        'record_number': record?['record_number'] as String?,
        'phone': record?['phone'] as String?,
        'event_type': _primaryEventType(eventTypes),
        'event_types': eventTypes,
        'has_charge_items': unpaidChargeFlagsByRecordUuid[recordUuid] ?? false,
        'is_checked': _toBool(row['is_checked']),
        'has_note': _toBool(row['has_note']),
        'start_time': _asUtc(row['start_time']).toIso8601String(),
        'end_time': row['end_time'] != null
            ? _asUtc(row['end_time']).toIso8601String()
            : null,
        'created_at': _asUtc(row['created_at']).toIso8601String(),
        'updated_at': _asUtc(row['updated_at']).toIso8601String(),
        'is_removed': _toBool(row['is_removed']),
        'removal_reason': row['removal_reason'] as String?,
        'original_event_id': row['original_event_id'] as String?,
        'new_event_id': row['new_event_id'] as String?,
        'version': (row['version'] as num?)?.toInt() ?? 1,
        'is_deleted': _toBool(row['is_deleted']),
      };
    }).toList();

    final notes = <Map<String, dynamic>>[];
    if (recordUuids.isNotEmpty) {
      final notesRaw = await db.client
          .from('notes')
          .select(
            'id, record_uuid, pages_data, created_at, updated_at, version, is_deleted',
          )
          .inFilter('record_uuid', recordUuids)
          .order('created_at', ascending: true);
      for (final row in _rows(notesRaw)) {
        notes.add({
          'id': row['id'] as String,
          'record_uuid': row['record_uuid'] as String,
          'pages_data': row['pages_data'] as String?,
          'created_at': _asUtc(row['created_at']).toIso8601String(),
          'updated_at': _asUtc(row['updated_at']).toIso8601String(),
          'version': (row['version'] as num?)?.toInt() ?? 1,
          'is_deleted': _toBool(row['is_deleted']),
        });
      }
    }

    final drawingsRaw = await db.client
        .from('schedule_drawings')
        .select(
          'id, book_uuid, date, view_mode, strokes_data, created_at, updated_at, version, is_deleted',
        )
        .eq('book_uuid', bookUuid)
        .order('date', ascending: true);

    final drawings = _rows(drawingsRaw).map((row) {
      return {
        'id': row['id'] as int,
        'book_uuid': row['book_uuid'] as String,
        'date': _asUtc(row['date']).toIso8601String(),
        'view_mode': (row['view_mode'] as num?)?.toInt() ?? 0,
        'strokes_data': row['strokes_data'] as String?,
        'created_at': _asUtc(row['created_at']).toIso8601String(),
        'updated_at': _asUtc(row['updated_at']).toIso8601String(),
        'version': (row['version'] as num?)?.toInt() ?? 1,
        'is_deleted': _toBool(row['is_deleted']),
      };
    }).toList();

    final chargeItems = <Map<String, dynamic>>[];
    if (recordUuids.isNotEmpty) {
      final chargeItemsRaw = await db.client
          .from('charge_items')
          .select(
            'id, record_uuid, event_id, item_name, item_price, received_amount, paid_items_json, created_at, updated_at, version, is_deleted',
          )
          .inFilter('record_uuid', recordUuids)
          .order('updated_at', ascending: true);

      for (final row in _rows(chargeItemsRaw)) {
        chargeItems.add({
          'id': row['id'].toString(),
          'record_uuid': row['record_uuid'] as String,
          'event_id': row['event_id']?.toString(),
          'item_name': row['item_name'] as String,
          'item_price': (row['item_price'] as num?)?.toInt() ?? 0,
          'received_amount': (row['received_amount'] as num?)?.toInt() ?? 0,
          'paid_items_json': row['paid_items_json']?.toString() ?? '[]',
          'created_at': _asUtc(row['created_at']).toIso8601String(),
          'updated_at': _asUtc(row['updated_at']).toIso8601String(),
          'version': (row['version'] as num?)?.toInt() ?? 1,
          'is_deleted': _toBool(row['is_deleted']),
        });
      }
    }

    await addDeviceAccess(bookUuid, deviceId);

    return {
      'book': {
        'book_uuid': book['book_uuid'] as String,
        'name': book['name'] as String,
        'created_at': _asUtc(book['created_at']).toIso8601String(),
        'updated_at': _asUtc(book['updated_at']).toIso8601String(),
        'archived_at': book['archived_at'] != null
            ? _asUtc(book['archived_at']).toIso8601String()
            : null,
        'version': (book['version'] as num?)?.toInt() ?? 1,
        'is_deleted': _toBool(book['is_deleted']),
      },
      'events': events,
      'notes': notes,
      'drawings': drawings,
      'charge_items': chargeItems,
    };
  }

  Future<Map<String, dynamic>> getBookMetadata(
    String bookUuid,
    String deviceId,
  ) async {
    final _ = deviceId;

    final bookRows = await db.client
        .from('books')
        .select(
          'book_uuid, name, created_at, updated_at, archived_at, version, is_deleted',
        )
        .eq('book_uuid', bookUuid)
        .limit(1);

    final book = _first(bookRows);
    if (book == null) {
      throw Exception('Book not found: $bookUuid');
    }

    return {
      'book_uuid': book['book_uuid'] as String,
      'name': book['name'] as String,
      'created_at': _asUtc(book['created_at']).toIso8601String(),
      'updated_at': _asUtc(book['updated_at']).toIso8601String(),
      'archived_at': book['archived_at'] != null
          ? _asUtc(book['archived_at']).toIso8601String()
          : null,
      'version': (book['version'] as num?)?.toInt() ?? 1,
      'is_deleted': _toBool(book['is_deleted']),
    };
  }

  Future<void> addDeviceAccess(String bookUuid, String deviceId) async {
    try {
      await _bookAccessService.grantBookAccess(
        bookUuid: bookUuid,
        deviceId: deviceId,
      );
    } catch (e) {
      print('⚠️ Failed to add device access: $e');
    }
  }
}
