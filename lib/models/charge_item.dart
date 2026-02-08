import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Charge item model - Individual charge entry linked to a record (person-level)
/// Can optionally be associated with a specific event for filtering
class ChargeItem {
  final String id; // UUID for sync
  final String recordUuid; // FK to records (required)
  final String? eventId; // Optional FK to events
  final String itemName;
  final int itemPrice; // Integer only, no decimals
  final int receivedAmount; // Amount received/paid
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;
  final int version;
  final bool isDirty;
  final bool isDeleted;

  ChargeItem({
    String? id,
    required this.recordUuid,
    this.eventId,
    required this.itemName,
    required this.itemPrice,
    this.receivedAmount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncedAt,
    this.version = 1,
    this.isDirty = false,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Check if the item is fully paid
  bool get isPaid => receivedAmount >= itemPrice;

  /// Get remaining amount to be paid
  int get remainingAmount => itemPrice - receivedAmount;

  ChargeItem copyWith({
    String? id,
    String? recordUuid,
    String? eventId,
    bool clearEventId = false,
    String? itemName,
    int? itemPrice,
    int? receivedAmount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? syncedAt,
    bool clearSyncedAt = false,
    int? version,
    bool? isDirty,
    bool? isDeleted,
  }) {
    return ChargeItem(
      id: id ?? this.id,
      recordUuid: recordUuid ?? this.recordUuid,
      eventId: clearEventId ? null : (eventId ?? this.eventId),
      itemName: itemName ?? this.itemName,
      itemPrice: itemPrice ?? this.itemPrice,
      receivedAmount: receivedAmount ?? this.receivedAmount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: clearSyncedAt ? null : (syncedAt ?? this.syncedAt),
      version: version ?? this.version,
      isDirty: isDirty ?? this.isDirty,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  /// Convert to database map (snake_case)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'record_uuid': recordUuid,
      'event_id': eventId,
      'item_name': itemName,
      'item_price': itemPrice,
      'received_amount': receivedAmount,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'synced_at': syncedAt != null ? syncedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'version': version,
      'is_dirty': isDirty ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// Create from database map (handles both snake_case and camelCase)
  factory ChargeItem.fromMap(Map<String, dynamic> map) {
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

    return ChargeItem(
      id: map['id']?.toString() ?? const Uuid().v4(),
      recordUuid: map['recordUuid'] ?? map['record_uuid'] ?? '',
      eventId: map['eventId'] ?? map['event_id'],
      itemName: map['itemName'] ?? map['item_name'] ?? '',
      itemPrice: map['itemPrice']?.toInt() ?? map['item_price']?.toInt() ?? 0,
      receivedAmount: map['receivedAmount']?.toInt() ?? map['received_amount']?.toInt() ?? 0,
      createdAt: parseTimestamp(
        map['createdAt'] ?? map['created_at'],
        fallback: DateTime.now(),
      ) ?? DateTime.now(),
      updatedAt: parseTimestamp(
        map['updatedAt'] ?? map['updated_at'],
        fallback: DateTime.now(),
      ) ?? DateTime.now(),
      syncedAt: parseTimestamp(
        map['syncedAt'] ?? map['synced_at'],
        fallback: null,
      ),
      version: map['version']?.toInt() ?? 1,
      isDirty: (map['isDirty'] ?? map['is_dirty'] ?? 0) == 1,
      isDeleted: (map['isDeleted'] ?? map['is_deleted'] ?? 0) == 1,
    );
  }

  String toJson() => json.encode(toMap());

  factory ChargeItem.fromJson(String source) =>
      ChargeItem.fromMap(json.decode(source));

  /// Convert to server format (camelCase with ISO timestamps)
  Map<String, dynamic> toServerMap() {
    return {
      'id': id,
      'recordUuid': recordUuid,
      'eventId': eventId,
      'itemName': itemName,
      'itemPrice': itemPrice,
      'receivedAmount': receivedAmount,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'version': version,
      'isDeleted': isDeleted,
    };
  }

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
    return 'ChargeItem(id: $id, recordUuid: $recordUuid, eventId: $eventId, itemName: $itemName, itemPrice: $itemPrice, receivedAmount: $receivedAmount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChargeItem &&
        other.id == id &&
        other.recordUuid == recordUuid &&
        other.eventId == eventId &&
        other.itemName == itemName &&
        other.itemPrice == itemPrice &&
        other.receivedAmount == receivedAmount;
  }

  @override
  int get hashCode {
    return Object.hash(id, recordUuid, eventId, itemName, itemPrice, receivedAmount);
  }
}
