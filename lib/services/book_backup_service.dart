import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database/prd_database_service.dart';
import 'server_config_service.dart';
import 'api_client.dart';

/// Service for uploading and restoring complete books to/from server
/// Now uses ApiClient for all HTTP operations (no direct HTTP calls)
class BookBackupService {
  final PRDDatabaseService dbService;
  final ApiClient apiClient;
  late final ServerConfigService _serverConfigService;

  BookBackupService({
    required this.dbService,
    required this.apiClient,
  }) {
    _serverConfigService = ServerConfigService(dbService);
  }

  /// List all backups for this device
  Future<List<Map<String, dynamic>>> listBackups() async {

    // Get device info directly from database
    final db = await dbService.database;

    final deviceRows = await db.query('device_info', limit: 1);
    if (deviceRows.isEmpty) {
      throw Exception('Device not registered. Please register device first.');
    }
    final deviceRow = deviceRows.first;
    final deviceId = deviceRow['device_id'] as String;
    final deviceToken = deviceRow['device_token'] as String;

    // Use ApiClient to list server books
    final result = await apiClient.listServerBooks(
      deviceId: deviceId,
      deviceToken: deviceToken,
    );

    return result;
  }

  /// Restore a book from server backup and download directly to local device
  /// backupId is the server book ID (integer)
  Future<String> restoreBook(int backupId) async {

    // Get device info directly from database
    final db = await dbService.database;
    final deviceRows = await db.query('device_info', limit: 1);
    if (deviceRows.isEmpty) {
      throw Exception('Device not registered. Please register device first.');
    }
    final deviceRow = deviceRows.first;
    final deviceId = deviceRow['device_id'] as String;
    final deviceToken = deviceRow['device_token'] as String;

    // List backups to find the bookUuid for this backupId
    final backups = await listBackups();
    final backup = backups.firstWhere(
      (b) => b['id'] == backupId,
      orElse: () => throw Exception('Backup not found: $backupId'),
    );
    final bookUuid = backup['bookUuid'] as String;

    // Pull complete book data from server using ApiClient
    final bookData = await apiClient.pullBook(
      bookUuid: bookUuid,
      deviceId: deviceId,
      deviceToken: deviceToken,
    );


    // Apply book data directly to local database
    final count = await _applyBackupDataLocally(bookData);

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
      await txn.delete('books', where: 'book_uuid = ?', whereArgs: [book['book_uuid']]);

      // Insert book
      await txn.insert('books', {
        'book_uuid': book['book_uuid'],
        'name': book['name'],
        'created_at': book['created_at'] is int
            ? book['created_at']
            : DateTime.parse(book['created_at'] as String).toUtc().millisecondsSinceEpoch ~/ 1000,
        'archived_at': null,  // Clear archived status when restoring
        'version': book['version'] ?? 1,
        'is_dirty': 0,  // Server-based architecture: no dirty tracking
      });
      count++;

      // Insert events
      for (final event in events) {
        // Parse timestamps (handle both int and string formats)
        final startTime = event['start_time'] is int
            ? event['start_time']
            : DateTime.parse(event['start_time'] as String).millisecondsSinceEpoch ~/ 1000;
        final endTime = event['end_time'] != null
            ? (event['end_time'] is int
                ? event['end_time']
                : DateTime.parse(event['end_time'] as String).toUtc().millisecondsSinceEpoch ~/ 1000)
            : null;
        final createdAt = event['created_at'] is int
            ? event['created_at']
            : DateTime.parse(event['created_at'] as String).toUtc().millisecondsSinceEpoch ~/ 1000;
        final updatedAt = event['updated_at'] != null
            ? (event['updated_at'] is int
                ? event['updated_at']
                : DateTime.parse(event['updated_at'] as String).toUtc().millisecondsSinceEpoch ~/ 1000)
            : createdAt;

        await txn.insert('events', {
          'id': event['id'],
          'book_uuid': event['book_uuid'],
          'name': event['name'],
          'record_number': event['record_number'],
          'phone': event['phone'],
          'event_type': event['event_type'],
          'event_types': event['event_types'] ?? '[]',
          'has_charge_items': event['has_charge_items'] == true ? 1 : 0,
          'start_time': startTime,
          'end_time': endTime,
          'created_at': createdAt,
          'updated_at': updatedAt,
          'is_removed': event['is_removed'] == true ? 1 : 0,
          'removal_reason': event['removal_reason'],
          'original_event_id': event['original_event_id'],
          'new_event_id': event['new_event_id'],
          'is_checked': event['is_checked'] == true ? 1 : 0,
          'has_note': event['has_note'] == true ? 1 : 0,
          'version': event['version'] ?? 1,
          'is_dirty': 0,  // Server-based architecture: no dirty tracking
        });
        count++;
      }

      // Insert notes
      for (final note in notes) {
        // Parse timestamps (handle both int and string formats)
        final createdAt = note['created_at'] is int
            ? note['created_at']
            : DateTime.parse(note['created_at'] as String).toUtc().millisecondsSinceEpoch ~/ 1000;
        final updatedAt = note['updated_at'] != null
            ? (note['updated_at'] is int
                ? note['updated_at']
                : DateTime.parse(note['updated_at'] as String).toUtc().millisecondsSinceEpoch ~/ 1000)
            : createdAt;

        await txn.insert('notes', {
          'id': note['id'],
          'event_id': note['event_id'],
          'strokes_data': note['strokes_data'],
          'pages_data': note['pages_data'],
          'created_at': createdAt,
          'updated_at': updatedAt,
          'version': note['version'] ?? 1,
          'is_dirty': 0,  // Server-based architecture: no dirty tracking
        });
        count++;
      }

      // Insert schedule drawings
      for (final drawing in drawings) {
        // Parse timestamps (handle both int and string formats)
        final date = drawing['date'] is int
            ? drawing['date']
            : DateTime.parse(drawing['date'] as String).toUtc().millisecondsSinceEpoch ~/ 1000;
        final createdAt = drawing['created_at'] is int
            ? drawing['created_at']
            : DateTime.parse(drawing['created_at'] as String).toUtc().millisecondsSinceEpoch ~/ 1000;
        final updatedAt = drawing['updated_at'] != null
            ? (drawing['updated_at'] is int
                ? drawing['updated_at']
                : DateTime.parse(drawing['updated_at'] as String).toUtc().millisecondsSinceEpoch ~/ 1000)
            : createdAt;

        await txn.insert('schedule_drawings', {
          'id': drawing['id'],
          'book_uuid': drawing['book_uuid'],
          'date': date,
          'view_mode': drawing['view_mode'],
          'strokes_data': drawing['strokes_data'],
          'created_at': createdAt,
          'updated_at': updatedAt,
          'version': drawing['version'] ?? 1,
          'is_dirty': 0,  // Server-based architecture: no dirty tracking
        });
        count++;
      }
    });

    return count;
  }

}
