import 'package:flutter/foundation.dart';
import 'event_type.dart';

/// Event model - Individual appointment entry with minimal metadata as per PRD
class Event {
  /// Nullable: new events don't have ID until saved to database
  final int? id;
  final int bookId;
  final String name;
  /// Nullable: optional field per PRD
  final String? recordNumber;
  final List<EventType> eventTypes;
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

  Event({
    this.id,
    required this.bookId,
    required this.name,
    this.recordNumber,
    required List<EventType> eventTypes,
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
  }) : eventTypes = eventTypes.isEmpty
           ? throw ArgumentError('Event must have at least one event type')
           : eventTypes;

  Event copyWith({
    int? id,
    int? bookId,
    String? name,
    String? recordNumber,
    List<EventType>? eventTypes,
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
  }) {
    return Event(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      name: name ?? this.name,
      recordNumber: recordNumber ?? this.recordNumber,
      eventTypes: eventTypes ?? this.eventTypes,
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'name': name,
      'record_number': recordNumber,
      'event_types': EventType.toJsonList(eventTypes), // Convert list to JSON array string
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

    return Event(
      id: map['id']?.toInt(),
      bookId: map['book_id']?.toInt() ?? 0,
      name: map['name'] ?? '',
      recordNumber: map['record_number'],
      eventTypes: eventTypes,
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
    return 'Event(id: $id, bookId: $bookId, name: $name, recordNumber: $recordNumber, eventTypes: $eventTypes, startTime: $startTime, endTime: $endTime)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Event &&
        other.id == id &&
        other.bookId == bookId &&
        other.name == name &&
        other.recordNumber == recordNumber &&
        listEquals(other.eventTypes, eventTypes) &&
        other.startTime == startTime &&
        other.endTime == endTime &&
        other.isRemoved == isRemoved &&
        other.removalReason == removalReason &&
        other.originalEventId == originalEventId &&
        other.newEventId == newEventId &&
        other.isChecked == isChecked &&
        other.hasNote == hasNote;
  }

  @override
  int get hashCode {
    return Object.hash(id, bookId, name, recordNumber, Object.hashAll(eventTypes), startTime, endTime, isRemoved, removalReason, originalEventId, newEventId, isChecked, hasNote);
  }
}