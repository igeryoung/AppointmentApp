/// Record model - Global identity for patients/cases
///
/// - record_number is globally unique when non-empty
/// - Empty record_number ('') is allowed for standalone records
/// - All events with same record_number share the same record_uuid
/// - Notes are tied to record_uuid (shared across all events for same record)
class Record {
  final String? recordUuid;
  final String recordNumber;
  final String? name;
  final String? phone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final bool isDeleted;

  const Record({
    this.recordUuid,
    required this.recordNumber,
    this.name,
    this.phone,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
    this.isDeleted = false,
  });

  Record copyWith({
    String? recordUuid,
    String? recordNumber,
    String? name,
    String? phone,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
    bool? isDeleted,
  }) {
    return Record(
      recordUuid: recordUuid ?? this.recordUuid,
      recordNumber: recordNumber ?? this.recordNumber,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  bool get isStandalone => recordNumber.isEmpty;
  bool get hasRecordNumber => recordNumber.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'record_uuid': recordUuid,
      'record_number': recordNumber,
      'name': name,
      'phone': phone,
      'created_at': createdAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      'version': version,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Record.fromMap(Map<String, dynamic> map) {
    return Record(
      recordUuid: map['record_uuid'],
      recordNumber: map['record_number'] ?? '',
      name: map['name'],
      phone: map['phone'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] ?? 0) * 1000,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] ?? 0) * 1000,
        isUtc: true,
      ),
      version: map['version'] ?? 1,
      isDeleted: (map['is_deleted'] ?? 0) == 1,
    );
  }

  @override
  String toString() => 'Record(recordUuid: $recordUuid, recordNumber: $recordNumber, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Record &&
          other.recordUuid == recordUuid &&
          other.recordNumber == recordNumber &&
          other.name == name &&
          other.phone == phone;

  @override
  int get hashCode => Object.hash(recordUuid, recordNumber, name, phone);
}
