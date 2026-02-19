import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../database/connection.dart';

class ChargeItemRoutes {
  final DatabaseConnection db;

  ChargeItemRoutes(this.db);

  Router get router {
    final r = Router();

    r.get('/records/<recordUuid>/charge-items', _getChargeItemsByRecord);
    r.post('/records/<recordUuid>/charge-items', _saveChargeItemByRecord);
    r.delete('/charge-items/<chargeItemId>', _deleteChargeItem);

    return r;
  }

  Future<bool> _verifyDeviceAccess(String deviceId, String token) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM devices WHERE id = @id AND device_token = @token AND is_active = true',
        parameters: {'id': deviceId, 'token': token},
      );
      return row != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verifyRecordAccess(String deviceId, String recordUuid) async {
    try {
      final row = await db.querySingle(
        '''
        SELECT 1
        FROM events e
        INNER JOIN books b ON b.book_uuid = e.book_uuid
        LEFT JOIN book_device_access a ON a.book_uuid = b.book_uuid AND a.device_id = @deviceId
        WHERE e.record_uuid = @recordUuid
          AND e.is_deleted = false
          AND b.is_deleted = false
          AND (b.device_id = @deviceId OR a.device_id IS NOT NULL)
        LIMIT 1
        ''',
        parameters: {'deviceId': deviceId, 'recordUuid': recordUuid},
      );
      return row != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshEventChargeFlags(String recordUuid) async {
    final hasItemsRow = await db.querySingle(
      '''
      SELECT EXISTS(
        SELECT 1 FROM charge_items
        WHERE record_uuid = @recordUuid AND is_deleted = false
      ) AS has_items
      ''',
      parameters: {'recordUuid': recordUuid},
    );
    final hasItems =
        hasItemsRow?['has_items'] == true || hasItemsRow?['has_items'] == 1;

    await db.query(
      '''
      UPDATE events
      SET has_charge_items = @hasItems
      WHERE record_uuid = @recordUuid AND is_deleted = false
      ''',
      parameters: {'recordUuid': recordUuid, 'hasItems': hasItems},
    );
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
    return {
      'id': row['id'],
      'recordUuid': row['record_uuid'],
      'eventId': row['event_id'],
      'itemName': row['item_name'],
      'itemPrice': row['item_price'],
      'receivedAmount': row['received_amount'],
      'createdAt': (row['created_at'] as DateTime).toUtc().toIso8601String(),
      'updatedAt': (row['updated_at'] as DateTime).toUtc().toIso8601String(),
      'version': row['version'],
      'isDeleted': row['is_deleted'] == true || row['is_deleted'] == 1,
      // snake_case compatibility
      'record_uuid': row['record_uuid'],
      'event_id': row['event_id'],
      'item_name': row['item_name'],
      'item_price': row['item_price'],
      'received_amount': row['received_amount'],
      'created_at': (row['created_at'] as DateTime).toUtc().toIso8601String(),
      'updated_at': (row['updated_at'] as DateTime).toUtc().toIso8601String(),
      'is_deleted': row['is_deleted'] == true || row['is_deleted'] == 1,
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

      final rows = await db.queryRows(
        '''
        SELECT id, record_uuid, event_id, item_name, item_price, received_amount,
               created_at, updated_at, version, is_deleted
        FROM charge_items
        WHERE record_uuid = @recordUuid AND is_deleted = false
        ORDER BY updated_at DESC
        ''',
        parameters: {'recordUuid': recordUuid},
      );

      final items = rows.map(_serializeChargeItem).toList();
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
      final eventId = (json['eventId'] ?? json['event_id'])?.toString();
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

      final result = await db.querySingle(
        '''
        INSERT INTO charge_items (
          id, record_uuid, event_id, item_name, item_price, received_amount,
          created_at, updated_at, synced_at, version, is_deleted
        )
        VALUES (
          COALESCE(NULLIF(@id, '')::uuid, uuid_generate_v4()),
          @recordUuid, @eventId, @itemName, @itemPrice, @receivedAmount,
          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, @isDeleted
        )
        ON CONFLICT (id) DO UPDATE
        SET
          event_id = COALESCE(@eventId::uuid, charge_items.event_id),
          item_name = @itemName,
          item_price = @itemPrice,
          received_amount = @receivedAmount,
          updated_at = CURRENT_TIMESTAMP,
          synced_at = CURRENT_TIMESTAMP,
          version = charge_items.version + 1,
          is_deleted = @isDeleted
        WHERE (CAST(@expectedVersion AS INTEGER) IS NULL OR charge_items.version = CAST(@expectedVersion AS INTEGER))
          AND charge_items.record_uuid = @recordUuid
        RETURNING
          id, record_uuid, event_id, item_name, item_price, received_amount,
          created_at, updated_at, version, is_deleted
        ''',
        parameters: {
          'id': id,
          'recordUuid': recordUuid,
          'eventId': eventId,
          'itemName': itemName,
          'itemPrice': itemPrice,
          'receivedAmount': receivedAmount,
          'expectedVersion': expectedVersion,
          'isDeleted': isDeleted,
        },
      );

      if (result == null) {
        final current = await db.querySingle(
          '''
          SELECT id, record_uuid, event_id, item_name, item_price, received_amount,
                 created_at, updated_at, version, is_deleted
          FROM charge_items
          WHERE id = @id::uuid
          ''',
          parameters: {'id': id},
        );

        return Response(
          409,
          body: jsonEncode({
            'success': false,
            'conflict': true,
            'message': 'Charge item version conflict',
            'serverVersion': current?['version'],
            'chargeItem': current == null
                ? null
                : _serializeChargeItem(current),
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

      final existing = await db.querySingle(
        '''
        SELECT id, record_uuid, is_deleted
        FROM charge_items
        WHERE id = @id::uuid
        ''',
        parameters: {'id': chargeItemId},
      );
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

      await db.query(
        '''
        UPDATE charge_items
        SET
          is_deleted = true,
          updated_at = CURRENT_TIMESTAMP,
          synced_at = CURRENT_TIMESTAMP,
          version = version + 1
        WHERE id = @id::uuid
        ''',
        parameters: {'id': chargeItemId},
      );

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
