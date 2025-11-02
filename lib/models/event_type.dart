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
}
