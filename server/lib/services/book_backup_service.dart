import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';
import '../database/connection.dart';

/// Service for book backup and restore operations
///
/// Supports both file-based (SQL + gzip) and legacy JSON backups.
/// New backups use file-based storage for better performance.
class BookBackupService {
  final DatabaseConnection db;
  final String backupDir;

  BookBackupService(this.db, {String? backupDir})
      : backupDir = backupDir ?? 'server/backups' {
    // Ensure backup directory exists
    final dir = Directory(this.backupDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      print('📁 Created backup directory: ${this.backupDir}');
    }
  }

  /// Upload a complete book backup to server (UPSERT based on book_uuid)
  Future<int> uploadBookBackup({
    required String deviceId,
    required int bookId,
    required String backupName,
    required Map<String, dynamic> backupData,
  }) async {
    // Extract book_uuid from backup data
    final bookData = backupData['book'] as Map<String, dynamic>;
    final bookUuid = bookData['book_uuid'] as String?;

    if (bookUuid == null) {
      throw Exception('Book UUID is required for backup');
    }

    // Calculate backup size
    final jsonString = jsonEncode(backupData);
    final backupSize = jsonString.length;

    // UPSERT: Insert or update based on (device_id, book_uuid)
    final result = await db.querySingle(
      '''
      INSERT INTO book_backups (book_id, book_uuid, backup_name, device_id, backup_data, backup_size, created_at)
      VALUES (@bookId, @bookUuid, @backupName, @deviceId, @backupData::jsonb, @backupSize, CURRENT_TIMESTAMP)
      ON CONFLICT (device_id, book_uuid) WHERE is_deleted = false
      DO UPDATE SET
        backup_name = EXCLUDED.backup_name,
        backup_data = EXCLUDED.backup_data,
        backup_size = EXCLUDED.backup_size,
        created_at = CURRENT_TIMESTAMP,
        restored_at = NULL
      RETURNING id
      ''',
      parameters: {
        'bookId': bookId,
        'bookUuid': bookUuid,
        'backupName': backupName,
        'deviceId': deviceId,
        'backupData': jsonString,
        'backupSize': backupSize,
      },
    );

    final backupId = result!['id'] as int;

    // **CRITICAL FIX**: Also create/update book in books table for Server-Store
    // This enables note/drawing endpoints to verify book ownership
    // Use book_uuid as the unique identifier, not book_id (which can conflict across devices)
    try {
      print('📝 Creating/updating book in books table (UUID: $bookUuid, Device: $deviceId)');

      final bookCreatedAt = _convertTimestamp(bookData['created_at']) ?? DateTime.now();
      final bookUpdatedAt = _convertTimestamp(bookData['updated_at']) ?? bookCreatedAt;

      // Insert or update based on (device_id, book_uuid) - the true unique identifier
      // Let the server assign a new auto-increment ID if this is a new book
      await db.querySingle(
        '''
        INSERT INTO books (device_id, book_uuid, name, created_at, updated_at, synced_at, version, is_deleted)
        VALUES (@deviceId, @bookUuid, @name, @createdAt, @updatedAt, CURRENT_TIMESTAMP, @version, false)
        ON CONFLICT (book_uuid)
        DO UPDATE SET
          device_id = EXCLUDED.device_id,
          name = EXCLUDED.name,
          updated_at = EXCLUDED.updated_at,
          synced_at = CURRENT_TIMESTAMP,
          version = EXCLUDED.version,
          is_deleted = false
        RETURNING id
        ''',
        parameters: {
          'deviceId': deviceId,
          'bookUuid': bookUuid,
          'name': bookData['name'],
          'createdAt': bookCreatedAt,
          'updatedAt': bookUpdatedAt,
          'version': bookData['version'] ?? 1,
        },
      );

      print('✅ Book created/updated in books table (UUID: $bookUuid, Device: $deviceId)');
    } catch (e) {
      print('❌ Failed to create book in books table: $e');
      // Don't fail the entire upload if this fails - backup is still stored
      print('⚠️  Warning: Book backup stored but book not accessible for Server-Store operations');
    }

    return backupId;
  }

