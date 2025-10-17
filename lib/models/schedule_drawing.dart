import 'dart:convert';
import 'note.dart';

/// Schedule Drawing model - Handwriting overlay on schedule view
class ScheduleDrawing {
  final int? id;
  final int bookId;
  final DateTime date; // Reference date for the drawing
  final int viewMode; // 0: Day, 1: 3-Day, 2: Week
  final List<Stroke> strokes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ScheduleDrawing({
    this.id,
    required this.bookId,
    required this.date,
    required this.viewMode,
    required this.strokes,
    required this.createdAt,
    required this.updatedAt,
  });

  ScheduleDrawing copyWith({
    int? id,
    int? bookId,
    DateTime? date,
    int? viewMode,
    List<Stroke>? strokes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScheduleDrawing(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      date: date ?? this.date,
      viewMode: viewMode ?? this.viewMode,
      strokes: strokes ?? this.strokes,
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
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
    };
  }

  factory ScheduleDrawing.fromMap(Map<String, dynamic> map) {
    List<Stroke> strokes = [];
    if (map['strokes_data'] != null) {
      final strokesJson = jsonDecode(map['strokes_data']) as List;
      strokes = strokesJson.map((s) => Stroke.fromMap(s)).toList();
    }

    return ScheduleDrawing(
      id: map['id']?.toInt(),
      bookId: map['book_id']?.toInt() ?? 0,
      date: DateTime.fromMillisecondsSinceEpoch((map['date'] ?? 0) * 1000),
      viewMode: map['view_mode']?.toInt() ?? 0,
      strokes: strokes,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['created_at'] ?? 0) * 1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((map['updated_at'] ?? 0) * 1000),
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
