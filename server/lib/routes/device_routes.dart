import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../database/connection.dart';
import '../models/device.dart';

/// Router for device management endpoints.
class DeviceRoutes {
  final DatabaseConnection db;
  final _uuid = const Uuid();

  DeviceRoutes(this.db);

  Router get router {
    final router = Router();
    router.post('/register', _registerDevice);
    router.get('/<deviceId>', _getDevice);
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
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final registerRequest = DeviceRegisterRequest.fromJson(json);

      final expectedPassword =
          Platform.environment['REGISTRATION_PASSWORD'] ?? 'password';
      if (registerRequest.password != expectedPassword) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'message': 'Invalid registration password',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deviceId = _uuid.v4();
      final deviceToken = _generateToken(deviceId);

      await db.client.from('devices').insert({
        'id': deviceId,
        'device_name': registerRequest.deviceName,
        'device_token': deviceToken,
        'platform': registerRequest.platform,
        'registered_at': DateTime.now().toUtc().toIso8601String(),
        'is_active': true,
      });

      final response = DeviceRegisterResponse(
        deviceId: deviceId,
        deviceToken: deviceToken,
        message: 'Device registered successfully',
      );

      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to register device: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getDevice(Request request, String deviceId) async {
    try {
      final rows = await db.client
          .from('devices')
          .select('*')
          .eq('id', deviceId)
          .limit(1);
      final row = _first(rows);

      if (row == null) {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Device not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final device = Device.fromDatabase(row);
      return Response.ok(
        jsonEncode(device.toJson()),
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

  String _generateToken(String deviceId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _uuid.v4();
    final content = '$deviceId:$timestamp:$random';
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> _verifyDeviceToken(String deviceId, String token) async {
    try {
      final rows = await db.client
          .from('devices')
          .select('device_token, is_active')
          .eq('id', deviceId)
          .limit(1);
      final row = _first(rows);
      if (row == null) return false;
      return row['is_active'] == true && row['device_token'] == token;
    } catch (e) {
      return false;
    }
  }
}
