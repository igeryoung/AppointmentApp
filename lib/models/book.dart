import 'package:uuid/uuid.dart';

/// Book model - Top-level container representing an independent schedule
class Book {
  final int? id;
  final String uuid;
  final String name;
  final DateTime createdAt;
  final DateTime? archivedAt;
  final bool isDirty;

  Book({
    this.id,
    String? uuid,
    required this.name,
    required this.createdAt,
    this.archivedAt,
    this.isDirty = false,
  }) : uuid = uuid ?? const Uuid().v4();

  /// Create Book instance from database record
  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as int?,
      uuid: map['book_uuid'] as String?,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as int) * 1000,
      ),
      archivedAt: map['archived_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['archived_at'] * 1000)
          : null,
      isDirty: (map['is_dirty'] as int? ?? 0) == 1,
    );
  }

  /// Convert to database record
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'book_uuid': uuid,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'archived_at': archivedAt != null ? archivedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'is_dirty': isDirty ? 1 : 0,
    };
  }

  /// Create copy with modified properties
  Book copyWith({
    int? id,
    String? uuid,
    String? name,
    DateTime? createdAt,
    DateTime? archivedAt,
    bool? isDirty,
  }) {
    return Book(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      archivedAt: archivedAt ?? this.archivedAt,
      isDirty: isDirty ?? this.isDirty,
    );
  }

  bool get isArchived => archivedAt != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Book &&
        other.id == id &&
        other.uuid == uuid &&
        other.name == name &&
        other.createdAt == createdAt &&
        other.archivedAt == archivedAt &&
        other.isDirty == isDirty;
  }

  @override
  int get hashCode => Object.hash(id, uuid, name, createdAt, archivedAt, isDirty);

  @override
  String toString() {
    return 'Book(id: $id, uuid: $uuid, name: $name, createdAt: $createdAt, archivedAt: $archivedAt, isDirty: $isDirty)';
  }
}