@Tags(['unit'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/models/note.dart';
import 'package:schedule_note_app/screens/event_detail/widgets/handwriting_section.dart';
import 'package:schedule_note_app/widgets/handwriting_canvas.dart';

Widget _buildLocalizedApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'TW'),
    home: Scaffold(
      body: Center(child: SizedBox(width: 900, height: 480, child: home)),
    ),
  );
}

const _pageOneStroke = Stroke(
  eventUuid: 'event-a',
  points: [StrokePoint(10, 10), StrokePoint(15, 15)],
);

const _pageTwoStroke = Stroke(
  eventUuid: 'event-b',
  points: [StrokePoint(20, 20), StrokePoint(25, 25)],
);

void main() {
  group('HandwritingSection read-only mode', () {
    Future<void> pumpSection(WidgetTester tester) async {
      final canvasKey = GlobalKey<HandwritingCanvasState>();

      await tester.pumpWidget(
        _buildLocalizedApp(
          HandwritingSection(
            canvasKey: canvasKey,
            initialPages: const [
              [_pageOneStroke],
              [_pageTwoStroke],
            ],
            onPagesChanged: (_) {},
            currentEventUuid: 'event-a',
            isReadOnlyMode: true,
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    testWidgets(
      'EVENT-NOTE-WIDGET-001: keeps page navigation active in read-only mode',
      (tester) async {
        await pumpSection(tester);

        expect(find.text('1/2頁'), findsOneWidget);

        await tester.tap(find.byTooltip('下一頁'));
        await tester.pumpAndSettle();

        expect(find.text('2/2頁'), findsOneWidget);
      },
    );

    testWidgets(
      'EVENT-NOTE-WIDGET-002: keeps note focus toggle active in read-only mode',
      (tester) async {
        await pumpSection(tester);

        expect(find.text('全部'), findsOneWidget);
        expect(find.text('本次'), findsNothing);

        await tester.tap(find.text('全部'));
        await tester.pumpAndSettle();

        expect(find.text('本次'), findsOneWidget);
      },
    );
  });
}
