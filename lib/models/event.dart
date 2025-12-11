import 'package:flutter/foundation.dart';
import 'event_type.dart';
import 'charge_item.dart';

/// Event model - Individual appointment linked to a global record
///
/// - Every event has a record_uuid (link to global record)
/// - title is the display name (typically person's name)
/// - recordNumber is denormalized for convenience
/// - Notes are accessed via record_uuid
class Event {
  final String? id;
  final String bookUuid;
  final String recordUuid;
  final String title;
  final String recordNumber;
  final List<EventType> eventTypes;
  final List<ChargeItem> chargeItems;
  final bool hasChargeItems;
  final DateTime startTime;
  final DateTime? endTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isRemoved;
  final String? removalReason;
  final String? originalEventId;
  final String? newEventId;
  final bool isChecked;
  final bool hasNote;
  final int version;

  Event({
    this.id,
    required this.bookUuid,
    required this.recordUuid,
    required this.title,
    this.recordNumber = '',
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
  })  : eventTypes = eventTypes.isEmpty
            ? throw ArgumentError('Event must have at least one event type')
            : eventTypes,
        chargeItems = chargeItems ?? [];

  Event copyWith({
    String? id,
    String? bookUuid,
    String? recordUuid,
    String? title,
    String? recordNumber,
    List<EventType>? eventTypes,
    List<ChargeItem>? chargeItems,
    bool? hasChargeItems,
    DateTime? startTime,
    DateTime? endTime,
    bool clearEndTime = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isRemoved,
    String? removalReason,
    String? originalEventId,
    String? newEventId,
    bool? isChecked,
    bool? hasNote,
    int? version,
  }) {
    return Event(
      id: id ?? this.id,
      bookUuid: bookUuid ?? this.bookUuid,
      recordUuid: recordUuid ?? this.recordUuid,
      title: title ?? this.title,
      recordNumber: recordNumber ?? this.recordNumber,
      eventTypes: eventTypes ?? this.eventTypes,
      chargeItems: chargeItems ?? this.chargeItems,
      hasChargeItems: hasChargeItems ?? this.hasChargeItems,
      startTime: startTime ?? this.startTime,
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isRemoved: isRemoved ?? this.isRemoved,
      removalReason: removalReason ?? this.removalReason,
      originalEventId: originalEventId ?? this.originalEventId,
      newEventId: newEventId ?? this.newEventId,
      isChecked: isChecked ?? this.isChecked,
      hasNote: hasNote ?? this.hasNote,
      version: version ?? this.version,
    );
  }

  bool get isOpenEnded => endTime == null;
  bool get isTimeChanged => originalEventId != null;
  bool get hasNewTime => newEventId != null;
  bool get hasRecordNumber => recordNumber.isNotEmpty;

  int? get durationInMinutes {
    if (endTime == null) return null;
    return endTime!.difference(startTime).inMinutes;
  }

  String get timeRangeDisplay {
    final startStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
    if (endTime == null) return startStr;
    final endStr = '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}';
    return '$startStr - $endStr';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_uuid': bookUuid,
      'record_uuid': recordUuid,
      'title': title,
      'record_number': recordNumber,
      'event_types': EventType.toJsonList(eventTypes),
      'has_charge_items': hasChargeItems ? 1 : 0,
      'start_time': startTime.toUtc().millisecondsSinceEpoch ~/ 1000,
      'end_time': endTime?.toUtc().millisecondsSinceEpoch != null
          ? endTime!.toUtc().millisecondsSinceEpoch ~/ 1000
          : null,
      'created_at': createdAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      'is_removed': isRemoved ? 1 : 0,
      'removal_reason': removalReason,
      'original_event_id': originalEventId,
      'new_event_id': newEventId,
      'is_checked': isChecked ? 1 : 0,
      'has_note': hasNote ? 1 : 0,
      'version': version,
    };
  }

  factory Event.fromMap(Map<String, dynamic> map) {
    List<EventType> eventTypes;
    if (map['event_types'] != null && map['event_types'].toString().isNotEmpty) {
      eventTypes = EventType.fromStringList(map['event_types']);
    } else {
      eventTypes = [EventType.other];
    }

    DateTime parseTime(dynamic value) {
      if (value == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true).toLocal();
      if (value is String) {
        final seconds = int.tryParse(value);
        if (seconds != null) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
    }

    return Event(
      id: map['id'],
      bookUuid: map['book_uuid'] ?? '',
      recordUuid: map['record_uuid'] ?? '',
      title: map['title'] ?? '',
      recordNumber: map['record_number'] ?? '',
      eventTypes: eventTypes,
      chargeItems: [],
      hasChargeItems: (map['has_charge_items'] ?? 0) == 1,
      startTime: parseTime(map['start_time']),
      endTime: map['end_time'] != null ? parseTime(map['end_time']) : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['created_at'] ?? 0) * 1000, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((map['updated_at'] ?? 0) * 1000, isUtc: true),
      isRemoved: (map['is_removed'] ?? 0) == 1,
      removalReason: map['removal_reason'],
      originalEventId: map['original_event_id'],
      newEventId: map['new_event_id'],
      isChecked: (map['is_checked'] ?? 0) == 1,
      hasNote: (map['has_note'] ?? 0) == 1,
      version: map['version'] ?? 1,
    );
  }

  @override
  String toString() => 'Event(id: $id, title: $title, recordUuid: $recordUuid, startTime: $startTime)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Event &&
          other.id == id &&
          other.bookUuid == bookUuid &&
          other.recordUuid == recordUuid &&
          other.title == title &&
          listEquals(other.eventTypes, eventTypes);

  @override
  int get hashCode => Object.hash(id, bookUuid, recordUuid, title, Object.hashAll(eventTypes));
}
