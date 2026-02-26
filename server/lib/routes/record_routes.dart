import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../database/connection.dart';

/// Router for record management endpoints
class RecordRoutes {
  final DatabaseConnection db;
  final _uuid = const Uuid();

  RecordRoutes(this.db);

  Router get router {
    final r = Router();

    r.post('/', _createRecord);
    r.get('/<recordUuid>', _getRecord);
    r.get('/by-number/<recordNumber>', _getRecordByNumber);
    r.put('/<recordUuid>', _updateRecord);
    r.delete('/<recordUuid>', _deleteRecord);
    r.post('/get-or-create', _getOrCreate);
    r.post('/validate', _validate);

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

  String _toStringValue(dynamic value) => value?.toString() ?? '';

  Future<Response> _createRecord(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final recordNumber = (data['record_number'] ?? '').toString();
      final name = data['name']?.toString();
      final phone = data['phone']?.toString();

      if (recordNumber.isNotEmpty && name != null && name.isNotEmpty) {
        final existingRows = await db.client
            .from('records')
            .select('record_uuid')
            .eq('name', name)
            .eq('record_number', recordNumber)
            .eq('is_deleted', false)
            .limit(1);
        final existing = _first(existingRows);
        if (existing != null) {
          return Response.ok(
            jsonEncode({'record_uuid': existing['record_uuid'], 'exists': true}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final insertedRows = await db.client
          .from('records')
          .insert({
            'record_uuid': _uuid.v4(),
            'record_number': recordNumber,
            'name': name,
            'phone': phone,
            'created_at': now,
            'updated_at': now,
            'synced_at': now,
            'version': 1,
            'is_deleted': false,
          })
          .select(
            'record_uuid, record_number, name, phone, created_at, updated_at, version',
          )
          .limit(1);

      final row = _first(insertedRows)!;
      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'created_at': _toStringValue(row['created_at']),
          'updated_at': _toStringValue(row['updated_at']),
          'version': row['version'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _getRecord(Request request, String recordUuid) async {
    try {
      final rows = await db.client
          .from('records')
          .select('*')
          .eq('record_uuid', recordUuid)
          .eq('is_deleted', false)
          .limit(1);
      final row = _first(rows);

      if (row == null) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'created_at': _toStringValue(row['created_at']),
          'updated_at': _toStringValue(row['updated_at']),
          'version': row['version'],
          'is_deleted': row['is_deleted'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _getRecordByNumber(
    Request request,
    String recordNumber,
  ) async {
    try {
      final rows = await db.client
          .from('records')
          .select('*')
          .eq('record_number', recordNumber)
          .eq('is_deleted', false)
          .limit(1);
      final row = _first(rows);

      if (row == null) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'created_at': _toStringValue(row['created_at']),
          'updated_at': _toStringValue(row['updated_at']),
          'version': row['version'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _updateRecord(Request request, String recordUuid) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final existingRows = await db.client
          .from('records')
          .select('version')
          .eq('record_uuid', recordUuid)
          .eq('is_deleted', false)
          .limit(1);
      final existing = _first(existingRows);
      if (existing == null) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      final updates = <String, dynamic>{};
      if (data.containsKey('name')) {
        updates['name'] = data['name'];
      }
      if (data.containsKey('phone')) {
        updates['phone'] = data['phone'];
      }
      if (data.containsKey('record_number')) {
        updates['record_number'] = data['record_number'];
      }

      if (updates.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'No fields to update'}),
        );
      }

      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
      updates['version'] = ((existing['version'] as num?)?.toInt() ?? 1) + 1;

      final updatedRows = await db.client
          .from('records')
          .update(updates)
          .eq('record_uuid', recordUuid)
          .select('*')
          .limit(1);
      final row = _first(updatedRows);

      if (row == null) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'updated_at': _toStringValue(row['updated_at']),
          'version': row['version'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _deleteRecord(Request request, String recordUuid) async {
    try {
      await db.client
          .from('records')
          .update({
            'is_deleted': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('record_uuid', recordUuid);
      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _getOrCreate(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final recordNumber = (data['record_number'] ?? '').toString();
      final name = data['name']?.toString();
      final phone = data['phone']?.toString();

      if (recordNumber.isNotEmpty && name != null && name.isNotEmpty) {
        final existingRows = await db.client
            .from('records')
            .select(
              'record_uuid, record_number, name, phone, created_at, updated_at, version',
            )
            .eq('name', name)
            .eq('record_number', recordNumber)
            .eq('is_deleted', false)
            .limit(1);
        final existing = _first(existingRows);
        if (existing != null) {
          return Response.ok(
            jsonEncode({
              'record_uuid': existing['record_uuid'],
              'record_number': existing['record_number'],
              'name': existing['name'],
              'phone': existing['phone'],
              'created_at': _toStringValue(existing['created_at']),
              'updated_at': _toStringValue(existing['updated_at']),
              'version': existing['version'],
              'created': false,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final insertedRows = await db.client
          .from('records')
          .insert({
            'record_uuid': _uuid.v4(),
            'record_number': recordNumber,
            'name': name,
            'phone': phone,
            'created_at': now,
            'updated_at': now,
            'synced_at': now,
            'version': 1,
            'is_deleted': false,
          })
          .select(
            'record_uuid, record_number, name, phone, created_at, updated_at, version',
          )
          .limit(1);

      final row = _first(insertedRows)!;
      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'created_at': _toStringValue(row['created_at']),
          'updated_at': _toStringValue(row['updated_at']),
          'version': row['version'],
          'created': true,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _validate(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final recordNumber = (data['record_number'] as String?)?.trim() ?? '';
      final name = (data['name'] as String?)?.trim() ?? '';

      if (recordNumber.isEmpty) {
        return Response.ok(
          jsonEncode({'exists': false, 'valid': true}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final rows = await db.client
          .from('records')
          .select('record_uuid, name')
          .eq('record_number', recordNumber)
          .eq('is_deleted', false)
          .limit(1);
      final row = _first(rows);

      if (row == null) {
        return Response.ok(
          jsonEncode({'exists': false, 'valid': true}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final existingName = (row['name'] ?? '').toString();
      if (existingName == name) {
        return Response.ok(
          jsonEncode({
            'exists': true,
            'valid': true,
            'record': {'record_uuid': row['record_uuid'], 'name': row['name']},
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'exists': true, 'valid': false}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }
}
