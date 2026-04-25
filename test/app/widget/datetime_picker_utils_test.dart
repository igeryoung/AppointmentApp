@Tags(['widget'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/utils/datetime_picker_utils.dart';

Widget _buildHarness({required VoidCallback onPick}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: ElevatedButton(onPressed: onPick, child: const Text('Pick')),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'DATETIME-PICKER-WIDGET-001: fixed-date mode skips calendar and returns selected time on fixed date',
    (tester) async {
      DateTime? picked;

      await tester.pumpWidget(
        _buildHarness(
          onPick: () {
            unawaited(
              DateTimePickerUtils.pickDateTime(
                tester.element(find.text('Pick')),
                initialDateTime: DateTime(2026, 3, 6, 11),
                fixedDate: DateTime(2026, 3, 5, 9),
              ).then((value) => picked = value),
            );
          },
        ),
      );

      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.byType(CalendarDatePicker), findsNothing);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(picked, DateTime(2026, 3, 5, 11));
    },
  );
}
