import 'dart:convert';

/// Event type enumeration for type-safe event classification
///
/// Supported types:
/// - consultation: Regular consultations (門診)
/// - surgery: Surgical procedures (手術)
/// - followUp: Follow-up appointments (復診)
/// - emergency: Emergency cases (急診)
/// - checkUp: Health check-ups (健檢)
/// - treatment: Treatment sessions (治療)
/// - other: Unspecified or custom types
enum EventType {
  consultation,
  surgery,
  followUp,
  emergency,
  checkUp,
  treatment,
  other;

  /// Convert EventType to string for database storage
  String toJson() => name;

  /// Parse string to EventType
  /// Returns EventType.other for unknown values
  static EventType fromString(String value) {
    try {
      return EventType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => EventType.other,
      );
    } catch (e) {
      return EventType.other;
    }
  }

  /// Check if this is a valid medical event type (not 'other')
  bool get isValid => this != EventType.other;

  /// Convert list of EventTypes to JSON array string for database storage
  /// Automatically sorts alphabetically before conversion
  static String toJsonList(List<EventType> types) {
    if (types.isEmpty) {
      throw ArgumentError('Event types list cannot be empty');
    }
    final sorted = sortAlphabetically(types);
    final stringList = sorted.map((t) => t.toJson()).toList();
    return jsonEncode(stringList);
  }

  /// Parse JSON array string to list of EventTypes
  /// Returns list with EventType.other for invalid entries
  static List<EventType> fromStringList(String jsonStr) {
    try {
      if (jsonStr.isEmpty) {
        return [EventType.other];
      }
      final List<dynamic> parsed = jsonDecode(jsonStr);
      final types = parsed.map((s) => EventType.fromString(s.toString())).toList();
      return types.isEmpty ? [EventType.other] : types;
    } catch (e) {
      return [EventType.other];
    }
  }

  /// Sort event types alphabetically by their name
  /// Ensures consistent ordering for display and color assignment
  static List<EventType> sortAlphabetically(List<EventType> types) {
    final sorted = List<EventType>.from(types);
    sorted.sort((a, b) => a.name.compareTo(b.name));
    return sorted;
  }
}
