import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'prd_database_service.dart';
import 'server_config_service.dart';
import 'http_client_factory.dart';

/// Service for uploading and restoring complete books to/from server
class BookBackupService {
  final PRDDatabaseService dbService;
  late final ServerConfigService _serverConfigService;
  late final http.Client _client;

  BookBackupService({
    required this.dbService,
  }) {
    _serverConfigService = ServerConfigService(dbService);
    _client = HttpClientFactory.createClient();
  }

  /// Clean up resources
  void dispose() {
    _client.close();
  }

  /// Gather complete book data (book + events + notes + drawings)
  Future<Map<String, dynamic>> _gatherBookData(int bookId) async {
    final db = await dbService.database;

    // Get book
    final bookMaps = await db.query('books', where: 'id = ?', whereArgs: [bookId]);
    if (bookMaps.isEmpty) {
      throw Exception('Book not found');
    }
    final book = bookMaps.first;

    // Get all events for this book
    final events = await db.query('events', where: 'book_id = ?', whereArgs: [bookId]);

    // Get all notes for these events
    final eventIds = events.map((e) => e['id']).toList();
    final notes = eventIds.isNotEmpty
        ? await db.query('notes', where: 'event_id IN (${eventIds.join(',')})')
        : <Map<String, dynamic>>[];

    // Get all schedule drawings for this book
    final drawings = await db.query('schedule_drawings', where: 'book_id = ?', whereArgs: [bookId]);

    return {
      'book': book,
      'events': events,
      'notes': notes,
      'drawings': drawings,
    };
  }

