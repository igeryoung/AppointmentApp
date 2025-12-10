import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../models/event.dart';
import '../../../models/note.dart';
import 'person_info_utilities_mixin.dart';

/// Mixin providing Note cache operations for PRDDatabaseService
mixin NoteCacheOperationsMixin {
  /// Subclasses must provide database access
  Future<Database> get database;

  /// Required from EventOperationsMixin
  Future<Event?> getEventById(String id);

  // ===================
  // Note Cache Operations
  // ===================

  /// Get cached note by event ID
  /// Automatically increments cache hit count
  Future<Note?> getCachedNote(String eventId) async {
    final db = await database;
    final maps = await db.query('notes', where: 'event_id = ?', whereArgs: [eventId], limit: 1);
    if (maps.isEmpty) return null;
    return Note.fromMap(maps.first);
  }

  /// Load note for event with person sync logic
  /// If event has record_number, syncs with latest note from same person group
  Future<Note?> loadNoteForEvent(String eventId) async {
    final db = await database;

    // Get the event to check for record_number
    final event = await getEventById(eventId);
    if (event == null) {
      return null;
    }

    // Load current note for this event
    Note? currentNote = await getCachedNote(eventId);

    // If no record number, just return the note (no syncing)
    final personKey = PersonInfoUtilitiesMixin.getPersonKeyFromEvent(event);
    if (personKey == null) {
      return currentNote;
    }

    final (nameNorm, recordNorm) = personKey;

    // Find latest note in person group
    final groupNotes = await db.query(
      'notes',
      where: 'person_name_normalized = ? AND record_number_normalized = ?',
      whereArgs: [nameNorm, recordNorm],
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    // If no group note found, update current note with normalized keys
    if (groupNotes.isEmpty) {
      if (currentNote != null) {
        // Mark current note with person keys
        await db.update(
          'notes',
          {
            'person_name_normalized': nameNorm,
            'record_number_normalized': recordNorm,
          },
          where: 'event_id = ?',
          whereArgs: [eventId],
        );
        currentNote = currentNote.copyWith(
          personNameNormalized: nameNorm,
          recordNumberNormalized: recordNorm,
        );
      }
      return currentNote;
    }

    final latestGroupNote = Note.fromMap(groupNotes.first);

    // If current note doesn't exist or group note is newer, sync
    if (currentNote == null ||
        latestGroupNote.updatedAt.isAfter(currentNote.updatedAt)) {

      // Update current event's note with latest pages
      await db.update(
        'notes',
        {
          'pages_data': groupNotes.first['pages_data'],
          'updated_at': latestGroupNote.updatedAt.millisecondsSinceEpoch ~/ 1000,
          'person_name_normalized': nameNorm,
          'record_number_normalized': recordNorm,
        },
        where: 'event_id = ?',
        whereArgs: [eventId],
      );

      // Return the synced note
      currentNote = latestGroupNote.copyWith(
        id: currentNote?.id,
        eventId: eventId,
        personNameNormalized: nameNorm,
        recordNumberNormalized: recordNorm,
      );

    } else {
      // Current note is up to date, just ensure normalized keys are set
      await db.update(
        'notes',
        {
          'person_name_normalized': nameNorm,
          'record_number_normalized': recordNorm,
        },
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
      currentNote = currentNote.copyWith(
        personNameNormalized: nameNorm,
        recordNumberNormalized: recordNorm,
      );
    }

    return currentNote;
  }

  /// Save note with person group sync and lock release
  /// If event has record_number, syncs strokes to all events in same person group
  Future<Note> saveNoteWithSync(String eventId, Note note) async {
    final db = await database;

    // Get the event to check for record_number
    final event = await getEventById(eventId);
    if (event == null) {
      throw Exception('Event not found: $eventId');
    }

    final now = DateTime.now();
    // Increment version when saving
    final newVersion = note.version + 1;
    final updatedNote = note.copyWith(updatedAt: now, version: newVersion);

    // Get person key if event has record number
    final personKey = PersonInfoUtilitiesMixin.getPersonKeyFromEvent(event);

    // Save to current event's note
    final noteMap = updatedNote.toMap();

    // If event has record number, add normalized keys
    if (personKey != null) {
      final (nameNorm, recordNorm) = personKey;
      noteMap['person_name_normalized'] = nameNorm;
      noteMap['record_number_normalized'] = recordNorm;
    }

    // Release lock
    noteMap['locked_by_device_id'] = null;
    noteMap['locked_at'] = null;

    // Update cache timestamp
    final cachedAt = now.millisecondsSinceEpoch ~/ 1000;
    noteMap['cached_at'] = cachedAt;

    final totalStrokes = updatedNote.pages.fold<int>(0, (sum, page) => sum + page.length);

    try {
      // Force pages_data to be a string
      final pagesDataString = noteMap['pages_data'] as String;

      // Update current event's note
      final updatedRows = await db.rawUpdate(
        '''UPDATE notes
           SET event_id = ?, pages_data = ?, created_at = ?, updated_at = ?,
               cached_at = ?, version = ?, is_dirty = ?, person_name_normalized = ?,
               record_number_normalized = ?, locked_by_device_id = ?, locked_at = ?
           WHERE event_id = ?''',
        [
          noteMap['event_id'],
          pagesDataString,
          noteMap['created_at'],
          noteMap['updated_at'],
          cachedAt,
          noteMap['version'],
          noteMap['is_dirty'] ?? 0,
          noteMap['person_name_normalized'],
          noteMap['record_number_normalized'],
          null, // locked_by_device_id
          null, // locked_at
          eventId,
        ],
      );

      // If no rows updated, insert new note
      if (updatedRows == 0) {
        await db.rawInsert(
          '''INSERT INTO notes (event_id, pages_data, created_at, updated_at, cached_at,
             cache_hit_count, version, is_dirty, person_name_normalized, record_number_normalized,
             locked_by_device_id, locked_at)
             VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?)''',
          [
            noteMap['event_id'],
            pagesDataString,
            noteMap['created_at'],
            noteMap['updated_at'],
            cachedAt,
            noteMap['version'],
            noteMap['is_dirty'] ?? 0,
            noteMap['person_name_normalized'],
            noteMap['record_number_normalized'],
            null, // locked_by_device_id
            null, // locked_at
          ],
        );
      }


      // Update event's hasNote field based on whether note has strokes
      final hasStrokes = totalStrokes > 0;
      await db.rawUpdate(
        'UPDATE events SET has_note = ? WHERE id = ?',
        [hasStrokes ? 1 : 0, eventId],
      );

      // If event has record number, sync to all other events in same person group
      if (personKey != null) {
        final (nameNorm, recordNorm) = personKey;


        // Update all other notes in the group (that are not locked)
        final syncedRows = await db.rawUpdate(
          '''UPDATE notes
             SET pages_data = ?, updated_at = ?
             WHERE person_name_normalized = ?
               AND record_number_normalized = ?
               AND event_id != ?
               AND locked_by_device_id IS NULL''',
          [
            pagesDataString,
            noteMap['updated_at'],
            nameNorm,
            recordNorm,
            eventId,
          ],
        );


        // Update hasNote for all events in the person group
        if (syncedRows > 0) {
          final eventIdsResult = await db.rawQuery(
            '''SELECT event_id FROM notes
               WHERE person_name_normalized = ?
                 AND record_number_normalized = ?
                 AND event_id != ?''',
            [nameNorm, recordNorm, eventId],
          );

          for (final row in eventIdsResult) {
            final syncEventId = row['event_id'] as String;
            await db.rawUpdate(
              'UPDATE events SET has_note = ? WHERE id = ?',
              [hasStrokes ? 1 : 0, syncEventId],
            );
          }
        }
      }
    } catch (e) {
      rethrow;
    }

    return updatedNote;
  }

  /// Handle record number update for an event
  /// Called when event's record_number changes from NULL to a value
  /// Returns the updated note (may be synced from person group)
  Future<Note?> handleRecordNumberUpdate(String eventId, Event updatedEvent) async {
    final db = await database;

    // Get person key from updated event
    final personKey = PersonInfoUtilitiesMixin.getPersonKeyFromEvent(updatedEvent);
    if (personKey == null) {
      return await getCachedNote(eventId);
    }

    final (nameNorm, recordNorm) = personKey;


    // Get current event's note
    final currentNote = await getCachedNote(eventId);

    // Find existing note in person group
    final groupNotes = await db.query(
      'notes',
      where: 'person_name_normalized = ? AND record_number_normalized = ?',
      whereArgs: [nameNorm, recordNorm],
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    // Case 1: Found existing person note in DB
    if (groupNotes.isNotEmpty) {
      final groupNote = Note.fromMap(groupNotes.first);


      // Update current event's note with person group pages
      await db.update(
        'notes',
        {
          'pages_data': groupNotes.first['pages_data'],
          'updated_at': groupNote.updatedAt.millisecondsSinceEpoch ~/ 1000,
          'person_name_normalized': nameNorm,
          'record_number_normalized': recordNorm,
        },
        where: 'event_id = ?',
        whereArgs: [eventId],
      );

      return groupNote.copyWith(
        id: currentNote?.id,
        eventId: eventId,
        personNameNormalized: nameNorm,
        recordNumberNormalized: recordNorm,
      );
    }

    // Case 2: No existing person note, but current has strokes
    if (currentNote != null && currentNote.isNotEmpty) {

      // Mark current note as the person note
      await db.update(
        'notes',
        {
          'person_name_normalized': nameNorm,
          'record_number_normalized': recordNorm,
        },
        where: 'event_id = ?',
        whereArgs: [eventId],
      );

      return currentNote.copyWith(
        personNameNormalized: nameNorm,
        recordNumberNormalized: recordNorm,
      );
    }

    // Case 3: No person note, no current strokes - just mark with person keys
    if (currentNote != null) {

      await db.update(
        'notes',
        {
          'person_name_normalized': nameNorm,
          'record_number_normalized': recordNorm,
        },
        where: 'event_id = ?',
        whereArgs: [eventId],
      );

      return currentNote.copyWith(
        personNameNormalized: nameNorm,
        recordNumberNormalized: recordNorm,
      );
    }

    return null;
  }

  /// Save note to cache (insert or update)
  /// Updates cached_at timestamp automatically
  Future<Note> saveCachedNote(Note note) async {
    final db = await database;
    final now = DateTime.now();
    // Increment version when saving
    final newVersion = note.version + 1;
    final updatedNote = note.copyWith(updatedAt: now, version: newVersion);

    // Debug the serialization
    final noteMap = updatedNote.toMap();
    final totalStrokes = updatedNote.pages.fold<int>(0, (sum, page) => sum + page.length);
    noteMap.forEach((key, value) {
    });

    try {
      // Force pages_data to be a proper string to avoid SQLite parameter binding issues
      final updateMap = Map<String, dynamic>.from(noteMap);
      final originalPagesData = updateMap['pages_data'];

      // Force string conversion to prevent SQLite parameter binding corruption
      if (originalPagesData is String) {
        updateMap['pages_data'] = originalPagesData.toString();
      } else {
        updateMap['pages_data'] = originalPagesData.toString();
      }


      // Try to update existing note first using raw SQL to avoid parameter binding issues
      final pagesDataString = updateMap['pages_data'] as String;
      final cachedAt = now.millisecondsSinceEpoch ~/ 1000; // Cache timestamp
      final isDirty = updateMap['is_dirty'] ?? 0; // Get dirty flag from note
      final version = updateMap['version'] ?? 1; // Get version from note
      final updatedRows = await db.rawUpdate(
        'UPDATE notes SET event_id = ?, pages_data = ?, created_at = ?, updated_at = ?, cached_at = ?, version = ?, is_dirty = ? WHERE event_id = ?',
        [
          updateMap['event_id'],
          pagesDataString, // Explicitly pass as string
          updateMap['created_at'],
          updateMap['updated_at'],
          cachedAt, // Update cache timestamp
          version, // Update version
          isDirty, // Update dirty flag
          note.eventId,
        ],
      );


      // If no rows were updated, insert new note
      if (updatedRows == 0) {
        await db.rawInsert(
          'INSERT INTO notes (event_id, pages_data, created_at, updated_at, cached_at, cache_hit_count, version, is_dirty) VALUES (?, ?, ?, ?, ?, 0, ?, ?)',
          [
            updateMap['event_id'],
            pagesDataString, // Explicitly pass as string
            updateMap['created_at'],
            updateMap['updated_at'],
            cachedAt, // Set initial cache timestamp
            version, // Set initial version
            isDirty, // Set dirty flag
          ],
        );
      }
    } catch (e) {
      noteMap.forEach((key, value) {
      });
      rethrow;
    }

    return updatedNote;
  }

  /// Delete cached note by event ID
  Future<void> deleteCachedNote(String eventId) async {
    final db = await database;
    await db.delete('notes', where: 'event_id = ?', whereArgs: [eventId]);
  }

  /// Batch get cached notes
  /// Returns map of eventId → Note (only includes found notes)
  Future<Map<String, Note>> batchGetCachedNotes(List<String> eventIds) async {
    if (eventIds.isEmpty) return {};

    final db = await database;
    final placeholders = eventIds.map((_) => '?').join(',');
    final maps = await db.query(
      'notes',
      where: 'event_id IN ($placeholders)',
      whereArgs: eventIds,
    );

    final result = <String, Note>{};
    for (final map in maps) {
      final note = Note.fromMap(map);
      result[note.eventId] = note;
    }

    return result;
  }

  /// Batch save cached notes
  /// Updates cached_at timestamp for all notes
  Future<void> batchSaveCachedNotes(Map<String, Note> notes) async {
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
        INSERT INTO notes (event_id, pages_data, created_at, updated_at, cached_at, cache_hit_count, version, is_dirty)
        VALUES (?, ?, ?, ?, ?, 0, ?, ?)
        ON CONFLICT(event_id) DO UPDATE SET
          pages_data = excluded.pages_data,
          updated_at = excluded.updated_at,
          cached_at = excluded.cached_at,
          version = excluded.version,
          is_dirty = excluded.is_dirty
      ''', [
        eventId,
        noteMap['pages_data'],
        noteMap['created_at'],
        noteMap['updated_at'],
        cachedAt,
        noteMap['version'] ?? 1,
        noteMap['is_dirty'] ?? 0,
      ]);
    }

    await batch.commit(noResult: true);
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
    return dirtyNotes;
  }

  /// Get dirty notes for a specific book
  /// Returns list of notes with is_dirty = 1 that belong to events in the specified book
  Future<List<Note>> getDirtyNotesByBookId(String bookUuid) async {
    final db = await database;

    // Join notes with events to filter by book_uuid
    final maps = await db.rawQuery('''
      SELECT notes.* FROM notes
      INNER JOIN events ON notes.event_id = events.id
      WHERE notes.is_dirty = ? AND events.book_uuid = ?
    ''', [1, bookUuid]);

    final dirtyNotes = maps.map((map) => Note.fromMap(map)).toList();
    return dirtyNotes;
  }
}
