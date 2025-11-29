import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/book.dart';
import '../../models/cache_policy.dart';
import '../../models/charge_item.dart';
import '../../models/event.dart';
import '../../models/note.dart';
import '../../models/person_charge_item.dart';
import '../../models/schedule_drawing.dart';
import '../database_service_interface.dart';

// Import mixins
import 'mixins/book_operations_mixin.dart';
import 'mixins/event_operations_mixin.dart';
import 'mixins/note_cache_operations_mixin.dart';
import 'mixins/schedule_drawing_cache_mixin.dart';
import 'mixins/cache_policy_operations_mixin.dart';
import 'mixins/device_info_operations_mixin.dart';
import 'mixins/cache_management_operations_mixin.dart';
import 'mixins/person_info_utilities_mixin.dart';
import 'mixins/lock_mechanism_mixin.dart';
import 'mixins/person_charge_item_operations_mixin.dart';
import 'mixins/person_info_operations_mixin.dart';

export 'mixins/device_info_operations_mixin.dart' show DeviceCredentials;

/// PRD-compliant database service implementing Book → Event → Note hierarchy
class PRDDatabaseService
    with
        BookOperationsMixin,
        EventOperationsMixin,
        NoteCacheOperationsMixin,
        ScheduleDrawingCacheMixin,
        CachePolicyOperationsMixin,
        DeviceInfoOperationsMixin,
        CacheManagementOperationsMixin,
        PersonInfoUtilitiesMixin,
        LockMechanismMixin,
        PersonChargeItemOperationsMixin,
        PersonInfoOperationsMixin
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
      version: 22, // v22 migrates event IDs from INTEGER to UUID (TEXT)
      onCreate: _createTables,
      onConfigure: _onConfigure,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('Database upgrade from v$oldVersion to v$newVersion');

    // Version 22 introduces UUID event IDs (breaking change)
    // For development ease, we recreate the database rather than migrate data
    if (oldVersion < 22) {
      debugPrint('⚠️ Database upgrade from v$oldVersion to v$newVersion requires recreation.');
      debugPrint('⚠️ Event IDs changed from INTEGER to UUID. Deleting old database and recreating...');

      // Close the database
      await db.close();

      // Delete the old database file
      final databasesPath = await getDatabasesPath();
      final dbName = kDebugMode ? 'prd_schedule_test.db' : 'prd_schedule.db';
      final path = join(databasesPath, dbName);
      await deleteDatabase(path);

      throw Exception(
        'Database has been reset due to UUID migration. Please restart the app to use the new database.'
      );
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // Version 22 schema - UUID Event IDs
    //
    // Changes from v21:
    // - Events use UUID (TEXT) PRIMARY KEY instead of INTEGER AUTOINCREMENT
    // - original_event_id and new_event_id changed to TEXT (UUIDs)
    // - Notes.event_id changed to TEXT (UUID) to match events.id
    //
    // Full Feature Set:
    // - Books with UUID as PRIMARY KEY (no auto-increment id)
    // - Events with UUID PRIMARY KEY, book_uuid foreign key, multi-type support, phone, has_charge_items flag, completion status, and sync columns
    // - Notes with multi-page support, person sharing, locks, cache, and sync columns
    // - Person charge items with shared sync across events
    // - Person info with synced phone numbers
    // - Schedule drawings with book_uuid foreign key, cache and sync columns
    // - Device info, sync metadata, and cache policy tables

    // Books table - Top-level containers with UUID as PRIMARY KEY
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

    // Events table - Individual appointment entries with PRD metadata
    await db.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        book_uuid TEXT NOT NULL,
        name TEXT NOT NULL,
        record_number TEXT,
        phone TEXT,
        event_type TEXT,
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
        FOREIGN KEY (book_uuid) REFERENCES books (book_uuid) ON DELETE CASCADE
      )
    ''');

    // Notes table - Multi-page handwriting notes linked to events
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        strokes_data TEXT,
        pages_data TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        cached_at INTEGER,
        cache_hit_count INTEGER DEFAULT 0,
        person_name_normalized TEXT,
        record_number_normalized TEXT,
        locked_by_device_id TEXT,
        locked_at INTEGER,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE
      )
    ''');

    // Indexes optimized for Schedule views
    await db.execute('''
      CREATE INDEX idx_events_book_uuid_time ON events(book_uuid, start_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_events_book_uuid_date ON events(book_uuid, date(start_time, 'unixepoch'))
    ''');

    await db.execute('''
      CREATE INDEX idx_notes_event ON notes(event_id)
    ''');

    // Indexes for person sharing and lock mechanism
    await db.execute('''
      CREATE INDEX idx_notes_person_key
      ON notes(person_name_normalized, record_number_normalized)
    ''');
    await db.execute('''
      CREATE INDEX idx_notes_locked_by
      ON notes(locked_by_device_id)
    ''');

    // Person Charge Items table - Shared charge items across all events for a person (name + record number)
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

    // Indexes for person charge items
    await db.execute('''
      CREATE INDEX idx_person_charge_items_person_key
      ON person_charge_items(person_name_normalized, record_number_normalized)
    ''');
    await db.execute('''
      CREATE INDEX idx_person_charge_items_dirty
      ON person_charge_items(is_dirty)
    ''');

    // Person Info table - Stores person-level data like phone numbers (synced across all events)
    await db.execute('''
      CREATE TABLE person_info (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_name_normalized TEXT NOT NULL,
        record_number_normalized TEXT NOT NULL,
        phone TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        UNIQUE(person_name_normalized, record_number_normalized)
      )
    ''');

    // Index for person info lookups
    await db.execute('''
      CREATE INDEX idx_person_info_person_key
      ON person_info(person_name_normalized, record_number_normalized)
    ''');

    // Schedule Drawings table - Handwriting overlay on schedule views
    await db.execute('''
      CREATE TABLE schedule_drawings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_uuid TEXT NOT NULL,
        date INTEGER NOT NULL,
        view_mode INTEGER NOT NULL,
        strokes_data TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        cached_at INTEGER,
        cache_hit_count INTEGER DEFAULT 0,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        FOREIGN KEY (book_uuid) REFERENCES books (book_uuid) ON DELETE CASCADE,
        UNIQUE(book_uuid, date, view_mode)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_schedule_drawings_book_uuid_date_view
      ON schedule_drawings(book_uuid, date, view_mode)
    ''');

    // Device Info table - Stores local device registration info (single row)
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

    // Sync Metadata table - Tracks last sync state per table
    await db.execute('''
      CREATE TABLE sync_metadata (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT UNIQUE NOT NULL,
        last_sync_at INTEGER NOT NULL,
        synced_record_count INTEGER DEFAULT 0
      )
    ''');

    // Cache Policy table - Server-Store cache configuration (single row)
    await db.execute('''
      CREATE TABLE cache_policy (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        max_cache_size_mb INTEGER DEFAULT 50,
        cache_duration_days INTEGER DEFAULT 7,
        auto_cleanup INTEGER DEFAULT 1,
        last_cleanup_at INTEGER
      )
    ''');

    // Insert default cache policy
    await db.insert('cache_policy', {
      'id': 1,
      'max_cache_size_mb': 50,
      'cache_duration_days': 7,
      'auto_cleanup': 1,
    });

    // Create cache-related indexes
    await db.execute('CREATE INDEX idx_notes_cached ON notes(cached_at DESC)');
    await db.execute('CREATE INDEX idx_notes_lru ON notes(cache_hit_count ASC)');
    await db.execute('CREATE INDEX idx_drawings_cached ON schedule_drawings(cached_at DESC)');
  }


  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('person_info');
    await db.delete('person_charge_items');
    await db.delete('schedule_drawings');
    await db.delete('notes');
    await db.delete('events');
    await db.delete('books');
  }

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
