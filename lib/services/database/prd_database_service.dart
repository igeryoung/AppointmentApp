import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../models/book.dart';
import '../../models/cache_policy.dart';
import '../../models/event.dart';
import '../../models/note.dart';
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
        LockMechanismMixin
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
      version: 14, // Fixed version for multi-type event support (fixed event_type constraint)
      onCreate: _createTables,
      onConfigure: _onConfigure,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Drop old tables and recreate with new schema
      await db.execute('DROP TABLE IF EXISTS appointments');
      await db.execute('DROP TABLE IF EXISTS books');
      await _createTables(db, newVersion);
    }
    if (oldVersion < 3) {
      // Add new columns for event removal and time change features
      await db.execute('ALTER TABLE events ADD COLUMN is_removed INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE events ADD COLUMN removal_reason TEXT');
      await db.execute('ALTER TABLE events ADD COLUMN original_event_id INTEGER');
    }
    if (oldVersion < 4) {
      // Add new column for bidirectional event time change tracking
      await db.execute('ALTER TABLE events ADD COLUMN new_event_id INTEGER');
    }
    if (oldVersion < 5) {
      // Add schedule_drawings table for handwriting overlay on schedule
      await db.execute('''
        CREATE TABLE schedule_drawings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id INTEGER NOT NULL,
          date INTEGER NOT NULL,
          view_mode INTEGER NOT NULL,
          strokes_data TEXT,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_schedule_drawings_book_date_view
        ON schedule_drawings(book_id, date, view_mode)
      ''');
    }
    if (oldVersion < 6) {
      // Add sync support - device info and sync metadata tables
      await db.execute('''
        CREATE TABLE IF NOT EXISTS device_info (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          device_id TEXT UNIQUE NOT NULL,
          device_token TEXT NOT NULL,
          device_name TEXT NOT NULL,
          platform TEXT,
          registered_at INTEGER NOT NULL,
          server_url TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_metadata (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT UNIQUE NOT NULL,
          last_sync_at INTEGER NOT NULL,
          synced_record_count INTEGER DEFAULT 0
        )
      ''');

      // Add sync columns to existing tables
      await db.execute('ALTER TABLE books ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE books ADD COLUMN is_dirty INTEGER DEFAULT 0');

      await db.execute('ALTER TABLE events ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE events ADD COLUMN is_dirty INTEGER DEFAULT 0');

      await db.execute('ALTER TABLE notes ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE notes ADD COLUMN is_dirty INTEGER DEFAULT 0');

      await db.execute('ALTER TABLE schedule_drawings ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE schedule_drawings ADD COLUMN is_dirty INTEGER DEFAULT 0');

      debugPrint('✅ Sync support added to database (version 6)');
    }
    if (oldVersion < 7) {
      // Add book_uuid column to books table (without UNIQUE constraint in ALTER TABLE)
      await db.execute('ALTER TABLE books ADD COLUMN book_uuid TEXT');

      // Generate UUIDs for existing books
      final existingBooks = await db.query('books');
      const uuid = Uuid();
      for (final book in existingBooks) {
        final bookId = book['id'] as int;
        final bookUuid = uuid.v4();
        await db.update(
          'books',
          {'book_uuid': bookUuid},
          where: 'id = ?',
          whereArgs: [bookId],
        );
      }

      // Create unique index on book_uuid (enforces uniqueness)
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_books_uuid_unique ON books(book_uuid)');

      debugPrint('✅ Book UUID support added to database (version 7)');
    }
    if (oldVersion < 8) {
      // Add cache metadata columns for Server-Store architecture
      debugPrint('🔄 Upgrading to database version 8 (Server-Store cache support)...');

      // Notes cache metadata
      await db.execute('ALTER TABLE notes ADD COLUMN cached_at INTEGER');
      await db.execute('ALTER TABLE notes ADD COLUMN cache_hit_count INTEGER DEFAULT 0');

      // Drawings cache metadata
      await db.execute('ALTER TABLE schedule_drawings ADD COLUMN cached_at INTEGER');
      await db.execute('ALTER TABLE schedule_drawings ADD COLUMN cache_hit_count INTEGER DEFAULT 0');

      // Set cached_at for existing records (use created_at)
      await db.execute('UPDATE notes SET cached_at = created_at WHERE cached_at IS NULL');
      await db.execute('UPDATE schedule_drawings SET cached_at = created_at WHERE cached_at IS NULL');

      debugPrint('✅ Cache metadata columns added');

      // Create cache_policy table (single-row configuration table)
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

      debugPrint('✅ Cache policy table created');

      // Create cache-related indexes
      await db.execute('CREATE INDEX idx_notes_cached ON notes(cached_at DESC)');
      await db.execute('CREATE INDEX idx_notes_lru ON notes(cache_hit_count ASC)');
      await db.execute('CREATE INDEX idx_drawings_cached ON schedule_drawings(cached_at DESC)');

      debugPrint('✅ Cache indexes created');
      debugPrint('✅ Database upgraded to version 8 (Server-Store cache support)');
    }
    if (oldVersion < 9) {
      // Make record_number optional in events table
      debugPrint('🔄 Upgrading to database version 9 (optional record_number)...');

      // SQLite doesn't support ALTER COLUMN to remove NOT NULL, so we need to recreate the table
      await db.execute('PRAGMA foreign_keys = OFF');

      // Create new events table with optional record_number
      await db.execute('''
        CREATE TABLE events_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          record_number TEXT,
          event_type TEXT NOT NULL,
          start_time INTEGER NOT NULL,
          end_time INTEGER,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          is_removed INTEGER DEFAULT 0,
          removal_reason TEXT,
          original_event_id INTEGER,
          new_event_id INTEGER,
          version INTEGER DEFAULT 1,
          is_dirty INTEGER DEFAULT 0,
          FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
        )
      ''');

      // Copy data from old table to new table
      await db.execute('''
        INSERT INTO events_new (
          id, book_id, name, record_number, event_type, start_time, end_time,
          created_at, updated_at, is_removed, removal_reason, original_event_id,
          new_event_id, version, is_dirty
        )
        SELECT
          id, book_id, name, record_number, event_type, start_time, end_time,
          created_at, updated_at, is_removed, removal_reason, original_event_id,
          new_event_id, version, is_dirty
        FROM events
      ''');

      // Drop old table
      await db.execute('DROP TABLE events');

      // Rename new table to original name
      await db.execute('ALTER TABLE events_new RENAME TO events');

      // Recreate indexes
      await db.execute('CREATE INDEX idx_events_book ON events(book_id)');
      await db.execute('CREATE INDEX idx_events_start_time ON events(start_time)');

      await db.execute('PRAGMA foreign_keys = ON');

      debugPrint('✅ Database upgraded to version 9 (record_number is now optional)');
    }
    if (oldVersion < 10) {
      // Add shared person notes with lock mechanism
      debugPrint('🔄 Upgrading to database version 10 (shared person notes with lock)...');

      // Add new columns to notes table
      await db.execute('ALTER TABLE notes ADD COLUMN person_name_normalized TEXT');
      await db.execute('ALTER TABLE notes ADD COLUMN record_number_normalized TEXT');
      await db.execute('ALTER TABLE notes ADD COLUMN locked_by_device_id TEXT');
      await db.execute('ALTER TABLE notes ADD COLUMN locked_at INTEGER');

      // Create indexes for person lookup and lock management
      await db.execute('''
        CREATE INDEX idx_notes_person_key
        ON notes(person_name_normalized, record_number_normalized)
      ''');
      await db.execute('''
        CREATE INDEX idx_notes_locked_by
        ON notes(locked_by_device_id)
      ''');

      debugPrint('✅ Added person sharing and lock columns to notes table');

      // Populate normalized fields for existing notes with record_numbers
      final result = await db.rawQuery('''
        SELECT notes.id, notes.event_id, events.name, events.record_number
        FROM notes
        INNER JOIN events ON notes.event_id = events.id
        WHERE events.record_number IS NOT NULL AND events.record_number != ''
      ''');

      debugPrint('🔄 Found ${result.length} notes with record numbers to normalize');

      for (final row in result) {
        final noteId = row['id'] as int;
        final name = row['name'] as String;
        final recordNumber = row['record_number'] as String;

        // Normalize: trim and lowercase
        final nameNorm = name.trim().toLowerCase();
        final recordNorm = recordNumber.trim().toLowerCase();

        await db.update(
          'notes',
          {
            'person_name_normalized': nameNorm,
            'record_number_normalized': recordNorm,
          },
          where: 'id = ?',
          whereArgs: [noteId],
        );
      }

      debugPrint('✅ Normalized ${result.length} existing notes');

      // Handle duplicates: for each person group, sync strokes from most recent
      final duplicateGroups = await db.rawQuery('''
        SELECT person_name_normalized, record_number_normalized, COUNT(*) as count
        FROM notes
        WHERE person_name_normalized IS NOT NULL
          AND record_number_normalized IS NOT NULL
        GROUP BY person_name_normalized, record_number_normalized
        HAVING COUNT(*) > 1
      ''');

      debugPrint('🔄 Found ${duplicateGroups.length} duplicate person groups to sync');

      for (final group in duplicateGroups) {
        final nameNorm = group['person_name_normalized'] as String;
        final recordNorm = group['record_number_normalized'] as String;

        // Get most recent note in this group
        final latestNotes = await db.query(
          'notes',
          where: 'person_name_normalized = ? AND record_number_normalized = ?',
          whereArgs: [nameNorm, recordNorm],
          orderBy: 'updated_at DESC',
          limit: 1,
        );

        if (latestNotes.isEmpty) continue;

        // Get pages_data, fallback to migrating strokes_data if needed
        final latestPagesData = latestNotes.first['pages_data'] ?? '[${latestNotes.first['strokes_data'] ?? '[]'}]';
        final latestUpdatedAt = latestNotes.first['updated_at'];

        // Sync to all other notes in the group
        await db.update(
          'notes',
          {
            'pages_data': latestPagesData,
            'updated_at': latestUpdatedAt,
          },
          where: 'person_name_normalized = ? AND record_number_normalized = ? AND id != ?',
          whereArgs: [nameNorm, recordNorm, latestNotes.first['id']],
        );

        debugPrint('✅ Synced pages for person group: $nameNorm+$recordNorm');
      }

      debugPrint('✅ Database upgraded to version 10 (shared person notes with lock)');
    }
    if (oldVersion < 11) {
      // Add is_checked column for event completion status
      debugPrint('🔄 Upgrading to database version 11 (event checked/completed status)...');

      await db.execute('ALTER TABLE events ADD COLUMN is_checked INTEGER DEFAULT 0');

      debugPrint('✅ Database upgraded to version 11 (event checked/completed status)');
    }
    if (oldVersion < 12) {
      // Migrate to multi-page handwriting notes
      debugPrint('🔄 Upgrading to database version 12 (multi-page handwriting notes)...');

      // Add new pages_data column
      await db.execute('ALTER TABLE notes ADD COLUMN pages_data TEXT');

      // Migrate existing strokes_data to pages_data format (wrap in array)
      final notesWithData = await db.query('notes', where: 'strokes_data IS NOT NULL');
      debugPrint('🔄 Migrating ${notesWithData.length} notes to multi-page format...');

      for (final note in notesWithData) {
        final strokesData = note['strokes_data'] as String?;
        if (strokesData != null && strokesData != '[]') {
          // Wrap single-page strokes in array: [strokes] -> [[strokes]]
          final pagesData = '[$strokesData]';
          await db.update(
            'notes',
            {'pages_data': pagesData},
            where: 'id = ?',
            whereArgs: [note['id']],
          );
        } else {
          // Empty strokes: [] -> [[]]
          await db.update(
            'notes',
            {'pages_data': '[[]]'},
            where: 'id = ?',
            whereArgs: [note['id']],
          );
        }
      }

      // Set pages_data to [[]] for any notes that didn't have strokes_data
      await db.execute("UPDATE notes SET pages_data = '[[]]' WHERE pages_data IS NULL");

      debugPrint('✅ Database upgraded to version 12 (multi-page handwriting notes)');
    }
    if (oldVersion < 13) {
      // Add multi-type event support with event_types JSON array column
      debugPrint('🔄 Upgrading to database version 13 (multi-type event support)...');

      // SQLite doesn't support ALTER COLUMN to change constraints, so we need to recreate the table
      await db.execute('PRAGMA foreign_keys = OFF');

      // Create new events table with event_type nullable and event_types NOT NULL
      await db.execute('''
        CREATE TABLE events_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          record_number TEXT,
          event_type TEXT,
          event_types TEXT NOT NULL,
          start_time INTEGER NOT NULL,
          end_time INTEGER,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          is_removed INTEGER DEFAULT 0,
          removal_reason TEXT,
          original_event_id INTEGER,
          new_event_id INTEGER,
          is_checked INTEGER DEFAULT 0,
          FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
        )
      ''');

      // Migrate existing data: wrap single event_type in JSON array for event_types
      await db.execute('''
        INSERT INTO events_new (
          id, book_id, name, record_number, event_type, event_types, start_time, end_time,
          created_at, updated_at, is_removed, removal_reason, original_event_id,
          new_event_id, is_checked
        )
        SELECT
          id, book_id, name, record_number, event_type,
          '["' || event_type || '"]' as event_types,
          start_time, end_time,
          created_at, updated_at, is_removed, removal_reason, original_event_id,
          new_event_id, is_checked
        FROM events
      ''');

      // Drop old table
      await db.execute('DROP TABLE events');

      // Rename new table to original name
      await db.execute('ALTER TABLE events_new RENAME TO events');

      // Recreate indexes
      await db.execute('CREATE INDEX idx_events_book ON events(book_id)');
      await db.execute('CREATE INDEX idx_events_start_time ON events(start_time)');

      await db.execute('PRAGMA foreign_keys = ON');

      debugPrint('✅ Database upgraded to version 13 (multi-type event support)');
    }
    if (oldVersion < 14) {
      // Fix version 13: Recreate events table to make event_type nullable and event_types NOT NULL
      debugPrint('🔄 Upgrading to database version 14 (fix event_type constraint)...');

      await db.execute('PRAGMA foreign_keys = OFF');

      // Create new events table with proper constraints
      await db.execute('''
        CREATE TABLE events_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          record_number TEXT,
          event_type TEXT,
          event_types TEXT NOT NULL,
          start_time INTEGER NOT NULL,
          end_time INTEGER,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          is_removed INTEGER DEFAULT 0,
          removal_reason TEXT,
          original_event_id INTEGER,
          new_event_id INTEGER,
          is_checked INTEGER DEFAULT 0,
          FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
        )
      ''');

      // Migrate data, ensuring event_types is populated
      await db.execute('''
        INSERT INTO events_new (
          id, book_id, name, record_number, event_type, event_types, start_time, end_time,
          created_at, updated_at, is_removed, removal_reason, original_event_id,
          new_event_id, is_checked
        )
        SELECT
          id, book_id, name, record_number, event_type,
          COALESCE(event_types, '["' || COALESCE(event_type, 'other') || '"]') as event_types,
          start_time, end_time,
          created_at, updated_at, is_removed, removal_reason, original_event_id,
          new_event_id, is_checked
        FROM events
      ''');

      // Drop old table
      await db.execute('DROP TABLE events');

      // Rename new table to original name
      await db.execute('ALTER TABLE events_new RENAME TO events');

      // Recreate indexes
      await db.execute('CREATE INDEX idx_events_book ON events(book_id)');
      await db.execute('CREATE INDEX idx_events_start_time ON events(start_time)');

      await db.execute('PRAGMA foreign_keys = ON');

      debugPrint('✅ Database upgraded to version 14 (event_type constraint fixed)');
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // Books table - Top-level containers
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_uuid TEXT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        archived_at INTEGER
      )
    ''');

    // Create unique index on book_uuid
    if (version >= 7) {
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_books_uuid_unique ON books(book_uuid)');
    }

    // Events table - Individual appointment entries with PRD metadata
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        record_number TEXT,
        event_type TEXT,
        event_types TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        is_removed INTEGER DEFAULT 0,
        removal_reason TEXT,
        original_event_id INTEGER,
        new_event_id INTEGER,
        is_checked INTEGER DEFAULT 0,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    // Notes table - Multi-page handwriting notes linked to events
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id INTEGER NOT NULL UNIQUE,
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
        FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE
      )
    ''');

    // Indexes optimized for Schedule views
    await db.execute('''
      CREATE INDEX idx_events_book_time ON events(book_id, start_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_events_book_date ON events(book_id, date(start_time, 'unixepoch'))
    ''');

    await db.execute('''
      CREATE INDEX idx_notes_event ON notes(event_id)
    ''');

    // Indexes for person sharing and lock mechanism (version 10+)
    if (version >= 10) {
      await db.execute('''
        CREATE INDEX idx_notes_person_key
        ON notes(person_name_normalized, record_number_normalized)
      ''');
      await db.execute('''
        CREATE INDEX idx_notes_locked_by
        ON notes(locked_by_device_id)
      ''');
    }

    // Schedule Drawings table - Handwriting overlay on schedule views
    await db.execute('''
      CREATE TABLE schedule_drawings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        date INTEGER NOT NULL,
        view_mode INTEGER NOT NULL,
        strokes_data TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        cached_at INTEGER,
        cache_hit_count INTEGER DEFAULT 0,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_schedule_drawings_book_date_view
      ON schedule_drawings(book_id, date, view_mode)
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

    // Cache Policy table - Server-Store cache configuration (single row, version 8+)
    if (version >= 8) {
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

      debugPrint('✅ Cache policy table and indexes created (version 8)');
    }

    // Add sync columns to all data tables (version 6+)
    if (version >= 6) {
      await db.execute('ALTER TABLE books ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE books ADD COLUMN is_dirty INTEGER DEFAULT 0');

      await db.execute('ALTER TABLE events ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE events ADD COLUMN is_dirty INTEGER DEFAULT 0');

      await db.execute('ALTER TABLE notes ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE notes ADD COLUMN is_dirty INTEGER DEFAULT 0');

      await db.execute('ALTER TABLE schedule_drawings ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE schedule_drawings ADD COLUMN is_dirty INTEGER DEFAULT 0');
    }
  }

  Future<void> clearAllData() async {
    final db = await database;
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
