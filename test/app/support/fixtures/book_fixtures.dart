import 'package:schedule_note_app/models/book.dart';

Book makeBook({
  required String uuid,
  required String name,
  DateTime? createdAt,
  DateTime? archivedAt,
}) {
  return Book(
    uuid: uuid,
    name: name,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    archivedAt: archivedAt,
  );
}
