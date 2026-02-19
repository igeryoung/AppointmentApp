import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'http_client_factory.dart';
import '../models/note.dart';

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
      if (kDebugMode) {}
    } else if (baseUrl.startsWith('http://')) {}
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
      final response = await _client
          .get(
            Uri.parse(
              '$baseUrl/api/books/$bookUuid/persons/$encodedRecordNumber',
            ),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

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
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/records/validate'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
            body: jsonEncode({'record_number': recordNumber, 'name': name}),
          )
          .timeout(timeout);

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

  /// Update record metadata on server.
  /// Used to sync record-level fields (name/phone/record_number).
  Future<Map<String, dynamic>> updateRecord({
    required String recordUuid,
    required Map<String, dynamic> recordData,
    required String deviceId,
    required String deviceToken,
  }) async {
    if (recordData.isEmpty) {
      throw ArgumentError('recordData cannot be empty');
    }

    try {
      final response = await _client
          .put(
            Uri.parse('$baseUrl/api/records/$recordUuid'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
            body: jsonEncode(recordData),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['record'] as Map<String, dynamic>?) ?? json;
      }

      throw ApiException(
        'Update record failed: ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
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
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

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

  /// Fetch events by date range from server
  /// Returns list of events within the specified date range
  Future<List<Map<String, dynamic>>> fetchEventsByDateRange({
    required String bookUuid,
    required DateTime startDate,
    required DateTime endDate,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/books/$bookUuid/events').replace(
        queryParameters: {
          'startDate': startDate.toUtc().toIso8601String(),
          'endDate': endDate.toUtc().toIso8601String(),
        },
      );

      final response = await _client
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['events'] as List).cast<Map<String, dynamic>>();
      } else {
        throw ApiException(
          'Fetch events by date range failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Create event on server
  Future<Map<String, dynamic>> createEvent({
    required String bookUuid,
    required Map<String, dynamic> eventData,
    required String deviceId,
    required String deviceToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/books/$bookUuid/events'),
          headers: {
            'Content-Type': 'application/json',
            'X-Device-ID': deviceId,
            'X-Device-Token': deviceToken,
          },
          body: jsonEncode(eventData),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['event'] as Map<String, dynamic>;
    }

    throw ApiException(
      'Create event failed: ${response.statusCode}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  /// Update event on server
  Future<Map<String, dynamic>> updateEvent({
    required String bookUuid,
    required String eventId,
    required Map<String, dynamic> eventData,
    required String deviceId,
    required String deviceToken,
  }) async {
    final response = await _client
        .patch(
          Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId'),
          headers: {
            'Content-Type': 'application/json',
            'X-Device-ID': deviceId,
            'X-Device-Token': deviceToken,
          },
          body: jsonEncode(eventData),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['event'] as Map<String, dynamic>;
    }

    if (response.statusCode == 409) {
      String message = 'Event version conflict';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        message = body['message'] as String? ?? message;
      } catch (_) {
        // Keep fallback message if response body isn't JSON.
      }
      throw ApiConflictException(
        message,
        statusCode: 409,
        responseBody: response.body,
      );
    }

    throw ApiException(
      'Update event failed: ${response.statusCode}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  /// Soft remove event on server
  Future<Map<String, dynamic>> removeEvent({
    required String bookUuid,
    required String eventId,
    required String reason,
    required String deviceId,
    required String deviceToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId/remove'),
          headers: {
            'Content-Type': 'application/json',
            'X-Device-ID': deviceId,
            'X-Device-Token': deviceToken,
          },
          body: jsonEncode({'reason': reason}),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['event'] as Map<String, dynamic>;
    }

    throw ApiException(
      'Remove event failed: ${response.statusCode}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  /// Hard delete event on server
  Future<void> deleteEvent({
    required String bookUuid,
    required String eventId,
    required String deviceId,
    required String deviceToken,
  }) async {
    final response = await _client
        .delete(
          Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId'),
          headers: {
            'Content-Type': 'application/json',
            'X-Device-ID': deviceId,
            'X-Device-Token': deviceToken,
          },
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw ApiException(
        'Delete event failed: ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Reschedule event (creates new event and removes old event)
  Future<Map<String, dynamic>> rescheduleEvent({
    required String bookUuid,
    required String eventId,
    required DateTime newStartTime,
    DateTime? newEndTime,
    required String reason,
    required String deviceId,
    required String deviceToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId/reschedule'),
          headers: {
            'Content-Type': 'application/json',
            'X-Device-ID': deviceId,
            'X-Device-Token': deviceToken,
          },
          body: jsonEncode({
            'newStartTime': newStartTime.toUtc().toIso8601String(),
            'newEndTime': newEndTime?.toUtc().toIso8601String(),
            'reason': reason,
          }),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(
      'Reschedule event failed: ${response.statusCode}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
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
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId/note'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

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
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/books/$bookUuid/records/$recordUuid/note'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

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

      final response = await _client
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
            body: jsonEncode(requestBody),
          )
          .timeout(timeout);

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
        debugPrint(
          '[ApiClient] saveNote: 404 - Event not found on server. Response: ${response.body}',
        );
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
      final response = await _client
          .delete(
            Uri.parse('$baseUrl/api/books/$bookUuid/events/$eventId/note'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

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
    required List<String> recordUuids,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/notes/batch'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
            body: jsonEncode({'record_uuids': recordUuids}),
          )
          .timeout(timeout);

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
      final uri = Uri.parse('$baseUrl/api/books/$bookUuid/drawings').replace(
        queryParameters: {'date': dateStr, 'viewMode': viewMode.toString()},
      );

      final response = await _client
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

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
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/books/$bookUuid/drawings'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
            body: jsonEncode(drawingData),
          )
          .timeout(timeout);

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
      final uri = Uri.parse('$baseUrl/api/books/$bookUuid/drawings').replace(
        queryParameters: {'date': dateStr, 'viewMode': viewMode.toString()},
      );

      final response = await _client
          .delete(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

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

      final response = await _client
          .post(
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
          )
          .timeout(timeout);

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
  // Server-Store API: Charge Items
  // ===================

  /// Fetch charge items for a record from server
  Future<List<Map<String, dynamic>>> fetchChargeItems({
    required String recordUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/records/$recordUuid/charge-items'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final items = json['chargeItems'] as List<dynamic>;
        return items.cast<Map<String, dynamic>>();
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw ApiException(
          'Fetch charge items failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Save (create or update) a charge item to server
  Future<Map<String, dynamic>> saveChargeItem({
    required String recordUuid,
    required Map<String, dynamic> chargeItemData,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/records/$recordUuid/charge-items'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
            body: jsonEncode(chargeItemData),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['chargeItem'] as Map<String, dynamic>;
      } else if (response.statusCode == 409) {
        throw ApiConflictException(
          'Charge item version conflict',
          statusCode: 409,
          responseBody: response.body,
        );
      } else {
        throw ApiException(
          'Save charge item failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a charge item from server
  Future<void> deleteChargeItem({
    required String chargeItemId,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('$baseUrl/api/charge-items/$chargeItemId'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw ApiException(
          'Delete charge item failed: ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // ===================
  // Book API
  // ===================

  /// Create a new book on the server
  Future<Map<String, dynamic>> createBook({
    required String name,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/books'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
            body: jsonEncode({'name': name}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final book = json['book'] as Map<String, dynamic>?;
        if (book == null) return json;
        // Backward-compatible fields for existing call sites/tests.
        return {...book, 'uuid': book['bookUuid'] ?? book['book_uuid']};
      } else if (response.statusCode == 401) {
        throw ApiException(
          'Unauthorized: Invalid device credentials',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      } else if (response.statusCode == 400) {
        throw ApiException(
          'Bad request: ${(jsonDecode(response.body) as Map<String, dynamic>)['message']}',
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

  /// List books on server for current device
  Future<List<Map<String, dynamic>>> listServerBooks({
    required String deviceId,
    required String deviceToken,
    String? searchQuery,
  }) async {
    try {
      final uri = searchQuery != null && searchQuery.isNotEmpty
          ? Uri.parse('$baseUrl/api/books?search=$searchQuery')
          : Uri.parse('$baseUrl/api/books');

      final response = await _client
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final books = (json['books'] as List).cast<Map<String, dynamic>>();
        return books;
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

  /// Fetch complete book payload (book + events + notes + drawings)
  /// from canonical endpoint.
  Future<Map<String, dynamic>> pullBook({
    required String bookUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/books/$bookUuid/bundle'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['bundle'] as Map<String, dynamic>;
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

  /// Get book metadata
  Future<Map<String, dynamic>> getServerBookInfo({
    required String bookUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/books/$bookUuid'),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
              'X-Device-Token': deviceToken,
            },
          )
          .timeout(timeout);

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

  /// Rename/update book metadata
  Future<Map<String, dynamic>> updateBook({
    required String bookUuid,
    required String name,
    required String deviceId,
    required String deviceToken,
  }) async {
    final response = await _client
        .patch(
          Uri.parse('$baseUrl/api/books/$bookUuid'),
          headers: {
            'Content-Type': 'application/json',
            'X-Device-ID': deviceId,
            'X-Device-Token': deviceToken,
          },
          body: jsonEncode({'name': name}),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['book'] as Map<String, dynamic>;
    }

    throw ApiException(
      'Update book failed: ${response.statusCode}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  Future<Map<String, dynamic>> archiveBook({
    required String bookUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/books/$bookUuid/archive'),
          headers: {
            'Content-Type': 'application/json',
            'X-Device-ID': deviceId,
            'X-Device-Token': deviceToken,
          },
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['book'] as Map<String, dynamic>;
    }

    throw ApiException(
      'Archive book failed: ${response.statusCode}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  Future<void> deleteBook({
    required String bookUuid,
    required String deviceId,
    required String deviceToken,
  }) async {
    final response = await _client
        .delete(
          Uri.parse('$baseUrl/api/books/$bookUuid'),
          headers: {
            'Content-Type': 'application/json',
            'X-Device-ID': deviceId,
            'X-Device-Token': deviceToken,
          },
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw ApiException(
        'Delete book failed: ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  // ===================
  // Device Registration API
  // ===================

  /// Check if a device is registered on the server
  Future<bool> checkDeviceRegistration({required String deviceId}) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/devices/$deviceId'))
          .timeout(timeout);

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
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/devices/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deviceName': deviceName,
              'platform': platform,
              'password': password,
            }),
          )
          .timeout(timeout);

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
}

/// API Exception with details
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  ApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() {
    return 'ApiException: $message (status: $statusCode)';
  }
}

/// API Conflict Exception (409) with server state
class ApiConflictException extends ApiException {
  ApiConflictException(super.message, {super.statusCode, super.responseBody});

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
