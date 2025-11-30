import 'package:postgres/postgres.dart';
import '../database/connection.dart';

/// Service for pulling books from server to local device
///
/// Supports one-way sync (Server → Local) with complete book data
class BookPullService {
  final DatabaseConnection db;

  BookPullService(this.db);

  /// List all books with optional search by name
  ///
  /// Returns all books (including archived) from the entire server store
  /// No longer filtered by device_id - shows all books
  /// Optional [searchQuery] filters books by name (case-insensitive)
  Future<List<Map<String, dynamic>>> listBooksForDevice(
    String deviceId, {
    String? searchQuery,
  }) async {
    String query = '''
      SELECT
        book_uuid,
        name,
        created_at,
        updated_at,
        archived_at,
        version,
        is_deleted,
        device_id
      FROM books
      WHERE 1=1
    ''';

    Map<String, dynamic> parameters = {};

    // Add search filter if provided
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query += ' AND LOWER(name) LIKE @searchQuery';
      parameters['searchQuery'] = '%${searchQuery.toLowerCase()}%';
    }

    query += ' ORDER BY created_at DESC';

    final results = await db.queryRows(query, parameters: parameters);

    return results.map((row) {
      return {
        'book_uuid': row['book_uuid'] as String,
        'name': row['name'] as String,
        'created_at': (row['created_at'] as DateTime).toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toIso8601String(),
        'archived_at': row['archived_at'] != null
            ? (row['archived_at'] as DateTime).toIso8601String()
            : null,
        'version': row['version'] as int,
        'is_deleted': row['is_deleted'] as bool,
        'device_id': row['device_id'] as String,
      };
    }).toList();
  }

  /// Get complete book data (book + events + notes + drawings)
  ///
  /// Returns all data needed to recreate the book locally
  /// No longer filtered by device_id - any authenticated device can pull any book
  /// Throws if book doesn't exist
  Future<Map<String, dynamic>> getCompleteBookData(
    String bookUuid,
    String deviceId,
  ) async {
    // 1. Verify book exists (no longer checking device ownership)
    final bookResult = await db.querySingle(
      '''
      SELECT
        book_uuid,
        name,
        created_at,
        updated_at,
        archived_at,
        version,
        is_deleted
      FROM books
      WHERE book_uuid = @bookUuid
      ''',
      parameters: {
        'bookUuid': bookUuid,
      },
    );

    if (bookResult == null) {
      throw Exception('Book not found: $bookUuid');
    }

    // 2. Get all events for the book
    final eventsResults = await db.queryRows(
      '''
      SELECT
        id,
        book_uuid,
        name,
        record_number,
        event_type,
        start_time,
        end_time,
        created_at,
        updated_at,
        is_removed,
        removal_reason,
        original_event_id,
        new_event_id,
        version,
        is_deleted
      FROM events
      WHERE book_uuid = @bookUuid
      ORDER BY start_time ASC
      ''',
      parameters: {'bookUuid': bookUuid},
    );

    final events = eventsResults.map((row) {
      return {
        'id': row['id'] as String,
        'book_uuid': row['book_uuid'] as String,
        'name': row['name'] as String,
        'record_number': row['record_number'] as String,
        'event_type': row['event_type'] as String,
        'start_time': (row['start_time'] as DateTime).toIso8601String(),
        'end_time': row['end_time'] != null
            ? (row['end_time'] as DateTime).toIso8601String()
            : null,
        'created_at': (row['created_at'] as DateTime).toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toIso8601String(),
        'is_removed': row['is_removed'] as bool,
        'removal_reason': row['removal_reason'] as String?,
        'original_event_id': row['original_event_id'] as String?,
        'new_event_id': row['new_event_id'] as String?,
        'version': row['version'] as int,
        'is_deleted': row['is_deleted'] as bool,
      };
    }).toList();

    // 3. Get all notes for events in this book
    final notesResults = await db.queryRows(
      '''
      SELECT
        n.id,
        n.event_id,
        n.pages_data,
        n.created_at,
        n.updated_at,
        n.version,
        n.is_deleted
      FROM notes n
      INNER JOIN events e ON n.event_id = e.id
      WHERE e.book_uuid = @bookUuid
      ORDER BY n.created_at ASC
      ''',
      parameters: {'bookUuid': bookUuid},
    );

    final notes = notesResults.map((row) {
      return {
        'id': row['id'] as int,
        'event_id': row['event_id'] as String,
        'pages_data': row['pages_data'] as String?,
        'created_at': (row['created_at'] as DateTime).toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toIso8601String(),
        'version': row['version'] as int,
        'is_deleted': row['is_deleted'] as bool,
      };
    }).toList();

    // 4. Get all schedule drawings for the book
    final drawingsResults = await db.queryRows(
      '''
      SELECT
        id,
        book_uuid,
        date,
        view_mode,
        strokes_data,
        created_at,
        updated_at,
        version,
        is_deleted
      FROM schedule_drawings
      WHERE book_uuid = @bookUuid
      ORDER BY date ASC, view_mode ASC
      ''',
      parameters: {'bookUuid': bookUuid},
    );

    final drawings = drawingsResults.map((row) {
      return {
        'id': row['id'] as int,
        'book_uuid': row['book_uuid'] as String,
        'date': (row['date'] as DateTime).toIso8601String(),
        'view_mode': row['view_mode'] as int,
        'strokes_data': row['strokes_data'] as String?,
        'created_at': (row['created_at'] as DateTime).toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toIso8601String(),
        'version': row['version'] as int,
        'is_deleted': row['is_deleted'] as bool,
      };
    }).toList();

    // 5. Add device access tracking
    await addDeviceAccess(bookUuid, deviceId, 'pulled');

    // 6. Assemble complete book data
    return {
      'book': {
        'book_uuid': bookResult['book_uuid'] as String,
        'name': bookResult['name'] as String,
        'created_at': (bookResult['created_at'] as DateTime).toIso8601String(),
        'updated_at': (bookResult['updated_at'] as DateTime).toIso8601String(),
        'archived_at': bookResult['archived_at'] != null
            ? (bookResult['archived_at'] as DateTime).toIso8601String()
            : null,
        'version': bookResult['version'] as int,
        'is_deleted': bookResult['is_deleted'] as bool,
      },
      'events': events,
      'notes': notes,
      'drawings': drawings,
    };
  }

  /// Get book metadata only (without events/notes/drawings)
  ///
  /// Useful for checking if a book exists or getting version info
  /// No longer filtered by device_id - any authenticated device can access
  /// Throws if book doesn't exist
  Future<Map<String, dynamic>> getBookMetadata(
    String bookUuid,
    String deviceId,
  ) async {
    final bookResult = await db.querySingle(
      '''
      SELECT
        book_uuid,
        name,
        created_at,
        updated_at,
        archived_at,
        version,
        is_deleted
      FROM books
      WHERE book_uuid = @bookUuid
      ''',
      parameters: {
        'bookUuid': bookUuid,
      },
    );

    if (bookResult == null) {
      throw Exception('Book not found: $bookUuid');
    }

    return {
      'book_uuid': bookResult['book_uuid'] as String,
      'name': bookResult['name'] as String,
      'created_at': (bookResult['created_at'] as DateTime).toIso8601String(),
      'updated_at': (bookResult['updated_at'] as DateTime).toIso8601String(),
      'archived_at': bookResult['archived_at'] != null
          ? (bookResult['archived_at'] as DateTime).toIso8601String()
          : null,
      'version': bookResult['version'] as int,
      'is_deleted': bookResult['is_deleted'] as bool,
    };
  }

  /// Add a device to the access list for a book
  Future<void> addDeviceAccess(String bookUuid, String deviceId, String accessType) async {
    try {
      await db.query(
        '''
        INSERT INTO book_device_access (book_uuid, device_id, access_type, created_at)
        VALUES (@bookUuid, @deviceId, @accessType, CURRENT_TIMESTAMP)
        ON CONFLICT (book_uuid, device_id) DO NOTHING
        ''',
        parameters: {
          'bookUuid': bookUuid,
          'deviceId': deviceId,
          'accessType': accessType,
        },
      );
      print('📝 Added device access: Book $bookUuid, Device $deviceId, Type: $accessType');
    } catch (e) {
      print('⚠️  Failed to add device access: $e');
      // Don't fail the operation if access tracking fails
    }
  }
}
