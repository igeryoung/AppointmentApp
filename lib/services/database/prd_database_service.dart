import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
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
      version: 19, // v19 adds person_info table for synced phone numbers
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

    // Version 16 to 17: Add phone and charge_items columns
    if (oldVersion == 16 && newVersion >= 17) {
      debugPrint('Upgrading database from v16 to v17: adding phone and charge_items columns');
      await db.execute('ALTER TABLE events ADD COLUMN phone TEXT');
      await db.execute('ALTER TABLE events ADD COLUMN charge_items TEXT DEFAULT "[]"');
    }

    // Version 17 to 18: Add person_charge_items table for shared charge items
    if (oldVersion == 17 && newVersion >= 18) {
      debugPrint('Upgrading database from v17 to v18: adding person_charge_items table');
      await _migrateToPersonChargeItems(db);
    }

    // Handle skipped versions (e.g., 16 -> 18)
    if (oldVersion == 16 && newVersion >= 18) {
      debugPrint('Upgrading database from v16 to v18: migrating charge items');
      await _migrateToPersonChargeItems(db);
    }

    // Version 18 to 19: Add person_info table for synced phone numbers
    if (oldVersion == 18 && newVersion >= 19) {
      debugPrint('Upgrading database from v18 to v19: adding person_info table');
      await _migrateToPersonInfo(db);
    }

    // Handle skipped versions (e.g., 17 -> 19, 16 -> 19)
    if (oldVersion == 17 && newVersion >= 19) {
      debugPrint('Upgrading database from v17 to v19: migrating phone numbers');
      await _migrateToPersonInfo(db);
    }

    if (oldVersion == 16 && newVersion >= 19) {
      debugPrint('Upgrading database from v16 to v19: migrating phone numbers');
      await _migrateToPersonInfo(db);
    }

    // For versions older than v16, require reinstall
    if (oldVersion < 16) {
      debugPrint('⚠️ Database upgrade from v$oldVersion to v$newVersion is not supported.');
      debugPrint('⚠️ Version 16 is the baseline. Please clear app data and reinstall.');

      throw Exception(
        'Database upgrade from version $oldVersion to $newVersion is not supported. '
        'Version 16 is the baseline version. Please clear app data and reinstall.'
      );
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // Version 19 schema - includes all features
    // - Books with UUID and sync columns
    // - Events with multi-type support, phone, charge items, completion status, and sync columns
    // - Notes with multi-page support, person sharing, locks, cache, and sync columns
    // - Person charge items with shared sync across events (v18)
    // - Person info with synced phone numbers (new in v19)
    // - Schedule drawings with cache and sync columns
    // - Device info, sync metadata, and cache policy tables

    // Books table - Top-level containers
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_uuid TEXT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        archived_at INTEGER,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0
      )
    ''');

    // Create unique index on book_uuid
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_books_uuid_unique ON books(book_uuid)');

    // Events table - Individual appointment entries with PRD metadata
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        record_number TEXT,
        phone TEXT,
        event_type TEXT,
        event_types TEXT NOT NULL,
        charge_items TEXT DEFAULT "[]",
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        is_removed INTEGER DEFAULT 0,
        removal_reason TEXT,
        original_event_id INTEGER,
        new_event_id INTEGER,
        is_checked INTEGER DEFAULT 0,
        has_note INTEGER DEFAULT 0,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
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
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
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
        book_id INTEGER NOT NULL,
        date INTEGER NOT NULL,
        view_mode INTEGER NOT NULL,
        strokes_data TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        cached_at INTEGER,
        cache_hit_count INTEGER DEFAULT 0,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
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

  /// Migrate existing charge items from events.charge_items to person_charge_items table
  Future<void> _migrateToPersonChargeItems(Database db) async {
    debugPrint('Starting migration to person_charge_items table');

    // Create the person_charge_items table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS person_charge_items (
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

    // Create indexes
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_person_charge_items_person_key
      ON person_charge_items(person_name_normalized, record_number_normalized)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_person_charge_items_dirty
      ON person_charge_items(is_dirty)
    ''');

    // Fetch all events with record numbers and charge items
    final events = await db.query(
      'events',
      where: 'record_number IS NOT NULL AND record_number != "" AND charge_items IS NOT NULL AND charge_items != "[]"',
    );

    debugPrint('Found ${events.length} events with charge items to migrate');

    // Track unique person+item combinations to avoid duplicates
    final migratedItems = <String, Map<String, dynamic>>{};

    for (final eventMap in events) {
      final name = eventMap['name'] as String;
      final recordNumber = eventMap['record_number'] as String;
      final chargeItemsJson = eventMap['charge_items'] as String?;

      if (chargeItemsJson == null || chargeItemsJson.isEmpty || chargeItemsJson == '[]') {
        continue;
      }

      // Normalize person info
      final nameNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(name);
      final recordNumberNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(recordNumber);

      // Parse charge items
      final chargeItems = ChargeItem.fromJsonList(chargeItemsJson);

      for (final chargeItem in chargeItems) {
        // Create unique key for this person+item combination
        final uniqueKey = '$nameNormalized+$recordNumberNormalized+${chargeItem.itemName}';

        // Check if we've already migrated this item
        if (!migratedItems.containsKey(uniqueKey)) {
          // First occurrence - use its paid status and cost
          migratedItems[uniqueKey] = {
            'person_name_normalized': nameNormalized,
            'record_number_normalized': recordNumberNormalized,
            'item_name': chargeItem.itemName,
            'cost': chargeItem.cost,
            'is_paid': chargeItem.isPaid ? 1 : 0,
          };
        } else {
          // Duplicate found - merge logic: if any occurrence is paid, consider it paid
          final existing = migratedItems[uniqueKey]!;
          if (chargeItem.isPaid) {
            existing['is_paid'] = 1;
          }
          // Use the higher cost if they differ (safety check)
          if (chargeItem.cost > (existing['cost'] as int)) {
            existing['cost'] = chargeItem.cost;
          }
        }
      }
    }

    // Insert all unique items into person_charge_items
    for (final itemData in migratedItems.values) {
      try {
        await db.insert(
          'person_charge_items',
          itemData,
          conflictAlgorithm: ConflictAlgorithm.ignore, // Skip if already exists
        );
      } catch (e) {
        debugPrint('Failed to migrate charge item: ${itemData['item_name']}, error: $e');
      }
    }

    debugPrint('Successfully migrated ${migratedItems.length} unique charge items');
  }

  /// Migrate existing phone numbers from events to person_info table
  Future<void> _migrateToPersonInfo(Database db) async {
    debugPrint('Starting migration to person_info table');

    // Create the person_info table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS person_info (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_name_normalized TEXT NOT NULL,
        record_number_normalized TEXT NOT NULL,
        phone TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        UNIQUE(person_name_normalized, record_number_normalized)
      )
    ''');

    // Create index
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_person_info_person_key
      ON person_info(person_name_normalized, record_number_normalized)
    ''');

    // Fetch all events with record numbers and phone numbers
    final events = await db.query(
      'events',
      where: 'record_number IS NOT NULL AND record_number != "" AND phone IS NOT NULL AND phone != ""',
    );

    debugPrint('Found ${events.length} events with phone numbers to migrate');

    // Track unique person+phone combinations
    final personPhones = <String, Map<String, dynamic>>{};

    for (final eventMap in events) {
      final name = eventMap['name'] as String;
      final recordNumber = eventMap['record_number'] as String;
      final phone = eventMap['phone'] as String?;

      if (phone == null || phone.isEmpty) {
        continue;
      }

      // Normalize person info
      final nameNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(name);
      final recordNumberNormalized = PersonInfoUtilitiesMixin.normalizePersonKey(recordNumber);

      // Create unique key for this person
      final personKey = '$nameNormalized+$recordNumberNormalized';

      // Use the first phone number found for this person (or keep existing if already set)
      if (!personPhones.containsKey(personKey)) {
        personPhones[personKey] = {
          'person_name_normalized': nameNormalized,
          'record_number_normalized': recordNumberNormalized,
          'phone': phone,
        };
      }
    }

    // Insert all unique person info into person_info table
    for (final personData in personPhones.values) {
      try {
        await db.insert(
          'person_info',
          personData,
          conflictAlgorithm: ConflictAlgorithm.ignore, // Skip if already exists
        );
      } catch (e) {
        debugPrint('Failed to migrate person info: ${personData['person_name_normalized']}+${personData['record_number_normalized']}, error: $e');
      }
    }

    debugPrint('Successfully migrated ${personPhones.length} unique person info records');
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
