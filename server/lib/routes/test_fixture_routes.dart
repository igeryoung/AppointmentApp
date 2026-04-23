import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../database/connection.dart';
import '../services/account_auth_service.dart';
import '../services/book_access_service.dart';
import '../services/note_service.dart';

class TestFixtureRoutes {
  final DatabaseConnection db;
  final BookAccessService _bookAccessService;
  final AccountAuthService _accountAuthService;
  final _uuid = const Uuid();

  TestFixtureRoutes(this.db)
    : _bookAccessService = BookAccessService(db),
      _accountAuthService = AccountAuthService(db);

  Router get router {
    final router = Router();
    router.post('/devices/register', _registerFixtureDevice);
    router.post('/live-event-metadata', _provisionLiveEventMetadata);
    router.post('/live-event-metadata/cleanup', _cleanupLiveEventMetadata);
    return router;
  }

  String _hashBookPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  Response _json(int statusCode, Map<String, dynamic> body) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final rawBody = await request.readAsString();
    if (rawBody.trim().isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(rawBody) as Map);
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  bool _isFixturePasswordValid(String password) {
    final expected =
        (Platform.environment['REGISTRATION_PASSWORD'] ?? 'password').trim();
    return password.trim().isNotEmpty && password.trim() == expected;
  }

  String _normalizeDeviceRole(String? role) {
    final normalized = role?.trim().toLowerCase() ?? '';
    if (normalized == NoteService.roleRead) return NoteService.roleRead;
    if (normalized == NoteService.roleWrite) return NoteService.roleWrite;
    return NoteService.roleRead;
  }

  String _generateDeviceToken(String deviceId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _uuid.v4();
    final content = '$deviceId:$timestamp:$random';
    return sha256.convert(utf8.encode(content)).toString();
  }

  String _fixturePasswordHash(String accountId) {
    return sha256.convert(utf8.encode('fixture:$accountId')).toString();
  }

