@Tags(['unit'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/screens/server_setup_screen.dart';

Widget _buildLocalizedApp(Widget home) {
  return MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh', ''), Locale('zh', 'TW')],
    locale: const Locale('zh', 'TW'),
    home: home,
  );
}

void main() {
  testWidgets(
    'APP-WIDGET-002: setup rejects invalid URL format and stays on URL step',
    (tester) async {
      await tester.pumpWidget(_buildLocalizedApp(const ServerSetupScreen()));

      final urlInput = find.byType(TextFormField);
      expect(urlInput, findsOneWidget);

      await tester.enterText(urlInput, 'not-a-url');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      // Still at URL step (registration step would show lock icon field).
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byType(ServerSetupScreen), findsOneWidget);
    },
  );

  testWidgets(
    'APP-WIDGET-003: setup shows error for unreachable server URL and stays on setup screen',
    (tester) async {
      await tester.pumpWidget(_buildLocalizedApp(const ServerSetupScreen()));

      final urlInput = find.byType(TextFormField);
      expect(urlInput, findsOneWidget);

      await tester.enterText(urlInput, 'https://127.0.0.1:1');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      expect(find.byType(ServerSetupScreen), findsOneWidget);
      expect(find.textContaining('Cannot connect to server'), findsOneWidget);
    },
  );
}
