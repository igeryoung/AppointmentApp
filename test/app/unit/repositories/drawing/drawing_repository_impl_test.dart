@Tags(['drawing', 'unit'])
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/models/schedule_drawing.dart';
import 'package:schedule_note_app/repositories/drawing_repository_impl.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/db_seed.dart';
import '../../../support/fixtures/drawing_fixtures.dart';
import '../../../support/test_db_path.dart';

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  late DrawingRepositoryImpl repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('drawing_repository');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');
    repository = DrawingRepositoryImpl(() => dbService.database);
    await seedBook(db, bookUuid: 'book-a');
    await seedBook(db, bookUuid: 'book-b');
  });

  tearDown(() async {
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  test(
    'DRAWING-UNIT-001: saveToCache()/getCached() normalize date to day boundary',
    () async {
      // Arrange
      final drawing = makeDrawing(
        bookUuid: 'book-a',
        date: DateTime.utc(2026, 1, 5, 16, 45),
        viewMode: ScheduleDrawing.VIEW_MODE_3DAY,
      );

      // Act
      await repository.saveToCache(drawing);
      final cached = await repository.getCached(
        'book-a',
        DateTime.utc(2026, 1, 5, 1, 0),
      );

      // Assert
      expect(cached, isNotNull);
      expect(cached!.date.year, 2026);
      expect(cached.date.month, 1);
      expect(cached.date.day, 5);
    },
  );

  test(
    'DRAWING-UNIT-002: saveToCache() updates existing row without duplicates',
    () async {
      // Arrange
      final base = makeDrawing(
        bookUuid: 'book-a',
        date: DateTime.utc(2026, 1, 6, 10),
        strokes: [
          const Stroke(id: 's1', eventUuid: 'e1', points: [StrokePoint(1, 1)]),
        ],
      );
      final updated = base.copyWith(
        strokes: [
          const Stroke(
            id: 's1',
            eventUuid: 'e1',
            points: [StrokePoint(1, 1), StrokePoint(2, 2)],
          ),
        ],
      );

      // Act
      await repository.saveToCache(base);
      await repository.saveToCache(updated);
      final allForBook = await repository.getAllCachedForBook('book-a');
      final cached = await repository.getCached(
        'book-a',
        DateTime.utc(2026, 1, 6),
      );

      // Assert
      expect(allForBook.length, 1);
      expect(cached, isNotNull);
      expect(cached!.strokes.single.points.length, 2);
    },
  );

  test(
    'DRAWING-UNIT-003: deleteCache() removes cached drawing for date and view mode',
    () async {
      // Arrange
      await repository.saveToCache(
        makeDrawing(bookUuid: 'book-a', date: DateTime.utc(2026, 1, 7, 7)),
      );

      // Act
      await repository.deleteCache('book-a', DateTime.utc(2026, 1, 7, 22));
      final deleted = await repository.getCached(
        'book-a',
        DateTime.utc(2026, 1, 7),
      );

      // Assert
      expect(deleted, isNull);
    },
  );

  test(
    'DRAWING-UNIT-004: batchGetCachedDrawings() filters by date range and optional view mode',
    () async {
      // Arrange
      await repository.saveToCache(
        makeDrawing(
          bookUuid: 'book-a',
          date: DateTime.utc(2026, 1, 10),
          viewMode: ScheduleDrawing.VIEW_MODE_3DAY,
        ),
      );
      await repository.saveToCache(
        makeDrawing(
          bookUuid: 'book-a',
          date: DateTime.utc(2026, 1, 11),
          viewMode: ScheduleDrawing.VIEW_MODE_2DAY,
        ),
      );
      await repository.saveToCache(
        makeDrawing(
          bookUuid: 'book-a',
          date: DateTime.utc(2026, 1, 12),
          viewMode: ScheduleDrawing.VIEW_MODE_3DAY,
        ),
      );

      // Act
      final allModes = await repository.batchGetCachedDrawings(
        bookUuid: 'book-a',
        startDate: DateTime.utc(2026, 1, 10),
        endDate: DateTime.utc(2026, 1, 12),
      );
      final threeDayOnly = await repository.batchGetCachedDrawings(
        bookUuid: 'book-a',
        startDate: DateTime.utc(2026, 1, 10),
        endDate: DateTime.utc(2026, 1, 12),
        viewMode: ScheduleDrawing.VIEW_MODE_3DAY,
      );

      // Assert
      expect(allModes.length, 3);
      expect(threeDayOnly.length, 2);
      expect(
        threeDayOnly.every((d) => d.viewMode == ScheduleDrawing.VIEW_MODE_3DAY),
        isTrue,
      );
    },
  );

  test(
    'DRAWING-UNIT-005: batchSaveCachedDrawings() inserts and updates drawings',
    () async {
      // Arrange
      final initial = makeDrawing(
        bookUuid: 'book-a',
        date: DateTime.utc(2026, 1, 20),
        strokes: [
          const Stroke(id: 'x1', eventUuid: 'e1', points: [StrokePoint(1, 1)]),
        ],
      );
      await repository.batchSaveCachedDrawings([initial]);
      final updated = initial.copyWith(
        strokes: [
          const Stroke(
            id: 'x1',
            eventUuid: 'e1',
            points: [StrokePoint(1, 1), StrokePoint(9, 9)],
          ),
        ],
      );

      // Act
      await repository.batchSaveCachedDrawings([updated]);
      final cached = await repository.getCached(
        'book-a',
        DateTime.utc(2026, 1, 20),
      );

      // Assert
      expect(cached, isNotNull);
      expect(cached!.strokes.single.points.length, 2);
    },
  );
}
