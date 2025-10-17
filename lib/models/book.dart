/// Book model - Top-level container representing an independent schedule
class Book {
  final int? id;
  final String name;
  final DateTime createdAt;
  final DateTime? archivedAt;

  const Book({
    this.id,
    required this.name,
    required this.createdAt,
    this.archivedAt,
  });

  /// Create Book instance from database record
  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as int) * 1000,
      ),
      archivedAt: map['archived_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['archived_at'] * 1000)
          : null,
    );
  }

  /// Convert to database record
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'archived_at': archivedAt != null ? archivedAt!.millisecondsSinceEpoch ~/ 1000 : null,
    };
  }

  /// Create copy with modified properties
  Book copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    DateTime? archivedAt,
  }) {
    return Book(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      archivedAt: archivedAt ?? this.archivedAt,
    );
  }

  bool get isArchived => archivedAt != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Book &&
        other.id == id &&
        other.name == name &&
        other.createdAt == createdAt &&
        other.archivedAt == archivedAt;
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt, archivedAt);

  @override
  String toString() {
    return 'Book(id: $id, name: $name, createdAt: $createdAt, archivedAt: $archivedAt)';
  }
}