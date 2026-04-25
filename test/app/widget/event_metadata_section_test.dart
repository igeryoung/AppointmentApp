@Tags(['widget'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/models/event.dart';
import 'package:schedule_note_app/models/event_type.dart';
import 'package:schedule_note_app/screens/event_detail/event_detail_controller.dart';
import 'package:schedule_note_app/screens/event_detail/widgets/event_metadata_section.dart';
import 'package:schedule_note_app/utils/datetime_picker_utils.dart';

Widget _buildLocalizedApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'TW'),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: home),
    ),
  );
}

Event _buildEvent() {
  return Event(
    id: 'event-1',
    bookUuid: 'book-1',
    recordUuid: 'record-1',
    title: 'Kai',
    eventTypes: const [EventType.other],
    startTime: DateTime.utc(2026, 3, 5, 9),
    endTime: DateTime.utc(2026, 3, 5, 10),
    createdAt: DateTime.utc(2026, 3, 5, 8),
    updatedAt: DateTime.utc(2026, 3, 5, 8),
  );
}

Widget _buildSection({
  required TextEditingController nameController,
  required TextEditingController phoneController,
  required String recordNumber,
  required List<String> availableRecordNumbers,
  required List<RecordNumberOption> allRecordNumberOptions,
  bool isNameSuggestionsLoading = false,
  bool isRecordNumberSuggestionsLoading = false,
  VoidCallback? onEndTimeTap,
  ValueChanged<String>? onRecordNumberSelected,
  ValueChanged<String>? onNameSelected,
}) {
  return EventMetadataSection(
    event: _buildEvent(),
    nameController: nameController,
    phoneController: phoneController,
    recordNumber: recordNumber,
    availableRecordNumbers: availableRecordNumbers,
    isRecordNumberFieldEnabled: true,
    selectedEventTypes: const [EventType.other],
    startTime: DateTime.utc(2026, 3, 5, 9),
    endTime: DateTime.utc(2026, 3, 5, 10),
    onStartTimeTap: () {},
    onEndTimeTap: onEndTimeTap ?? () {},
    onClearEndTime: () {},
    onEventTypesChanged: (_) {},
    onRecordNumberChanged: (_) {},
    allNames: const ['Kai'],
    allRecordNumberOptions: allRecordNumberOptions,
    isNameSuggestionsLoading: isNameSuggestionsLoading,
    isRecordNumberSuggestionsLoading: isRecordNumberSuggestionsLoading,
    onRecordNumberSelected: onRecordNumberSelected,
    onNameSelected: onNameSelected,
  );
}