  /// List all backups for a device (returns only the newest backup per book_uuid)
  Future<List<Map<String, dynamic>>> listBackups(String deviceId) async {
    final rows = await db.queryRows(
      '''
      SELECT DISTINCT ON (book_uuid)
        id,
        book_id,
        book_uuid,
        backup_name,
        backup_size,
        created_at,
        restored_at
      FROM book_backups
      WHERE device_id = @deviceId AND is_deleted = false
      ORDER BY book_uuid, created_at DESC
      ''',
      parameters: {'deviceId': deviceId},
    );

    return rows.map((row) => {
      'id': row['id'],
      'bookId': row['book_id'],
      'bookUuid': row['book_uuid'],
      'backupName': row['backup_name'],
      'backupSize': row['backup_size'],
      'createdAt': (row['created_at'] as DateTime).toIso8601String(),
      'restoredAt': row['restored_at'] != null
          ? (row['restored_at'] as DateTime).toIso8601String()
          : null,
    }).toList();
  }

  /// Get backup data for restore
  Future<Map<String, dynamic>?> getBackup(int backupId, String deviceId) async {
    final row = await db.querySingle(
      '''
      SELECT backup_data
      FROM book_backups
      WHERE id = @backupId AND device_id = @deviceId AND is_deleted = false
      ''',
      parameters: {
        'backupId': backupId,
        'deviceId': deviceId,
      },
    );

    if (row == null) return null;

    // PostgreSQL returns JSONB as Map already
    return row['backup_data'] as Map<String, dynamic>;
  }

