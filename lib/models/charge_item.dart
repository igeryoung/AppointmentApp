import 'dart:convert';

/// Charge item model - Individual charge entry with name, cost, and payment status
class ChargeItem {
  final String itemName;
  final int cost; // Integer only, no decimals
  final bool isPaid;

  ChargeItem({
    required this.itemName,
    required this.cost,
    this.isPaid = false,
  });

  ChargeItem copyWith({
    String? itemName,
    int? cost,
    bool? isPaid,
  }) {
    return ChargeItem(
      itemName: itemName ?? this.itemName,
      cost: cost ?? this.cost,
      isPaid: isPaid ?? this.isPaid,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'item_name': itemName,
      'cost': cost,
      'is_paid': isPaid ? 1 : 0,
    };
  }

  factory ChargeItem.fromMap(Map<String, dynamic> map) {
    return ChargeItem(
      itemName: map['item_name'] ?? '',
      cost: map['cost']?.toInt() ?? 0,
      isPaid: (map['is_paid'] ?? 0) == 1,
    );
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
        other.itemName == itemName &&
        other.cost == cost &&
        other.isPaid == isPaid;
  }

  @override
  int get hashCode {
    return Object.hash(itemName, cost, isPaid);
  }
}
