import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/book.dart';
import '../models/cache_policy.dart';
import '../models/event.dart';
import '../models/note.dart';
import '../models/schedule_drawing.dart';
import 'database_service_interface.dart';

/// PRD-compliant database service implementing Book → Event → Note hierarchy
class PRDDatabaseService implements IDatabaseService {
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
      version: 9, // New version for optional record_number
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
        event_type TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        is_removed INTEGER DEFAULT 0,
        removal_reason TEXT,
        original_event_id INTEGER,
        new_event_id INTEGER,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    // Notes table - Handwriting-only notes linked to events
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id INTEGER NOT NULL UNIQUE,
        strokes_data TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        cached_at INTEGER,
        cache_hit_count INTEGER DEFAULT 0,
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

  // ===================
  // Book Operations
  // ===================

  Future<List<Book>> getAllBooks({bool includeArchived = false}) async {
    final db = await database;
    final whereClause = includeArchived ? '' : 'WHERE archived_at IS NULL';
    final maps = await db.rawQuery('''
      SELECT * FROM books $whereClause ORDER BY created_at DESC
    ''');
    return maps.map((map) => Book.fromMap(map)).toList();
  }

  Future<Book?> getBookById(int id) async {
    final db = await database;
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Book.fromMap(maps.first);
  }

  Future<Book> createBook(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }

    final db = await database;
    final now = DateTime.now();
    final bookUuid = const Uuid().v4();

    final id = await db.insert('books', {
      'name': name.trim(),
      'book_uuid': bookUuid,
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
    });