void main() {
  group('Event metadata autocomplete regression', () {
    testWidgets(
      'EVENT-METADATA-WIDGET-001: record dropdown still shows server suggestions when local availability is stale',
      (tester) async {
        final nameController = TextEditingController(text: 'Kai');
        final phoneController = TextEditingController();
        addTearDown(() {
          nameController.dispose();
          phoneController.dispose();
        });

        await tester.pumpWidget(
          _buildLocalizedApp(
            _buildSection(
              nameController: nameController,
              phoneController: phoneController,
              recordNumber: '',
              // Stale local list: does not intersect server suggestion list.
              availableRecordNumbers: const ['LEGACY-999'],
              allRecordNumberOptions: [
                RecordNumberOption(recordNumber: 'K001', name: 'Kai'),
              ],
            ),
          ),
        );

        final recordField = find.byType(TextField).at(2);
        await tester.showKeyboard(recordField);
        await tester.pumpAndSettle();

        expect(find.text('K001 - Kai'), findsOneWidget);
      },
    );

    testWidgets(
      'EVENT-METADATA-WIDGET-002: record-number field shows loading suffix while suggestions are fetching',
      (tester) async {
        final nameController = TextEditingController(text: 'Kai');
        final phoneController = TextEditingController();
        addTearDown(() {
          nameController.dispose();
          phoneController.dispose();
        });

        await tester.pumpWidget(
          _buildLocalizedApp(
            _buildSection(
              nameController: nameController,
              phoneController: phoneController,
              recordNumber: '',
              availableRecordNumbers: const [],
              allRecordNumberOptions: const [],
              isRecordNumberSuggestionsLoading: true,
            ),
          ),
        );

        final recordField = tester.widget<TextField>(
          find.byType(TextField).at(2),
        );
        expect(recordField.decoration?.suffixIcon, isNotNull);
      },
    );

    testWidgets(
      'EVENT-METADATA-WIDGET-003: name field shows loading suffix while suggestions are fetching',
      (tester) async {
        final nameController = TextEditingController(text: 'Kai');
        final phoneController = TextEditingController();
        addTearDown(() {
          nameController.dispose();
          phoneController.dispose();
        });

        await tester.pumpWidget(
          _buildLocalizedApp(
            _buildSection(
              nameController: nameController,
              phoneController: phoneController,
              recordNumber: '',
              availableRecordNumbers: const [],
              allRecordNumberOptions: const [],
              isNameSuggestionsLoading: true,
            ),
          ),
        );

        final nameField = tester.widget<TextField>(
          find.byType(TextField).first,
        );
        expect(nameField.decoration?.suffixIcon, isNotNull);
      },
    );

    testWidgets(
      'EVENT-METADATA-WIDGET-004: clicking record suggestion fills the field on desktop-style tap flow',
      (tester) async {
        final nameController = TextEditingController(text: 'Kai');
        final phoneController = TextEditingController();
        String? selectedRecordNumber;
        addTearDown(() {
          nameController.dispose();
          phoneController.dispose();
        });

        await tester.pumpWidget(
          _buildLocalizedApp(
            _buildSection(
              nameController: nameController,
              phoneController: phoneController,
              recordNumber: '',
              availableRecordNumbers: const ['K001'],
              allRecordNumberOptions: [
                RecordNumberOption(recordNumber: 'K001', name: 'Kai'),
              ],
              onRecordNumberSelected: (value) {
                selectedRecordNumber = value;
              },
            ),
          ),
        );

        final recordFieldFinder = find.byType(TextField).at(2);
        await tester.tap(recordFieldFinder);
        await tester.pumpAndSettle();

        final optionFinder = find.text('K001 - Kai');
        expect(optionFinder, findsOneWidget);

        await tester.tap(optionFinder);
        await tester.pumpAndSettle();

        final recordField = tester.widget<TextField>(recordFieldFinder);
        expect(recordField.controller?.text, 'K001');
        expect(selectedRecordNumber, 'K001');
      },
    );
  });

  group('Event metadata end time picker regression', () {
    testWidgets(
      'EVENT-METADATA-WIDGET-005: tapping end time can open a time-only picker locked to the start day',
      (tester) async {
        final nameController = TextEditingController(text: 'Kai');
        final phoneController = TextEditingController();
        DateTime? picked;
        addTearDown(() {
          nameController.dispose();
          phoneController.dispose();
        });

        final startTime = DateTime(2026, 3, 5, 9);
        await tester.pumpWidget(
          _buildLocalizedApp(
            _buildSection(
              nameController: nameController,
              phoneController: phoneController,
              recordNumber: '',
              availableRecordNumbers: const [],
              allRecordNumberOptions: const [],
              onEndTimeTap: () {
                unawaited(
                  DateTimePickerUtils.pickDateTime(
                    tester.element(find.textContaining('10:00').last),
                    initialDateTime: DateTime(2026, 3, 5, 10),
                    fixedDate: startTime,
                    validateBusinessHours: true,
                    isEndTime: true,
                    referenceStartTime: startTime,
                  ).then((value) => picked = value),
                );
              },
            ),
          ),
        );

        await tester.tap(find.textContaining('10:00').last);
        await tester.pumpAndSettle();

        expect(find.byType(TimePickerDialog), findsOneWidget);
        expect(find.byType(CalendarDatePicker), findsNothing);

        await tester.tap(find.text('確定'));
        await tester.pumpAndSettle();

        expect(picked, DateTime(2026, 3, 5, 10));
      },
    );
  });
}
