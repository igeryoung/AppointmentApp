import 'dart:convert';
import 'note.dart';

/// Schedule Drawing model - Handwriting overlay on schedule view
class ScheduleDrawing {
  /// Constant for 2-day view mode
  static const int VIEW_MODE_2DAY = 2;
  /// Constant for 3-day view mode
  static const int VIEW_MODE_3DAY = 1;

  final int? id;
  final int bookId;
  final DateTime date; // Reference date for the drawing
  /// ViewMode field (always 1 for 3-day view; kept for database compatibility)
  final int viewMode;
  final List<Stroke> strokes;
  final int version; // Optimistic locking version
  final DateTime createdAt;
  final DateTime updatedAt;

  const ScheduleDrawing({
    this.id,
    required this.bookId,
    required this.date,
    required this.viewMode,
    required this.strokes,
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  ScheduleDrawing copyWith({
    int? id,
    int? bookId,
    DateTime? date,
    int? viewMode,
    List<Stroke>? strokes,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScheduleDrawing(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      date: date ?? this.date,
      viewMode: viewMode ?? this.viewMode,
      strokes: strokes ?? this.strokes,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'date': date.millisecondsSinceEpoch ~/ 1000,
      'view_mode': viewMode,
      'strokes_data': jsonEncode(strokes.map((s) => s.toMap()).toList()),
      'version': version,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
    };
  }

  factory ScheduleDrawing.fromMap(Map<String, dynamic> map) {
    // Handle both camelCase (from server API) and snake_case (from local DB)
    List<Stroke> strokes = [];

    // Check for strokesData (server) or strokes_data (local DB)
    final strokesDataRaw = map['strokesData'] ?? map['strokes_data'];
    if (strokesDataRaw != null) {
      // Handle both pre-decoded list and JSON string
      final strokesJson = strokesDataRaw is String
          ? jsonDecode(strokesDataRaw) as List
          : strokesDataRaw as List;
      strokes = strokesJson.map((s) => Stroke.fromMap(s)).toList();
    }

    // Parse timestamps - handle both ISO strings (from server) and Unix seconds (from local DB)
    DateTime parseTimestamp(dynamic value, {required DateTime fallback}) {
      if (value == null) return fallback;
      if (value is String) {
        // ISO 8601 string from server
        return DateTime.parse(value);
      } else if (value is int) {
        // Unix seconds from local DB
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      return fallback;
    }

    return ScheduleDrawing(
      id: map['id']?.toInt(),
      bookId: (map['bookId'] ?? map['book_id'])?.toInt() ?? 0,
      date: parseTimestamp(
        map['date'],
        fallback: DateTime.now(),
      ),
      viewMode: (map['viewMode'] ?? map['view_mode'])?.toInt() ?? 0,
      strokes: strokes,
      version: map['version']?.toInt() ?? 1,
      createdAt: parseTimestamp(
        map['createdAt'] ?? map['created_at'],
        fallback: DateTime.now(),
      ),
      updatedAt: parseTimestamp(
        map['updatedAt'] ?? map['updated_at'],
        fallback: DateTime.now(),
      ),
    );
  }

  bool get isEmpty => strokes.isEmpty;
  bool get isNotEmpty => strokes.isNotEmpty;

  @override
  String toString() {
    return 'ScheduleDrawing(id: $id, bookId: $bookId, date: $date, viewMode: $viewMode, strokeCount: ${strokes.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScheduleDrawing &&
        other.id == id &&
        other.bookId == bookId &&
        other.date == date &&
        other.viewMode == viewMode;
  }

  @override
  int get hashCode {
    return Object.hash(id, bookId, date, viewMode);
  }
}
