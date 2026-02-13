import 'package:schedule_note_app/models/event.dart';
import 'package:sqflite/sqflite.dart';

Future<void> seedBook(
  Database db, {
  required String bookUuid,
  String name = 'Test Book',
  int? createdAtSeconds,
}) async {
  await db.insert('books', {
    'book_uuid': bookUuid,
    'name': name,
    'created_at':
        createdAtSeconds ??
        DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
    'archived_at': null,
  });
}

Future<void> seedRecord(
  Database db, {
  required String recordUuid,
  String name = 'Test Person',
  String recordNumber = 'R-001',
  int? createdAtSeconds,
}) async {
  final now =
      createdAtSeconds ??
      DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
  await db.insert('records', {
    'record_uuid': recordUuid,
    'record_number': recordNumber,
    'name': name,
    'phone': null,
    'created_at': now,
    'updated_at': now,
    'version': 1,
    'is_dirty': 0,
    'is_deleted': 0,
  });
}

Future<void> seedEvent(Database db, {required Event event}) async {
  await db.insert('events', event.toMap());
}
