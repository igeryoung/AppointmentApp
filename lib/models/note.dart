import 'dart:convert';

/// Note model - Handwriting-only note page linked to a single event as per PRD
class Note {
  final int? id;
  final int eventId;
  final List<Stroke> strokes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    this.id,
    required this.eventId,
    required this.strokes,
    required this.createdAt,
    required this.updatedAt,
  });

  Note copyWith({
    int? id,
    int? eventId,
    List<Stroke>? strokes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      strokes: strokes ?? this.strokes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    List<Stroke> strokes = [];
    if (map['strokes_data'] != null) {
      final strokesJson = jsonDecode(map['strokes_data']) as List;
      strokes = strokesJson.map((s) => Stroke.fromMap(s)).toList();
    }

    return Note(
      id: map['id']?.toInt(),
      eventId: map['event_id']?.toInt() ?? 0,
      strokes: strokes,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['created_at'] ?? 0) * 1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((map['updated_at'] ?? 0) * 1000),
    );
  }

  bool get isEmpty => strokes.isEmpty;
  bool get isNotEmpty => strokes.isNotEmpty;

  @override
  String toString() {
    return 'Note(id: $id, eventId: $eventId, strokeCount: ${strokes.length})';
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

  const Stroke({
    required this.points,
    this.strokeWidth = 2.0,
    this.color = 0xFF000000, // Default black
  });

  Stroke addPoint(StrokePoint point) {
    return Stroke(
      points: [...points, point],
      strokeWidth: strokeWidth,
      color: color,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'points': points.map((p) => p.toMap()).toList(),
      'stroke_width': strokeWidth,
      'color': color,
    };
  }

  factory Stroke.fromMap(Map<String, dynamic> map) {
    final pointsList = map['points'] as List? ?? [];
    return Stroke(
      points: pointsList.map((p) => StrokePoint.fromMap(p)).toList(),
      strokeWidth: map['stroke_width']?.toDouble() ?? 2.0,
      color: map['color']?.toInt() ?? 0xFF000000,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Stroke &&
        other.strokeWidth == strokeWidth &&
        other.color == color &&
        other.points.length == points.length;
  }

  @override
  int get hashCode {
    return Object.hash(strokeWidth, color, points.length);
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