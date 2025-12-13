import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/event.dart';
import '../database_service_interface.dart';

import 'mixins/book_operations_mixin.dart';
import 'mixins/record_operations_mixin.dart';
import 'mixins/event_operations_mixin.dart';
import 'mixins/note_operations_mixin.dart';
import 'mixins/schedule_drawing_operations_mixin.dart';
import 'mixins/device_info_operations_mixin.dart';
import 'mixins/person_charge_item_operations_mixin.dart';

export 'mixins/device_info_operations_mixin.dart' show DeviceCredentials;

/// Database service with record-based architecture
///
/// - Records are first-class entities with global identity (record_number)
/// - All events with same record_number share the same record_uuid
/// - Notes are tied to record_uuid (shared across all events for same record)
class PRDDatabaseService
    with
        BookOperationsMixin,
        RecordOperationsMixin,
        EventOperationsMixin,
        NoteOperationsMixin,
        ScheduleDrawingOperationsMixin,
        DeviceInfoOperationsMixin,
        PersonChargeItemOperationsMixin
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
      version: 23,
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

    // Unique constraint only for non-empty record_number
    await db.execute('''
      CREATE UNIQUE INDEX idx_records_record_number_unique
      ON records(record_number) WHERE record_number <> ''
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
        FOREIGN KEY (book_uuid) REFERENCES books (book_uuid) ON DELETE CASCADE,
        UNIQUE(book_uuid, date, view_mode)
      )
    ''');

    // Person Charge Items
    await db.execute('''
      CREATE TABLE person_charge_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_name_normalized TEXT NOT NULL,
        record_number_normalized TEXT NOT NULL,
        item_name TEXT NOT NULL,
        cost INTEGER NOT NULL,
        is_paid INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        UNIQUE(person_name_normalized, record_number_normalized, item_name)
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
    await db.execute('CREATE INDEX idx_charge_items_person ON person_charge_items(person_name_normalized, record_number_normalized)');
  }

  @override
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('person_charge_items');
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
}