  /// Upload a book to server
  Future<int> uploadBook(int bookId, {String? customName}) async {
    debugPrint('📤 Uploading book #$bookId...');

    // Get server URL
    final serverUrl = await _serverConfigService.getServerUrlOrDefault();
    debugPrint('Using server URL: $serverUrl');

    // Get device info directly from database
    final db = await dbService.database;
    final deviceRows = await db.query('device_info', limit: 1);
    if (deviceRows.isEmpty) {
      throw Exception('Device not registered. Please register device first.');
    }
    final deviceRow = deviceRows.first;
    final deviceId = deviceRow['device_id'] as String;
    final deviceToken = deviceRow['device_token'] as String;

    // Gather book data
    final backupData = await _gatherBookData(bookId);
    final bookName = customName ?? backupData['book']['name'] as String;

    // Prepare request
    final url = Uri.parse('$serverUrl/api/books/upload');
    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': deviceId,
        'deviceToken': deviceToken,
        'bookId': bookId,
        'backupName': bookName,
        'backupData': backupData,
      }),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        final backupId = result['backupId'] as int;
        debugPrint('✅ Book uploaded successfully: Backup ID $backupId');
        return backupId;
      } else {
        throw Exception(result['message'] ?? 'Upload failed');
      }
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  /// List all backups for this device
  Future<List<Map<String, dynamic>>> listBackups() async {
    debugPrint('📋 Fetching backup list...');

    // Get server URL
    final serverUrl = await _serverConfigService.getServerUrlOrDefault();

    // Get device info directly from database
    final db = await dbService.database;
    final deviceRows = await db.query('device_info', limit: 1);
    if (deviceRows.isEmpty) {
      throw Exception('Device not registered. Please register device first.');
    }
    final deviceRow = deviceRows.first;
    final deviceId = deviceRow['device_id'] as String;
    final deviceToken = deviceRow['device_token'] as String;

    // Fetch backups
    final url = Uri.parse('$serverUrl/api/books/list').replace(queryParameters: {
      'deviceId': deviceId,
      'deviceToken': deviceToken,
    });

    final response = await _client.get(url);

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        return (result['backups'] as List).cast<Map<String, dynamic>>();
      } else {
        throw Exception(result['message'] ?? 'Failed to list backups');
      }
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  /// Restore a book from server backup and download directly to local device
  Future<String> restoreBook(int backupId) async {
    debugPrint('📥 Restoring book from backup #$backupId...');

    // Get server URL
    final serverUrl = await _serverConfigService.getServerUrlOrDefault();

    // Get device info directly from database
    final db = await dbService.database;
    final deviceRows = await db.query('device_info', limit: 1);
    if (deviceRows.isEmpty) {
      throw Exception('Device not registered. Please register device first.');
    }
    final deviceRow = deviceRows.first;
    final deviceId = deviceRow['device_id'] as String;
    final deviceToken = deviceRow['device_token'] as String;

    // Download backup data directly from server
    final downloadUrl = Uri.parse('$serverUrl/api/books/download/$backupId').replace(
      queryParameters: {
        'deviceId': deviceId,
        'deviceToken': deviceToken,
      },
    );

    final response = await _client.get(downloadUrl);

    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }

    final result = jsonDecode(response.body);
    if (result['success'] != true) {
      throw Exception(result['message'] ?? 'Download failed');
    }

    debugPrint('✅ Backup data downloaded from server');

    // Apply backup data directly to local database
    final backupData = result['backupData'] as Map<String, dynamic>;
    final count = await _applyBackupDataLocally(backupData);

    debugPrint('✅ Book restored to local device: $count items');
    return 'Book restored successfully ($count items)';
  }

  /// Apply backup data directly to local database
  Future<int> _applyBackupDataLocally(Map<String, dynamic> backupData) async {
    final db = await dbService.database;
    int count = 0;

    await db.transaction((txn) async {
      // Extract data
      final book = backupData['book'] as Map<String, dynamic>;
      final events = (backupData['events'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final notes = (backupData['notes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final drawings = (backupData['drawings'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // Delete existing book if exists (CASCADE will delete events, notes, drawings)
      await txn.delete('books', where: 'id = ?', whereArgs: [book['id']]);

      // Insert book
      await txn.insert('books', {
        'id': book['id'],
        'book_uuid': book['book_uuid'],
        'name': book['name'],
        'created_at': book['created_at'],
        'archived_at': book['archived_at'],
      });
      count++;

      // Insert events
      for (final event in events) {
        await txn.insert('events', {
          'id': event['id'],
          'book_id': event['book_id'],
          'name': event['name'],
          'record_number': event['record_number'],
          'event_type': event['event_type'],
          'start_time': event['start_time'],
          'end_time': event['end_time'],
          'created_at': event['created_at'],
          'updated_at': event['updated_at'],
          'is_removed': event['is_removed'] ?? 0,
          'removal_reason': event['removal_reason'],
          'original_event_id': event['original_event_id'],
          'new_event_id': event['new_event_id'],
        });
        count++;
      }

      // Insert notes
      for (final note in notes) {
        await txn.insert('notes', {
          'id': note['id'],
          'event_id': note['event_id'],
          'strokes_data': note['strokes_data'],
          'created_at': note['created_at'],
          'updated_at': note['updated_at'],
        });
        count++;
      }

      // Insert schedule drawings
      for (final drawing in drawings) {
        await txn.insert('schedule_drawings', {
          'id': drawing['id'],
          'book_id': drawing['book_id'],
          'date': drawing['date'],
          'view_mode': drawing['view_mode'],
          'strokes_data': drawing['strokes_data'],
          'created_at': drawing['created_at'],
          'updated_at': drawing['updated_at'],
        });
        count++;
      }
    });

    return count;
  }

  /// Delete a backup from server
  Future<void> deleteBackup(int backupId) async {
    debugPrint('🗑️ Deleting backup #$backupId...');

    // Get server URL
    final serverUrl = await _serverConfigService.getServerUrlOrDefault();

    // Get device info directly from database
    final db = await dbService.database;
    final deviceRows = await db.query('device_info', limit: 1);
    if (deviceRows.isEmpty) {
      throw Exception('Device not registered. Please register device first.');
    }
    final deviceRow = deviceRows.first;
    final deviceId = deviceRow['device_id'] as String;
    final deviceToken = deviceRow['device_token'] as String;

    // Delete backup
    final url = Uri.parse('$serverUrl/api/books/$backupId').replace(queryParameters: {
      'deviceId': deviceId,
      'deviceToken': deviceToken,
    });

    final response = await _client.delete(url);

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        debugPrint('✅ Backup deleted successfully');
      } else {
        throw Exception(result['message'] ?? 'Delete failed');
      }
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }
}
