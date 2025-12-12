import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';

Router recordRoutes() {
  final router = Router();

  // Create record
  router.post('/', (Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final recordNumber = data['record_number'] ?? '';
      final name = data['name'];
      final phone = data['phone'];

      final conn = await DatabaseConnection().connection;

      // Check if record_number already exists (if non-empty)
      if (recordNumber.isNotEmpty) {
        final existing = await conn.execute(
          'SELECT record_uuid FROM records WHERE record_number = \$1 AND is_deleted = false',
          parameters: [recordNumber],
        );
        if (existing.isNotEmpty) {
          return Response.ok(
            jsonEncode({'record_uuid': existing.first[0], 'exists': true}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      final result = await conn.execute(
        '''INSERT INTO records (record_number, name, phone)
           VALUES (\$1, \$2, \$3)
           RETURNING record_uuid, record_number, name, phone, created_at, updated_at, version''',
        parameters: [recordNumber, name, phone],
      );

      final row = result.first;
      return Response.ok(
        jsonEncode({
          'record_uuid': row[0],
          'record_number': row[1],
          'name': row[2],
          'phone': row[3],
          'created_at': row[4].toString(),
          'updated_at': row[5].toString(),
          'version': row[6],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  // Get record by UUID
  router.get('/<recordUuid>', (Request request, String recordUuid) async {
    try {
      final conn = await DatabaseConnection().connection;
      final result = await conn.execute(
        'SELECT * FROM records WHERE record_uuid = \$1 AND is_deleted = false',
        parameters: [recordUuid],
      );

      if (result.isEmpty) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      final row = result.first;
      return Response.ok(
        jsonEncode({
          'record_uuid': row[0],
          'record_number': row[1],
          'name': row[2],
          'phone': row[3],
          'created_at': row[4].toString(),
          'updated_at': row[5].toString(),
          'version': row[7],
          'is_deleted': row[8],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  // Get record by record_number
  router.get('/by-number/<recordNumber>', (Request request, String recordNumber) async {
    try {
      final conn = await DatabaseConnection().connection;
      final result = await conn.execute(
        'SELECT * FROM records WHERE record_number = \$1 AND is_deleted = false',
        parameters: [recordNumber],
      );

      if (result.isEmpty) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      final row = result.first;
      return Response.ok(
        jsonEncode({
          'record_uuid': row[0],
          'record_number': row[1],
          'name': row[2],
          'phone': row[3],
          'created_at': row[4].toString(),
          'updated_at': row[5].toString(),
          'version': row[7],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  // Update record
  router.put('/<recordUuid>', (Request request, String recordUuid) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final conn = await DatabaseConnection().connection;

      final updates = <String>[];
      final params = <dynamic>[];
      var paramIndex = 1;

      if (data.containsKey('name')) {
        updates.add('name = \$${paramIndex++}');
        params.add(data['name']);
      }
      if (data.containsKey('phone')) {
        updates.add('phone = \$${paramIndex++}');
        params.add(data['phone']);
      }
      if (data.containsKey('record_number')) {
        updates.add('record_number = \$${paramIndex++}');
        params.add(data['record_number']);
      }

      if (updates.isEmpty) {
        return Response.badRequest(body: jsonEncode({'error': 'No fields to update'}));
      }

      params.add(recordUuid);
      final result = await conn.execute(
        'UPDATE records SET ${updates.join(', ')} WHERE record_uuid = \$${paramIndex} RETURNING *',
        parameters: params,
      );

      if (result.isEmpty) {
        return Response.notFound(jsonEncode({'error': 'Record not found'}));
      }

      final row = result.first;
      return Response.ok(
        jsonEncode({
          'record_uuid': row[0],
          'record_number': row[1],
          'name': row[2],
          'phone': row[3],
          'updated_at': row[5].toString(),
          'version': row[7],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  // Delete record (soft delete)
  router.delete('/<recordUuid>', (Request request, String recordUuid) async {
    try {
      final conn = await DatabaseConnection().connection;
      await conn.execute(
        'UPDATE records SET is_deleted = true WHERE record_uuid = \$1',
        parameters: [recordUuid],
      );
      return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  // Get or create record
  router.post('/get-or-create', (Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final recordNumber = data['record_number'] ?? '';
      final name = data['name'];
      final phone = data['phone'];

      final conn = await DatabaseConnection().connection;

      // For non-empty record_number, try to find existing
      if (recordNumber.isNotEmpty) {
        final existing = await conn.execute(
          'SELECT * FROM records WHERE record_number = \$1 AND is_deleted = false',
          parameters: [recordNumber],
        );
        if (existing.isNotEmpty) {
          final row = existing.first;
          return Response.ok(
            jsonEncode({
              'record_uuid': row[0],
              'record_number': row[1],
              'name': row[2],
              'phone': row[3],
              'created_at': row[4].toString(),
              'updated_at': row[5].toString(),
              'version': row[7],
              'created': false,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // Create new record
      final result = await conn.execute(
        '''INSERT INTO records (record_number, name, phone)
           VALUES (\$1, \$2, \$3)
           RETURNING record_uuid, record_number, name, phone, created_at, updated_at, version''',
        parameters: [recordNumber, name, phone],
      );

      final row = result.first;
      return Response.ok(
        jsonEncode({
          'record_uuid': row[0],
          'record_number': row[1],
          'name': row[2],
          'phone': row[3],
          'created_at': row[4].toString(),
          'updated_at': row[5].toString(),
          'version': row[6],
          'created': true,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
    }
  });

  return router;
}
