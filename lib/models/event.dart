import 'package:flutter/foundation.dart';
import 'event_type.dart';
import 'charge_item.dart';

/// Event model - Individual appointment entry with minimal metadata as per PRD
class Event {
  /// Nullable: new events don't have ID until saved to database
  final int? id;
  final int bookId;
  final String name;
  /// Nullable: optional field per PRD
  final String? recordNumber;
  /// Nullable: optional phone number
  final String? phone;
  final List<EventType> eventTypes;
  /// Legacy field - kept for detail view compatibility where charge items are loaded explicitly
  final List<ChargeItem> chargeItems;
  /// Efficient flag to indicate if this event has charge items (loaded from person_charge_items table)
  final bool hasChargeItems;
  final DateTime startTime;
  /// Nullable: open-ended events have no end time (as per PRD)
  final DateTime? endTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isRemoved; // Soft removal flag
  /// Nullable: only set when event is removed
  final String? removalReason;
  /// Nullable: only set for time-change related events
  final int? originalEventId; // Reference to original event for time changes
  /// Nullable: only set for time-change related events
  final int? newEventId; // Reference to new event if this event's time was changed
  final bool isChecked; // Marks event as completed/checked
  final bool hasNote; // Indicates if this event has a handwriting note with strokes
  final int version; // Version number for optimistic locking during server sync
  final bool isDirty; // Marks event as needing sync to server

  Event({
    this.id,
    required this.bookId,
    required this.name,
    this.recordNumber,
    this.phone,
    required List<EventType> eventTypes,
    List<ChargeItem>? chargeItems,
    this.hasChargeItems = false,
    required this.startTime,
    this.endTime,
    required this.createdAt,
    required this.updatedAt,
    this.isRemoved = false,
    this.removalReason,
    this.originalEventId,
    this.newEventId,
    this.isChecked = false,
    this.hasNote = false,
    this.version = 1,
    this.isDirty = true,
  }) : eventTypes = eventTypes.isEmpty
           ? throw ArgumentError('Event must have at least one event type')
           : eventTypes,
       chargeItems = chargeItems ?? [];

  Event copyWith({
    int? id,
    int? bookId,
    String? name,
    String? recordNumber,
    String? phone,
    List<EventType>? eventTypes,
    List<ChargeItem>? chargeItems,
    bool? hasChargeItems,
    DateTime? startTime,
    DateTime? endTime,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isRemoved,
    String? removalReason,
    int? originalEventId,
    int? newEventId,
    bool? isChecked,
    bool? hasNote,
    int? version,
    bool? isDirty,
  }) {
    return Event(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      name: name ?? this.name,
      recordNumber: recordNumber ?? this.recordNumber,
      phone: phone ?? this.phone,
      eventTypes: eventTypes ?? this.eventTypes,
      chargeItems: chargeItems ?? this.chargeItems,
      hasChargeItems: hasChargeItems ?? this.hasChargeItems,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isRemoved: isRemoved ?? this.isRemoved,
      removalReason: removalReason ?? this.removalReason,
      originalEventId: originalEventId ?? this.originalEventId,
      newEventId: newEventId ?? this.newEventId,
      isChecked: isChecked ?? this.isChecked,
      hasNote: hasNote ?? this.hasNote,
      version: version ?? this.version,
      isDirty: isDirty ?? this.isDirty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'name': name,
      'record_number': recordNumber,
      'phone': phone,
      'event_types': EventType.toJsonList(eventTypes), // Convert list to JSON array string
      'has_charge_items': hasChargeItems ? 1 : 0,
      'start_time': startTime.millisecondsSinceEpoch ~/ 1000,
      'end_time': endTime != null ? endTime!.millisecondsSinceEpoch ~/ 1000 : null,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'is_removed': isRemoved ? 1 : 0,
      'removal_reason': removalReason,
      'original_event_id': originalEventId,
      'new_event_id': newEventId,
      'is_checked': isChecked ? 1 : 0,
      'has_note': hasNote ? 1 : 0,
      'version': version,
      'is_dirty': isDirty ? 1 : 0,
    };
  }

