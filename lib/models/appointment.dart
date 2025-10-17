import 'dart:convert';

/// 手写笔触数据
class Stroke {
  final List<StrokePoint> points;
  final int color; // ARGB color value
  final double width;
  final DateTime timestamp;

  const Stroke({
    required this.points,
    required this.color,
    required this.width,
    required this.timestamp,
  });

  factory Stroke.fromMap(Map<String, dynamic> map) {
    return Stroke(
      points: (map['points'] as List<dynamic>)
          .map((p) => StrokePoint(p['dx'] as double, p['dy'] as double))
          .toList(),
      color: map['color'] as int,
      width: map['width'] as double,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
      'color': color,
      'width': width,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}

/// 手写点数据 - 避免与Flutter的Offset冲突
class StrokePoint {
  final double dx;
  final double dy;

  const StrokePoint(this.dx, this.dy);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StrokePoint && other.dx == dx && other.dy == dy;
  }

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'StrokePoint($dx, $dy)';
}

/// Appointment model - 预约事件，包含基本信息和手写笔记
class Appointment {
  final int? id;
  final int bookId;
  final DateTime startTime;
  final int duration; // 分钟，0表示开放式
  final String? name;
  final String? recordNumber;
  final String? type;
  final List<Stroke> noteStrokes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Appointment({
    this.id,
    required this.bookId,
    required this.startTime,
    this.duration = 0,
    this.name,
    this.recordNumber,
    this.type,
    this.noteStrokes = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// 结束时间 - 如果duration为0则返回null（开放式）
  DateTime? get endTime {
    if (duration == 0) return null;
    return startTime.add(Duration(minutes: duration));
  }

  /// 是否为开放式预约
  bool get isOpenEnded => duration == 0;

  /// 从数据库记录创建Appointment实例
  factory Appointment.fromMap(Map<String, dynamic> map) {
    List<Stroke> strokes = [];
    if (map['note_strokes'] != null && map['note_strokes'] is String) {
      try {
        final strokesData = jsonDecode(map['note_strokes'] as String) as List;
        strokes = strokesData
            .map((s) => Stroke.fromMap(s as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // 如果解析失败，使用空列表
        strokes = [];
      }
    }

    return Appointment(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      startTime: DateTime.fromMillisecondsSinceEpoch(
        (map['start_time'] as int) * 1000,
      ),
      duration: map['duration'] as int? ?? 0,
      name: map['name'] as String?,
      recordNumber: map['record_number'] as String?,
      type: map['type'] as String?,
      noteStrokes: strokes,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as int) * 1000,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] as int) * 1000,
      ),
    );
  }

  /// 转换为数据库记录
  Map<String, dynamic> toMap() {
    String strokesJson = '';
    if (noteStrokes.isNotEmpty) {
      strokesJson = jsonEncode(noteStrokes.map((s) => s.toMap()).toList());
    }

    return {
      if (id != null) 'id': id,
      'book_id': bookId,
      'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
      'duration': duration,
      'name': name,
      'record_number': recordNumber,
      'type': type,
      'note_strokes': strokesJson,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
    };
  }

  /// 创建副本，允许修改部分属性
  Appointment copyWith({
    int? id,
    int? bookId,
    DateTime? startTime,
    int? duration,
    String? name,
    String? recordNumber,
    String? type,
    List<Stroke>? noteStrokes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Appointment(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      name: name ?? this.name,
      recordNumber: recordNumber ?? this.recordNumber,
      type: type ?? this.type,
      noteStrokes: noteStrokes ?? this.noteStrokes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Appointment &&
        other.id == id &&
        other.bookId == bookId &&
        other.startTime == startTime &&
        other.duration == duration &&
        other.name == name &&
        other.recordNumber == recordNumber &&
        other.type == type &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      bookId,
      startTime,
      duration,
      name,
      recordNumber,
      type,
      createdAt,
      updatedAt,
    );
  }

  @override
  String toString() {
    return 'Appointment(id: $id, bookId: $bookId, name: $name, '
        'startTime: $startTime, duration: $duration)';
  }
}