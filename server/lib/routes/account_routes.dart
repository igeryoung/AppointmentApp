import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../database/connection.dart';
import '../services/account_auth_service.dart';

class AccountRoutes {
  static const int _passwordIterations = 120000;
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_.-]{3,64}$');

  final DatabaseConnection db;
  final _uuid = const Uuid();
  late final AccountAuthService _authService;

  AccountRoutes(this.db) {
    _authService = AccountAuthService(db);
  }

  Router get router {
    final router = Router();
    router.post('/register', _register);
    router.post('/login', _login);
    router.get('/me', _me);
    return router;
  }

  Response _json(int statusCode, Map<String, dynamic> body) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
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

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(body) as Map);
  }

  String _normalizeUsername(dynamic value) {
    return (value?.toString() ?? '').trim().toLowerCase();
  }

  String _requiredTrimmed(Map<String, dynamic> json, String key) {
    return (json[key]?.toString() ?? '').trim();
  }

  Response? _validateUsernamePassword(String username, String password) {
    if (!_usernamePattern.hasMatch(username)) {
      return _json(400, {
        'success': false,
        'message':
            'Username must be 3-64 characters and use only letters, numbers, underscore, dot, or hyphen',
        'error': 'INVALID_USERNAME',
      });
    }
    if (password.length < 8) {
      return _json(400, {
        'success': false,
        'message': 'Password must be at least 8 characters',
        'error': 'INVALID_PASSWORD',
      });
    }
    return null;
  }

  String get _defaultAccountRole {
    final normalized = (Platform.environment['DEFAULT_DEVICE_ROLE'] ?? '')
        .trim()
        .toLowerCase();
    if (normalized == AccountAuthService.roleWrite) {
      return AccountAuthService.roleWrite;
    }
    return AccountAuthService.roleRead;
  }

  bool _registrationPasswordMatches(String provided) {
    final expected =
        Platform.environment['REGISTRATION_PASSWORD'] ?? 'password';
    return provided == expected;
  }

  String _generateSalt() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }

  List<int> _pbkdf2({
    required String password,
    required String salt,
    required int iterations,
    required int length,
  }) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final saltBytes = utf8.encode(salt);
    final blockCount = (length / 32).ceil();
    final output = <int>[];

    for (var block = 1; block <= blockCount; block++) {
      final blockIndex = [
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ];
      var u = hmac.convert([...saltBytes, ...blockIndex]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.addAll(t);
    }

    return output.take(length).toList();
  }

  String _hashPassword(String password, String salt) {
    final bytes = _pbkdf2(
      password: password,
      salt: salt,
      iterations: _passwordIterations,
      length: 32,
    );
    return base64UrlEncode(bytes);
  }

  bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    var diff = aBytes.length ^ bBytes.length;
    final maxLength = max(aBytes.length, bBytes.length);
    for (var i = 0; i < maxLength; i++) {
      final av = i < aBytes.length ? aBytes[i] : 0;
      final bv = i < bBytes.length ? bBytes[i] : 0;
      diff |= av ^ bv;
    }
    return diff == 0;
  }

  String _generateDeviceToken(String deviceId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _uuid.v4();
    return sha256
        .convert(utf8.encode('$deviceId:$timestamp:$random'))
        .toString();
  }

  Future<Map<String, dynamic>> _createDeviceSession({
    required String accountId,
    required String accountRole,
    required String deviceName,
    required String platform,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final deviceId = _uuid.v4();
    final deviceToken = _generateDeviceToken(deviceId);
    final inserted = await db.client
        .from('devices')
        .insert({
          'id': deviceId,
          'account_id': accountId,
          'device_name': deviceName,
          'device_token': deviceToken,
          'device_role': accountRole,
          'platform': platform,
          'registered_at': now,
          'is_active': true,
        })
        .select('id, device_token')
        .limit(1);
    final row = _first(inserted);
    if (row == null) throw Exception('Failed to create device session');
    return {'deviceId': row['id'].toString(), 'deviceToken': deviceToken};
  }

  Map<String, dynamic> _sessionResponse({
    required String accountId,
    required String username,
    required String accountRole,
    required String deviceId,
    required String deviceToken,
    required String message,
  }) {
    return {
      'success': true,
      'accountId': accountId,
      'username': username,
      'deviceId': deviceId,
      'deviceToken': deviceToken,
      'deviceRole': accountRole,
      'accountRole': accountRole,
      'message': message,
    };
  }

  Future<Response> _register(Request request) async {
    try {
      final json = await _readJson(request);
      final username = _normalizeUsername(json['username']);
      final password = _requiredTrimmed(json, 'password');
      final registrationPassword = _requiredTrimmed(
        json,
        'registrationPassword',
      );
      final deviceName = _requiredTrimmed(json, 'deviceName');
      final platform = _requiredTrimmed(json, 'platform');

      final validation = _validateUsernamePassword(username, password);
      if (validation != null) return validation;

      if (!_registrationPasswordMatches(registrationPassword)) {
        return _json(401, {
          'success': false,
          'message': 'Invalid registration password',
          'error': 'INVALID_REGISTRATION_PASSWORD',
        });
      }

      final existing = await db.client
          .from('accounts')
          .select('id')
          .eq('username', username)
          .limit(1);
      if (_first(existing) != null) {
        return _json(409, {
          'success': false,
          'message': 'Username already exists',
          'error': 'USERNAME_EXISTS',
        });
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final accountId = _uuid.v4();
      final accountRole = _defaultAccountRole;
      final salt = _generateSalt();
      final passwordHash = _hashPassword(password, salt);

      await db.client.from('accounts').insert({
        'id': accountId,
        'username': username,
        'password_hash': passwordHash,
        'password_salt': salt,
        'password_iterations': _passwordIterations,
        'account_role': accountRole,
        'is_active': true,
        'created_at': now,
      });

      final session = await _createDeviceSession(
        accountId: accountId,
        accountRole: accountRole,
        deviceName: deviceName.isEmpty ? 'Device' : deviceName,
        platform: platform.isEmpty ? 'unknown' : platform,
      );

      return _json(
        200,
        _sessionResponse(
          accountId: accountId,
          username: username,
          accountRole: accountRole,
          deviceId: session['deviceId'] as String,
          deviceToken: session['deviceToken'] as String,
          message: 'Account registered successfully',
        ),
      );
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to register account: $e',
      });
    }
  }

  Future<Response> _login(Request request) async {
    try {
      final json = await _readJson(request);
      final username = _normalizeUsername(json['username']);
      final password = _requiredTrimmed(json, 'password');
      final deviceName = _requiredTrimmed(json, 'deviceName');
      final platform = _requiredTrimmed(json, 'platform');

      final accountRows = await db.client
          .from('accounts')
          .select(
            'id, username, password_hash, password_salt, password_iterations, account_role, is_active',
          )
          .eq('username', username)
          .limit(1);
      final account = _first(accountRows);
      if (account == null || account['is_active'] != true) {
        return _json(401, {
          'success': false,
          'message': 'Invalid username or password',
          'error': 'INVALID_CREDENTIALS',
        });
      }

      final salt = account['password_salt']?.toString() ?? '';
      final iterations =
          int.tryParse(account['password_iterations']?.toString() ?? '') ??
          _passwordIterations;
      final expectedHash = account['password_hash']?.toString() ?? '';
      final actualHash = base64UrlEncode(
        _pbkdf2(
          password: password,
          salt: salt,
          iterations: iterations,
          length: 32,
        ),
      );
      if (!_constantTimeEquals(expectedHash, actualHash)) {
        return _json(401, {
          'success': false,
          'message': 'Invalid username or password',
          'error': 'INVALID_CREDENTIALS',
        });
      }

      final accountId = account['id'].toString();
      final accountRole = _authService.normalizeRole(account['account_role']);
      final session = await _createDeviceSession(
        accountId: accountId,
        accountRole: accountRole,
        deviceName: deviceName.isEmpty ? 'Device' : deviceName,
        platform: platform.isEmpty ? 'unknown' : platform,
      );

      return _json(
        200,
        _sessionResponse(
          accountId: accountId,
          username: account['username'].toString(),
          accountRole: accountRole,
          deviceId: session['deviceId'] as String,
          deviceToken: session['deviceToken'] as String,
          message: 'Login successful',
        ),
      );
    } catch (e) {
      return _json(500, {'success': false, 'message': 'Login failed: $e'});
    }
  }

  Future<Response> _me(Request request) async {
    try {
      final deviceId = request.headers['x-device-id']?.trim() ?? '';
      final deviceToken = request.headers['x-device-token']?.trim() ?? '';
      if (deviceId.isEmpty || deviceToken.isEmpty) {
        return _json(401, {
          'success': false,
          'message': 'Missing device credentials',
        });
      }

      final session = await _authService.authenticateDevice(
        deviceId,
        deviceToken,
      );
      if (session == null) {
        return _json(401, {
          'success': false,
          'message': 'Invalid device credentials',
        });
      }

      return _json(200, {
        'success': true,
        'accountId': session.accountId,
        'username': session.username,
        'accountRole': session.accountRole,
        'deviceRole': session.accountRole,
        'deviceId': session.deviceId,
      });
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to load account',
      });
    }
  }
}
