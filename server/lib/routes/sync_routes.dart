import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/connection.dart';
import '../models/sync_change.dart';
import '../services/sync_service.dart';

/// Router for sync endpoints
class SyncRoutes {
  final DatabaseConnection db;
  late final SyncService syncService;

  SyncRoutes(this.db) {
    syncService = SyncService(db);
  }

  Router get router {
    final router = Router();

    router.post('/pull', _pullChanges);
    router.post('/push', _pushChanges);
    router.post('/full', _fullSync);
    router.post('/resolve-conflict', _resolveConflict);

    return router;
  }

  /// Pull server changes since last sync
  Future<Response> _pullChanges(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final syncRequest = SyncRequest.fromJson(json);

      // Verify device token
      if (!await _verifyDevice(syncRequest.deviceId, syncRequest.deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get server changes since last sync
      final serverChanges = await syncService.getServerChanges(
        syncRequest.deviceId,
        syncRequest.lastSyncAt,
      );

      final response = SyncResponse(
        success: true,
        message: 'Changes retrieved successfully',
        serverChanges: serverChanges,
        serverTime: DateTime.now(),
        changesApplied: serverChanges.length,
      );

      print('✅ Pull: ${serverChanges.length} changes sent to device ${syncRequest.deviceId}');

      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Pull changes failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to pull changes: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Push local changes to server
  Future<Response> _pushChanges(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final syncRequest = SyncRequest.fromJson(json);

      // Verify device token
      if (!await _verifyDevice(syncRequest.deviceId, syncRequest.deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (syncRequest.localChanges == null || syncRequest.localChanges!.isEmpty) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'message': 'No changes to push',
            'serverTime': DateTime.now().toIso8601String(),
            'changesApplied': 0,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Apply local changes to server
      final result = await syncService.applyClientChanges(
        syncRequest.deviceId,
        syncRequest.localChanges!,
      );

      final response = SyncResponse(
        success: result.conflicts.isEmpty,
        message: result.conflicts.isEmpty
            ? 'Changes applied successfully'
            : 'Conflicts detected',
        conflicts: result.conflicts.isEmpty ? null : result.conflicts,
        serverTime: DateTime.now(),
        changesApplied: result.appliedCount,
      );

      print('✅ Push: ${result.appliedCount} changes applied, ${result.conflicts.length} conflicts');

      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Push changes failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to push changes: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Full bidirectional sync
  Future<Response> _fullSync(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final syncRequest = SyncRequest.fromJson(json);

      // Verify device token
      if (!await _verifyDevice(syncRequest.deviceId, syncRequest.deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Perform full sync
      final result = await syncService.performFullSync(
        syncRequest.deviceId,
        syncRequest.lastSyncAt,
        syncRequest.localChanges ?? [],
      );

      final response = SyncResponse(
        success: result.conflicts.isEmpty,
        message: result.conflicts.isEmpty
            ? 'Full sync completed successfully'
            : 'Full sync completed with conflicts',
        serverChanges: result.serverChanges,
        conflicts: result.conflicts.isEmpty ? null : result.conflicts,
        serverTime: DateTime.now(),
        changesApplied: result.appliedCount,
      );

      print('✅ Full sync: ${result.appliedCount} applied, ${result.serverChanges.length} sent, ${result.conflicts.length} conflicts');

      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Full sync failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to perform full sync: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Resolve a conflict
  Future<Response> _resolveConflict(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final resolutionRequest = ConflictResolutionRequest.fromJson(json);

      // Verify device token
      if (!await _verifyDevice(
          resolutionRequest.deviceId, resolutionRequest.deviceToken)) {
        return Response.forbidden(
          jsonEncode({'success': false, 'message': 'Invalid device credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Resolve conflict
      await syncService.resolveConflict(resolutionRequest);

      print('✅ Conflict resolved: ${resolutionRequest.tableName}/${resolutionRequest.recordId}');

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Conflict resolved successfully',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('❌ Conflict resolution failed: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'message': 'Failed to resolve conflict: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Verify device credentials
  Future<bool> _verifyDevice(String deviceId, String token) async {
    try {
      final row = await db.querySingle(
        'SELECT id FROM devices WHERE id = @id AND device_token = @token AND is_active = true',
        parameters: {'id': deviceId, 'token': token},
      );
      return row != null;
    } catch (e) {
      print('❌ Device verification failed: $e');
      return false;
    }
  }
}
