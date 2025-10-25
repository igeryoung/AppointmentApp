import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../database/connection.dart';
import '../models/device.dart';

/// Router for device management endpoints
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

  /// Register a new device
  Future<Response> _registerDevice(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final registerRequest = DeviceRegisterRequest.fromJson(json);

      // Generate unique device ID and token
      final deviceId = _uuid.v4();
      final deviceToken = _generateToken(deviceId);

      // Insert device into database
      await db.query(
        '''
        INSERT INTO devices (id, device_name, device_token, platform, registered_at, is_active)
        VALUES (@id, @name, @token, @platform, CURRENT_TIMESTAMP, true)
        ''',
        parameters: {
          'id': deviceId,
          'name': registerRequest.deviceName,
          'token': deviceToken,
          'platform': registerRequest.platform,
        },
      );

      print('✅ Device registered: $deviceId (${registerRequest.deviceName})');

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
      print('❌ Device registration failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to register device: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Get device by ID
  Future<Response> _getDevice(Request request, String deviceId) async {
    try {
      final row = await db.querySingle(
        'SELECT * FROM devices WHERE id = @id',
        parameters: {'id': deviceId},
      );

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
      print('❌ Get device failed: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': 'Failed to get device: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Update device's last sync time
  Future<Response> _updateSyncTime(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final deviceId = json['device_id'] as String;
      final deviceToken = json['device_token'] as String;

      // Verify device token
      if (!await _verifyDeviceToken(deviceId, deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device token'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await db.query(
        '''
        UPDATE devices
        SET last_sync_at = CURRENT_TIMESTAMP
        WHERE id = @id
        ''',
        parameters: {'id': deviceId},
      );

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Sync time updated'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Update sync time failed: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': 'Failed to update sync time: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Generate secure device token
  String _generateToken(String deviceId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _uuid.v4();
    final content = '$deviceId:$timestamp:$random';
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify device token
  Future<bool> _verifyDeviceToken(String deviceId, String token) async {
    try {
      final row = await db.querySingle(
        'SELECT device_token FROM devices WHERE id = @id AND is_active = true',
        parameters: {'id': deviceId},
      );

      return row != null && row['device_token'] == token;
    } catch (e) {
      print('❌ Token verification failed: $e');
      return false;
    }
  }
}
