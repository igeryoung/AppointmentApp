import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';

Event makeEvent({
  required String id,
  required String bookUuid,
  required String recordUuid,
  String title = 'Test Event',
  String recordNumber = 'R-001',
  List<EventType>? eventTypes,
  DateTime? startTime,
  DateTime? endTime,
  DateTime? createdAt,
  DateTime? updatedAt,
  bool isRemoved = false,
  String? removalReason,
  String? originalEventId,
  String? newEventId,
  bool isChecked = false,
  bool hasNote = false,
  int version = 1,
}) {
  final baseStart = startTime ?? DateTime.utc(2026, 1, 1, 9);
  return Event(
    id: id,
    bookUuid: bookUuid,
    recordUuid: recordUuid,
    title: title,
    recordNumber: recordNumber,
    eventTypes: eventTypes ?? [EventType.consultation],
    startTime: baseStart,
    endTime: endTime ?? baseStart.add(const Duration(minutes: 30)),
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1, 8),
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1, 8),
    isRemoved: isRemoved,
    removalReason: removalReason,
    originalEventId: originalEventId,
    newEventId: newEventId,
    isChecked: isChecked,
    hasNote: hasNote,
    version: version,
  );
}