    return Book(id: id, uuid: bookUuid, name: name.trim(), createdAt: now);
  }

  Future<Book> updateBook(Book book) async {
    if (book.id == null) throw ArgumentError('Book ID cannot be null');
    if (book.name.trim().isEmpty) throw ArgumentError('Book name cannot be empty');

    final db = await database;
    final updatedRows = await db.update(
      'books',
      {'name': book.name.trim()},
      where: 'id = ?',
      whereArgs: [book.id],
    );

    if (updatedRows == 0) throw Exception('Book not found');
    return book.copyWith(name: book.name.trim());
  }

  Future<void> archiveBook(int id) async {
    final db = await database;
    final now = DateTime.now();
    final updatedRows = await db.update(
      'books',
      {'archived_at': now.millisecondsSinceEpoch ~/ 1000},
      where: 'id = ? AND archived_at IS NULL',
      whereArgs: [id],
    );
    if (updatedRows == 0) throw Exception('Book not found or already archived');
  }

  Future<void> deleteBook(int id) async {
    final db = await database;
    final deletedRows = await db.delete('books', where: 'id = ?', whereArgs: [id]);
    if (deletedRows == 0) throw Exception('Book not found');
  }

  // ===================
  // Event Operations
  // ===================

  /// Get events for Day view
  ///
  /// [date] should be normalized to midnight (start of day)
  Future<List<Event>> getEventsByDay(int bookId, DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'events',
      where: 'book_id = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        bookId,
        startOfDay.millisecondsSinceEpoch ~/ 1000,
        endOfDay.millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => Event.fromMap(map)).toList();
  }

  /// Get events for 3-Day view
  ///
  /// [startDate] MUST be the 3-day window start date (calculated by _get3DayWindowStart)
  /// to ensure events are loaded for the correct window being displayed
  Future<List<Event>> getEventsBy3Days(int bookId, DateTime startDate) async {
    final db = await database;
    final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endOfPeriod = startOfDay.add(const Duration(days: 3));

    final maps = await db.query(
      'events',
      where: 'book_id = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        bookId,
        startOfDay.millisecondsSinceEpoch ~/ 1000,
        endOfPeriod.millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => Event.fromMap(map)).toList();
  }

  /// Get events for Week view
  ///
  /// [weekStart] MUST be the week start date (Monday, calculated by _getWeekStart)
  /// to ensure events are loaded for the correct week being displayed
  Future<List<Event>> getEventsByWeek(int bookId, DateTime weekStart) async {
    final db = await database;
    final weekEnd = weekStart.add(const Duration(days: 7));

    final maps = await db.query(
      'events',
      where: 'book_id = ? AND start_time >= ? AND start_time < ?',
      whereArgs: [
        bookId,
        weekStart.millisecondsSinceEpoch ~/ 1000,
        weekEnd.millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => Event.fromMap(map)).toList();
  }

  /// Get all events for a book (regardless of date)
  @override
  Future<List<Event>> getAllEventsByBook(int bookId) async {
    final db = await database;

    final maps = await db.query(
      'events',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'start_time ASC',
    );

    return maps.map((map) => Event.fromMap(map)).toList();
  }

  Future<Event?> getEventById(int id) async {
    final db = await database;
    final maps = await db.query('events', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Event.fromMap(maps.first);
  }

  Future<Event> createEvent(Event event) async {
    final db = await database;
    final now = DateTime.now();

    final eventToCreate = event.copyWith(createdAt: now, updatedAt: now);
    final id = await db.insert('events', eventToCreate.toMap());

    // Create associated empty note
    await db.insert('notes', {
      'event_id': id,
      'strokes_data': '[]',
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
      'updated_at': now.millisecondsSinceEpoch ~/ 1000,
    });

    return eventToCreate.copyWith(id: id);
  }

  Future<Event> updateEvent(Event event) async {
    if (event.id == null) throw ArgumentError('Event ID cannot be null');

    final db = await database;
    final now = DateTime.now();
    final updatedEvent = event.copyWith(updatedAt: now);
    final updateData = updatedEvent.toMap();
    updateData.remove('id');

    final updatedRows = await db.update(
      'events',
      updateData,
      where: 'id = ?',
      whereArgs: [event.id],
    );

    if (updatedRows == 0) throw Exception('Event not found');
    return updatedEvent;
  }

  Future<void> deleteEvent(int id) async {
    final db = await database;
    final deletedRows = await db.delete('events', where: 'id = ?', whereArgs: [id]);
    if (deletedRows == 0) throw Exception('Event not found');
  }

  /// Soft remove an event with a reason
  Future<Event> removeEvent(int eventId, String reason) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Removal reason cannot be empty');
    }

    final db = await database;

    // Get the current event
    final maps = await db.query('events', where: 'id = ?', whereArgs: [eventId], limit: 1);
    if (maps.isEmpty) throw Exception('Event not found');

    final event = Event.fromMap(maps.first);
    if (event.isRemoved) throw Exception('Event is already removed');

    // Update the event with removal information
    final updatedEvent = event.copyWith(
      isRemoved: true,
      removalReason: reason.trim(),
      updatedAt: DateTime.now(),
    );

    final updatedRows = await db.update(
      'events',
      updatedEvent.toMap(),
      where: 'id = ?',
      whereArgs: [eventId],
    );

    if (updatedRows == 0) throw Exception('Failed to remove event');
    return updatedEvent;
  }

  /// Change event time while preserving metadata and notes
  Future<Event> changeEventTime(Event originalEvent, DateTime newStartTime, DateTime? newEndTime, String reason) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('Time change reason cannot be empty');
    }
    if (originalEvent.id == null) {
      throw ArgumentError('Original event must have an ID');
    }

    final db = await database;
    final now = DateTime.now();

    // First, soft remove the original event
    await removeEvent(originalEvent.id!, reason.trim());

    // Create a new event with the new time but same metadata
    final newEvent = originalEvent.copyWith(
      id: null, // Will be auto-generated
      startTime: newStartTime,
      endTime: newEndTime,
      originalEventId: originalEvent.id,
      isRemoved: false,
      removalReason: null,
      updatedAt: now,
    );

    // Insert the new event (remove id to let DB auto-generate)
    final newEventMap = newEvent.toMap();
    newEventMap.remove('id');
    newEventMap['is_dirty'] = 1; // Mark as dirty to trigger server sync
    final newEventId = await db.insert('events', newEventMap);
    final createdEvent = newEvent.copyWith(id: newEventId);

    // Update the original event to point to the new event
    await db.update(
      'events',
      {'new_event_id': newEventId},
      where: 'id = ?',
      whereArgs: [originalEvent.id],
    );

    // Copy the note from original event to new event if it exists
    final originalNote = await getCachedNote(originalEvent.id!);
    if (originalNote != null) {
      // Directly insert a new note for the new event (don't use updateNote)
      final newNoteMap = originalNote.toMap();
      newNoteMap['event_id'] = newEventId;
      newNoteMap['updated_at'] = now.millisecondsSinceEpoch ~/ 1000;
      newNoteMap['is_dirty'] = 1; // Mark as dirty to trigger server sync
      newNoteMap.remove('id'); // Let DB auto-generate the ID

      await db.insert('notes', newNoteMap);
    } else {
      // If no original note exists, create an empty one for the new event
      await db.insert('notes', {
        'event_id': newEventId,
        'strokes_data': '[]',
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'updated_at': now.millisecondsSinceEpoch ~/ 1000,
        'is_dirty': 1, // Mark as dirty to trigger server sync
      });
    }

    return createdEvent;
  }

  // ===================
  // Note Cache Operations
  // ===================

  /// Get cached note by event ID
  /// Automatically increments cache hit count
  Future<Note?> getCachedNote(int eventId) async {
    final db = await database;
    final maps = await db.query('notes', where: 'event_id = ?', whereArgs: [eventId], limit: 1);
    if (maps.isEmpty) return null;
    return Note.fromMap(maps.first);
  }

  /// Save note to cache (insert or update)
  /// Updates cached_at timestamp automatically
  Future<Note> saveCachedNote(Note note) async {
    final db = await database;
    final now = DateTime.now();
    final updatedNote = note.copyWith(updatedAt: now);

    // Debug the serialization
    final noteMap = updatedNote.toMap();
    debugPrint('🔍 SQLite: updateNote called with ${updatedNote.strokes.length} strokes');
    debugPrint('🔍 SQLite: noteMap contents:');
    noteMap.forEach((key, value) {
      debugPrint('   $key: $value (${value.runtimeType})');
    });

    try {
      // Force strokes_data to be a proper string to avoid SQLite parameter binding issues
      final updateMap = Map<String, dynamic>.from(noteMap);
      final originalStrokesData = updateMap['strokes_data'];

      // Force string conversion to prevent SQLite parameter binding corruption
      if (originalStrokesData is String) {
        debugPrint('🔍 SQLite: strokes_data is String, ensuring it stays as String');
        // Even if it's already a string, explicitly recreate it to avoid any reference issues
        updateMap['strokes_data'] = originalStrokesData.toString();
      } else {
        debugPrint('⚠️ SQLite: strokes_data is NOT a String: ${originalStrokesData.runtimeType}');
        updateMap['strokes_data'] = originalStrokesData.toString();
      }

      debugPrint('🔍 SQLite: Final strokes_data type: ${updateMap['strokes_data'].runtimeType}');
      debugPrint('🔍 SQLite: Final strokes_data length: ${updateMap['strokes_data'].toString().length} chars');

      // Try to update existing note first using raw SQL to avoid parameter binding issues
      final strokesDataString = updateMap['strokes_data'] as String;
      final cachedAt = now.millisecondsSinceEpoch ~/ 1000; // Cache timestamp
      final isDirty = updateMap['is_dirty'] ?? 0; // Get dirty flag from note
      debugPrint('🔍 SQLite: Using raw SQL with explicit string parameter');
      final updatedRows = await db.rawUpdate(
        'UPDATE notes SET event_id = ?, strokes_data = ?, created_at = ?, updated_at = ?, cached_at = ?, is_dirty = ? WHERE event_id = ?',
        [
          updateMap['event_id'],
          strokesDataString, // Explicitly pass as string
          updateMap['created_at'],
          updateMap['updated_at'],
          cachedAt, // Update cache timestamp
          isDirty, // Update dirty flag
          note.eventId,
        ],
      );

      debugPrint('✅ SQLite: Update successful, updated $updatedRows rows');

      // If no rows were updated, insert new note
      if (updatedRows == 0) {
        debugPrint('🔍 SQLite: Inserting new note using raw SQL');
        await db.rawInsert(
          'INSERT INTO notes (event_id, strokes_data, created_at, updated_at, cached_at, cache_hit_count, is_dirty) VALUES (?, ?, ?, ?, ?, 0, ?)',
          [
            updateMap['event_id'],
            strokesDataString, // Explicitly pass as string
            updateMap['created_at'],
            updateMap['updated_at'],
            cachedAt, // Set initial cache timestamp
            isDirty, // Set dirty flag
          ],
        );
        debugPrint('✅ SQLite: Insert successful');
      }
    } catch (e) {
      debugPrint('❌ SQLite: Database operation failed: $e');
      debugPrint('❌ SQLite: Failed noteMap was:');
      noteMap.forEach((key, value) {
        debugPrint('   $key: $value (${value.runtimeType})');
      });
      rethrow;
    }

    return updatedNote;
  }

  /// Delete cached note by event ID
  Future<void> deleteCachedNote(int eventId) async {
    final db = await database;
    await db.delete('notes', where: 'event_id = ?', whereArgs: [eventId]);
  }

  /// Batch get cached notes
  /// Returns map of eventId → Note (only includes found notes)
  Future<Map<int, Note>> batchGetCachedNotes(List<int> eventIds) async {
    if (eventIds.isEmpty) return {};

    final db = await database;
    final placeholders = eventIds.map((_) => '?').join(',');
    final maps = await db.query(
      'notes',
      where: 'event_id IN ($placeholders)',
      whereArgs: eventIds,
    );

    final result = <int, Note>{};
    for (final map in maps) {
      final note = Note.fromMap(map);
      result[note.eventId] = note;
    }

    debugPrint('✅ batchGetCachedNotes: Found ${result.length}/${eventIds.length} notes');
    return result;
  }

  /// Batch save cached notes
  /// Updates cached_at timestamp for all notes
  Future<void> batchSaveCachedNotes(Map<int, Note> notes) async {
    if (notes.isEmpty) return;

    final db = await database;
    final batch = db.batch();
    final now = DateTime.now();
    final cachedAt = now.millisecondsSinceEpoch ~/ 1000;

    for (final entry in notes.entries) {
      final eventId = entry.key;
      final note = entry.value;
      final noteMap = note.toMap();

      // Use rawInsert with ON CONFLICT clause for upsert
      batch.rawInsert('''
        INSERT INTO notes (event_id, strokes_data, created_at, updated_at, cached_at, cache_hit_count)
        VALUES (?, ?, ?, ?, ?, 0)
        ON CONFLICT(event_id) DO UPDATE SET
          strokes_data = excluded.strokes_data,
          updated_at = excluded.updated_at,
          cached_at = excluded.cached_at
      ''', [
        eventId,
        noteMap['strokes_data'],
        noteMap['created_at'],
        noteMap['updated_at'],
        cachedAt,
      ]);
    }

    await batch.commit(noResult: true);
    debugPrint('✅ batchSaveCachedNotes: Saved ${notes.length} notes');
  }

  /// Get all dirty notes (notes that need to be synced to server)
  /// Returns list of notes with is_dirty = 1
  Future<List<Note>> getAllDirtyNotes() async {
    final db = await database;
    final maps = await db.query(
      'notes',
      where: 'is_dirty = ?',
      whereArgs: [1],
    );

    final dirtyNotes = maps.map((map) => Note.fromMap(map)).toList();
    debugPrint('✅ getAllDirtyNotes: Found ${dirtyNotes.length} dirty notes');
    return dirtyNotes;
  }

  /// Get dirty notes for a specific book
  /// Returns list of notes with is_dirty = 1 that belong to events in the specified book
  Future<List<Note>> getDirtyNotesByBookId(int bookId) async {
    final db = await database;

    // Join notes with events to filter by book_id
    final maps = await db.rawQuery('''
      SELECT notes.* FROM notes
      INNER JOIN events ON notes.event_id = events.id
      WHERE notes.is_dirty = ? AND events.book_id = ?
    ''', [1, bookId]);

    final dirtyNotes = maps.map((map) => Note.fromMap(map)).toList();
    debugPrint('✅ getDirtyNotesByBookId: Found ${dirtyNotes.length} dirty notes for book $bookId');
    return dirtyNotes;
  }

  // ===================
  // Schedule Drawing Cache Operations
  // ===================

  /// Get cached drawing for specific book, date, and view mode
  /// Automatically increments cache hit count
  ///
  /// [date] MUST be the effective date for the view:
  /// - Day view: the selected date
  /// - 3-Day view: the window start date (calculated by _get3DayWindowStart)
  /// - Week view: the week start date (calculated by _getWeekStart)
  Future<ScheduleDrawing?> getCachedDrawing(int bookId, DateTime date, int viewMode) async {
    final db = await database;
    final normalizedDate = DateTime(date.year, date.month, date.day);

    final maps = await db.query(
      'schedule_drawings',
      where: 'book_id = ? AND date = ? AND view_mode = ?',
      whereArgs: [
        bookId,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        viewMode,
      ],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ScheduleDrawing.fromMap(maps.first);
  }

  /// Save drawing to cache (insert or update)
  /// Updates cached_at timestamp automatically
  ///
  /// The [drawing.date] MUST be the effective date for the view:
  /// - Day view: the selected date
  /// - 3-Day view: the window start date (calculated by _get3DayWindowStart)
  /// - Week view: the week start date (calculated by _getWeekStart)
  Future<ScheduleDrawing> saveCachedDrawing(ScheduleDrawing drawing) async {
    final db = await database;
    final now = DateTime.now();
    final normalizedDate = DateTime(drawing.date.year, drawing.date.month, drawing.date.day);
    final updatedDrawing = drawing.copyWith(
      date: normalizedDate,
      updatedAt: now,
    );

    final drawingMap = updatedDrawing.toMap();
    // Add cache metadata
    drawingMap['cached_at'] = now.millisecondsSinceEpoch ~/ 1000;
    debugPrint('🎨 SQLite: updateScheduleDrawing called with ${updatedDrawing.strokes.length} strokes');

    try {
      // Try to update existing drawing
      final updatedRows = await db.update(
        'schedule_drawings',
        drawingMap,
        where: 'book_id = ? AND date = ? AND view_mode = ?',
        whereArgs: [
          drawing.bookId,
          normalizedDate.millisecondsSinceEpoch ~/ 1000,
          drawing.viewMode,
        ],
      );

      // If no rows updated, insert new drawing
      if (updatedRows == 0) {
        debugPrint('🎨 SQLite: Inserting new schedule drawing');
        // Initialize cache_hit_count for new drawings
        drawingMap['cache_hit_count'] = 0;
        final id = await db.insert('schedule_drawings', drawingMap);
        return updatedDrawing.copyWith(id: id);
      }

      debugPrint('✅ SQLite: Schedule drawing updated successfully');
      return updatedDrawing;
    } catch (e) {
      debugPrint('❌ SQLite: Failed to save schedule drawing: $e');
      rethrow;
    }
  }

  /// Delete cached drawing
  Future<void> deleteCachedDrawing(int bookId, DateTime date, int viewMode) async {
    final db = await database;
    final normalizedDate = DateTime(date.year, date.month, date.day);

    await db.delete(
      'schedule_drawings',
      where: 'book_id = ? AND date = ? AND view_mode = ?',
      whereArgs: [
        bookId,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        viewMode,
      ],
    );
  }

  /// Batch get cached drawings for a date range
  /// Returns list of drawings found in cache
  Future<List<ScheduleDrawing>> batchGetCachedDrawings({
    required int bookId,
    required DateTime startDate,
    required DateTime endDate,
    int? viewMode,
  }) async {
    final db = await database;
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);

    String whereClause = 'book_id = ? AND date >= ? AND date <= ?';
    List<dynamic> whereArgs = [
      bookId,
      normalizedStart.millisecondsSinceEpoch ~/ 1000,
      normalizedEnd.millisecondsSinceEpoch ~/ 1000,
    ];

    if (viewMode != null) {
      whereClause += ' AND view_mode = ?';
      whereArgs.add(viewMode);
    }

    final maps = await db.query(
      'schedule_drawings',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date ASC',
    );

    final drawings = maps.map((map) => ScheduleDrawing.fromMap(map)).toList();
    debugPrint('✅ batchGetCachedDrawings: Found ${drawings.length} drawings');
    return drawings;
  }

  /// Batch save cached drawings
  /// Updates cached_at timestamp for all drawings
  Future<void> batchSaveCachedDrawings(List<ScheduleDrawing> drawings) async {
    if (drawings.isEmpty) return;

    final db = await database;
    final batch = db.batch();
    final now = DateTime.now();
    final cachedAt = now.millisecondsSinceEpoch ~/ 1000;

    for (final drawing in drawings) {
      final normalizedDate = DateTime(drawing.date.year, drawing.date.month, drawing.date.day);
      final drawingMap = drawing.toMap();

      // Try update first
      batch.rawUpdate('''
        UPDATE schedule_drawings
        SET strokes_data = ?, updated_at = ?, cached_at = ?
        WHERE book_id = ? AND date = ? AND view_mode = ?
      ''', [
        drawingMap['strokes_data'],
        drawingMap['updated_at'],
        cachedAt,
        drawing.bookId,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        drawing.viewMode,
      ]);

      // If no rows updated, insert
      batch.rawInsert('''
        INSERT OR IGNORE INTO schedule_drawings
        (book_id, date, view_mode, strokes_data, created_at, updated_at, cached_at, cache_hit_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0)
      ''', [
        drawing.bookId,
        normalizedDate.millisecondsSinceEpoch ~/ 1000,
        drawing.viewMode,
        drawingMap['strokes_data'],
        drawingMap['created_at'],
        drawingMap['updated_at'],
        cachedAt,
      ]);
    }

    await batch.commit(noResult: true);
    debugPrint('✅ batchSaveCachedDrawings: Saved ${drawings.length} drawings');
  }

  // ===================
  // Cache Policy Operations
  // ===================

  /// Get cache policy configuration (single-row table, id=1)
  Future<CachePolicy> getCachePolicy() async {
    final db = await database;
    final maps = await db.query('cache_policy', where: 'id = 1', limit: 1);

    if (maps.isEmpty) {
      // Fallback to default if not found (shouldn't happen after v8 migration)
      debugPrint('⚠️ Cache policy not found, returning default');
      return CachePolicy.defaultPolicy();
    }

    return CachePolicy.fromMap(maps.first);
  }

  /// Update cache policy configuration
  Future<void> updateCachePolicy(CachePolicy policy) async {
    final db = await database;
    final updatedRows = await db.update(
      'cache_policy',
      policy.toMap(),
      where: 'id = 1',
    );

    if (updatedRows == 0) {
      // If update failed, insert (shouldn't happen after v8 migration)
      debugPrint('⚠️ Cache policy update failed, inserting new row');
      await db.insert('cache_policy', policy.toMap());
    }

    debugPrint('✅ Cache policy updated: $policy');
  }

  /// Get device credentials for API authentication
  ///
  /// Returns null if device is not registered yet
  Future<DeviceCredentials?> getDeviceCredentials() async {
    final db = await database;
    final maps = await db.query('device_info', where: 'id = 1', limit: 1);

    if (maps.isEmpty) {
      return null;
    }

    final row = maps.first;
    return DeviceCredentials(
      deviceId: row['device_id'] as String,
      deviceToken: row['device_token'] as String,
    );
  }

  /// Save device credentials after registration
  Future<void> saveDeviceCredentials({
    required String deviceId,
    required String deviceToken,
    required String deviceName,
    String? platform,
  }) async {
    final db = await database;
    await db.insert(
      'device_info',
      {
        'id': 1,
        'device_id': deviceId,
        'device_token': deviceToken,
        'device_name': deviceName,
        'platform': platform,
        'registered_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ===================
  // Cache Management Operations
  // ===================

  /// Increment cache hit count for a note (called on every read)
  Future<void> incrementNoteCacheHit(int eventId) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE notes
      SET cache_hit_count = cache_hit_count + 1
      WHERE event_id = ?
    ''', [eventId]);
  }

  /// Increment cache hit count for a drawing (called on every read)
  Future<void> incrementDrawingCacheHit(int bookId, DateTime date, int viewMode) async {
    final db = await database;
    final normalizedDate = DateTime(date.year, date.month, date.day);
    await db.rawUpdate('''
      UPDATE schedule_drawings
      SET cache_hit_count = cache_hit_count + 1
      WHERE book_id = ? AND date = ? AND view_mode = ?
    ''', [
      bookId,
      normalizedDate.millisecondsSinceEpoch ~/ 1000,
      viewMode,
    ]);
  }

  /// Get cache size in bytes for notes
  Future<int> getNotesCacheSize() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(LENGTH(strokes_data)) as total_size
      FROM notes
      WHERE strokes_data IS NOT NULL
    ''');
    return (result.first['total_size'] as int?) ?? 0;
  }

  /// Get cache size in bytes for drawings
  Future<int> getDrawingsCacheSize() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(LENGTH(strokes_data)) as total_size
      FROM schedule_drawings
      WHERE strokes_data IS NOT NULL
    ''');
    return (result.first['total_size'] as int?) ?? 0;
  }

  /// Get count of notes in cache
  Future<int> getNotesCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM notes');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get count of drawings in cache
  Future<int> getDrawingsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM schedule_drawings');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total cache hit count for notes
  Future<int> getNotesHitCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(cache_hit_count) as total_hits
      FROM notes
    ''');
    return (result.first['total_hits'] as int?) ?? 0;
  }

  /// Get total cache hit count for drawings
  Future<int> getDrawingsHitCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(cache_hit_count) as total_hits
      FROM schedule_drawings
    ''');
    return (result.first['total_hits'] as int?) ?? 0;
  }

  /// Count expired notes based on cache duration
  Future<int> countExpiredNotes(int durationDays) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: durationDays))
        .millisecondsSinceEpoch ~/
        1000;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM notes
      WHERE cached_at < ?
    ''', [cutoffTime]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Count expired drawings based on cache duration
  Future<int> countExpiredDrawings(int durationDays) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: durationDays))
        .millisecondsSinceEpoch ~/
        1000;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM schedule_drawings
      WHERE cached_at < ?
    ''', [cutoffTime]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete expired notes from cache
  Future<int> deleteExpiredNotes(int durationDays) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: durationDays))
        .millisecondsSinceEpoch ~/
        1000;
    return await db.delete(
      'notes',
      where: 'cached_at < ?',
      whereArgs: [cutoffTime],
    );
  }

  /// Delete expired drawings from cache
  Future<int> deleteExpiredDrawings(int durationDays) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: durationDays))
        .millisecondsSinceEpoch ~/
        1000;
    return await db.delete(
      'schedule_drawings',
      where: 'cached_at < ?',
      whereArgs: [cutoffTime],
    );
  }

  /// Delete least recently used notes (by hit count) to meet size target
  /// Returns number of entries deleted
  Future<int> deleteLRUNotes(int targetCount) async {
    if (targetCount <= 0) return 0;

    final db = await database;
    // Get IDs of least-used notes
    final result = await db.rawQuery('''
      SELECT id FROM notes
      ORDER BY cache_hit_count ASC, cached_at ASC
      LIMIT ?
    ''', [targetCount]);

    if (result.isEmpty) return 0;

    final idsToDelete = result.map((row) => row['id'] as int).toList();

    // Delete them
    return await db.delete(
      'notes',
      where: 'id IN (${idsToDelete.join(',')})',
    );
  }

  /// Delete least recently used drawings (by hit count) to meet size target
  /// Returns number of entries deleted
  Future<int> deleteLRUDrawings(int targetCount) async {
    if (targetCount <= 0) return 0;

    final db = await database;
    // Get IDs of least-used drawings
    final result = await db.rawQuery('''
      SELECT id FROM schedule_drawings
      ORDER BY cache_hit_count ASC, cached_at ASC
      LIMIT ?
    ''', [targetCount]);

    if (result.isEmpty) return 0;

    final idsToDelete = result.map((row) => row['id'] as int).toList();

    // Delete them
    return await db.delete(
      'schedule_drawings',
      where: 'id IN (${idsToDelete.join(',')})',
    );
  }

  /// Clear all notes from cache
  Future<void> clearNotesCache() async {
    final db = await database;
    await db.delete('notes');
  }

  /// Clear all drawings from cache
  Future<void> clearDrawingsCache() async {
    final db = await database;
    await db.delete('schedule_drawings');
  }

  // ===================
  // Utility Operations
  // ===================

  Future<int> getEventCountByBook(int bookId) async {
    final db = await database;
    final result = await db.query(
      'events',
      columns: ['COUNT(*) as count'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    return result.first['count'] as int;
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

/// Device credentials for API authentication
class DeviceCredentials {
  final String deviceId;
  final String deviceToken;

  const DeviceCredentials({
    required this.deviceId,
    required this.deviceToken,
  });
}