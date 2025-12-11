import 'dart:convert';

enum StrokeType { pen, highlighter }

/// Note model - Multi-page handwriting note linked to a global record
///
/// - Notes are tied to record_uuid (not event)
/// - All events for the same record share one note
/// - One note per record
class Note {
  final int? id;
  final String recordUuid;
  final List<List<Stroke>> pages;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final String? lockedByDeviceId;
  final DateTime? lockedAt;

  const Note({
    this.id,
    required this.recordUuid,
    required this.pages,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
    this.lockedByDeviceId,
    this.lockedAt,
  });

  Note copyWith({
    int? id,
    String? recordUuid,
    List<List<Stroke>>? pages,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
    String? lockedByDeviceId,
    DateTime? lockedAt,
    bool clearLock = false,
  }) {
    return Note(
      id: id ?? this.id,
      recordUuid: recordUuid ?? this.recordUuid,
      pages: pages ?? this.pages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      lockedByDeviceId: clearLock ? null : (lockedByDeviceId ?? this.lockedByDeviceId),
      lockedAt: clearLock ? null : (lockedAt ?? this.lockedAt),
    );
  }

  int get pageCount => pages.length;
  bool get isEmpty => pages.every((page) => page.isEmpty);
  bool get isNotEmpty => pages.any((page) => page.isNotEmpty);
  bool get isLocked => lockedByDeviceId != null;

  List<Stroke> getPageStrokes(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pages.length) return [];
    return pages[pageIndex];
  }

  Note addPage() {
    return copyWith(
      pages: [...pages, []],
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Note updatePageStrokes(int pageIndex, List<Stroke> strokes) {
    if (pageIndex < 0 || pageIndex >= pages.length) return this;
    final updatedPages = List<List<Stroke>>.from(pages);
    updatedPages[pageIndex] = strokes;
    return copyWith(pages: updatedPages, updatedAt: DateTime.now().toUtc());
  }

  Note clearPage(int pageIndex) => updatePageStrokes(pageIndex, []);

  Map<String, dynamic> toMap() {
    final pagesData = pages.map((page) => page.map((s) => s.toMap()).toList()).toList();
    return {
      'id': id,
      'record_uuid': recordUuid,
      'pages_data': jsonEncode(pagesData),
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'version': version,
      'locked_by_device_id': lockedByDeviceId,
      'locked_at': lockedAt?.millisecondsSinceEpoch != null
          ? lockedAt!.millisecondsSinceEpoch ~/ 1000
          : null,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    List<List<Stroke>> pages = [];

    final pagesDataRaw = map['pages_data'];
    if (pagesDataRaw != null) {
      final pagesJson = pagesDataRaw is String ? jsonDecode(pagesDataRaw) as List : pagesDataRaw as List;
      pages = pagesJson.map((pageJson) {
        final pageList = pageJson as List;
        return pageList.map((s) => Stroke.fromMap(s)).toList();
      }).toList();
    }

    if (pages.isEmpty) pages = [[]];

    return Note(
      id: map['id'],
      recordUuid: map['record_uuid'] ?? '',
      pages: pages,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['created_at'] ?? 0) * 1000, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((map['updated_at'] ?? 0) * 1000, isUtc: true),
      version: map['version'] ?? 1,
      lockedByDeviceId: map['locked_by_device_id'],
      lockedAt: map['locked_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['locked_at'] * 1000, isUtc: true)
          : null,
    );
  }

  @override
  String toString() {
    final totalStrokes = pages.fold<int>(0, (sum, page) => sum + page.length);
    return 'Note(recordUuid: $recordUuid, pages: ${pages.length}, strokes: $totalStrokes)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Note && other.id == id && other.recordUuid == recordUuid;

  @override
  int get hashCode => Object.hash(id, recordUuid);
}

class Stroke {
  final List<StrokePoint> points;
  final double strokeWidth;
  final int color;
  final StrokeType strokeType;

  const Stroke({
    required this.points,
    this.strokeWidth = 2.0,
    this.color = 0xFF000000,
    this.strokeType = StrokeType.pen,
  });

  Stroke addPoint(StrokePoint point) {
    return Stroke(points: [...points, point], strokeWidth: strokeWidth, color: color, strokeType: strokeType);
  }

  Map<String, dynamic> toMap() {
    return {
      'points': points.map((p) => p.toMap()).toList(),
      'stroke_width': strokeWidth,
      'color': color,
      'stroke_type': strokeType.index,
    };
  }

  factory Stroke.fromMap(Map<String, dynamic> map) {
    final pointsList = map['points'] as List? ?? [];
    final strokeTypeIndex = map['stroke_type'] ?? 0;
    return Stroke(
      points: pointsList.map((p) => StrokePoint.fromMap(p)).toList(),
      strokeWidth: (map['stroke_width'] ?? 2.0).toDouble(),
      color: map['color'] ?? 0xFF000000,
      strokeType: strokeTypeIndex < StrokeType.values.length ? StrokeType.values[strokeTypeIndex] : StrokeType.pen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stroke && other.strokeWidth == strokeWidth && other.color == color && other.points.length == points.length;

  @override
  int get hashCode => Object.hash(strokeWidth, color, points.length);
}

class StrokePoint {
  final double dx;
  final double dy;
  final double pressure;

  const StrokePoint(this.dx, this.dy, {this.pressure = 1.0});

  Map<String, dynamic> toMap() => {'dx': dx, 'dy': dy, 'pressure': pressure};

  factory StrokePoint.fromMap(Map<String, dynamic> map) {
    return StrokePoint(
      (map['dx'] ?? 0.0).toDouble(),
      (map['dy'] ?? 0.0).toDouble(),
      pressure: (map['pressure'] ?? 1.0).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StrokePoint && other.dx == dx && other.dy == dy && other.pressure == pressure;

  @override
  int get hashCode => Object.hash(dx, dy, pressure);

  @override
  String toString() => 'StrokePoint($dx, $dy, $pressure)';
}
