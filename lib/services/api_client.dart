import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'http_client_factory.dart';
import '../models/sync_models.dart';

/// HTTP API client for communicating with sync server
class ApiClient {
  final String baseUrl;
  final Duration timeout;
  late final http.Client _client;

  ApiClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
  }) {
    _client = HttpClientFactory.createClient();

    // Log SSL configuration
    if (baseUrl.startsWith('https://')) {
      debugPrint('🔒 API client using HTTPS: $baseUrl');
      if (kDebugMode) {
        debugPrint('   Self-signed certificates are accepted in debug mode');
      }
    } else if (baseUrl.startsWith('http://')) {
      debugPrint('⚠️  API client using HTTP (insecure): $baseUrl');
    }
  }

  /// Clean up resources
  void dispose() {
    _client.close();
  }

  /// Health check
  Future<bool> healthCheck() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Health check failed: $e');
      return false;
    }
  }

  // ===================
  // Server-Store API: Notes
  // ===================

  /// Fetch a single note from server
  Future<Map<String, dynamic>?> fetchNote({
    required String bookUuid,
    required int eventId,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId/note'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // Server returns { success: true, note: null } when note doesn't exist
        return json['note'] as Map<String, dynamic>?;
      } else {
        throw ApiException(
          'Fetch note failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Fetch note failed: $e');
      rethrow;
    }
  }

  /// Save (create or update) a note to server
  ///
  /// If eventData is provided and the event doesn't exist on the server,
  /// the server will auto-create the event before saving the note
  Future<Map<String, dynamic>> saveNote({
    required String bookUuid,
    required int eventId,
    required Map<String, dynamic> noteData,
    required String deviceId,
    required String deviceToken,
    Map<String, dynamic>? eventData,
  }) async {
    try {
      // Include eventData in request body if provided
      final requestBody = Map<String, dynamic>.from(noteData);
      if (eventData != null) {
        requestBody['eventData'] = eventData;
      }

      final response = await _client.post(
        Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId/note'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
        body: jsonEncode(requestBody),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['note'] as Map<String, dynamic>;
      } else if (response.statusCode == 409) {
        // Version conflict
        throw ApiConflictException(
          'Note version conflict',
          statusCode: 409,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'Save note failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Save note failed: $e');
      rethrow;
    }
  }

  /// Delete a note from server
  Future<void> deleteNote({
    required String bookUuid,
    required int eventId,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId/note'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode != 200) {
        throw ApiException(
          'Delete note failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Delete note failed: $e');
      rethrow;
    }
  }

  /// Batch fetch notes from server
  Future<List<Map<String, dynamic>>> batchFetchNotes({
    required List<int> eventIds,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/notes/batch'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
        body: jsonEncode({'eventIds': eventIds}),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final notes = json['notes'] as List<dynamic>;
        return notes.cast<Map<String, dynamic>>();
      } else {
        throw ApiException(
          'Batch fetch notes failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Batch fetch notes failed: $e');
      rethrow;
    }
  }

  // ===================
  // Server-Store API: Drawings
  // ===================

  /// Fetch a single drawing from server
  Future<Map<String, dynamic>?> fetchDrawing({
    required String bookUuid,
    required DateTime date,
    required int viewMode,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      // Format date as YYYY-MM-DD
      final dateStr = date.toIso8601String().split('T')[0];
      final uri = Uri.parse('$baseUrl/api/books/$bookUuid/drawings')
          .replace(queryParameters: {
        'date': dateStr,
        'viewMode': viewMode.toString(),
      });

      final response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // Server returns { success: true, drawing: null } when drawing doesn't exist
        return json['drawing'] as Map<String, dynamic>?;
      } else {
        throw ApiException(
          'Fetch drawing failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Fetch drawing failed: $e');
      rethrow;
    }
  }

  /// Save (create or update) a drawing to server
  Future<Map<String, dynamic>> saveDrawing({
    required String bookUuid,
    required Map<String, dynamic> drawingData,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/books/$bookUuid/drawings'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
        body: jsonEncode(drawingData),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['drawing'] as Map<String, dynamic>;
      } else if (response.statusCode == 409) {
        // Version conflict
        throw ApiConflictException(
          'Drawing version conflict',
          statusCode: 409,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'Save drawing failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Save drawing failed: $e');
      rethrow;
    }
  }

  /// Delete a drawing from server
  Future<void> deleteDrawing({
    required String bookUuid,
    required DateTime date,
    required int viewMode,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      // Format date as YYYY-MM-DD
      final dateStr = date.toIso8601String().split('T')[0];
      final uri = Uri.parse('$baseUrl/api/books/$bookUuid/drawings')
          .replace(queryParameters: {
        'date': dateStr,
        'viewMode': viewMode.toString(),
      });

      final response = await _client.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode != 200) {
        throw ApiException(
          'Delete drawing failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Delete drawing failed: $e');
      rethrow;
    }
  }

  /// Batch fetch drawings from server
  Future<List<Map<String, dynamic>>> batchFetchDrawings({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      // Format dates as YYYY-MM-DD
      final startDateStr = startDate.toIso8601String().split('T')[0];
      final endDateStr = endDate.toIso8601String().split('T')[0];

      final response = await _client.post(
        Uri.parse('$baseUrl/api/drawings/batch'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
        body: jsonEncode({
          'bookUuid': bookUuid,
          'startDate': startDateStr,
          'endDate': endDateStr,
        }),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final drawings = json['drawings'] as List<dynamic>;
        return drawings.cast<Map<String, dynamic>>();
      } else {
        throw ApiException(
          'Batch fetch drawings failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Batch fetch drawings failed: $e');
      rethrow;
    }
  }

  // ===================
  // Book Creation API
  // ===================

  /// Create a new book on the server and get UUID
  /// This must be called before creating a book locally
  Future<Map<String, dynamic>> createBook({
    required String name,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final now = DateTime.now();

      final response = await _client.post(
        Uri.parse('$baseUrl/api/create-books'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
        body: jsonEncode({
          'name': name,
          'created_at': now.toUtc().toIso8601String(),
        }),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json;
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Unauthorized: Invalid device credentials',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else if (response.statusCode == 400) {
        throw ApiException(
          'Bad request: ${jsonDecode(response.body)['message']}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'Book creation failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Book creation failed: $e');
      rethrow;
    }
  }

  // ===================
  // Book Pull API (Server → Local)
  // ===================

  /// List all books available on server for the device
  /// Optional [searchQuery] filters books by name (case-insensitive)
  /// Returns books in the format expected by the restore dialog
  Future<List<Map<String, dynamic>>> listServerBooks({
    required String deviceId,
    required String deviceToken,
    String? searchQuery,
  }) async {
    try {
      final uri = searchQuery != null && searchQuery.isNotEmpty
          ? Uri.parse('$baseUrl/api/books/list?search=$searchQuery')
          : Uri.parse('$baseUrl/api/books/list');

      final response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final books = (json['books'] as List).cast<Map<String, dynamic>>();

        // Transform to backup list format for compatibility
        // NOTE: Using bookUuid as 'id' for backward compatibility with restore dialog
        return books.map((book) {
          return {
            'id': book['id'],
            'bookUuid': book['bookUuid'],
            'backupName': book['name'],
            'backupSize': book['size'] ?? 0,
            'createdAt': book['createdAt'],
            'restoredAt': null,
          };
        }).toList();
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Unauthorized: Invalid device credentials',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'List server books failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ List server books failed: $e');
      rethrow;
    }
  }

  /// Pull complete book data from server (book + events + notes + drawings)
  /// This is used to add a server book to local device
  Future<Map<String, dynamic>> pullBook({
    required String bookUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/books/pull/$bookUuid'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['data'] as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Unauthorized: Invalid device credentials',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else if (response.statusCode == 404) {
        throw ApiException(
          'Book not found or does not belong to this device',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'Pull book failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Pull book failed: $e');
      rethrow;
    }
  }

  /// Get book metadata only (without events/notes/drawings)
  /// Useful for checking if a book exists on server or getting version info
  Future<Map<String, dynamic>> getServerBookInfo({
    required String bookUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/books/$bookUuid/info'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['book'] as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Unauthorized: Invalid device credentials',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else if (response.statusCode == 404) {
        throw ApiException(
          'Book not found or does not belong to this device',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'Get server book info failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Get server book info failed: $e');
      rethrow;
    }
  }

  // ===================
  // Book Backup API (Local → Server Upload)
  // ===================

  /// Upload book backup to server
  /// Used to backup a complete book (book + events + notes + drawings)
  Future<int> uploadBookBackup({
    required String bookUuid,
    required String backupName,
    required Map<String, dynamic> backupData,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      debugPrint('📤 Uploading book backup: $backupName');

      final response = await _client.post(
        Uri.parse('$baseUrl/api/books/$bookUuid/backup'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
        body: jsonEncode({
          'backupName': backupName,
        }),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final backupId = json['backupId'] as int;
        debugPrint('✅ Book backup uploaded successfully: Backup ID $backupId');
        return backupId;
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Unauthorized: Invalid device credentials',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'Upload book backup failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Upload book backup failed: $e');
      rethrow;
    }
  }

  // ===================
  // Device Registration API
  // ===================

  /// Check if a device is registered on the server
  Future<bool> checkDeviceRegistration({
    required String deviceId,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/devices/$deviceId'),
      ).timeout(timeout);

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Check device registration failed: $e');
      return false;
    }
  }

  /// Register a new device with password
  Future<Map<String, dynamic>> registerDevice({
    required String deviceName,
    required String password,
    String? platform,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/devices/register'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'deviceName': deviceName,
          'platform': platform,
          'password': password,
        }),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json;
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Invalid registration password',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'Device registration failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Device registration failed: $e');
      rethrow;
    }
  }

  // ===================
  // Generic Sync API
  // ===================

  /// Push local changes to server
  /// Sends local changes and returns server acknowledgment
  Future<SyncResponse> pushChanges(SyncRequest request) async {
    try {
      debugPrint('🔄 Pushing ${request.localChanges?.length ?? 0} changes to server');

      final response = await _client.post(
        Uri.parse('$baseUrl/api/sync/push'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': request.deviceId,
          'X-Device-Token': request.deviceToken,
        },
        body: jsonEncode(request.toJson()),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final syncResponse = SyncResponse.fromJson(json);
        debugPrint('✅ Push successful: ${syncResponse.changesApplied} changes applied');
        if (syncResponse.conflicts != null && syncResponse.conflicts!.isNotEmpty) {
          debugPrint('⚠️  ${syncResponse.conflicts!.length} conflicts detected');
        }
        return syncResponse;
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Unauthorized: Invalid device credentials',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else if (response.statusCode == 409) {
        // Conflicts detected
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return SyncResponse.fromJson(json);
      } else {
        throw ApiException(
          'Push changes failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Push changes failed: $e');
      rethrow;
    }
  }

  /// Pull server changes
  /// Retrieves changes from server since last sync
  Future<SyncResponse> pullChanges(SyncRequest request) async {
    try {
      debugPrint('🔄 Pulling changes from server (lastSync: ${request.lastSyncAt})');

      final response = await _client.post(
        Uri.parse('$baseUrl/api/sync/pull'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': request.deviceId,
          'X-Device-Token': request.deviceToken,
        },
        body: jsonEncode(request.toJson()),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final syncResponse = SyncResponse.fromJson(json);
        debugPrint('✅ Pull successful: ${syncResponse.serverChanges?.length ?? 0} changes received');
        return syncResponse;
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Unauthorized: Invalid device credentials',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'Pull changes failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Pull changes failed: $e');
      rethrow;
    }
  }

  /// Perform full bidirectional sync
  /// Pushes local changes and pulls server changes in a single transaction
  Future<SyncResponse> fullSync(SyncRequest request) async {
    try {
      debugPrint('🔄 Starting full sync (${request.localChanges?.length ?? 0} local changes)');

      final response = await _client.post(
        Uri.parse('$baseUrl/api/sync/full'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': request.deviceId,
          'X-Device-Token': request.deviceToken,
        },
        body: jsonEncode(request.toJson()),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final syncResponse = SyncResponse.fromJson(json);
        debugPrint('✅ Full sync successful:');
        debugPrint('   - Applied: ${syncResponse.changesApplied} local changes');
        debugPrint('   - Received: ${syncResponse.serverChanges?.length ?? 0} server changes');
        if (syncResponse.conflicts != null && syncResponse.conflicts!.isNotEmpty) {
          debugPrint('   - Conflicts: ${syncResponse.conflicts!.length}');
        }
        return syncResponse;
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Unauthorized: Invalid device credentials',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else if (response.statusCode == 409) {
        // Conflicts detected
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final syncResponse = SyncResponse.fromJson(json);
        debugPrint('⚠️  Full sync completed with conflicts: ${syncResponse.conflicts!.length}');
        return syncResponse;
      } else {
        throw ApiException(
          'Full sync failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ Full sync failed: $e');
      rethrow;
    }
  }
}

/// API Exception with details
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  ApiException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() {
    return 'ApiException: $message (status: $statusCode)';
  }
}

/// API Conflict Exception (409) with server state
class ApiConflictException extends ApiException {
  ApiConflictException(
    super.message, {
    super.statusCode,
    super.responseBody,
  });

  Map<String, dynamic>? get serverState {
    if (responseBody == null) return null;
    try {
      return jsonDecode(responseBody!) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Extract server version from conflict response
  /// Returns null if not available
  int? get serverVersion {
    final state = serverState;
    if (state == null) return null;
    return state['serverVersion'] as int?;
  }

  /// Extract server drawing data from conflict response
  /// Returns null if not available
  Map<String, dynamic>? get serverDrawing {
    final state = serverState;
    if (state == null) return null;
    return state['serverDrawing'] as Map<String, dynamic>?;
  }

  /// Extract server note data from conflict response
  /// Returns null if not available
  Map<String, dynamic>? get serverNote {
    final state = serverState;
    if (state == null) return null;
    return state['serverNote'] as Map<String, dynamic>?;
  }
}
