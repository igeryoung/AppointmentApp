import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

Future<String> setUniqueDatabasePath(String suiteName) async {
  final rootPath = p.join(
    Directory.systemTemp.path,
    'schedule_note_tests',
    suiteName,
  );
  final rootDir = Directory(rootPath);

  if (rootDir.existsSync()) {
    await rootDir.delete(recursive: true);
  }
  await rootDir.create(recursive: true);
  await databaseFactory.setDatabasesPath(rootPath);

  return rootPath;
}
