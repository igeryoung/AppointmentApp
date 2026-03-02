@Tags(['widget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/repositories/event_repository.dart';
import 'package:schedule_note_app/services/database/mixins/event_operations_mixin.dart';
import 'package:schedule_note_app/widgets/schedule/query_appointments_dialog.dart';

Widget _buildLocalizedApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'TW'),
    home: home,
  );
}

class _FakeEventRepository implements IEventRepository {
  _FakeEventRepository({
    required this.nameSuggestionsByPrefix,
    required this.recordSuggestionsByQuery,
  });

  final Map<String, List<String>> nameSuggestionsByPrefix;
  final Map<String, List<NameRecordPair>> recordSuggestionsByQuery;
  final List<String> nameSuggestionRequests = [];
  final List<String> recordSuggestionRequests = [];

  @override
  Future<List<String>> fetchNameSuggestions(
    String bookUuid,
    String prefix,
  ) async {
    nameSuggestionRequests.add(prefix);
    return nameSuggestionsByPrefix[prefix] ?? const [];
  }

  @override
  Future<List<NameRecordPair>> fetchRecordNumberSuggestions(
    String bookUuid,
    String prefix, {
    String? namePrefix,
  }) async {
    final key = '$prefix|${namePrefix ?? ''}';
    recordSuggestionRequests.add(key);
    return recordSuggestionsByQuery[key] ?? const [];
  }

  @override
  Future<List<Event>> searchByNameAndRecordNumber(
    String bookUuid,
    String name,
    String recordNumber,
  ) async {
    return [];
  }

  @override
  Future<void> applyServerChange(Map<String, dynamic> changeData) {
    throw UnimplementedError();
  }

  @override
  Future<ChangeEventTimeResult> changeEventTime(
    Event originalEvent,
    DateTime newStartTime,
    DateTime? newEndTime,
    String reason,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Event> create(Event event) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> getAllNames(String bookUuid) {
    throw UnimplementedError();
  }

  @override
  Future<List<NameRecordPair>> getAllNameRecordPairs(String bookUuid) {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> getAllRecordNumbers(String bookUuid) {
    throw UnimplementedError();
  }

  @override
  Future<List<Event>> getAll() {
    throw UnimplementedError();
  }

  @override
  Future<List<Event>> getByBookId(String bookUuid) {
    throw UnimplementedError();
  }

  @override
  Future<List<Event>> getByDateRange(
    String bookUuid,
    DateTime startDate,
    DateTime endDate,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Event?> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Event?> getByServerId(String serverId) {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> getRecordNumbersByName(String bookUuid, String name) {
    throw UnimplementedError();
  }

  @override
  Future<Event> removeEvent(String eventId, String reason) {
    throw UnimplementedError();
  }

  @override
  Future<Event> update(Event event) {
    throw UnimplementedError();
  }
}

class _QueryAppointmentsDialogHost extends StatelessWidget {
  const _QueryAppointmentsDialogHost({required this.repository});

  final IEventRepository repository;

  Future<void> _openDialog(BuildContext context) {
    return showQueryAppointmentsDialog(context, 'book-1', repository);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => _openDialog(context),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  }

  group('Query appointments dialog autocomplete pipeline', () {
    testWidgets(
      'QUERY-APPOINTMENTS-WIDGET-001: name field fetches on first character and filters locally afterwards',
      (tester) async {
        final repository = _FakeEventRepository(
          nameSuggestionsByPrefix: {
            'a': ['Amy', 'Alex', 'Anna'],
          },
          recordSuggestionsByQuery: const {},
        );

        await tester.pumpWidget(
          _buildLocalizedApp(
            _QueryAppointmentsDialogHost(repository: repository),
          ),
        );

        await openDialog(tester);
        await tester.tap(find.byType(TextField).first);
        await tester.pump();

        expect(find.text('Amy'), findsNothing);

        await tester.enterText(find.byType(TextField).first, 'A');
        await tester.pumpAndSettle();

        expect(repository.nameSuggestionRequests, ['a']);
        expect(find.text('Amy'), findsOneWidget);
        expect(find.text('Alex'), findsOneWidget);
        expect(find.text('Anna'), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, 'Al');
        await tester.pumpAndSettle();

        expect(repository.nameSuggestionRequests, ['a']);
        expect(find.text('Alex'), findsOneWidget);
        expect(find.text('Amy'), findsNothing);
        expect(find.text('Anna'), findsNothing);
      },
    );

    testWidgets(
      'QUERY-APPOINTMENTS-WIDGET-002: clearing name resets cache and a new first character fetches again',
      (tester) async {
        final repository = _FakeEventRepository(
          nameSuggestionsByPrefix: {
            'a': ['Amy'],
            'b': ['Ben'],
          },
          recordSuggestionsByQuery: const {},
        );

        await tester.pumpWidget(
          _buildLocalizedApp(
            _QueryAppointmentsDialogHost(repository: repository),
          ),
        );

        await openDialog(tester);

        await tester.enterText(find.byType(TextField).first, 'A');
        await tester.pumpAndSettle();
        expect(repository.nameSuggestionRequests, ['a']);
        expect(find.text('Amy'), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, '');
        await tester.pumpAndSettle();
        expect(find.text('Amy'), findsNothing);

        await tester.enterText(find.byType(TextField).first, 'B');
        await tester.pumpAndSettle();

        expect(repository.nameSuggestionRequests, ['a', 'b']);
        expect(find.text('Ben'), findsOneWidget);
      },
    );

    testWidgets(
      'QUERY-APPOINTMENTS-WIDGET-003: record number fetch uses current name prefix and later input stays local',
      (tester) async {
        final repository = _FakeEventRepository(
          nameSuggestionsByPrefix: {
            'a': ['Alice', 'Alfred'],
          },
          recordSuggestionsByQuery: {
            '1|al': const [
              NameRecordPair(name: 'Alice', recordNumber: '100'),
              NameRecordPair(name: 'Alfred', recordNumber: '145'),
            ],
          },
        );

        await tester.pumpWidget(
          _buildLocalizedApp(
            _QueryAppointmentsDialogHost(repository: repository),
          ),
        );

        await openDialog(tester);

        await tester.enterText(find.byType(TextField).first, 'Al');
        await tester.pumpAndSettle();
        expect(repository.nameSuggestionRequests, ['a']);

        tester.binding.focusManager.primaryFocus?.unfocus();
        await tester.pump();

        await tester.enterText(find.byType(TextField).at(1), '1');
        await tester.pumpAndSettle();

        expect(repository.recordSuggestionRequests, ['1|al']);
        expect(find.text('Alice - 100'), findsOneWidget);
        expect(find.text('Alfred - 145'), findsOneWidget);

        await tester.enterText(find.byType(TextField).at(1), '10');
        await tester.pumpAndSettle();

        expect(repository.recordSuggestionRequests, ['1|al']);
        expect(find.text('Alice - 100'), findsOneWidget);
        expect(find.text('Alfred - 145'), findsNothing);
      },
    );
  });
}
