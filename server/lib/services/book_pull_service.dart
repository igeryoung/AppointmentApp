import 'dart:convert';
import 'package:postgres/postgres.dart';
import '../database/connection.dart';

/// Service for pulling books from server to local device
///
/// Supports one-way sync (Server → Local) with complete book data
class BookPullService {
  final DatabaseConnection db;

  BookPullService(this.db);

  /// Format timestamps that represent user-facing schedule times.
  /// Always returns a UTC ISO string so clients don't double-apply timezone offsets.
  String _formatUserTimestamp(DateTime dateTime) {
    final utc = dateTime.isUtc
        ? dateTime
        : DateTime.utc(
            dateTime.year,
            dateTime.month,
            dateTime.day,
            dateTime.hour,
            dateTime.minute,
            dateTime.second,
            dateTime.millisecond,
            dateTime.microsecond,
          );
    return utc.toIso8601String();
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return value == true;
  }

  String _normalizeEventTypes(dynamic value) {
    if (value == null) return '[]';
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? '[]' : value;
    }
    try {
      return jsonEncode(value);
    } catch (_) {
      return '[]';
    }
  }

  String _primaryEventType(String eventTypes) {
    try {
      final decoded = jsonDecode(eventTypes);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.first.toString();
      }
    } catch (_) {
      // Fall through to default.
    }
    return 'other';
  }

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
        'created_at': (row['created_at'] as DateTime).toUtc().toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toUtc().toIso8601String(),
        'archived_at': row['archived_at'] != null
            ? (row['archived_at'] as DateTime).toUtc().toIso8601String()
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
        e.id,
        e.book_uuid,
        e.record_uuid,
        e.title,
        r.name,
        r.record_number,
        r.phone,
        e.event_types,
        e.has_charge_items,
        e.is_checked,
        e.has_note,
        e.start_time,
        e.end_time,
        e.created_at,
        e.updated_at,
        e.is_removed,
        e.removal_reason,
        e.original_event_id,
        e.new_event_id,
        e.version,
        e.is_deleted
      FROM events e
      LEFT JOIN records r ON r.record_uuid = e.record_uuid
      WHERE e.book_uuid = @bookUuid
      ORDER BY e.start_time ASC
      ''',
      parameters: {'bookUuid': bookUuid},
    );

    final events = eventsResults.map((row) {
      final eventTypes = _normalizeEventTypes(row['event_types']);
      return {
        'id': row['id'] as String,
        'book_uuid': row['book_uuid'] as String,
        'record_uuid': row['record_uuid'] as String,
        'title': row['title'] as String,
        'name': (row['name'] as String?) ?? (row['title'] as String),
        'record_number': row['record_number'] as String?,
        'phone': row['phone'] as String?,
        'event_type': _primaryEventType(eventTypes),
        'event_types': eventTypes,
        'has_charge_items': _toBool(row['has_charge_items']),
        'is_checked': _toBool(row['is_checked']),
        'has_note': _toBool(row['has_note']),
        'start_time': _formatUserTimestamp(row['start_time'] as DateTime),
        'end_time': row['end_time'] != null
            ? _formatUserTimestamp(row['end_time'] as DateTime)
            : null,
        'created_at': (row['created_at'] as DateTime).toUtc().toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toUtc().toIso8601String(),
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
      SELECT DISTINCT
        n.id,
        n.record_uuid,
        n.pages_data,
        n.created_at,
        n.updated_at,
        n.version,
        n.is_deleted
      FROM notes n
      INNER JOIN events e ON n.record_uuid = e.record_uuid
      WHERE e.book_uuid = @bookUuid
      ORDER BY n.created_at ASC
      ''',
      parameters: {'bookUuid': bookUuid},
    );

    final notes = notesResults.map((row) {
      return {
        'id': row['id'] as String,
        'record_uuid': row['record_uuid'] as String,
        'pages_data': row['pages_data'] as String?,
        'created_at': (row['created_at'] as DateTime).toUtc().toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toUtc().toIso8601String(),
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
        'date': _formatUserTimestamp(row['date'] as DateTime),
        'view_mode': row['view_mode'] as int,
        'strokes_data': row['strokes_data'] as String?,
        'created_at': (row['created_at'] as DateTime).toUtc().toIso8601String(),
        'updated_at': (row['updated_at'] as DateTime).toUtc().toIso8601String(),
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
        'created_at': (bookResult['created_at'] as DateTime).toUtc().toIso8601String(),
        'updated_at': (bookResult['updated_at'] as DateTime).toUtc().toIso8601String(),
        'archived_at': bookResult['archived_at'] != null
            ? (bookResult['archived_at'] as DateTime).toUtc().toIso8601String()
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
      'created_at': (bookResult['created_at'] as DateTime).toUtc().toIso8601String(),
      'updated_at': (bookResult['updated_at'] as DateTime).toUtc().toIso8601String(),
      'archived_at': bookResult['archived_at'] != null
          ? (bookResult['archived_at'] as DateTime).toUtc().toIso8601String()
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
