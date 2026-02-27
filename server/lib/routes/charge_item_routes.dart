import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../database/connection.dart';

class ChargeItemRoutes {
  static const String _roleRead = 'read';
  static const String _roleWrite = 'write';

  final DatabaseConnection db;

  ChargeItemRoutes(this.db);

  Router get router {
    final r = Router();

    r.get('/records/<recordUuid>/charge-items', _getChargeItemsByRecord);
    r.post('/records/<recordUuid>/charge-items', _saveChargeItemByRecord);
    r.delete('/charge-items/<chargeItemId>', _deleteChargeItem);

    return r;
  }

  Map<String, dynamic>? _first(dynamic data) {
    if (data is List && data.isNotEmpty) {
      final row = data.first;
      if (row is Map<String, dynamic>) return row;
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  DateTime _asUtc(dynamic value) {
    if (value is DateTime) return value.isUtc ? value : value.toUtc();
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null)
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return parsed.isUtc ? parsed : parsed.toUtc();
  }

  Future<bool> _verifyDeviceAccess(String deviceId, String token) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final rows = await db.client
            .from('devices')
            .select('id, device_token, is_active')
            .eq('id', deviceId)
            .limit(1);
        final row = _first(rows);
        if (row == null) return false;
        final active = row['is_active'] == true;
        return active && row['device_token']?.toString() == token;
      } catch (_) {
        if (attempt == 2) return false;
        await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
      }
    }
    return false;
  }

  String _normalizeRole(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == _roleRead) return _roleRead;
    if (normalized == _roleWrite) return _roleWrite;
    return _roleWrite;
  }

  Future<String> _getDeviceRole(String deviceId) async {
    try {
      final rows = await db.client
          .from('devices')
          .select('device_role')
          .eq('id', deviceId)
          .limit(1);
      final row = _first(rows);
      if (row == null) return _roleWrite;
      return _normalizeRole(row['device_role']);
    } catch (_) {
      return _roleWrite;
    }
  }

  Future<bool> _canDeviceWrite(String deviceId) async {
    final role = await _getDeviceRole(deviceId);
    return role == _roleWrite;
  }

  Future<Set<String>> _accessibleBookUuids(String deviceId) async {
    final ownedRows = await db.client
        .from('books')
        .select('book_uuid')
        .eq('device_id', deviceId)
        .eq('is_deleted', false);

    final accessRows = await db.client
        .from('book_device_access')
        .select('book_uuid')
        .eq('device_id', deviceId);

    final result = <String>{};
    for (final row in _rows(ownedRows)) {
      final uuid = row['book_uuid']?.toString();
      if (uuid != null && uuid.isNotEmpty) result.add(uuid);
    }
    for (final row in _rows(accessRows)) {
      final uuid = row['book_uuid']?.toString();
      if (uuid != null && uuid.isNotEmpty) result.add(uuid);
    }
    return result;
  }

  Future<bool> _verifyRecordAccess(String deviceId, String recordUuid) async {
    try {
      final accessibleBooks = await _accessibleBookUuids(deviceId);
      if (accessibleBooks.isEmpty) return false;

      final eventRows = await db.client
          .from('events')
          .select('book_uuid')
          .eq('record_uuid', recordUuid)
          .eq('is_deleted', false);

      for (final row in _rows(eventRows)) {
        final bookUuid = row['book_uuid']?.toString();
        if (bookUuid != null && accessibleBooks.contains(bookUuid)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshEventChargeFlags(String recordUuid) async {
    final rows = await db.client
        .from('charge_items')
        .select('id')
        .eq('record_uuid', recordUuid)
        .eq('is_deleted', false)
        .limit(1);
    final hasItems = _first(rows) != null;

    await db.client
        .from('events')
        .update({
          'has_charge_items': hasItems,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('record_uuid', recordUuid)
        .eq('is_deleted', false);
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  bool _toBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes' || text == 'on') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no' || text == 'off') {
      return false;
    }
    return fallback;
  }

  Map<String, dynamic> _serializeChargeItem(Map<String, dynamic> row) {
    final createdAt = _asUtc(row['created_at']).toIso8601String();
    final updatedAt = _asUtc(row['updated_at']).toIso8601String();
    final isDeleted = row['is_deleted'] == true || row['is_deleted'] == 1;

    return {
      'id': row['id'],
      'recordUuid': row['record_uuid'],
      'eventId': row['event_id'],
      'itemName': row['item_name'],
      'itemPrice': _toInt(row['item_price']),
      'receivedAmount': _toInt(row['received_amount']),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'version': _toInt(row['version'], fallback: 1),
      'isDeleted': isDeleted,
      // snake_case compatibility
      'record_uuid': row['record_uuid'],
      'event_id': row['event_id'],
      'item_name': row['item_name'],
      'item_price': _toInt(row['item_price']),
      'received_amount': _toInt(row['received_amount']),
      'created_at': createdAt,
      'updated_at': updatedAt,
      'is_deleted': isDeleted,
    };
  }

  Future<Response> _getChargeItemsByRecord(Request request) async {
    try {
      final recordUuid = request.params['recordUuid'] ?? '';
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (recordUuid.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'message': 'Missing recordUuid'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!await _verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!await _verifyRecordAccess(deviceId, recordUuid)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized record access',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!await _canDeviceWrite(deviceId)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Read-only device cannot modify charge items',
            'error': 'READ_ONLY_DEVICE',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final rows = await db.client
          .from('charge_items')
          .select(
            'id, record_uuid, event_id, item_name, item_price, received_amount, created_at, updated_at, version, is_deleted',
          )
          .eq('record_uuid', recordUuid)
          .eq('is_deleted', false)
          .order('updated_at', ascending: false);

      final items = _rows(rows).map(_serializeChargeItem).toList();
      return Response.ok(
        jsonEncode({
          'success': true,
          'chargeItems': items,
          'count': items.length,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to fetch charge items: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _saveChargeItemByRecord(Request request) async {
    try {
      final recordUuid = request.params['recordUuid'] ?? '';
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (recordUuid.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'message': 'Missing recordUuid'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!await _verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!await _canDeviceWrite(deviceId)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Read-only device cannot modify charge items',
            'error': 'READ_ONLY_DEVICE',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!await _verifyRecordAccess(deviceId, recordUuid)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized record access',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final id = (json['id'] ?? '').toString().trim();
      final rawEventId = (json['eventId'] ?? json['event_id'])
          ?.toString()
          .trim();
      final eventId = (rawEventId == null || rawEventId.isEmpty)
          ? null
          : rawEventId;
      final itemName = (json['itemName'] ?? json['item_name'] ?? '')
          .toString()
          .trim();
      final itemPrice = _toInt(json['itemPrice'] ?? json['item_price']);
      final receivedAmount = _toInt(
        json['receivedAmount'] ?? json['received_amount'],
      );
      final isDeleted = _toBool(
        json['isDeleted'] ?? json['is_deleted'],
        fallback: false,
      );
      final clientVersion = json['version'] == null
          ? null
          : _toInt(json['version']);
      final expectedVersion = clientVersion == null ? null : clientVersion - 1;

      if (itemName.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'itemName is required',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      Map<String, dynamic>? result;

      if (id.isEmpty) {
        final inserted = await db.client
            .from('charge_items')
            .insert({
              'record_uuid': recordUuid,
              'event_id': eventId,
              'item_name': itemName,
              'item_price': itemPrice,
              'received_amount': receivedAmount,
              'created_at': nowIso,
              'updated_at': nowIso,
              'synced_at': nowIso,
              'version': 1,
              'is_deleted': isDeleted,
            })
            .select(
              'id, record_uuid, event_id, item_name, item_price, received_amount, created_at, updated_at, version, is_deleted',
            )
            .limit(1);
        result = _first(inserted);
      } else {
        final existingRows = await db.client
            .from('charge_items')
            .select(
              'id, record_uuid, event_id, item_name, item_price, received_amount, created_at, updated_at, version, is_deleted',
            )
            .eq('id', id)
            .limit(1);
        final existing = _first(existingRows);

        if (existing == null) {
          final inserted = await db.client
              .from('charge_items')
              .insert({
                'id': id,
                'record_uuid': recordUuid,
                'event_id': eventId,
                'item_name': itemName,
                'item_price': itemPrice,
                'received_amount': receivedAmount,
                'created_at': nowIso,
                'updated_at': nowIso,
                'synced_at': nowIso,
                'version': 1,
                'is_deleted': isDeleted,
              })
              .select(
                'id, record_uuid, event_id, item_name, item_price, received_amount, created_at, updated_at, version, is_deleted',
              )
              .limit(1);
          result = _first(inserted);
        } else {
          if (existing['record_uuid']?.toString() != recordUuid) {
            return Response(
              409,
              body: jsonEncode({
                'success': false,
                'conflict': true,
                'message': 'Charge item version conflict',
                'serverVersion': existing['version'],
                'chargeItem': _serializeChargeItem(existing),
              }),
              headers: {'Content-Type': 'application/json'},
            );
          }

          final serverVersion = _toInt(existing['version'], fallback: 1);
          if (expectedVersion != null && serverVersion != expectedVersion) {
            return Response(
              409,
              body: jsonEncode({
                'success': false,
                'conflict': true,
                'message': 'Charge item version conflict',
                'serverVersion': serverVersion,
                'chargeItem': _serializeChargeItem(existing),
              }),
              headers: {'Content-Type': 'application/json'},
            );
          }

          final updated = await db.client
              .from('charge_items')
              .update({
                'event_id': eventId ?? existing['event_id'],
                'item_name': itemName,
                'item_price': itemPrice,
                'received_amount': receivedAmount,
                'updated_at': nowIso,
                'synced_at': nowIso,
                'version': serverVersion + 1,
                'is_deleted': isDeleted,
              })
              .eq('id', id)
              .select(
                'id, record_uuid, event_id, item_name, item_price, received_amount, created_at, updated_at, version, is_deleted',
              )
              .limit(1);
          result = _first(updated);
        }
      }

      if (result == null) {
        return Response.internalServerError(
          body: jsonEncode({
            'success': false,
            'message': 'Failed to save charge item',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _refreshEventChargeFlags(recordUuid);
      return Response.ok(
        jsonEncode({
          'success': true,
          'chargeItem': _serializeChargeItem(result),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to save charge item: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _deleteChargeItem(Request request) async {
    try {
      final chargeItemId = request.params['chargeItemId'] ?? '';
      final deviceId = request.headers['x-device-id'];
      final deviceToken = request.headers['x-device-token'];

      if (chargeItemId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'message': 'Missing chargeItemId',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (deviceId == null || deviceToken == null) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!await _verifyDeviceAccess(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Invalid device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final existingRows = await db.client
          .from('charge_items')
          .select('id, record_uuid, version, is_deleted')
          .eq('id', chargeItemId)
          .limit(1);
      final existing = _first(existingRows);
      if (existing == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Charge item not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final recordUuid = existing['record_uuid'].toString();
      if (!await _verifyRecordAccess(deviceId, recordUuid)) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Unauthorized record access',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final currentVersion = _toInt(existing['version'], fallback: 1);

      await db.client
          .from('charge_items')
          .update({
            'is_deleted': true,
            'updated_at': nowIso,
            'synced_at': nowIso,
            'version': currentVersion + 1,
          })
          .eq('id', chargeItemId);

      await _refreshEventChargeFlags(recordUuid);
      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to delete charge item: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