  /// Convert Unix timestamp (seconds) to DateTime
  DateTime? _convertTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    return null;
  }

  /// Restore a book from backup (replace existing)
  Future<void> restoreBookBackup({
    required int backupId,
    required String deviceId,
  }) async {
    // Get backup data
    final backupData = await getBackup(backupId, deviceId);
    if (backupData == null) {
      throw Exception('Backup not found');
    }

    // Extract data
    final book = backupData['book'] as Map<String, dynamic>;
    final events = (backupData['events'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final notes = (backupData['notes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final drawings = (backupData['drawings'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Begin transaction
    await db.transaction((txn) async {
      // Delete existing book if exists (CASCADE will delete events, notes, drawings)
      await txn.execute(
        Sql.named('DELETE FROM books WHERE id = @bookId'),
        parameters: {'bookId': book['id']},
      );

      // Insert book
      final bookCreatedAt = _convertTimestamp(book['created_at']);
      // Generate UUID if not present (for old backups)
      final bookUuid = book['book_uuid'] ?? const Uuid().v4();

      await txn.execute(
        Sql.named('''
        INSERT INTO books (id, device_id, book_uuid, name, created_at, updated_at, archived_at, synced_at, version, is_deleted)
        VALUES (@id, @deviceId, @bookUuid, @name, @createdAt, @updatedAt, @archivedAt, CURRENT_TIMESTAMP, @version, @isDeleted)
        '''),
        parameters: {
          'id': book['id'],
          'deviceId': deviceId,
          'bookUuid': bookUuid,
          'name': book['name'],
          'createdAt': bookCreatedAt,
          'updatedAt': _convertTimestamp(book['updated_at']) ?? bookCreatedAt,
          'archivedAt': _convertTimestamp(book['archived_at']),
          'version': book['version'] ?? 1,
          'isDeleted': book['is_deleted'] ?? false,
        },
      );

      // Insert events
      for (final event in events) {
        final eventCreatedAt = _convertTimestamp(event['created_at']);
        await txn.execute(
          Sql.named('''
          INSERT INTO events (
            id, book_id, device_id, name, record_number, event_type,
            start_time, end_time, created_at, updated_at,
            is_removed, removal_reason, original_event_id, new_event_id,
            synced_at, version, is_deleted
          ) VALUES (
            @id, @bookId, @deviceId, @name, @recordNumber, @eventType,
            @startTime, @endTime, @createdAt, @updatedAt,
            @isRemoved, @removalReason, @originalEventId, @newEventId,
            CURRENT_TIMESTAMP, @version, @isDeleted
          )
          '''),
          parameters: {
            'id': event['id'],
            'bookId': event['book_id'],
            'deviceId': deviceId,
            'name': event['name'],
            'recordNumber': event['record_number'],
            'eventType': event['event_type'],
            'startTime': _convertTimestamp(event['start_time']),
            'endTime': _convertTimestamp(event['end_time']),
            'createdAt': eventCreatedAt,
            'updatedAt': _convertTimestamp(event['updated_at']) ?? eventCreatedAt,
            'isRemoved': event['is_removed'] ?? false,
            'removalReason': event['removal_reason'],
            'originalEventId': event['original_event_id'],
            'newEventId': event['new_event_id'],
            'version': event['version'] ?? 1,
            'isDeleted': event['is_deleted'] ?? false,
          },
        );
      }

      // Insert notes
      for (final note in notes) {
        final noteCreatedAt = _convertTimestamp(note['created_at']);
        await txn.execute(
          Sql.named('''
          INSERT INTO notes (
            id, event_id, device_id, strokes_data,
            created_at, updated_at, synced_at, version, is_deleted
          ) VALUES (
            @id, @eventId, @deviceId, @strokesData,
            @createdAt, @updatedAt, CURRENT_TIMESTAMP, @version, @isDeleted
          )
          '''),
          parameters: {
            'id': note['id'],
            'eventId': note['event_id'],
            'deviceId': deviceId,
            'strokesData': note['strokes_data'],
            'createdAt': noteCreatedAt,
            'updatedAt': _convertTimestamp(note['updated_at']) ?? noteCreatedAt,
            'version': note['version'] ?? 1,
            'isDeleted': note['is_deleted'] ?? false,
          },
        );
      }

      // Insert schedule drawings
      for (final drawing in drawings) {
        final drawingCreatedAt = _convertTimestamp(drawing['created_at']);
        await txn.execute(
          Sql.named('''
          INSERT INTO schedule_drawings (
            id, book_id, device_id, date, view_mode, strokes_data,
            created_at, updated_at, synced_at, version, is_deleted
          ) VALUES (
            @id, @bookId, @deviceId, @date, @viewMode, @strokesData,
            @createdAt, @updatedAt, CURRENT_TIMESTAMP, @version, @isDeleted
          )
          '''),
          parameters: {
            'id': drawing['id'],
            'bookId': drawing['book_id'],
            'deviceId': deviceId,
            'date': _convertTimestamp(drawing['date']),
            'viewMode': drawing['view_mode'],
            'strokesData': drawing['strokes_data'],
            'createdAt': drawingCreatedAt,
            'updatedAt': _convertTimestamp(drawing['updated_at']) ?? drawingCreatedAt,
            'version': drawing['version'] ?? 1,
            'isDeleted': drawing['is_deleted'] ?? false,
          },
        );
      }

      // Mark backup as restored
      await txn.execute(
        Sql.named('UPDATE book_backups SET restored_at = CURRENT_TIMESTAMP WHERE id = @backupId'),
        parameters: {'backupId': backupId},
      );
    });
  }

  /// Delete a backup
  Future<void> deleteBackup(int backupId, String deviceId) async {
    // Get backup info to delete file
    final backup = await db.querySingle(
      '''
      SELECT backup_path FROM book_backups
      WHERE id = @backupId AND device_id = @deviceId
      ''',
      parameters: {
        'backupId': backupId,
        'deviceId': deviceId,
      },
    );

    // Delete file if exists
    if (backup != null && backup['backup_path'] != null) {
      final filePath = path.join(backupDir, backup['backup_path'] as String);
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
        print('🗑️  Deleted backup file: $filePath');
      }
    }

    // Mark as deleted in database
    await db.query(
      '''
      UPDATE book_backups
      SET is_deleted = true
      WHERE id = @backupId AND device_id = @deviceId
      ''',
      parameters: {
        'backupId': backupId,
        'deviceId': deviceId,
      },
    );
  }

  // ============================================================================
  // FILE-BASED BACKUP METHODS (New Implementation)
  // ============================================================================

  /// Create a file-based backup of a book (SQL + gzip)
  ///
  /// This is the new recommended way to backup books.
  /// Returns the backup ID.
  Future<int> createFileBackup({
    required String bookUuid,
    required String deviceId,
    String? backupName,
  }) async {
    final timestamp = DateTime.now().toUtc();
    final dateFormat = DateFormat('yyyy-MM-dd_HHmmss');
    final timestampStr = dateFormat.format(timestamp);

    // Generate backup file path
    final fileName = 'book_${bookUuid.substring(0, 8)}_$timestampStr.sql.gz';
    final filePath = path.join(backupDir, fileName);

    print('📦 Creating file-based backup for Book UUID: $bookUuid...');

    try {
      // Step 1: Query all book data
      final bookData = await _queryBookData(bookUuid, deviceId);

      // Step 2: Generate SQL
      final sql = _generateBackupSQL(bookData);
      print('   Generated ${sql.length} bytes of SQL');

      // Step 3: Compress and save
      final file = File(filePath);
      final outputStream = file.openWrite();
      final encoder = GZipEncoder();
      final compressedBytes = encoder.encode(sql.codeUnits);

      if (compressedBytes == null) {
        throw Exception('Failed to compress backup data');
      }

      outputStream.add(compressedBytes);
      await outputStream.close();

      final originalSize = sql.length;
      final compressedSize = compressedBytes.length;
      final compressionRatio = (1 - compressedSize / originalSize) * 100;

      print('   Compressed: ${originalSize} → ${compressedSize} bytes (${compressionRatio.toStringAsFixed(1)}% reduction)');

      // Step 4: Record metadata in database
      final backupNameFinal = backupName ?? 'Backup $timestampStr';
      final result = await db.querySingle(
        '''
        INSERT INTO book_backups (
          book_id, book_uuid, backup_name, device_id,
          backup_path, backup_size_bytes, backup_type, status,
          created_at
        )
        VALUES (
          NULL, @bookUuid, @backupName, @deviceId,
          @backupPath, @backupSize, 'full', 'completed',
          @createdAt
        )
        RETURNING id
        ''',
        parameters: {
          'bookUuid': bookUuid,
          'backupName': backupNameFinal,
          'deviceId': deviceId,
          'backupPath': fileName,
          'backupSize': compressedSize,
          'createdAt': timestamp,
        },
      );

      final backupId = result!['id'] as int;
      print('✅ File-based backup created: ID $backupId ($fileName)');

      // Step 5: Cleanup old backups
      await cleanupOldBackups(bookUuid, deviceId);

      return backupId;
    } catch (e, stackTrace) {
      print('❌ Failed to create file-based backup: $e');
      print('   Stack trace: $stackTrace');

      // Clean up partial file
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }

      rethrow;
    }
  }

  /// Restore a book from a file-based backup
  Future<void> restoreFromFileBackup({
    required int backupId,
    required String deviceId,
  }) async {
    print('🔄 Restoring from file-based backup #$backupId...');

    // Get backup metadata
    final backupMeta = await db.querySingle(
      '''
      SELECT backup_path, book_id, backup_type
      FROM book_backups
      WHERE id = @backupId AND device_id = @deviceId AND is_deleted = false
      ''',
      parameters: {
        'backupId': backupId,
        'deviceId': deviceId,
      },
    );

    if (backupMeta == null) {
      throw Exception('Backup not found');
    }

    final backupPath = backupMeta['backup_path'] as String?;

    // Check if this is a file-based backup
    if (backupPath == null) {
      throw Exception('This is not a file-based backup. Use restoreBookBackup() for JSON backups.');
    }

    // Read and decompress backup file
    final filePath = path.join(backupDir, backupPath);
    final file = File(filePath);

    if (!file.existsSync()) {
      throw Exception('Backup file not found: $filePath');
    }

    print('   Reading backup file: $backupPath');
    final compressedBytes = file.readAsBytesSync();
    final decoder = GZipDecoder();
    final decompressedBytes = decoder.decodeBytes(compressedBytes);
    final sql = String.fromCharCodes(decompressedBytes);

    print('   Decompressed: ${compressedBytes.length} → ${sql.length} bytes');

    // Execute SQL in transaction
    await db.transaction((txn) async {
      print('   Executing restore SQL in transaction...');

      // Split SQL into statements
      final statements = sql.split(';').where((s) => s.trim().isNotEmpty).toList();
      print('   Executing ${statements.length} SQL statements...');

      for (final statement in statements) {
        final trimmed = statement.trim();
        if (trimmed.isNotEmpty) {
          await txn.execute(Sql.named(trimmed));
        }
      }

      // Mark backup as restored
      await txn.execute(
        Sql.named('UPDATE book_backups SET restored_at = CURRENT_TIMESTAMP WHERE id = @backupId'),
        parameters: {'backupId': backupId},
      );

      print('✅ Restore completed successfully');
    });
  }

  /// List backups for a specific book
  Future<List<Map<String, dynamic>>> listBookBackups(String bookUuid, String deviceId) async {
    final rows = await db.queryRows(
      '''
      SELECT
        id, book_id, book_uuid, backup_name,
        backup_path, backup_size, backup_size_bytes,
        backup_type, status, created_at, restored_at
      FROM book_backups
      WHERE book_uuid = @bookUuid AND device_id = @deviceId AND is_deleted = false
      ORDER BY created_at DESC
      ''',
      parameters: {
        'bookUuid': bookUuid,
        'deviceId': deviceId,
      },
    );

    return rows.map((row) {
      final isFileBased = row['backup_path'] != null;
      final sizeBytes = row['backup_size_bytes'] as int? ?? row['backup_size'] as int? ?? 0;

      return {
        'id': row['id'],
        'bookId': row['book_id'],
        'bookUuid': row['book_uuid'],
        'backupName': row['backup_name'],
        'backupType': row['backup_type'] ?? (isFileBased ? 'full' : 'json'),
        'status': row['status'] ?? 'completed',
        'sizeBytes': sizeBytes,
        'sizeMB': (sizeBytes / 1024 / 1024).toStringAsFixed(2),
        'isFileBased': isFileBased,
        'createdAt': (row['created_at'] as DateTime).toIso8601String(),
        'restoredAt': row['restored_at'] != null
            ? (row['restored_at'] as DateTime).toIso8601String()
            : null,
      };
    }).toList();
  }

  /// Download a backup file (returns file path for streaming)
  Future<String?> getBackupFilePath(int backupId, String deviceId) async {
    final row = await db.querySingle(
      '''
      SELECT backup_path
      FROM book_backups
      WHERE id = @backupId AND device_id = @deviceId AND is_deleted = false
      ''',
      parameters: {
        'backupId': backupId,
        'deviceId': deviceId,
      },
    );

    if (row == null || row['backup_path'] == null) {
      return null;
    }

    final filePath = path.join(backupDir, row['backup_path'] as String);
    final file = File(filePath);

    if (!file.existsSync()) {
      print('⚠️  Backup file not found: $filePath');
      return null;
    }

    return filePath;
  }

  /// Clean up old backups, keeping only the last N backups per book
  Future<void> cleanupOldBackups(String bookUuid, String deviceId, {int keepCount = 10}) async {
    // Get all backups for this book, ordered by creation date
    final backups = await db.queryRows(
      '''
      SELECT id, backup_path
      FROM book_backups
      WHERE book_uuid = @bookUuid AND device_id = @deviceId AND is_deleted = false
      ORDER BY created_at DESC
      ''',
      parameters: {
        'bookUuid': bookUuid,
        'deviceId': deviceId,
      },
    );

    if (backups.length <= keepCount) {
      return; // Nothing to clean up
    }

    // Delete old backups (beyond keepCount)
    final toDelete = backups.skip(keepCount).toList();
    print('🧹 Cleaning up ${toDelete.length} old backup(s) for Book #$bookId...');

    for (final backup in toDelete) {
      final backupId = backup['id'] as int;
      final backupPath = backup['backup_path'] as String?;

      // Delete file
      if (backupPath != null) {
        final filePath = path.join(backupDir, backupPath);
        final file = File(filePath);
        if (file.existsSync()) {
          file.deleteSync();
          print('   Deleted: $backupPath');
        }
      }

      // Mark as deleted in DB
      await db.query(
        'UPDATE book_backups SET is_deleted = true WHERE id = @id',
        parameters: {'id': backupId},
      );
    }

    print('✅ Cleanup completed: kept ${keepCount} most recent backups');
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Query all data for a book
  Future<Map<String, dynamic>> _queryBookData(String bookUuid, String deviceId) async {
    // Verify book belongs to device
    final book = await db.querySingle(
      'SELECT * FROM books WHERE book_uuid = @bookUuid AND device_id = @deviceId',
      parameters: {'bookUuid': bookUuid, 'deviceId': deviceId},
    );

    if (book == null) {
      throw Exception('Book not found or access denied');
    }

    final bookId = book['id'] as int;

    // Query related data
    final events = await db.queryRows(
      'SELECT * FROM events WHERE book_id = @bookId ORDER BY id',
      parameters: {'bookId': bookId},
    );

    final notes = await db.queryRows(
      'SELECT * FROM notes WHERE event_id IN (SELECT id FROM events WHERE book_id = @bookId) ORDER BY id',
      parameters: {'bookId': bookId},
    );

    final drawings = await db.queryRows(
      'SELECT * FROM schedule_drawings WHERE book_id = @bookId ORDER BY id',
      parameters: {'bookId': bookId},
    );

    print('   Book data: ${events.length} events, ${notes.length} notes, ${drawings.length} drawings');

    return {
      'book': book,
      'events': events,
      'notes': notes,
      'drawings': drawings,
    };
  }

  /// Generate SQL backup from book data
  String _generateBackupSQL(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    buffer.writeln('-- Schedule Note Book Backup');
    buffer.writeln('-- Generated: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('-- Format: PostgreSQL SQL');
    buffer.writeln();

    // Helper to escape SQL strings
    String escape(dynamic value) {
      if (value == null) return 'NULL';
      if (value is String) {
        return "'${value.replaceAll("'", "''")}'";
      }
      if (value is DateTime) {
        return "'${value.toUtc().toIso8601String()}'";
      }
      if (value is bool) {
        return value ? 'true' : 'false';
      }
      return value.toString();
    }

    // Book
    final book = data['book'] as Map<String, dynamic>;
    buffer.writeln('-- Book');
    buffer.writeln('DELETE FROM books WHERE id = ${book['id']};');
    buffer.write('INSERT INTO books (id, device_id, book_uuid, name, created_at, updated_at, archived_at, synced_at, version, is_deleted) VALUES (');
    buffer.write('${book['id']}, ');
    buffer.write('${escape(book['device_id'])}, ');
    buffer.write('${escape(book['book_uuid'])}, ');
    buffer.write('${escape(book['name'])}, ');
    buffer.write('${escape(book['created_at'])}, ');
    buffer.write('${escape(book['updated_at'])}, ');
    buffer.write('${escape(book['archived_at'])}, ');
    buffer.write('${escape(book['synced_at'])}, ');
    buffer.write('${book['version']}, ');
    buffer.write('${escape(book['is_deleted'])}');
    buffer.writeln(');');
    buffer.writeln();

    // Events
    final events = data['events'] as List<Map<String, dynamic>>;
    if (events.isNotEmpty) {
      buffer.writeln('-- Events (${events.length})');
      for (final event in events) {
        buffer.write('INSERT INTO events (id, book_id, device_id, name, record_number, event_type, start_time, end_time, created_at, updated_at, is_removed, removal_reason, original_event_id, new_event_id, synced_at, version, is_deleted) VALUES (');
        buffer.write('${event['id']}, ');
        buffer.write('${event['book_id']}, ');
        buffer.write('${escape(event['device_id'])}, ');
        buffer.write('${escape(event['name'])}, ');
        buffer.write('${escape(event['record_number'])}, ');
        buffer.write('${escape(event['event_type'])}, ');
        buffer.write('${escape(event['start_time'])}, ');
        buffer.write('${escape(event['end_time'])}, ');
        buffer.write('${escape(event['created_at'])}, ');
        buffer.write('${escape(event['updated_at'])}, ');
        buffer.write('${escape(event['is_removed'])}, ');
        buffer.write('${escape(event['removal_reason'])}, ');
        buffer.write('${escape(event['original_event_id'])}, ');
        buffer.write('${escape(event['new_event_id'])}, ');
        buffer.write('${escape(event['synced_at'])}, ');
        buffer.write('${event['version']}, ');
        buffer.write('${escape(event['is_deleted'])}');
        buffer.writeln(');');
      }
      buffer.writeln();
    }

    // Notes
    final notes = data['notes'] as List<Map<String, dynamic>>;
    if (notes.isNotEmpty) {
      buffer.writeln('-- Notes (${notes.length})');
      for (final note in notes) {
        buffer.write('INSERT INTO notes (id, event_id, device_id, strokes_data, created_at, updated_at, synced_at, version, is_deleted) VALUES (');
        buffer.write('${note['id']}, ');
        buffer.write('${note['event_id']}, ');
        buffer.write('${escape(note['device_id'])}, ');
        buffer.write('${escape(note['strokes_data'])}, ');
        buffer.write('${escape(note['created_at'])}, ');
        buffer.write('${escape(note['updated_at'])}, ');
        buffer.write('${escape(note['synced_at'])}, ');
        buffer.write('${note['version']}, ');
        buffer.write('${escape(note['is_deleted'])}');
        buffer.writeln(');');
      }
      buffer.writeln();
    }

    // Drawings
    final drawings = data['drawings'] as List<Map<String, dynamic>>;
    if (drawings.isNotEmpty) {
      buffer.writeln('-- Schedule Drawings (${drawings.length})');
      for (final drawing in drawings) {
        buffer.write('INSERT INTO schedule_drawings (id, book_id, device_id, date, view_mode, strokes_data, created_at, updated_at, synced_at, version, is_deleted) VALUES (');
        buffer.write('${drawing['id']}, ');
        buffer.write('${drawing['book_id']}, ');
        buffer.write('${escape(drawing['device_id'])}, ');
        buffer.write('${escape(drawing['date'])}, ');
        buffer.write('${drawing['view_mode']}, ');
        buffer.write('${escape(drawing['strokes_data'])}, ');
        buffer.write('${escape(drawing['created_at'])}, ');
        buffer.write('${escape(drawing['updated_at'])}, ');
        buffer.write('${escape(drawing['synced_at'])}, ');
        buffer.write('${drawing['version']}, ');
        buffer.write('${escape(drawing['is_deleted'])}');
        buffer.writeln(');');
      }
      buffer.writeln();
    }

    buffer.writeln('-- End of backup');
    return buffer.toString();
  }
}
