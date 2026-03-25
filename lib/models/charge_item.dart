import 'dart:convert';
import 'package:uuid/uuid.dart';

class ChargeItemPayment {
  final String id;
  final int amount;
  final DateTime paidDate;

  ChargeItemPayment({
    String? id,
    required this.amount,
    required DateTime paidDate,
  }) : id = id ?? const Uuid().v4(),
       paidDate = DateTime(paidDate.year, paidDate.month, paidDate.day);

  ChargeItemPayment copyWith({String? id, int? amount, DateTime? paidDate}) {
    return ChargeItemPayment(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      paidDate: paidDate ?? this.paidDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'amount': amount, 'paid_date': formatDate(paidDate)};
  }

  Map<String, dynamic> toServerMap() {
    return {'id': id, 'amount': amount, 'paidDate': formatDate(paidDate)};
  }

  factory ChargeItemPayment.fromMap(Map<String, dynamic> map) {
    return ChargeItemPayment(
      id: map['id']?.toString(),
      amount: map['amount']?.toInt() ?? 0,
      paidDate: parseDate(
        map['paidDate'] ?? map['paid_date'],
        fallback: DateTime.now(),
      ),
    );
  }

  static DateTime parseDate(dynamic value, {DateTime? fallback}) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        final parsed = DateTime.tryParse(trimmed);
        if (parsed != null) {
          return DateTime(parsed.year, parsed.month, parsed.day);
        }
        final parts = trimmed.split('-');
        if (parts.length == 3) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final day = int.tryParse(parts[2]);
          if (year != null && month != null && day != null) {
            return DateTime(year, month, day);
          }
        }
      }
    }
    final effectiveFallback = fallback ?? DateTime.now();
    return DateTime(
      effectiveFallback.year,
      effectiveFallback.month,
      effectiveFallback.day,
    );
  }

  static String formatDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '${normalized.year}-$month-$day';
  }

  static String toJsonList(List<ChargeItemPayment> items) {
    return json.encode(items.map((item) => item.toMap()).toList());
  }

  static List<ChargeItemPayment> fromDynamic(dynamic value) {
    if (value == null) {
      return const [];
    }
    if (value is String) {
      return fromJsonList(value);
    }
    if (value is List) {
      return value
          .whereType<Map>()
          .map(
            (item) => ChargeItemPayment.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false);
    }
    return const [];
  }

  static List<ChargeItemPayment> fromJsonList(String jsonString) {
    if (jsonString.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = json.decode(jsonString);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) => ChargeItemPayment.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

/// Charge item model - Individual charge entry linked to a record (person-level)
/// Can optionally be associated with a specific event for filtering
class ChargeItem {
  final String id; // UUID for sync
  final String recordUuid; // FK to records (required)
  final String? eventId; // Optional FK to events
  final String itemName;
  final int itemPrice; // Integer only, no decimals
  final int _receivedAmount; // Aggregated amount received/paid
  final List<ChargeItemPayment> paidItems;
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
    int receivedAmount = 0,
    List<ChargeItemPayment>? paidItems,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncedAt,
    this.version = 1,
    this.isDirty = false,
    this.isDeleted = false,
  }) : id = id ?? const Uuid().v4(),
       _receivedAmount = receivedAmount,
       paidItems = List.unmodifiable(_sortPaidItems(paidItems ?? const [])),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  static List<ChargeItemPayment> _sortPaidItems(List<ChargeItemPayment> items) {
    final sorted = List<ChargeItemPayment>.from(items);
    sorted.sort((a, b) {
      final dateCompare = a.paidDate.compareTo(b.paidDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  int get receivedAmount => paidItems.isNotEmpty
      ? paidItems.fold(0, (sum, item) => sum + item.amount)
      : _receivedAmount;

  /// Check if the item is fully paid
  bool get isPaid => receivedAmount >= itemPrice;

  /// Get remaining amount to be paid
  int get remainingAmount {
    final remaining = itemPrice - receivedAmount;
    return remaining < 0 ? 0 : remaining;
  }

  ChargeItem appendPaidItem(ChargeItemPayment payment) {
    final updatedPayments = [...paidItems, payment];
    final updatedReceivedAmount = updatedPayments.fold<int>(
      0,
      (sum, item) => sum + item.amount,
    );
    return copyWith(
      paidItems: updatedPayments,
      receivedAmount: updatedReceivedAmount,
    );
  }

  ChargeItem copyWith({
    String? id,
    String? recordUuid,
    String? eventId,
    bool clearEventId = false,
    String? itemName,
    int? itemPrice,
    int? receivedAmount,
    List<ChargeItemPayment>? paidItems,
    bool clearPaidItems = false,
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
      receivedAmount:
          receivedAmount ??
          (paidItems != null
              ? paidItems.fold<int>(0, (sum, item) => sum + item.amount)
              : this.receivedAmount),
      paidItems: clearPaidItems ? const [] : (paidItems ?? this.paidItems),
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
      'paid_items_json': ChargeItemPayment.toJsonList(paidItems),
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'synced_at': syncedAt != null
          ? syncedAt!.millisecondsSinceEpoch ~/ 1000
          : null,
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

    final parsedPaidItems = ChargeItemPayment.fromDynamic(
      map['paidItems'] ??
          map['paid_items'] ??
          map['paidItemsJson'] ??
          map['paid_items_json'],
    );

    return ChargeItem(
      id: map['id']?.toString() ?? const Uuid().v4(),
      recordUuid: map['recordUuid'] ?? map['record_uuid'] ?? '',
      eventId: map['eventId'] ?? map['event_id'],
      itemName: map['itemName'] ?? map['item_name'] ?? '',
      itemPrice: map['itemPrice']?.toInt() ?? map['item_price']?.toInt() ?? 0,
      receivedAmount:
          map['receivedAmount']?.toInt() ??
          map['received_amount']?.toInt() ??
          0,
      paidItems: parsedPaidItems,
      createdAt:
          parseTimestamp(
            map['createdAt'] ?? map['created_at'],
            fallback: DateTime.now(),
          ) ??
          DateTime.now(),
      updatedAt:
          parseTimestamp(
            map['updatedAt'] ?? map['updated_at'],
            fallback: DateTime.now(),
          ) ??
          DateTime.now(),
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
      'paidItems': paidItems.map((item) => item.toServerMap()).toList(),
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
    return 'ChargeItem(id: $id, recordUuid: $recordUuid, eventId: $eventId, itemName: $itemName, itemPrice: $itemPrice, receivedAmount: $receivedAmount, paidItems: ${paidItems.length})';
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
        other.receivedAmount == receivedAmount &&
        ChargeItemPayment.toJsonList(other.paidItems) ==
            ChargeItemPayment.toJsonList(paidItems);
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      recordUuid,
      eventId,
      itemName,
      itemPrice,
      receivedAmount,
      ChargeItemPayment.toJsonList(paidItems),
    );
  }
}