  Future<Map<String, String>> _createDevice({
    required String deviceName,
    required String deviceRole,
    String? platform,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final accountId = _uuid.v4();
    final deviceId = _uuid.v4();
    final deviceToken = _generateDeviceToken(deviceId);
    final normalizedRole = _normalizeDeviceRole(deviceRole);

    await db.client.from('accounts').insert({
      'id': accountId,
      'username': 'fixture-${accountId.substring(0, 8)}',
      'password_hash': _fixturePasswordHash(accountId),
      'password_salt': 'fixture',
      'password_iterations': 1,
      'account_role': normalizedRole,
      'is_active': true,
      'created_at': now,
    });

    await db.client.from('devices').insert({
      'id': deviceId,
      'account_id': accountId,
      'device_name': deviceName,
      'device_token': deviceToken,
      'device_role': normalizedRole,
      'platform': platform ?? 'ios',
      'registered_at': now,
      'is_active': true,
    });

    return {
      'deviceId': deviceId,
      'deviceToken': deviceToken,
      'deviceRole': normalizedRole,
      'accountId': accountId,
    };
  }

  Future<Map<String, String>> _createSharedFixture({
    required String writeDeviceId,
    required String readDeviceId,
    required String bookPassword,
  }) async {
    final now = DateTime.now().toUtc();
    final suffix = now.millisecondsSinceEpoch.toString();
    final bookUuid = _uuid.v4();
    final eventId = _uuid.v4();
    final recordUuid = _uuid.v4();
    final startTime = now.add(const Duration(minutes: 30));
    final endTime = startTime.add(const Duration(minutes: 30));

    await db.client.from('books').insert({
      'book_uuid': bookUuid,
      'device_id': writeDeviceId,
      'owner_account_id': await _accountAuthService.accountIdForDevice(
        writeDeviceId,
      ),
      'name': 'IT shared fixture $suffix',
      'book_password_hash': _hashBookPassword(bookPassword),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'synced_at': now.toIso8601String(),
      'version': 1,
      'is_deleted': false,
    });

    await _bookAccessService.grantBookAccess(
      bookUuid: bookUuid,
      deviceId: writeDeviceId,
    );
    await _bookAccessService.grantBookAccess(
      bookUuid: bookUuid,
      deviceId: readDeviceId,
    );

    await db.client.from('records').insert({
      'record_uuid': recordUuid,
      'record_number': 'FIXTURE-$suffix',
      'name': 'IT Fixture $suffix',
      'phone': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'synced_at': now.toIso8601String(),
      'version': 1,
      'is_deleted': false,
    });

    await db.client.from('events').insert({
      'id': eventId,
      'book_uuid': bookUuid,
      'record_uuid': recordUuid,
      'title': 'IT shared fixture $suffix',
      'event_types': jsonEncode(const ['consultation']),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'synced_at': now.toIso8601String(),
      'version': 1,
      'is_deleted': false,
      'is_removed': false,
      'is_checked': false,
      'has_charge_items': false,
      'has_note': false,
    });

    return {'bookUuid': bookUuid, 'eventId': eventId, 'recordUuid': recordUuid};
  }

  Future<void> _cleanupFixtureIds({
    required List<String> bookUuids,
    required List<String> eventIds,
    required List<String> recordUuids,
    required List<String> deviceIds,
  }) async {
    final nonEmptyEventIds = eventIds
        .where((id) => id.trim().isNotEmpty)
        .toList();
    final nonEmptyRecordUuids = recordUuids
        .where((id) => id.trim().isNotEmpty)
        .toList();
    final nonEmptyBookUuids = bookUuids
        .where((id) => id.trim().isNotEmpty)
        .toList();
    final nonEmptyDeviceIds = deviceIds
        .where((id) => id.trim().isNotEmpty)
        .toList();

    if (nonEmptyEventIds.isNotEmpty) {
      await db.client
          .from('charge_items')
          .delete()
          .inFilter('event_id', nonEmptyEventIds);
      await db.client.from('events').delete().inFilter('id', nonEmptyEventIds);
    }
    if (nonEmptyRecordUuids.isNotEmpty) {
      await db.client
          .from('charge_items')
          .delete()
          .inFilter('record_uuid', nonEmptyRecordUuids);
      await db.client
          .from('notes')
          .delete()
          .inFilter('record_uuid', nonEmptyRecordUuids);
      await db.client
          .from('records')
          .delete()
          .inFilter('record_uuid', nonEmptyRecordUuids);
    }
    if (nonEmptyBookUuids.isNotEmpty) {
      await db.client
          .from('schedule_drawings')
          .delete()
          .inFilter('book_uuid', nonEmptyBookUuids);
      await db.client
          .from('account_book_access')
          .delete()
          .inFilter('book_uuid', nonEmptyBookUuids);
      await db.client
          .from('book_device_access')
          .delete()
          .inFilter('book_uuid', nonEmptyBookUuids);
      await db.client
          .from('books')
          .delete()
          .inFilter('book_uuid', nonEmptyBookUuids);
    }
    if (nonEmptyDeviceIds.isNotEmpty) {
      final accountRows = await db.client
          .from('devices')
          .select('account_id')
          .inFilter('id', nonEmptyDeviceIds);
      final accountIds = _rows(accountRows)
          .map((row) => row['account_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      await db.client
          .from('book_device_access')
          .delete()
          .inFilter('device_id', nonEmptyDeviceIds);
      await db.client
          .from('devices')
          .delete()
          .inFilter('id', nonEmptyDeviceIds);
      if (accountIds.isNotEmpty) {
        await db.client
            .from('account_book_access')
            .delete()
            .inFilter('account_id', accountIds);
        await db.client.from('accounts').delete().inFilter('id', accountIds);
      }
    }
  }

  Future<Response> _registerFixtureDevice(Request request) async {
    try {
      final json = await _readJson(request);
      final fixturePassword = (json['password'] as String?)?.trim() ?? '';
      if (!_isFixturePasswordValid(fixturePassword)) {
        return _json(401, {
          'success': false,
          'message': 'Invalid fixture password',
        });
      }

      final deviceName =
          (json['deviceName'] as String?)?.trim().isNotEmpty == true
          ? (json['deviceName'] as String).trim()
          : 'IT temp device ${DateTime.now().millisecondsSinceEpoch}';
      final deviceRole = _normalizeDeviceRole(json['deviceRole']?.toString());
      final platform = (json['platform'] as String?)?.trim();

      final device = await _createDevice(
        deviceName: deviceName,
        deviceRole: deviceRole,
        platform: platform,
      );

      return _json(200, {
        'success': true,
        'deviceId': device['deviceId'],
        'deviceToken': device['deviceToken'],
        'deviceRole': device['deviceRole'],
        'accountId': device['accountId'],
      });
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to register fixture device: $e',
      });
    }
  }

  Future<Response> _provisionLiveEventMetadata(Request request) async {
    final json = await _readJson(request);
    final fixturePassword = (json['password'] as String?)?.trim() ?? '';
    final bookPassword =
        ((json['bookPassword'] ?? json['book_password']) as String?)?.trim() ??
        'fixture-book-password';
    if (!_isFixturePasswordValid(fixturePassword)) {
      return _json(401, {
        'success': false,
        'message': 'Invalid fixture password',
      });
    }

    Map<String, String>? writeDevice;
    Map<String, String>? readDevice;
    Map<String, String>? fixture;

    try {
      writeDevice = await _createDevice(
        deviceName: 'IT write device ${DateTime.now().millisecondsSinceEpoch}',
        deviceRole: NoteService.roleWrite,
        platform: 'ios',
      );
      readDevice = await _createDevice(
        deviceName: 'IT read device ${DateTime.now().millisecondsSinceEpoch}',
        deviceRole: NoteService.roleRead,
        platform: 'ios',
      );
      fixture = await _createSharedFixture(
        writeDeviceId: writeDevice['deviceId']!,
        readDeviceId: readDevice['deviceId']!,
        bookPassword: bookPassword,
      );

      return _json(200, {
        'success': true,
        'writeDevice': writeDevice,
        'readDevice': readDevice,
        'fixture': fixture,
        'bookPassword': bookPassword,
      });
    } catch (e) {
      await _cleanupFixtureIds(
        bookUuids: [if (fixture != null) fixture['bookUuid'] ?? ''],
        eventIds: [if (fixture != null) fixture['eventId'] ?? ''],
        recordUuids: [if (fixture != null) fixture['recordUuid'] ?? ''],
        deviceIds: [
          if (writeDevice != null) writeDevice['deviceId'] ?? '',
          if (readDevice != null) readDevice['deviceId'] ?? '',
        ],
      );

      return _json(500, {
        'success': false,
        'message': 'Failed to provision live event metadata fixtures: $e',
      });
    }
  }

  Future<Response> _cleanupLiveEventMetadata(Request request) async {
    try {
      final json = await _readJson(request);
      final fixturePassword = (json['password'] as String?)?.trim() ?? '';
      if (!_isFixturePasswordValid(fixturePassword)) {
        return _json(401, {
          'success': false,
          'message': 'Invalid fixture password',
        });
      }

      final fixture = Map<String, dynamic>.from(
        (json['fixture'] as Map?) ?? const {},
      );
      final devices = Map<String, dynamic>.from(
        (json['devices'] as Map?) ?? const {},
      );

      await _cleanupFixtureIds(
        bookUuids: [fixture['bookUuid']?.toString() ?? ''],
        eventIds: [fixture['eventId']?.toString() ?? ''],
        recordUuids: [fixture['recordUuid']?.toString() ?? ''],
        deviceIds: [
          devices['writeDeviceId']?.toString() ?? '',
          devices['readDeviceId']?.toString() ?? '',
        ],
      );

      return _json(200, {
        'success': true,
        'message': 'Fixture data cleaned successfully',
      });
    } catch (e) {
      return _json(500, {
        'success': false,
        'message': 'Failed to cleanup live event metadata fixtures: $e',
      });
    }
  }
}
