import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'http_client_factory.dart';
import '../models/note.dart';
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
      if (kDebugMode) {
      }
    } else if (baseUrl.startsWith('http://')) {
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
      return false;
    }
  }

  /// Fetch person data by record number from server
  /// Returns person info including name and latest note
  /// Note: With the new record-based architecture, same record_number can have
  /// different names. This method returns the first match for backward compatibility.
  Future<Map<String, dynamic>?> fetchPersonByRecordNumber({
    required String bookUuid,
    required String recordNumber,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      // URL encode the record number in case it contains special characters
      final encodedRecordNumber = Uri.encodeComponent(recordNumber);
      final response = await _client.get(
        Uri.parse('$baseUrl/api/books/$bookUuid/persons/$encodedRecordNumber'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['person'] as Map<String, dynamic>?;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw ApiException(
          'Fetch person failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Validate record number against name
  /// Checks if record number exists and whether it matches the provided name
  /// Returns validation result with conflict information if applicable
  Future<RecordValidationResult> validateRecordNumber({
    required String recordNumber,
    required String name,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/records/validate'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
        body: jsonEncode({
          'record_number': recordNumber,
          'name': name,
        }),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return RecordValidationResult.fromJson(json);
      } else {
        throw ApiException(
          'Validate record number failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch event metadata from server
  Future<Map<String, dynamic>?> fetchEvent({
    required String bookUuid,
    required String eventId,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['event'] as Map<String, dynamic>?;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw ApiException(
          'Fetch event failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // ===================
  // Server-Store API: Notes
  // ===================

  /// Fetch a single note from server
  Future<Note?> fetchNote({
    required String bookUuid,
    required String eventId,
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
        final noteJson = json['note'] as Map<String, dynamic>?;
        return noteJson == null ? null : Note.fromServer(noteJson);
      } else {
        throw ApiException(
          'Fetch note failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch a single note by record UUID from server
  Future<Note?> fetchNoteByRecordUuid({
    required String bookUuid,
    required String recordUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/books/$bookUuid/records/$recordUuid/note'),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final noteJson = json['note'] as Map<String, dynamic>?;
        return noteJson == null ? null : Note.fromServer(noteJson);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw ApiException(
          'Fetch note by record failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Save (create or update) a note to server
  ///
  /// If eventData is provided and the event doesn't exist on the server,
  /// the server will auto-create the event before saving the note
  Future<Map<String, dynamic>> saveNote({
    required String bookUuid,
    required String eventId,
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

      final url = '$baseUrl/api/books/$bookUuid/events/$eventId/note';
      debugPrint('[ApiClient] saveNote: POST $url');
      debugPrint('[ApiClient] saveNote: hasEventData=${eventData != null}');

      final response = await _client.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
          'X-Device-Token': deviceToken,
        },
        body: jsonEncode(requestBody),
      ).timeout(timeout);

      debugPrint('[ApiClient] saveNote: response=${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['note'] as Map<String, dynamic>;
      } else if (response.statusCode == 409) {
        // Version conflict
        String message = 'Note version conflict';
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          message = body['message'] as String? ?? message;
        } catch (e) {
          // Keep fallback message if response body isn't JSON.
        }
        throw ApiConflictException(
          message,
          statusCode: 409,
          responseBody: response.body,
        );
      } else if (response.statusCode == 404) {
        debugPrint('[ApiClient] saveNote: 404 - Event not found on server. Response: ${response.body}');
        throw ApiException(
          'Event not found on server',
          statusCode: 404,
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
      rethrow;
    }
  }

  /// Delete a note from server
  Future<void> deleteNote({
    required String bookUuid,
    required String eventId,
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
      rethrow;
    }
  }

  /// Batch fetch notes from server
  Future<List<Map<String, dynamic>>> batchFetchNotes({
    required List<String> eventIds,
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
            'deviceId': book['deviceId'],  // Pass through deviceId from server
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
        if (syncResponse.conflicts != null && syncResponse.conflicts!.isNotEmpty) {
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
      rethrow;
    }
  }

  /// Pull server changes
  /// Retrieves changes from server since last sync
  Future<SyncResponse> pullChanges(SyncRequest request) async {
    try {

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
      rethrow;
    }
  }

  /// Perform full bidirectional sync
  /// Pushes local changes and pulls server changes in a single transaction
  Future<SyncResponse> fullSync(SyncRequest request) async {
    try {

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
        if (syncResponse.conflicts != null && syncResponse.conflicts!.isNotEmpty) {
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
        return syncResponse;
      } else {
        throw ApiException(
          'Full sync failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
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

/// Result of record number validation
class RecordValidationResult {
  final bool exists;
  final bool valid;
  final Map<String, dynamic>? record;

  RecordValidationResult({
    required this.exists,
    required this.valid,
    this.record,
  });

  factory RecordValidationResult.fromJson(Map<String, dynamic> json) {
    return RecordValidationResult(
      exists: json['exists'] as bool,
      valid: json['valid'] as bool,
      record: json['record'] as Map<String, dynamic>?,
    );
  }

  bool get hasConflict => exists && !valid;
}
