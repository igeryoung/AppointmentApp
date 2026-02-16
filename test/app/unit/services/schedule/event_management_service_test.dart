@Tags(['schedule', 'unit'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/screens/schedule/services/event_management_service.dart';
import 'package:schedule_note_app/screens/schedule/services/schedule_date_service.dart';
import 'package:schedule_note_app/services/database/prd_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/db_seed.dart';
import '../../../support/fixtures/event_fixtures.dart';
import '../../../support/test_db_path.dart';

void main() {
  late PRDDatabaseService dbService;
  late Database db;
  late Event seededEvent;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await setUniqueDatabasePath('event_management_service');
  });

  setUp(() async {
    PRDDatabaseService.resetInstance();
    dbService = PRDDatabaseService();
    db = await dbService.database;
    await dbService.clearAllData();
    await db.delete('device_info');

    await seedBook(db, bookUuid: 'book-a');
    await seedRecord(
      db,
      recordUuid: 'record-a1',
      name: 'Alice',
      recordNumber: '001',
    );

    seededEvent = makeEvent(
      id: 'event-a1',
      bookUuid: 'book-a',
      recordUuid: 'record-a1',
      title: 'Alice',
      recordNumber: '001',
      isChecked: false,
    );
    await seedEvent(db, event: seededEvent);
  });

  tearDown(() async {
    await dbService.close();
    PRDDatabaseService.resetInstance();
  });

  test(
    'SCHEDULE-UNIT-001: toggleEventChecked() updates menu-selected event state and persists checked status without note sync',
    () async {
      final menuEvents = <Event?>[];
      final syncedEvents = <Event>[];
      final updatedEvents = <Event>[];
      final snackbarMessages = <String>[];

      final dateService = ScheduleDateService(
        initialDate: DateTime.utc(2026, 1, 1),
        onDateChanged: (_, __) {},
        onSaveDrawing: () async {},
        onLoadDrawing: () async {},
        onUpdateCubit: (_) {},
        onShowNotification: (_) {},
        isMounted: () => true,
        isInDrawingMode: () => false,
        onCancelPendingSave: () {},
      );

      final service = EventManagementService(
        dbService: dbService,
        bookUuid: 'book-a',
        onMenuStateChanged: (selectedEvent, _) => menuEvents.add(selectedEvent),
        onNavigate: (_) async => true,
        onReloadEvents: () {},
        onUpdateEvent: (event) => updatedEvents.add(event),
        onDeleteEvent: (_, __) async => null,
        onHardDeleteEvent: (_) async => null,
        onChangeEventTime: (_, __, ___, ____) async {},
        onShowSnackbar: (message, {backgroundColor, durationSeconds}) {
          snackbarMessages.add(message);
        },
        isMounted: () => true,
        getLocalizedString: (_) => 'error',
        onSyncEvent: (event) async => syncedEvents.add(event),
        onSetPendingNextAppointment: (_) {},
        dateService: dateService,
      );

      service.showEventContextMenu(seededEvent, const Offset(40, 60));
      expect(service.selectedEventForMenu?.isChecked, isFalse);

      await service.toggleEventChecked(seededEvent, true);

      final persisted = await dbService.getEventById(seededEvent.id!);
      expect(persisted, isNotNull);
      expect(persisted!.isChecked, isTrue);

      expect(service.selectedEventForMenu, isNotNull);
      expect(service.selectedEventForMenu!.id, seededEvent.id);
      expect(service.selectedEventForMenu!.isChecked, isTrue);

      expect(menuEvents.length, greaterThanOrEqualTo(2));
      expect(menuEvents.last, isNotNull);
      expect(menuEvents.last!.isChecked, isTrue);

      expect(updatedEvents.length, 1);
      expect(updatedEvents.single.isChecked, isTrue);

      expect(syncedEvents, isEmpty);

      expect(snackbarMessages, isEmpty);
    },
  );
}
