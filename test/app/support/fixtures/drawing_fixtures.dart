import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';

ScheduleDrawing makeDrawing({
  required String bookUuid,
  DateTime? date,
  int viewMode = ScheduleDrawing.VIEW_MODE_3DAY,
  List<Stroke>? strokes,
  DateTime? createdAt,
  DateTime? updatedAt,
  int version = 1,
}) {
  final targetDate = date ?? DateTime.utc(2026, 1, 1);
  final now = createdAt ?? DateTime.utc(2026, 1, 1, 8);
  return ScheduleDrawing(
    bookUuid: bookUuid,
    date: targetDate,
    viewMode: viewMode,
    strokes: strokes ?? _defaultStrokes(),
    version: version,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}

List<Stroke> _defaultStrokes() {
  return [
    Stroke(
      id: 'draw-stroke-1',
      eventUuid: 'event-draw-1',
      points: const [StrokePoint(1, 1), StrokePoint(2, 3)],
    ),
  ];
}
