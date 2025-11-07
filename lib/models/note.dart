import 'dart:convert';

/// Stroke type enum - Defines the drawing tool type
enum StrokeType {
  pen,
  highlighter,
  // eraser is not stored as strokes, but included for completeness
}

/// Note model - Handwriting-only note page linked to a single event as per PRD
class Note {
  final int? id;
  final int eventId;
  final List<Stroke> strokes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDirty; // Indicates unsaved changes not synced to server

  const Note({
    this.id,
    required this.eventId,
    required this.strokes,
    required this.createdAt,
    required this.updatedAt,
    this.isDirty = false,
  });

  Note copyWith({
    int? id,
    int? eventId,
    List<Stroke>? strokes,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDirty,
  }) {
    return Note(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      strokes: strokes ?? this.strokes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDirty: isDirty ?? this.isDirty,
    );
  }

  Note addStroke(Stroke stroke) {
    return copyWith(
      strokes: [...strokes, stroke],
      updatedAt: DateTime.now(),
    );
  }

  Note removeLastStroke() {
    if (strokes.isEmpty) return this;
    return copyWith(
      strokes: strokes.sublist(0, strokes.length - 1),
      updatedAt: DateTime.now(),
    );
  }

  Note clearStrokes() {
    return copyWith(
      strokes: [],
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'event_id': eventId,
      'strokes_data': jsonEncode(strokes.map((s) => s.toMap()).toList()),
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'is_dirty': isDirty ? 1 : 0,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
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

    return Note(
      id: map['id']?.toInt(),
      eventId: (map['eventId'] ?? map['event_id'])?.toInt() ?? 0,
      strokes: strokes,
      createdAt: parseTimestamp(
        map['createdAt'] ?? map['created_at'],
        fallback: DateTime.now(),
      ),
      updatedAt: parseTimestamp(
        map['updatedAt'] ?? map['updated_at'],
        fallback: DateTime.now(),
      ),
      isDirty: (map['isDirty'] ?? map['is_dirty'] ?? 0) == 1,
    );
  }

  bool get isEmpty => strokes.isEmpty;
  bool get isNotEmpty => strokes.isNotEmpty;

  @override
  String toString() {
    return 'Note(id: $id, eventId: $eventId, strokeCount: ${strokes.length}, isDirty: $isDirty)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Note &&
        other.id == id &&
        other.eventId == eventId &&
        _listEquals(other.strokes, strokes);
  }

  @override
  int get hashCode {
    return Object.hash(id, eventId, strokes.length);
  }

  bool _listEquals<T>(List<T> list1, List<T> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }
}

/// Stroke model - Individual pen stroke with points and style
class Stroke {
  final List<StrokePoint> points;
  final double strokeWidth;
  final int color; // ARGB color value
  final StrokeType strokeType; // Tool type used for this stroke

  const Stroke({
    required this.points,
    this.strokeWidth = 2.0,
    this.color = 0xFF000000, // Default black
    this.strokeType = StrokeType.pen, // Default to pen for backward compatibility
  });

  Stroke addPoint(StrokePoint point) {
    return Stroke(
      points: [...points, point],
      strokeWidth: strokeWidth,
      color: color,
      strokeType: strokeType,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'points': points.map((p) => p.toMap()).toList(),
      'stroke_width': strokeWidth,
      'color': color,
      'stroke_type': strokeType.index, // Store as int for compatibility
    };
  }

  factory Stroke.fromMap(Map<String, dynamic> map) {
    final pointsList = map['points'] as List? ?? [];
    // Handle backward compatibility - if stroke_type is missing, default to pen
    final strokeTypeIndex = map['stroke_type']?.toInt() ?? 0;
    final strokeType = strokeTypeIndex < StrokeType.values.length
        ? StrokeType.values[strokeTypeIndex]
        : StrokeType.pen;

    return Stroke(
      points: pointsList.map((p) => StrokePoint.fromMap(p)).toList(),
      strokeWidth: map['stroke_width']?.toDouble() ?? 2.0,
      color: map['color']?.toInt() ?? 0xFF000000,
      strokeType: strokeType,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Stroke &&
        other.strokeWidth == strokeWidth &&
        other.color == color &&
        other.strokeType == strokeType &&
        other.points.length == points.length;
  }

  @override
  int get hashCode {
    return Object.hash(strokeWidth, color, strokeType, points.length);
  }
}

/// StrokePoint model - Individual point in a stroke
class StrokePoint {
  final double dx;
  final double dy;
  final double pressure; // For pressure-sensitive stylus

  const StrokePoint(
    this.dx,
    this.dy, {
    this.pressure = 1.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'dx': dx,
      'dy': dy,
      'pressure': pressure,
    };
  }

  factory StrokePoint.fromMap(Map<String, dynamic> map) {
    return StrokePoint(
      map['dx']?.toDouble() ?? 0.0,
      map['dy']?.toDouble() ?? 0.0,
      pressure: map['pressure']?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StrokePoint &&
        other.dx == dx &&
        other.dy == dy &&
        other.pressure == pressure;
  }

  @override
  int get hashCode {
    return Object.hash(dx, dy, pressure);
  }

  @override
  String toString() {
    return 'StrokePoint(dx: $dx, dy: $dy, pressure: $pressure)';
  }
}