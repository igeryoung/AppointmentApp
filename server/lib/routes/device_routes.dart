import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../database/connection.dart';
import '../models/device.dart';
import '../services/account_auth_service.dart';

/// Router for device management endpoints.
class DeviceRoutes {
  final DatabaseConnection db;
  late final AccountAuthService _accountAuth;

  DeviceRoutes(this.db) {
    _accountAuth = AccountAuthService(db);
  }

  Router get router {
    final router = Router();
    router.post('/register', _registerDevice);
    router.get('/<deviceId>', _getDevice);
    router.delete('/<deviceId>', _deleteDevice);
    router.post('/sync-time', _updateSyncTime);
    return router;
  }

  Map<String, dynamic>? _first(dynamic data) {
    if (data is List && data.isNotEmpty) {
      final row = data.first;
      if (row is Map<String, dynamic>) return row;
      if (row is Map) return Map<String, dynamic>.from(row);
    }
    return null;
  }

  Future<Response> _registerDevice(Request request) async {
    final _ = request;
    return Response(
      410,
      body: jsonEncode({
        'success': false,
        'message': 'Device-only registration has moved to account registration',
        'error': 'ACCOUNT_REGISTRATION_REQUIRED',
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _getDevice(Request request, String deviceId) async {
    try {
      final rows = await db.client
          .from('devices')
          .select('*')
          .eq('id', deviceId)
          .limit(1);
      final row = _first(rows);

      final accountId = row?['account_id']?.toString() ?? '';
      if (row == null || accountId.isEmpty) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Device not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final device = Device.fromDatabase(row);
      final deviceRole = await _accountAuth.getAccountRoleForDevice(deviceId);
      final payload = device.toJson()..['deviceRole'] = deviceRole;
      return Response.ok(
        jsonEncode(payload),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to get device: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _updateSyncTime(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final deviceId = json['device_id'] as String;
      final deviceToken = json['device_token'] as String;

      if (!await _verifyDeviceToken(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device token'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await db.client
          .from('devices')
          .update({'last_sync_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', deviceId);

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Sync time updated'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to update sync time: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _deleteDevice(Request request, String deviceId) async {
    try {
      final headerDeviceId = request.headers['X-Device-ID']?.trim() ?? '';
      final deviceToken = request.headers['X-Device-Token']?.trim() ?? '';

      if (headerDeviceId.isEmpty || deviceToken.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Missing device credentials',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (headerDeviceId != deviceId) {
        return Response.forbidden(
          jsonEncode({
            'success': false,
            'message': 'Device may only delete itself',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final session = await _accountAuth.authenticateDevice(
        deviceId,
        deviceToken,
      );
      if (session == null) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device token'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await db.client.from('devices').delete().eq('id', deviceId);
      final remainingDevices = await db.client
          .from('devices')
          .select('id')
          .eq('account_id', session.accountId)
          .limit(1);
      if (_first(remainingDevices) == null &&
          session.username.startsWith('fixture-')) {
        await db.client.from('accounts').delete().eq('id', session.accountId);
      }

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Device deleted successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to delete device: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<bool> _verifyDeviceToken(String deviceId, String token) async {
    try {
      return await _accountAuth.authenticateDevice(deviceId, token) != null;
    } catch (e) {
      return false;
    }
  }
}
