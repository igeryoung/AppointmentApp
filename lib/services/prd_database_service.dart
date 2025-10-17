import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book.dart';
import '../models/event.dart';
import '../models/note.dart';
import '../models/schedule_drawing.dart';

/// PRD-compliant database service implementing Book → Event → Note hierarchy
class PRDDatabaseService {
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
      version: 5, // New version for schedule drawings
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
  }

  Future<void> _createTables(Database db, int version) async {
    // Books table - Top-level containers
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        archived_at INTEGER
      )
    ''');

    // Events table - Individual appointment entries with PRD metadata
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        record_number TEXT NOT NULL,
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
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_schedule_drawings_book_date_view
      ON schedule_drawings(book_id, date, view_mode)
    ''');
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
    final id = await db.insert('books', {
      'name': name.trim(),
      'created_at': now.millisecondsSinceEpoch ~/ 1000,
    });

    return Book(id: id, name: name.trim(), createdAt: now);
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
    final originalNote = await getNoteByEventId(originalEvent.id!);
    if (originalNote != null) {
      // Directly insert a new note for the new event (don't use updateNote)
      final newNoteMap = originalNote.toMap();
      newNoteMap['event_id'] = newEventId;
      newNoteMap['updated_at'] = now.millisecondsSinceEpoch ~/ 1000;
      newNoteMap.remove('id'); // Let DB auto-generate the ID

      await db.insert('notes', newNoteMap);
    } else {
      // If no original note exists, create an empty one for the new event
      await db.insert('notes', {
        'event_id': newEventId,
        'strokes_data': '[]',
        'created_at': now.millisecondsSinceEpoch ~/ 1000,
        'updated_at': now.millisecondsSinceEpoch ~/ 1000,
      });
    }

    return createdEvent;
  }

  // ===================
  // Note Operations
  // ===================

  Future<Note?> getNoteByEventId(int eventId) async {
    final db = await database;
    final maps = await db.query('notes', where: 'event_id = ?', whereArgs: [eventId], limit: 1);
    if (maps.isEmpty) return null;
    return Note.fromMap(maps.first);
  }

  Future<Note> updateNote(Note note) async {
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
      debugPrint('🔍 SQLite: Using raw SQL with explicit string parameter');
      final updatedRows = await db.rawUpdate(
        'UPDATE notes SET event_id = ?, strokes_data = ?, created_at = ?, updated_at = ? WHERE event_id = ?',
        [
          updateMap['event_id'],
          strokesDataString, // Explicitly pass as string
          updateMap['created_at'],
          updateMap['updated_at'],
          note.eventId,
        ],
      );

      debugPrint('✅ SQLite: Update successful, updated $updatedRows rows');

      // If no rows were updated, insert new note
      if (updatedRows == 0) {
        debugPrint('🔍 SQLite: Inserting new note using raw SQL');
        await db.rawInsert(
          'INSERT INTO notes (event_id, strokes_data, created_at, updated_at) VALUES (?, ?, ?, ?)',
          [
            updateMap['event_id'],
            strokesDataString, // Explicitly pass as string
            updateMap['created_at'],
            updateMap['updated_at'],
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

  // ===================
  // Schedule Drawing Operations
  // ===================

  /// Get drawing for specific book, date, and view mode
  ///
  /// [date] MUST be the effective date for the view:
  /// - Day view: the selected date
  /// - 3-Day view: the window start date (calculated by _get3DayWindowStart)
  /// - Week view: the week start date (calculated by _getWeekStart)
  Future<ScheduleDrawing?> getScheduleDrawing(int bookId, DateTime date, int viewMode) async {
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

  /// Update or create schedule drawing
  ///
  /// The [drawing.date] MUST be the effective date for the view:
  /// - Day view: the selected date
  /// - 3-Day view: the window start date (calculated by _get3DayWindowStart)
  /// - Week view: the week start date (calculated by _getWeekStart)
  Future<ScheduleDrawing> updateScheduleDrawing(ScheduleDrawing drawing) async {
    final db = await database;
    final now = DateTime.now();
    final normalizedDate = DateTime(drawing.date.year, drawing.date.month, drawing.date.day);
    final updatedDrawing = drawing.copyWith(
      date: normalizedDate,
      updatedAt: now,
    );

    final drawingMap = updatedDrawing.toMap();
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

  /// Delete schedule drawing
  Future<void> deleteScheduleDrawing(int bookId, DateTime date, int viewMode) async {
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