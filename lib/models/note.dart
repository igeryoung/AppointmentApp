import 'dart:convert';

enum StrokeType { pen, highlighter }

/// Note model - Multi-page handwriting note linked to a global record
///
/// - Notes are tied to record_uuid (not event)
/// - All events for the same record share one note
/// - One note per record
class Note {
  final String? id;
  final String recordUuid;
  final List<List<Stroke>> pages;
  final Map<String, List<String>> erasedStrokesByEvent; // eventUuid -> list of erased stroke IDs
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final String? lockedByDeviceId;
  final DateTime? lockedAt;

  const Note({
    this.id,
    required this.recordUuid,
    required this.pages,
    this.erasedStrokesByEvent = const {},
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
    this.lockedByDeviceId,
    this.lockedAt,
  });

  Note copyWith({
    String? id,
    String? recordUuid,
    List<List<Stroke>>? pages,
    Map<String, List<String>>? erasedStrokesByEvent,
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
      erasedStrokesByEvent: erasedStrokesByEvent ?? this.erasedStrokesByEvent,
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

  /// Add erased stroke IDs for a specific event
  Note addErasedStrokes(String eventUuid, List<String> strokeIds) {
    if (strokeIds.isEmpty) return this;
    final updatedMap = Map<String, List<String>>.from(erasedStrokesByEvent);
    final existingList = updatedMap[eventUuid] ?? [];
    updatedMap[eventUuid] = [...existingList, ...strokeIds];
    return copyWith(erasedStrokesByEvent: updatedMap, updatedAt: DateTime.now().toUtc());
  }

  /// Get erased stroke IDs for a specific event
  List<String> getErasedStrokesForEvent(String eventUuid) {
    return erasedStrokesByEvent[eventUuid] ?? [];
  }

  Map<String, dynamic> toMap() {
    final pagesData = pages.map((page) => page.map((s) => s.toMap()).toList()).toList();
    // New format with version and erased strokes tracking
    final pagesDataJson = {
      'formatVersion': 2,
      'pages': pagesData,
      'erasedStrokesByEvent': erasedStrokesByEvent,
    };
    return {
      'id': id,
      'record_uuid': recordUuid,
      'pages_data': jsonEncode(pagesDataJson),
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'version': version,
      'locked_by_device_id': lockedByDeviceId,
      'locked_at': lockedAt?.millisecondsSinceEpoch != null
          ? lockedAt!.millisecondsSinceEpoch ~/ 1000
          : null,
    };
  }

  /// Parse result containing both pages and erasedStrokesByEvent
  static ({List<List<Stroke>> pages, Map<String, List<String>> erasedStrokesByEvent}) _parsePagesDataV2(
      dynamic pagesDataRaw) {
    if (pagesDataRaw == null) {
      return (pages: [], erasedStrokesByEvent: {});
    }

    final decoded = pagesDataRaw is String ? jsonDecode(pagesDataRaw) : pagesDataRaw;

    // Check if it's the new format (object with formatVersion) or old format (array)
    if (decoded is Map<String, dynamic>) {
      // New format v2
      final pagesJson = decoded['pages'] as List? ?? [];
      final erasedMap = decoded['erasedStrokesByEvent'] as Map<String, dynamic>? ?? {};

      final pages = pagesJson.map((pageJson) {
        final pageList = pageJson as List;
        return pageList.map((s) => Stroke.fromMap(s as Map<String, dynamic>)).toList();
      }).toList();

      final erasedStrokesByEvent = erasedMap.map((key, value) {
        final list = (value as List).map((e) => e as String).toList();
        return MapEntry(key, list);
      });

      return (pages: pages, erasedStrokesByEvent: erasedStrokesByEvent);
    } else if (decoded is List) {
      // Old format (just array of pages)
      final pages = decoded.map((pageJson) {
        final pageList = pageJson as List;
        return pageList.map((s) => Stroke.fromMap(s as Map<String, dynamic>)).toList();
      }).toList();

      return (pages: pages, erasedStrokesByEvent: {});
    }

    return (pages: [], erasedStrokesByEvent: {});
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    DateTime _parseTimestamp(dynamic value) {
      if (value == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      if (value is int || value is num) {
        final numVal = value as num;
        final millis = numVal > 1000000000000 ? numVal.toInt() : (numVal * 1000).toInt();
        return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        return parsed?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    int _parseInt(dynamic value, {int fallback = 1}) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? fallback;
    }

    final parsed = _parsePagesDataV2(map['pages_data']);
    var pages = parsed.pages;
    final erasedStrokesByEvent = parsed.erasedStrokesByEvent;

    if (pages.isEmpty) pages = [[]];

    return Note(
      id: map['id']?.toString(),
      recordUuid: map['record_uuid'] ?? '',
      pages: pages,
      erasedStrokesByEvent: erasedStrokesByEvent,
      createdAt: _parseTimestamp(map['created_at']),
      updatedAt: _parseTimestamp(map['updated_at']),
      version: _parseInt(map['version'], fallback: 1),
      lockedByDeviceId: map['locked_by_device_id'],
      lockedAt: map['locked_at'] != null ? _parseTimestamp(map['locked_at']) : null,
    );
  }

  factory Note.fromServer(Map<String, dynamic> map) {
    DateTime _parseServerTimestamp(dynamic value) {
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value).toUtc();
      }
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    final parsed = _parsePagesDataV2(map['pages_data']);
    var pages = parsed.pages;
    final erasedStrokesByEvent = parsed.erasedStrokesByEvent;
    if (pages.isEmpty) pages = [[]];

    return Note(
      id: map['id'] as String?,
      recordUuid: map['record_uuid'] as String? ?? '',
      pages: pages,
      erasedStrokesByEvent: erasedStrokesByEvent,
      createdAt: _parseServerTimestamp(map['created_at']),
      updatedAt: _parseServerTimestamp(map['updated_at']),
      version: map['version'] as int? ?? 1,
      lockedByDeviceId: map['locked_by_device_id'] as String?,
      lockedAt: map['locked_at'] != null ? _parseServerTimestamp(map['locked_at']) : null,
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
  final String? id; // Unique stroke ID for tracking
  final String? eventUuid; // Event that created this stroke
  final List<StrokePoint> points;
  final double strokeWidth;
  final int color;
  final StrokeType strokeType;

  const Stroke({
    this.id,
    this.eventUuid,
    required this.points,
    this.strokeWidth = 2.0,
    this.color = 0xFF000000,
    this.strokeType = StrokeType.pen,
  });

  Stroke addPoint(StrokePoint point) {
    return Stroke(
      id: id,
      eventUuid: eventUuid,
      points: [...points, point],
      strokeWidth: strokeWidth,
      color: color,
      strokeType: strokeType,
    );
  }

  Stroke copyWith({
    String? id,
    String? eventUuid,
    List<StrokePoint>? points,
    double? strokeWidth,
    int? color,
    StrokeType? strokeType,
  }) {
    return Stroke(
      id: id ?? this.id,
      eventUuid: eventUuid ?? this.eventUuid,
      points: points ?? this.points,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      color: color ?? this.color,
      strokeType: strokeType ?? this.strokeType,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (eventUuid != null) 'event_uuid': eventUuid,
      'points': points.map((p) => p.toMap()).toList(),
      'stroke_width': strokeWidth,
      'color': color,
      'stroke_type': strokeType.index,
    };
  }

  factory Stroke.fromMap(Map<String, dynamic> map) {
    final pointsList = map['points'] as List? ?? [];
    int _parseInt(dynamic value, {int fallback = 0}) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? fallback;
    }

    double _parseDouble(dynamic value, {double fallback = 0.0}) {
      if (value == null) return fallback;
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? fallback;
    }

    final strokeTypeIndex = _parseInt(map['stroke_type'], fallback: 0);
    return Stroke(
      id: map['id'] as String?,
      eventUuid: map['event_uuid'] as String?,
      points: pointsList.map((p) => StrokePoint.fromMap(p)).toList(),
      strokeWidth: _parseDouble(map['stroke_width'], fallback: 2.0),
      color: _parseInt(map['color'], fallback: 0xFF000000),
      strokeType: strokeTypeIndex < StrokeType.values.length ? StrokeType.values[strokeTypeIndex] : StrokeType.pen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stroke &&
          other.id == id &&
          other.eventUuid == eventUuid &&
          other.strokeWidth == strokeWidth &&
          other.color == color &&
          other.points.length == points.length;

  @override
  int get hashCode => Object.hash(id, eventUuid, strokeWidth, color, points.length);
}

class StrokePoint {
  final double dx;
  final double dy;
  final double pressure;

  const StrokePoint(this.dx, this.dy, {this.pressure = 1.0});

  Map<String, dynamic> toMap() => {'dx': dx, 'dy': dy, 'pressure': pressure};

  factory StrokePoint.fromMap(Map<String, dynamic> map) {
    double _parseDouble(dynamic value, {double fallback = 0.0}) {
      if (value == null) return fallback;
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? fallback;
    }

    return StrokePoint(
      _parseDouble(map['dx']),
      _parseDouble(map['dy']),
      pressure: _parseDouble(map['pressure'], fallback: 1.0),
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
