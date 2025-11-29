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

  /// Gather complete book data (book + events + notes + drawings)
  Future<Map<String, dynamic>> _gatherBookData(String bookUuid) async {
    final db = await dbService.database;

    // Get book
    final bookMaps = await db.query('books', where: 'book_uuid = ?', whereArgs: [bookUuid]);
    if (bookMaps.isEmpty) {
      throw Exception('Book not found');
    }
    final book = bookMaps.first;

    // Get all events for this book
    final events = await db.query('events', where: 'book_uuid = ?', whereArgs: [bookUuid]);

    // Get all notes for these events
    final eventIds = events.map((e) => e['id']).toList();
    final notes = eventIds.isNotEmpty
        ? await db.query('notes', where: 'event_id IN (${eventIds.join(',')})')
        : <Map<String, dynamic>>[];

    // Get all schedule drawings for this book
    final drawings = await db.query('schedule_drawings', where: 'book_uuid = ?', whereArgs: [bookUuid]);

    return {
      'book': book,
      'events': events,
      'notes': notes,
      'drawings': drawings,
    };
  }

  /// Upload a book to server
  Future<int> uploadBook(String bookUuid, {String? customName}) async {
    debugPrint('📤 Uploading book #$bookUuid...');

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
    final backupData = await _gatherBookData(bookUuid);
    final bookName = customName ?? backupData['book']['name'] as String;

    // Use ApiClient to upload
    return await apiClient.uploadBookBackup(
      bookUuid: bookUuid,
      backupName: bookName,
      backupData: backupData,
      deviceId: deviceId,
      deviceToken: deviceToken,
    );
  }

  /// List all backups for this device
  Future<List<Map<String, dynamic>>> listBackups() async {
    debugPrint('📋 [1/4] Starting listBackups...');

    // Get device info directly from database
    debugPrint('📋 [2/4] Getting database handle...');
    final db = await dbService.database;

    debugPrint('📋 [3/4] Querying device_info...');
    final deviceRows = await db.query('device_info', limit: 1);
    if (deviceRows.isEmpty) {
      throw Exception('Device not registered. Please register device first.');
    }
    final deviceRow = deviceRows.first;
    final deviceId = deviceRow['device_id'] as String;
    final deviceToken = deviceRow['device_token'] as String;

    debugPrint('📋 [4/4] Calling API to list server books (deviceId: ${deviceId.substring(0, 8)}...)');
    // Use ApiClient to list server books
    final result = await apiClient.listServerBooks(
      deviceId: deviceId,
      deviceToken: deviceToken,
    );

    debugPrint('✅ Got ${result.length} books from server');
    return result;
  }

  /// Restore a book from server backup and download directly to local device
  /// backupId is the server book ID (integer)
  Future<String> restoreBook(int backupId) async {
    debugPrint('📥 Restoring book from backup #$backupId...');

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

    debugPrint('✅ Book data pulled from server');

    // Apply book data directly to local database
    final count = await _applyBackupDataLocally(bookData);

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

}
