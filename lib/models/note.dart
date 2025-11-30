import 'dart:convert';

/// Stroke type enum - Defines the drawing tool type
enum StrokeType {
  pen,
  highlighter,
  // eraser is not stored as strokes, but included for completeness
}

/// Note model - Multi-page handwriting note linked to a single event
class Note {
  final int? id;
  final String eventId; // Event UUID
  final List<List<Stroke>> pages; // Multi-page support: array of pages, each page contains strokes
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version; // Version number for optimistic locking (incremented on each update)
  final bool isDirty; // Indicates unsaved changes not synced to server
  final String? personNameNormalized; // Normalized person name for shared notes
  final String? recordNumberNormalized; // Normalized record number for shared notes
  final String? lockedByDeviceId; // Device ID that currently holds the lock
  final DateTime? lockedAt; // Timestamp when lock was acquired

  const Note({
    this.id,
    required this.eventId,
    required this.pages,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
    this.isDirty = false,
    this.personNameNormalized,
    this.recordNumberNormalized,
    this.lockedByDeviceId,
    this.lockedAt,
  });

  Note copyWith({
    int? id,
    String? eventId,
    List<List<Stroke>>? pages,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
    bool? isDirty,
    String? personNameNormalized,
    String? recordNumberNormalized,
    String? lockedByDeviceId,
    DateTime? lockedAt,
  }) {
    return Note(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      pages: pages ?? this.pages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      isDirty: isDirty ?? this.isDirty,
      personNameNormalized: personNameNormalized ?? this.personNameNormalized,
      recordNumberNormalized: recordNumberNormalized ?? this.recordNumberNormalized,
      lockedByDeviceId: lockedByDeviceId ?? this.lockedByDeviceId,
      lockedAt: lockedAt ?? this.lockedAt,
    );
  }

  // Multi-page helper methods
  int get pageCount => pages.length;

  List<Stroke> getPageStrokes(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pages.length) return [];
    return pages[pageIndex];
  }

  Note addPage() {
    return copyWith(
      pages: [...pages, []],
      updatedAt: DateTime.now(),
    );
  }

  Note updatePageStrokes(int pageIndex, List<Stroke> strokes) {
    if (pageIndex < 0 || pageIndex >= pages.length) return this;
    final updatedPages = List<List<Stroke>>.from(pages);
    updatedPages[pageIndex] = strokes;
    return copyWith(
      pages: updatedPages,
      updatedAt: DateTime.now(),
    );
  }

  Note clearPage(int pageIndex) {
    return updatePageStrokes(pageIndex, []);
  }

  // Legacy methods for backward compatibility (deprecated)
  @Deprecated('Use pages instead')
  List<Stroke> get strokes => pages.isNotEmpty ? pages[0] : [];

  @Deprecated('Use addPage and updatePageStrokes instead')
  Note addStroke(Stroke stroke) {
    if (pages.isEmpty) {
      return copyWith(pages: [[stroke]], updatedAt: DateTime.now());
    }
    final firstPage = List<Stroke>.from(pages[0]);
    firstPage.add(stroke);
    return updatePageStrokes(0, firstPage);
  }

  @Deprecated('Use updatePageStrokes instead')
  Note clearStrokes() {
    if (pages.isEmpty) return this;
    return clearPage(0);
  }

  Map<String, dynamic> toMap() {
    final lockedAtMs = lockedAt?.millisecondsSinceEpoch;
    // Serialize pages as array of arrays
    final pagesData = pages.map((page) =>
      page.map((stroke) => stroke.toMap()).toList()
    ).toList();

    return {
      'id': id,
      'event_id': eventId,
      'pages_data': jsonEncode(pagesData),
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'version': version,
      'is_dirty': isDirty ? 1 : 0,
      'person_name_normalized': personNameNormalized,
      'record_number_normalized': recordNumberNormalized,
      'locked_by_device_id': lockedByDeviceId,
      'locked_at': lockedAtMs != null ? lockedAtMs ~/ 1000 : null,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    // Handle both camelCase (from server API) and snake_case (from local DB)
    List<List<Stroke>> pages = [];

    // Parse timestamps - handle both ISO strings (from server) and Unix seconds (from local DB)
    DateTime? parseTimestamp(dynamic value, {required DateTime? fallback}) {
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

    // Check for new multi-page format: pagesData (server) or pages_data (local DB)
    final pagesDataRaw = map['pagesData'] ?? map['pages_data'];
    if (pagesDataRaw != null) {
      // Handle both pre-decoded list and JSON string
      final pagesJson = pagesDataRaw is String
          ? jsonDecode(pagesDataRaw) as List
          : pagesDataRaw as List;

      // Parse pages: array of arrays
      pages = pagesJson.map((pageJson) {
        final pageList = pageJson as List;
        return pageList.map((s) => Stroke.fromMap(s)).toList();
      }).toList();
    } else {
      // Backward compatibility: Check for old single-page format (strokesData/strokes_data)
      final strokesDataRaw = map['strokesData'] ?? map['strokes_data'];
      if (strokesDataRaw != null) {
        final strokesJson = strokesDataRaw is String
            ? jsonDecode(strokesDataRaw) as List
            : strokesDataRaw as List;
        final strokes = strokesJson.map((s) => Stroke.fromMap(s)).toList();
        // Migrate: wrap single page in array
        pages = [strokes];
      }
    }

    // Ensure at least one empty page
    if (pages.isEmpty) {
      pages = [[]];
    }

    return Note(
      id: map['id']?.toInt(),
      eventId: (map['eventId'] ?? map['event_id']) as String? ?? '',
      pages: pages,
      createdAt: parseTimestamp(
        map['createdAt'] ?? map['created_at'],
        fallback: DateTime.now(),
      ) ?? DateTime.now(),
      updatedAt: parseTimestamp(
        map['updatedAt'] ?? map['updated_at'],
        fallback: DateTime.now(),
      ) ?? DateTime.now(),
      version: (map['version'] ?? 1) is int ? (map['version'] ?? 1) : int.tryParse(map['version'].toString()) ?? 1,
      isDirty: (map['isDirty'] ?? map['is_dirty'] ?? 0) == 1,
      personNameNormalized: map['personNameNormalized'] ?? map['person_name_normalized'],
      recordNumberNormalized: map['recordNumberNormalized'] ?? map['record_number_normalized'],
      lockedByDeviceId: map['lockedByDeviceId'] ?? map['locked_by_device_id'],
      lockedAt: parseTimestamp(
        map['lockedAt'] ?? map['locked_at'],
        fallback: null,
      ),
    );
  }

  bool get isEmpty => pages.every((page) => page.isEmpty);
  bool get isNotEmpty => pages.any((page) => page.isNotEmpty);

  @override
  String toString() {
    final totalStrokes = pages.fold<int>(0, (sum, page) => sum + page.length);
    return 'Note(id: $id, eventId: $eventId, pageCount: ${pages.length}, totalStrokes: $totalStrokes, version: $version, isDirty: $isDirty, personKey: $personNameNormalized+$recordNumberNormalized, locked: ${lockedByDeviceId != null})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Note &&
        other.id == id &&
        other.eventId == eventId &&
        _pagesEquals(other.pages, pages);
  }

  @override
  int get hashCode {
    return Object.hash(id, eventId, pages.length);
  }

  bool _pagesEquals(List<List<Stroke>> pages1, List<List<Stroke>> pages2) {
    if (pages1.length != pages2.length) return false;
    for (int i = 0; i < pages1.length; i++) {
      if (!_listEquals(pages1[i], pages2[i])) return false;
    }
    return true;
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