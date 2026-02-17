import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/note.dart';
import '../database_service_interface.dart';

import 'mixins/book_operations_mixin.dart';
import 'mixins/record_operations_mixin.dart';
import 'mixins/event_operations_mixin.dart';
import 'mixins/note_operations_mixin.dart';
import 'mixins/schedule_drawing_operations_mixin.dart';
import 'mixins/device_info_operations_mixin.dart';
import 'mixins/charge_item_operations_mixin.dart';

export 'mixins/device_info_operations_mixin.dart' show DeviceCredentials;

/// Database service with record-based architecture
///
/// - Records are first-class entities with global identity (name + record_number)
/// - All events with same {name, record_number} pair share the same record_uuid
/// - Notes are tied to record_uuid (shared across all events for same record)
/// - Empty record_number always creates a new standalone record
class PRDDatabaseService
    with
        BookOperationsMixin,
        RecordOperationsMixin,
        EventOperationsMixin,
        NoteOperationsMixin,
        ScheduleDrawingOperationsMixin,
        DeviceInfoOperationsMixin,
        ChargeItemOperationsMixin
    implements IDatabaseService {
  static PRDDatabaseService? _instance;
  static Database? _database;

  PRDDatabaseService._internal();

  factory PRDDatabaseService() {
    _instance ??= PRDDatabaseService._internal();
    return _instance!;
  }

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbName = kDebugMode ? 'prd_schedule_test.db' : 'prd_schedule.db';
    final path = join(databasesPath, dbName);

    return await openDatabase(
      path,
      version: 26,
      onCreate: _createTables,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 23) {
          await db.close();
          final databasesPath = await getDatabasesPath();
          final dbName = kDebugMode ? 'prd_schedule_test.db' : 'prd_schedule.db';
          await deleteDatabase(join(databasesPath, dbName));
          throw Exception('Database reset for v23 migration. Please restart the app.');
        }
        // v24: Change unique index from record_number to (name, record_number)
        if (oldVersion == 23 && newVersion >= 24) {
          await db.execute('DROP INDEX IF EXISTS idx_records_record_number_unique');
          await db.execute('''
            CREATE UNIQUE INDEX idx_records_name_record_number_unique
            ON records(name, record_number) WHERE record_number <> ''
          ''');
        }
        // v25: Drop old person_charge_items table and create new charge_items table
        if (oldVersion < 25) {
          // Drop old table and index
          await db.execute('DROP INDEX IF EXISTS idx_charge_items_person');
          await db.execute('DROP TABLE IF EXISTS person_charge_items');

          // Create new charge_items table
          await db.execute('''
            CREATE TABLE charge_items (
              id TEXT PRIMARY KEY,
              record_uuid TEXT NOT NULL,
              event_id TEXT,
              item_name TEXT NOT NULL,
              item_price INTEGER NOT NULL DEFAULT 0,
              received_amount INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              synced_at INTEGER,
              version INTEGER DEFAULT 1,
              is_dirty INTEGER DEFAULT 0,
              is_deleted INTEGER DEFAULT 0
            )
          ''');

          // Create indexes
          await db.execute('CREATE INDEX idx_charge_items_record_uuid ON charge_items(record_uuid)');
          await db.execute('CREATE INDEX idx_charge_items_event_id ON charge_items(event_id)');
        }
        // v26: Add missing columns to schedule_drawings table for caching
        if (oldVersion < 26) {
          await db.execute('ALTER TABLE schedule_drawings ADD COLUMN synced_at INTEGER');
          await db.execute('ALTER TABLE schedule_drawings ADD COLUMN cached_at INTEGER');
          await db.execute('ALTER TABLE schedule_drawings ADD COLUMN cache_hit_count INTEGER DEFAULT 0');
        }
      },
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Books
    await db.execute('''
      CREATE TABLE books (
        book_uuid TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        archived_at INTEGER,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0
      )
    ''');

    // Records - Global identity for patients/cases
    await db.execute('''
      CREATE TABLE records (
        record_uuid TEXT PRIMARY KEY,
        record_number TEXT NOT NULL DEFAULT '',
        name TEXT,
        phone TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    // Unique constraint on (name, record_number) for non-empty record_number
    // This allows same record_number with different names to be separate records
    await db.execute('''
      CREATE UNIQUE INDEX idx_records_name_record_number_unique
      ON records(name, record_number) WHERE record_number <> ''
    ''');

    // Events - linked to records
    await db.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        book_uuid TEXT NOT NULL,
        record_uuid TEXT NOT NULL,
        title TEXT NOT NULL,
        record_number TEXT NOT NULL DEFAULT '',
        event_types TEXT NOT NULL,
        has_charge_items INTEGER DEFAULT 0,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        is_removed INTEGER DEFAULT 0,
        removal_reason TEXT,
        original_event_id TEXT,
        new_event_id TEXT,
        is_checked INTEGER DEFAULT 0,
        has_note INTEGER DEFAULT 0,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        FOREIGN KEY (book_uuid) REFERENCES books (book_uuid) ON DELETE CASCADE,
        FOREIGN KEY (record_uuid) REFERENCES records (record_uuid) ON DELETE RESTRICT
      )
    ''');

    // Notes - linked to records (one per record)
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_uuid TEXT NOT NULL UNIQUE,
        pages_data TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        locked_by_device_id TEXT,
        locked_at INTEGER,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        FOREIGN KEY (record_uuid) REFERENCES records (record_uuid) ON DELETE CASCADE
      )
    ''');

    // Schedule Drawings
    await db.execute('''
      CREATE TABLE schedule_drawings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_uuid TEXT NOT NULL,
        date INTEGER NOT NULL,
        view_mode INTEGER NOT NULL,
        strokes_data TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        synced_at INTEGER,
        cached_at INTEGER,
        cache_hit_count INTEGER DEFAULT 0,
        FOREIGN KEY (book_uuid) REFERENCES books (book_uuid) ON DELETE CASCADE,
        UNIQUE(book_uuid, date, view_mode)
      )
    ''');

    // Charge Items (linked to records, optionally to events)
    await db.execute('''
      CREATE TABLE charge_items (
        id TEXT PRIMARY KEY,
        record_uuid TEXT NOT NULL,
        event_id TEXT,
        item_name TEXT NOT NULL,
        item_price INTEGER NOT NULL DEFAULT 0,
        received_amount INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        synced_at INTEGER,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    // Device Info
    await db.execute('''
      CREATE TABLE device_info (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        device_id TEXT UNIQUE NOT NULL,
        device_token TEXT NOT NULL,
        device_name TEXT NOT NULL,
        platform TEXT,
        registered_at INTEGER NOT NULL,
        server_url TEXT
      )
    ''');

    // Sync Metadata
    await db.execute('''
      CREATE TABLE sync_metadata (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT UNIQUE NOT NULL,
        last_sync_at INTEGER NOT NULL,
        synced_record_count INTEGER DEFAULT 0
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_records_name ON records(name)');
    await db.execute('CREATE INDEX idx_events_book_uuid ON events(book_uuid)');
    await db.execute('CREATE INDEX idx_events_record_uuid ON events(record_uuid)');
    await db.execute('CREATE INDEX idx_events_start_time ON events(book_uuid, start_time)');
    await db.execute('CREATE INDEX idx_notes_record ON notes(record_uuid)');
    await db.execute('CREATE INDEX idx_drawings_book ON schedule_drawings(book_uuid, date, view_mode)');
    await db.execute('CREATE INDEX idx_charge_items_record_uuid ON charge_items(record_uuid)');
    await db.execute('CREATE INDEX idx_charge_items_event_id ON charge_items(event_id)');
  }

  @override
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('charge_items');
    await db.delete('schedule_drawings');
    await db.delete('notes');
    await db.delete('events');
    await db.delete('records');
    await db.delete('books');
  }

  @override
  Future<void> replaceEventWithServerData(Event event) async {
    if (event.id == null) throw ArgumentError('Event ID cannot be null');
    final db = await database;
    final data = event.toMap();
    data['is_dirty'] = 0; // Mark as clean since it's from server
    await db.update('events', data, where: 'id = ?', whereArgs: [event.id]);
  }

  @override
  Future<int> getEventCountByBook(String bookUuid) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM events WHERE book_uuid = ?',
      [bookUuid],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<List<String>> getAllRecordNumbers(String bookUuid) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT e.record_number
      FROM events e
      WHERE e.book_uuid = ? AND e.record_number != ''
      ORDER BY e.record_number ASC
    ''', [bookUuid]);
    return results.map((r) => r['record_number'] as String).toList();
  }

  @override
  Future<List<String>> getRecordNumbersByName(String bookUuid, String name) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT e.record_number
      FROM events e
      INNER JOIN records r ON e.record_uuid = r.record_uuid
      WHERE e.book_uuid = ? AND LOWER(r.name) = LOWER(?) AND e.record_number != ''
      ORDER BY e.record_number ASC
    ''', [bookUuid, name]);
    return results.map((r) => r['record_number'] as String).toList();
  }

  @override
  Future<List<Event>> searchByNameAndRecordNumber(
    String bookUuid,
    String name,
    String recordNumber,
  ) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT e.*
      FROM events e
      INNER JOIN records r ON e.record_uuid = r.record_uuid
      WHERE e.book_uuid = ? AND LOWER(r.name) = LOWER(?) AND e.record_number = ?
      ORDER BY e.start_time ASC
    ''', [bookUuid, name, recordNumber]);
    return results.map((r) => Event.fromMap(r)).toList();
  }

  @override
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  static void resetInstance() {
    _instance = null;
    _database = null;
  }

  // ===================
  // Record-based Helper Methods
  // ===================

  /// Generate title from name and record number
  /// Format: "name(XX)" where XX is last 2 digits of record_number
  /// If no record_number, just returns name
  static String generateTitle(String name, String? recordNumber) {
    if (recordNumber == null || recordNumber.isEmpty) {
      return name;
    }
    final suffix = recordNumber.length >= 2
        ? recordNumber.substring(recordNumber.length - 2)
        : recordNumber;
    return '$name($suffix)';
  }

  /// Get all unique names in a book (for autocomplete)
  Future<List<String>> getAllNamesInBook(String bookUuid) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT r.name
      FROM events e
      INNER JOIN records r ON e.record_uuid = r.record_uuid
      WHERE e.book_uuid = ? AND r.name IS NOT NULL AND r.name != ''
      ORDER BY r.name ASC
    ''', [bookUuid]);
    return results.map((r) => r['name'] as String).toList();
  }

  /// Get all record numbers with names (for autocomplete)
  Future<List<Map<String, String>>> getAllRecordNumbersWithNames(String bookUuid) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT r.record_number, r.name
      FROM events e
      INNER JOIN records r ON e.record_uuid = r.record_uuid
      WHERE e.book_uuid = ? AND r.record_number != ''
      ORDER BY r.record_number ASC
    ''', [bookUuid]);
    return results.map((r) => {
      'recordNumber': r['record_number'] as String,
      'name': (r['name'] as String?) ?? '',
    }).toList();
  }

  /// Get name by record number
  /// @deprecated Use getRecordByNameAndRecordNumber instead for accurate matching
  Future<String?> getNameByRecordNumber(String recordNumber) async {
    final record = await getRecordByRecordNumber(recordNumber);
    return record?.name;
  }

  /// Get phone by record number
  /// @deprecated Use getRecordByNameAndRecordNumber instead for accurate matching
  Future<String?> getPhoneByRecordNumber(String recordNumber) async {
    final record = await getRecordByRecordNumber(recordNumber);
    return record?.phone;
  }

  /// Get record data (name, phone) by record number
  /// @deprecated Use getRecordByNameAndRecordNumber instead for accurate matching
  Future<Map<String, String?>?> getRecordDataByRecordNumber(String recordNumber) async {
    final record = await getRecordByRecordNumber(recordNumber);
    if (record == null) return null;
    return {
      'name': record.name,
      'phone': record.phone,
      'recordUuid': record.recordUuid,
    };
  }

  /// Get note by event ID (looks up event's record_uuid first)
  Future<Note?> getNoteByEventId(String eventId) async {
    final event = await getEventById(eventId);
    if (event == null) return null;
    return getNoteByRecordUuid(event.recordUuid);
  }

  /// Find existing note for a record by record_number
  /// @deprecated Use findNoteByNameAndRecordNumber instead for accurate matching
  Future<Note?> findNoteByRecordNumber(String recordNumber) async {
    if (recordNumber.isEmpty) return null;
    final record = await getRecordByRecordNumber(recordNumber);
    if (record == null || record.recordUuid == null) return null;
    return getNoteByRecordUuid(record.recordUuid!);
  }

  /// Find existing note for a record by name AND record_number
  Future<Note?> findNoteByNameAndRecordNumber(String name, String recordNumber) async {
    if (recordNumber.isEmpty || name.isEmpty) return null;
    final record = await getRecordByNameAndRecordNumber(name, recordNumber);
    if (record == null || record.recordUuid == null) return null;
    return getNoteByRecordUuid(record.recordUuid!);
  }

  /// Apply server drawing change
  Future<void> applyServerDrawingChange(Map<String, dynamic> data) async {
    final db = await database;
    final bookUuid = data['book_uuid'] as String;
    final date = DateTime.fromMillisecondsSinceEpoch((data['date'] as int) * 1000, isUtc: true);
    final viewMode = data['view_mode'] as int;
    final normalizedDate = DateTime(date.year, date.month, date.day);

    // Check if drawing exists
    final existing = await getDrawing(bookUuid, normalizedDate, viewMode);

    final drawingData = {
      'book_uuid': bookUuid,
      'date': normalizedDate.millisecondsSinceEpoch ~/ 1000,
      'view_mode': viewMode,
      'strokes_data': data['strokes_data'],
      'created_at': data['created_at'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'updated_at': data['updated_at'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'version': data['version'] ?? 1,
      'is_dirty': 0, // Server data is clean
    };

    if (existing != null) {
      await db.update(
        'schedule_drawings',
        drawingData,
        where: 'book_uuid = ? AND date = ? AND view_mode = ?',
        whereArgs: [bookUuid, normalizedDate.millisecondsSinceEpoch ~/ 1000, viewMode],
      );
    } else {
      await db.insert('schedule_drawings', drawingData);
    }
  }

  /// Create event with auto-generated title and record handling
  Future<Event> createEventWithRecord({
    required String bookUuid,
    required String name,
    String? recordNumber,
    String? phone,
    required List<EventType> eventTypes,
    required DateTime startTime,
    DateTime? endTime,
    String? eventId,
  }) async {
    // Get or create record
    final record = await getOrCreateRecord(
      recordNumber: recordNumber ?? '',
      name: name,
      phone: phone,
    );

    // Generate title
    final title = generateTitle(name, recordNumber);

    final now = DateTime.now();
    final event = Event(
      id: eventId,
      bookUuid: bookUuid,
      recordUuid: record.recordUuid!,
      title: title,
      recordNumber: recordNumber ?? '',
      eventTypes: eventTypes,
      startTime: startTime,
      endTime: endTime,
      createdAt: now,
      updatedAt: now,
    );

    return createEvent(event);
  }

  /// Update event with record handling
  Future<Event> updateEventWithRecord({
    required Event event,
    required String name,
    String? recordNumber,
    String? phone,
    List<EventType>? eventTypes,
    DateTime? startTime,
    DateTime? endTime,
    bool clearEndTime = false,
  }) async {
    final newRecordNumber = recordNumber ?? '';
    final oldRecordNumber = event.recordNumber;

    String recordUuid = event.recordUuid;

    // If record number changed, get or create new record
    if (newRecordNumber != oldRecordNumber) {
      final record = await getOrCreateRecord(
        recordNumber: newRecordNumber,
        name: name,
        phone: phone,
      );
      recordUuid = record.recordUuid!;
    } else {
      // Update existing record's name/phone if changed
      final existingRecord = await getRecordByUuid(event.recordUuid);
      if (existingRecord != null) {
        if (name != existingRecord.name || phone != existingRecord.phone) {
          await updateRecord(
            recordUuid: existingRecord.recordUuid!,
            name: name,
            phone: phone,
          );
        }
      }
    }

    // Generate title
    final title = generateTitle(name, recordNumber);

    final updated = event.copyWith(
      recordUuid: recordUuid,
      title: title,
      recordNumber: newRecordNumber,
      eventTypes: eventTypes ?? event.eventTypes,
      startTime: startTime ?? event.startTime,
      endTime: clearEndTime ? null : (endTime ?? event.endTime),
      clearEndTime: clearEndTime,
    );

    return updateEvent(updated);
  }
}
