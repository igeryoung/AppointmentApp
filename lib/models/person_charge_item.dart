import 'dart:convert';

/// Person Charge Item model - Charge items shared across all events for a person (name + record number)
/// Similar to person notes, charge items are tied to a person, not individual events
class PersonChargeItem {
  final int? id;
  final String personNameNormalized;
  final String recordNumberNormalized;
  final String itemName;
  final int cost; // Integer only, no decimals
  final bool isPaid;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  const PersonChargeItem({
    this.id,
    required this.personNameNormalized,
    required this.recordNumberNormalized,
    required this.itemName,
    required this.cost,
    this.isPaid = false,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
  });

  PersonChargeItem copyWith({
    int? id,
    String? personNameNormalized,
    String? recordNumberNormalized,
    String? itemName,
    int? cost,
    bool? isPaid,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
  }) {
    return PersonChargeItem(
      id: id ?? this.id,
      personNameNormalized: personNameNormalized ?? this.personNameNormalized,
      recordNumberNormalized: recordNumberNormalized ?? this.recordNumberNormalized,
      itemName: itemName ?? this.itemName,
      cost: cost ?? this.cost,
      isPaid: isPaid ?? this.isPaid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  /// Convert to database map (snake_case)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'person_name_normalized': personNameNormalized,
      'record_number_normalized': recordNumberNormalized,
      'item_name': itemName,
      'cost': cost,
      'is_paid': isPaid ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'version': version,
    };
  }

  /// Create from database map (handles both snake_case and camelCase)
  factory PersonChargeItem.fromMap(Map<String, dynamic> map) {
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

    return PersonChargeItem(
      id: map['id']?.toInt(),
      personNameNormalized: map['personNameNormalized'] ?? map['person_name_normalized'] ?? '',
      recordNumberNormalized: map['recordNumberNormalized'] ?? map['record_number_normalized'] ?? '',
      itemName: map['itemName'] ?? map['item_name'] ?? '',
      cost: map['cost']?.toInt() ?? 0,
      isPaid: (map['isPaid'] ?? map['is_paid'] ?? 0) == 1,
      createdAt: parseTimestamp(
        map['createdAt'] ?? map['created_at'],
        fallback: DateTime.now(),
      ) ?? DateTime.now(),
      updatedAt: parseTimestamp(
        map['updatedAt'] ?? map['updated_at'],
        fallback: DateTime.now(),
      ) ?? DateTime.now(),
      version: map['version']?.toInt() ?? 1,
    );
  }

  String toJson() => json.encode(toMap());

  factory PersonChargeItem.fromJson(String source) =>
      PersonChargeItem.fromMap(json.decode(source));

  /// Get person key for grouping (name + record number)
  String get personKey => '$personNameNormalized+$recordNumberNormalized';

  @override
  String toString() {
    return 'PersonChargeItem(id: $id, person: $personKey, item: $itemName, cost: $cost, isPaid: $isPaid)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PersonChargeItem &&
        other.id == id &&
        other.personNameNormalized == personNameNormalized &&
        other.recordNumberNormalized == recordNumberNormalized &&
        other.itemName == itemName &&
        other.cost == cost &&
        other.isPaid == isPaid;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      personNameNormalized,
      recordNumberNormalized,
      itemName,
      cost,
      isPaid,
    );
  }
}
