import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';

/// Router for record management endpoints
class RecordRoutes {
  final DatabaseConnection db;

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

  // Create record
  Future<Response> _createRecord(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final recordNumber = data['record_number'] ?? '';
      final name = data['name'] as String?;
      final phone = data['phone'];

      // Check if (name, record_number) already exists (when both are non-empty)
      if (recordNumber.isNotEmpty && name != null && name.isNotEmpty) {
        final existing = await db.queryRows(
          'SELECT record_uuid FROM records WHERE name = @name AND record_number = @record_number AND is_deleted = false',
          parameters: {'name': name, 'record_number': recordNumber},
        );
        if (existing.isNotEmpty) {
          return Response.ok(
            jsonEncode({'record_uuid': existing.first['record_uuid'], 'exists': true}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      final result = await db.queryRows(
        '''INSERT INTO records (record_number, name, phone)
           VALUES (@record_number, @name, @phone)
           RETURNING record_uuid, record_number, name, phone, created_at, updated_at, version''',
        parameters: {'record_number': recordNumber, 'name': name, 'phone': phone},
      );

      final row = result.first;
      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'created_at': row['created_at'].toString(),
          'updated_at': row['updated_at'].toString(),
          'version': row['version'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // Get record by UUID
  Future<Response> _getRecord(Request request, String recordUuid) async {
    try {
      final row = await db.querySingle(
        'SELECT * FROM records WHERE record_uuid = @record_uuid AND is_deleted = false',
        parameters: {'record_uuid': recordUuid},
      );

      if (row == null) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'created_at': row['created_at'].toString(),
          'updated_at': row['updated_at'].toString(),
          'version': row['version'],
          'is_deleted': row['is_deleted'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // Get record by record_number
  Future<Response> _getRecordByNumber(Request request, String recordNumber) async {
    try {
      final row = await db.querySingle(
        'SELECT * FROM records WHERE record_number = @record_number AND is_deleted = false',
        parameters: {'record_number': recordNumber},
      );

      if (row == null) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'created_at': row['created_at'].toString(),
          'updated_at': row['updated_at'].toString(),
          'version': row['version'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // Update record
  Future<Response> _updateRecord(Request request, String recordUuid) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final updates = <String>[];
      final params = <String, dynamic>{'record_uuid': recordUuid};

      if (data.containsKey('name')) {
        updates.add('name = @name');
        params['name'] = data['name'];
      }
      if (data.containsKey('phone')) {
        updates.add('phone = @phone');
        params['phone'] = data['phone'];
      }
      if (data.containsKey('record_number')) {
        updates.add('record_number = @record_number');
        params['record_number'] = data['record_number'];
      }

      if (updates.isEmpty) {
        return Response.badRequest(body: jsonEncode({'error': 'No fields to update'}));
      }

      final row = await db.querySingle(
        'UPDATE records SET ${updates.join(', ')} WHERE record_uuid = @record_uuid RETURNING *',
        parameters: params,
      );

      if (row == null) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'updated_at': row['updated_at'].toString(),
          'version': row['version'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // Delete record (soft delete)
  Future<Response> _deleteRecord(Request request, String recordUuid) async {
    try {
      await db.query(
        'UPDATE records SET is_deleted = true WHERE record_uuid = @record_uuid',
        parameters: {'record_uuid': recordUuid},
      );
      return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // Get or create record
  // Match by BOTH name AND record_number when both are non-empty
  Future<Response> _getOrCreate(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final recordNumber = data['record_number'] ?? '';
      final name = data['name'] as String?;
      final phone = data['phone'];

      // Match by BOTH name AND record_number when both are non-empty
      if (recordNumber.isNotEmpty && name != null && name.isNotEmpty) {
        final existing = await db.querySingle(
          'SELECT * FROM records WHERE name = @name AND record_number = @record_number AND is_deleted = false',
          parameters: {'name': name, 'record_number': recordNumber},
        );
        if (existing != null) {
          return Response.ok(
            jsonEncode({
              'record_uuid': existing['record_uuid'],
              'record_number': existing['record_number'],
              'name': existing['name'],
              'phone': existing['phone'],
              'created_at': existing['created_at'].toString(),
              'updated_at': existing['updated_at'].toString(),
              'version': existing['version'],
              'created': false,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // Create new record (either empty recordNumber, empty name, or no match found)
      final result = await db.queryRows(
        '''INSERT INTO records (record_number, name, phone)
           VALUES (@record_number, @name, @phone)
           RETURNING record_uuid, record_number, name, phone, created_at, updated_at, version''',
        parameters: {'record_number': recordNumber, 'name': name, 'phone': phone},
      );

      final row = result.first;
      return Response.ok(
        jsonEncode({
          'record_uuid': row['record_uuid'],
          'record_number': row['record_number'],
          'name': row['name'],
          'phone': row['phone'],
          'created_at': row['created_at'].toString(),
          'updated_at': row['updated_at'].toString(),
          'version': row['version'],
          'created': true,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }

  // Validate record number against name
  // Checks if record number exists with a different name (conflict)
  Future<Response> _validate(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final recordNumber = (data['record_number'] as String?)?.trim() ?? '';
      final name = (data['name'] as String?)?.trim() ?? '';

      // Empty record number is always valid (treated as "留空")
      if (recordNumber.isEmpty) {
        return Response.ok(
          jsonEncode({'exists': false, 'valid': true}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Check if record number exists
      final row = await db.querySingle(
        'SELECT record_uuid, name FROM records WHERE record_number = @record_number AND is_deleted = false',
        parameters: {'record_number': recordNumber},
      );

      if (row == null) {
        // Record number doesn't exist - it's new and valid
        return Response.ok(
          jsonEncode({'exists': false, 'valid': true}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Record exists - check if name matches
      final existingName = row['name'] as String?;

      if (existingName == name) {
        // Same name - valid, return the record data
        return Response.ok(
          jsonEncode({
            'exists': true,
            'valid': true,
            'record': {
              'record_uuid': row['record_uuid'],
              'name': row['name'],
            },
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Different name - conflict!
      return Response.ok(
        jsonEncode({
          'exists': true,
          'valid': false,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  }
}
