import 'dart:convert';

/// Charge item model - Individual charge entry with name, cost, and payment status
/// Can represent either a local charge item (id = null) or a synced person charge item (id = person_charge_items.id)
class ChargeItem {
  final int? id; // ID from person_charge_items table (null for legacy/unsynced items)
  final String itemName;
  final int cost; // Integer only, no decimals
  final bool isPaid;

  ChargeItem({
    this.id,
    required this.itemName,
    required this.cost,
    this.isPaid = false,
  });

  ChargeItem copyWith({
    int? id,
    String? itemName,
    int? cost,
    bool? isPaid,
  }) {
    return ChargeItem(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      cost: cost ?? this.cost,
      isPaid: isPaid ?? this.isPaid,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'item_name': itemName,
      'cost': cost,
      'is_paid': isPaid ? 1 : 0,
    };
  }

  factory ChargeItem.fromMap(Map<String, dynamic> map) {
    return ChargeItem(
      id: map['id']?.toInt(),
      itemName: map['item_name'] ?? '',
      cost: map['cost']?.toInt() ?? 0,
      isPaid: (map['is_paid'] ?? 0) == 1,
    );
  }

  /// Create a ChargeItem from a PersonChargeItem
  factory ChargeItem.fromPersonChargeItem(dynamic personChargeItem) {
    // Handle both PersonChargeItem objects and maps
    if (personChargeItem is Map<String, dynamic>) {
      return ChargeItem(
        id: personChargeItem['id']?.toInt(),
        itemName: personChargeItem['item_name'] ?? personChargeItem['itemName'] ?? '',
        cost: personChargeItem['cost']?.toInt() ?? 0,
        isPaid: (personChargeItem['is_paid'] ?? personChargeItem['isPaid'] ?? 0) == 1,
      );
    } else {
      // Assume it's a PersonChargeItem object
      return ChargeItem(
        id: personChargeItem.id,
        itemName: personChargeItem.itemName,
        cost: personChargeItem.cost,
        isPaid: personChargeItem.isPaid,
      );
    }
  }

  String toJson() => json.encode(toMap());

  factory ChargeItem.fromJson(String source) =>
      ChargeItem.fromMap(json.decode(source));

  /// Convert a list of ChargeItem to JSON array string for database storage
  static String toJsonList(List<ChargeItem> items) {
    return json.encode(items.map((item) => item.toMap()).toList());
  }

  /// Convert JSON array string from database to list of ChargeItem
  static List<ChargeItem> fromJsonList(String jsonString) {
    if (jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((item) => ChargeItem.fromMap(item)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  String toString() {
    return 'ChargeItem(itemName: $itemName, cost: $cost, isPaid: $isPaid)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChargeItem &&
        other.id == id &&
        other.itemName == itemName &&
        other.cost == cost &&
        other.isPaid == isPaid;
  }

  @override
  int get hashCode {
    return Object.hash(id, itemName, cost, isPaid);
  }
}
