import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/screens/schedule/schedule_header_title.dart';

void main() {
  group('ScheduleHeaderTitle', () {
    testWidgets(
      'does not request infinite height when used as an AppBar title',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                title: ScheduleHeaderTitle(
                  bookName: 'Clinic Schedule',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [Text('DATE-CONTROL')],
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Clinic Schedule'), findsOneWidget);
        expect(find.text('DATE-CONTROL'), findsOneWidget);
      },
    );

    testWidgets('renders the active book name beside the date controls', (
      tester,
    ) async {
      await tester.pumpWidget(_buildHarness(bookName: 'Clinic Schedule'));

      expect(find.text('Clinic Schedule'), findsOneWidget);
      expect(find.text('DATE-CONTROL'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Clinic Schedule')).dx,
        greaterThan(60),
      );
      final text = tester.widget<Text>(find.text('Clinic Schedule'));
      expect(text.style?.color, Colors.black);
      expect(text.style?.fontSize, 13);
      expect(text.style?.decoration, TextDecoration.underline);
      expect(
        tester.getCenter(find.text('Clinic Schedule')).dy,
        closeTo(tester.getCenter(find.text('DATE-CONTROL')).dy, 2),
      );
    });

    testWidgets(
      'keeps the date controls in the same horizontal position when book name is shown',
      (tester) async {
        await tester.pumpWidget(_buildHarness(bookName: 'Clinic Schedule'));
        final withBookCenter = tester.getCenter(find.text('DATE-CONTROL'));

        await tester.pumpWidget(_buildHarness(bookName: ''));
        final withoutBookCenter = tester.getCenter(find.text('DATE-CONTROL'));

        expect(withBookCenter.dx, closeTo(withoutBookCenter.dx, 0.01));
      },
    );
  });
}

Widget _buildHarness({required String bookName}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 600,
          height: kToolbarHeight,
          child: Material(
            child: ScheduleHeaderTitle(
              bookName: bookName,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [Text('DATE-CONTROL')],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