  factory Event.fromMap(Map<String, dynamic> map) {
    // Backward compatibility: Check for new 'event_types' field first,
    // then fall back to old 'event_type' field
    List<EventType> eventTypes;
    if (map['event_types'] != null && map['event_types'].toString().isNotEmpty) {
      // New format: JSON array string
      eventTypes = EventType.fromStringList(map['event_types']);
    } else if (map['event_type'] != null && map['event_type'].toString().isNotEmpty) {
      // Old format: single string - wrap in list
      eventTypes = [EventType.fromString(map['event_type'])];
    } else {
      // Fallback to 'other' type if no type specified
      eventTypes = [EventType.other];
    }

    // chargeItems is kept empty by default - loaded separately in detail view from person_charge_items table
    // This keeps list queries lightweight
    List<ChargeItem> chargeItems = [];

    return Event(
      id: map['id']?.toInt(),
      bookId: map['book_id']?.toInt() ?? 0,
      name: map['name'] ?? '',
      recordNumber: map['record_number'],
      phone: map['phone'],
      eventTypes: eventTypes,
      chargeItems: chargeItems,
      hasChargeItems: (map['has_charge_items'] ?? 0) == 1,
      startTime: DateTime.fromMillisecondsSinceEpoch((map['start_time'] ?? 0) * 1000),
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'] * 1000)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['created_at'] ?? 0) * 1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((map['updated_at'] ?? 0) * 1000),
      isRemoved: (map['is_removed'] ?? 0) == 1,
      removalReason: map['removal_reason'],
      originalEventId: map['original_event_id']?.toInt(),
      newEventId: map['new_event_id']?.toInt(),
      isChecked: (map['is_checked'] ?? 0) == 1,
      hasNote: (map['has_note'] ?? 0) == 1,
      version: map['version']?.toInt() ?? 1,
      isDirty: (map['is_dirty'] ?? 0) == 1,
    );
  }

  /// Returns true if this is an open-ended event (no end time)
  bool get isOpenEnded => endTime == null;

  /// Returns true if this event is a time-changed version of another event
  bool get isTimeChanged => originalEventId != null;

  /// Returns true if this event's time was changed (moved to a new event)
  bool get hasNewTime => newEventId != null;

  /// Returns the duration in minutes, or null if open-ended
  int? get durationInMinutes {
    if (endTime == null) return null;
    return endTime!.difference(startTime).inMinutes;
  }

  /// Returns a display string for the time range
  String get timeRangeDisplay {
    final startStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
    if (endTime == null) {
      return startStr;
    }
    final endStr = '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}';
    return '$startStr - $endStr';
  }

  @override
  String toString() {
    return 'Event(id: $id, bookId: $bookId, name: $name, recordNumber: $recordNumber, phone: $phone, eventTypes: $eventTypes, hasChargeItems: $hasChargeItems, startTime: $startTime, endTime: $endTime, version: $version, isDirty: $isDirty)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Event &&
        other.id == id &&
        other.bookId == bookId &&
        other.name == name &&
        other.recordNumber == recordNumber &&
        other.phone == phone &&
        listEquals(other.eventTypes, eventTypes) &&
        other.hasChargeItems == hasChargeItems &&
        other.startTime == startTime &&
        other.endTime == endTime &&
        other.isRemoved == isRemoved &&
        other.removalReason == removalReason &&
        other.originalEventId == originalEventId &&
        other.newEventId == newEventId &&
        other.isChecked == isChecked &&
        other.hasNote == hasNote &&
        other.version == version &&
        other.isDirty == isDirty;
  }

  @override
  int get hashCode {
    return Object.hash(id, bookId, name, recordNumber, phone, Object.hashAll(eventTypes), hasChargeItems, startTime, endTime, isRemoved, removalReason, originalEventId, newEventId, isChecked, hasNote, version);
  }
}