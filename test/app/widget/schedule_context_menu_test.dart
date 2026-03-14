import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/screens/schedule/schedule_context_menu.dart';

import '../support/fixtures/event_fixtures.dart';

Widget _buildLocalizedApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets(
    'SCHEDULE-WIDGET-001: low-row context menu stays anchored to schedule overlay bounds',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = makeEvent(
        id: 'event-a1',
        bookUuid: 'book-a',
        recordUuid: 'record-a1',
        title: 'Alice',
      );

      await tester.pumpWidget(
        _buildLocalizedApp(
          Align(
            alignment: Alignment.topLeft,
            child: Container(
              key: const Key('menu-boundary'),
              width: 300,
              height: 600,
              color: Colors.transparent,
              child: Stack(
                children: [
                  ScheduleContextMenu(
                    event: event,
                    position: const Offset(140, 500),
                    boundarySize: const Size(300, 600),
                    onClose: () {},
                    onChangeType: () {},
                    onChangeTime: () {},
                    onScheduleNextAppointment: () {},
                    onRemove: () {},
                    onDelete: () {},
                    onCheckedChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final boundary = find.byKey(const Key('menu-boundary'));
      final menuMaterial = find.descendant(
        of: find.byType(ScheduleContextMenu),
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.elevation == 8,
        ),
      );

      final boundaryTopLeft = tester.getTopLeft(boundary);
      final boundaryBottomRight = tester.getBottomRight(boundary);
      final menuTopLeft = tester.getTopLeft(menuMaterial);
      final menuBottomRight = tester.getBottomRight(menuMaterial);

      expect(menuTopLeft.dx - boundaryTopLeft.dx, closeTo(100.0, 0.01));
      expect(boundaryBottomRight.dy - menuBottomRight.dy, closeTo(104.0, 0.01));
    },
  );
}
