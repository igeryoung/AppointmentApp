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
      version: 21, // v21 makes book_uuid PRIMARY KEY, removes id column
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

    // Version 19 to 20: Add has_charge_items flag and remove legacy charge_items column
    if (oldVersion == 19 && newVersion >= 20) {
      debugPrint('Upgrading database from v19 to v20: adding has_charge_items flag');
      await _migrateToHasChargeItemsFlag(db);
    }

    // Handle skipped versions (e.g., 16 -> 20, 17 -> 20, 18 -> 20)
    if (oldVersion >= 16 && oldVersion < 19 && newVersion >= 20) {
      debugPrint('Upgrading database from v$oldVersion to v20: adding has_charge_items flag');
      await _migrateToHasChargeItemsFlag(db);
    }

    // Version 20 to 21: Make book_uuid PRIMARY KEY, remove id column
    if (oldVersion == 20 && newVersion >= 21) {
      debugPrint('Upgrading database from v20 to v21: migrating to book_uuid PRIMARY KEY');
      await _migrateToBookUuidPrimaryKey(db);
    }

    // Handle skipped versions (e.g., 16 -> 21, 17 -> 21, 18 -> 21, 19 -> 21)
    if (oldVersion >= 16 && oldVersion < 20 && newVersion >= 21) {
      debugPrint('Upgrading database from v$oldVersion to v21: migrating to book_uuid PRIMARY KEY');
      await _migrateToBookUuidPrimaryKey(db);
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
    // Version 20 schema - includes all features
    // - Books with UUID and sync columns
    // - Events with multi-type support, phone, has_charge_items flag, completion status, and sync columns
    // - Notes with multi-page support, person sharing, locks, cache, and sync columns
    // - Person charge items with shared sync across events (v18)
    // - Person info with synced phone numbers (v19)
    // - has_charge_items flag for efficient charge item presence check (v20)
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
        has_charge_items INTEGER DEFAULT 0,
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

  /// Migrate to has_charge_items flag and remove legacy charge_items column
  Future<void> _migrateToHasChargeItemsFlag(Database db) async {
    debugPrint('Starting migration to has_charge_items flag');

    // Step 1: Add has_charge_items column (default 0)
    await db.execute('ALTER TABLE events ADD COLUMN has_charge_items INTEGER DEFAULT 0');
    debugPrint('Added has_charge_items column');

    // Step 2: Populate has_charge_items based on person_charge_items table
    // For each event with a record number, check if person_charge_items exist
    await db.execute('''
      UPDATE events
      SET has_charge_items = 1
      WHERE record_number IS NOT NULL
        AND record_number != ""
        AND EXISTS (
          SELECT 1 FROM person_charge_items
          WHERE person_charge_items.person_name_normalized = LOWER(TRIM(events.name))
            AND person_charge_items.record_number_normalized = LOWER(TRIM(events.record_number))
        )
    ''');
    debugPrint('Populated has_charge_items flags based on person_charge_items');

    // Step 3: Remove legacy charge_items column
    // SQLite doesn't support DROP COLUMN directly, so we need to:
    // 1. Create new table without charge_items
    // 2. Copy data
    // 3. Drop old table
    // 4. Rename new table

    debugPrint('Removing legacy charge_items column...');

    // Create new events table without charge_items
    await db.execute('''
      CREATE TABLE events_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
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
        original_event_id INTEGER,
        new_event_id INTEGER,
        is_checked INTEGER DEFAULT 0,
        has_note INTEGER DEFAULT 0,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    // Copy data from old table to new table (excluding charge_items)
    await db.execute('''
      INSERT INTO events_new
        (id, book_id, name, record_number, phone, event_type, event_types, has_charge_items,
         start_time, end_time, created_at, updated_at, is_removed, removal_reason,
         original_event_id, new_event_id, is_checked, has_note, version, is_dirty)
      SELECT
        id, book_id, name, record_number, phone, event_type, event_types, has_charge_items,
        start_time, end_time, created_at, updated_at, is_removed, removal_reason,
        original_event_id, new_event_id, is_checked, has_note, version, is_dirty
      FROM events
    ''');

    // Drop old table
    await db.execute('DROP TABLE events');

    // Rename new table
    await db.execute('ALTER TABLE events_new RENAME TO events');

    // Recreate indexes
    await db.execute('CREATE INDEX idx_events_book_time ON events(book_id, start_time)');
    await db.execute('CREATE INDEX idx_events_book_date ON events(book_id, date(start_time, \'unixepoch\'))');

    debugPrint('Successfully removed legacy charge_items column and completed migration to v20');
  }

  /// Migrate to book_uuid PRIMARY KEY and remove id column
  Future<void> _migrateToBookUuidPrimaryKey(Database db) async {
    debugPrint('Starting migration to book_uuid PRIMARY KEY');

    // Step 1: Ensure all books have book_uuid
    final booksWithoutUuid = await db.query('books', where: 'book_uuid IS NULL OR book_uuid = ""');
    for (final book in booksWithoutUuid) {
      final newUuid = const Uuid().v4();
      await db.update(
        'books',
        {'book_uuid': newUuid},
        where: 'id = ?',
        whereArgs: [book['id']],
      );
      debugPrint('Generated UUID for book id=${book['id']}: $newUuid');
    }

    debugPrint('Ensured all books have UUID');

    // Step 2: Create new books table with book_uuid as PRIMARY KEY
    await db.execute('''
      CREATE TABLE books_new (
        book_uuid TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        archived_at INTEGER,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0
      )
    ''');

    // Copy data from old table to new table
    await db.execute('''
      INSERT INTO books_new (book_uuid, name, created_at, archived_at, version, is_dirty)
      SELECT book_uuid, name, created_at, archived_at, version, is_dirty
      FROM books
    ''');

    debugPrint('Created new books table with book_uuid as PRIMARY KEY');

    // Step 3: Create new events table with book_uuid foreign key
    await db.execute('''
      CREATE TABLE events_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        original_event_id INTEGER,
        new_event_id INTEGER,
        is_checked INTEGER DEFAULT 0,
        has_note INTEGER DEFAULT 0,
        version INTEGER DEFAULT 1,
        is_dirty INTEGER DEFAULT 0,
        FOREIGN KEY (book_uuid) REFERENCES books_new (book_uuid) ON DELETE CASCADE
      )
    ''');

    // Copy events data, converting book_id to book_uuid
    await db.execute('''
      INSERT INTO events_new
        (id, book_uuid, name, record_number, phone, event_type, event_types, has_charge_items,
         start_time, end_time, created_at, updated_at, is_removed, removal_reason,
         original_event_id, new_event_id, is_checked, has_note, version, is_dirty)
      SELECT
        e.id, b.book_uuid, e.name, e.record_number, e.phone, e.event_type, e.event_types, e.has_charge_items,
        e.start_time, e.end_time, e.created_at, e.updated_at, e.is_removed, e.removal_reason,
        e.original_event_id, e.new_event_id, e.is_checked, e.has_note, e.version, e.is_dirty
      FROM events e
      INNER JOIN books b ON e.book_id = b.id
    ''');

    debugPrint('Created new events table with book_uuid foreign key');

    // Step 4: Create new schedule_drawings table with book_uuid foreign key
    await db.execute('''
      CREATE TABLE schedule_drawings_new (
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
        FOREIGN KEY (book_uuid) REFERENCES books_new (book_uuid) ON DELETE CASCADE,
        UNIQUE(book_uuid, date, view_mode)
      )
    ''');

    // Copy schedule_drawings data, converting book_id to book_uuid
    await db.execute('''
      INSERT INTO schedule_drawings_new
        (id, book_uuid, date, view_mode, strokes_data, created_at, updated_at,
         cached_at, cache_hit_count, version, is_dirty)
      SELECT
        sd.id, b.book_uuid, sd.date, sd.view_mode, sd.strokes_data, sd.created_at, sd.updated_at,
        sd.cached_at, sd.cache_hit_count, sd.version, sd.is_dirty
      FROM schedule_drawings sd
      INNER JOIN books b ON sd.book_id = b.id
    ''');

    debugPrint('Created new schedule_drawings table with book_uuid foreign key');

    // Step 5: Drop old tables and rename new ones
    await db.execute('DROP TABLE IF EXISTS schedule_drawings');
    await db.execute('DROP TABLE IF EXISTS notes'); // Will be recreated
    await db.execute('DROP TABLE IF EXISTS events');
    await db.execute('DROP TABLE IF EXISTS books');

    await db.execute('ALTER TABLE books_new RENAME TO books');
    await db.execute('ALTER TABLE events_new RENAME TO events');
    await db.execute('ALTER TABLE schedule_drawings_new RENAME TO schedule_drawings');

    debugPrint('Dropped old tables and renamed new ones');

    // Step 6: Recreate notes table (references events which now has new structure)
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

    debugPrint('Recreated notes table');

    // Step 7: Recreate indexes
    await db.execute('CREATE INDEX idx_events_book_uuid_time ON events(book_uuid, start_time)');
    await db.execute('CREATE INDEX idx_events_book_uuid_date ON events(book_uuid, date(start_time, \'unixepoch\'))');
    await db.execute('CREATE INDEX idx_notes_event ON notes(event_id)');
    await db.execute('CREATE INDEX idx_notes_person_name ON notes(person_name_normalized) WHERE person_name_normalized IS NOT NULL');
    await db.execute('CREATE INDEX idx_notes_record_number ON notes(record_number_normalized) WHERE record_number_normalized IS NOT NULL');
    await db.execute('CREATE INDEX idx_notes_locked_by ON notes(locked_by_device_id) WHERE locked_by_device_id IS NOT NULL');
    await db.execute('CREATE INDEX idx_schedule_drawings_book_uuid_date ON schedule_drawings(book_uuid, date, view_mode)');

    debugPrint('Recreated indexes');

    debugPrint('Successfully migrated to book_uuid PRIMARY KEY and completed migration to v21');
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
