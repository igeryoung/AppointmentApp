import 'package:schedule_note_app/models/note.dart';

Note makeNote({
  required String recordUuid,
  List<List<Stroke>>? pages,
  DateTime? createdAt,
  DateTime? updatedAt,
  int version = 1,
}) {
  return Note(
    recordUuid: recordUuid,
    pages: pages ?? [makeStrokePage()],
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1, 9),
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1, 9),
    version: version,
  );
}

List<Stroke> makeStrokePage() {
  return [
    Stroke(
      id: 'stroke-1',
      eventUuid: 'event-1',
      points: const [StrokePoint(10, 10), StrokePoint(20, 20)],
      strokeWidth: 2.0,
      color: 0xFF000000,
    ),
  ];
}
