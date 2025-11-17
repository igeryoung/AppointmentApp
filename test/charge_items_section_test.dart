import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/models/charge_item.dart';
import 'package:schedule_note_app/screens/event_detail/widgets/charge_items_section.dart';

void main() {
  testWidgets('add dialog can be opened and closed without crashing', (tester) async {
    await tester.pumpWidget(const _ChargeItemsSectionHarness());

    // Expand the section to show the overlay.
    await tester.tap(find.text('Charge Items').first);
    await tester.pumpAndSettle();

    // Open the add dialog.
    await tester.tap(find.text('Add Charge Item'));
    await tester.pumpAndSettle();

    // Close the dialog without saving. The overlay should reopen automatically.
    await tester.tap(find.text('Cancel'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Add Charge Item'), findsOneWidget);

    // Close the overlay by tapping outside of it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });
}

class _ChargeItemsSectionHarness extends StatefulWidget {
  const _ChargeItemsSectionHarness();

  @override
  State<_ChargeItemsSectionHarness> createState() => _ChargeItemsSectionHarnessState();
}

class _ChargeItemsSectionHarnessState extends State<_ChargeItemsSectionHarness> {
  List<ChargeItem> _items = const [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: ChargeItemsSection(
            chargeItems: _items,
            onChargeItemsChanged: (updatedItems) {
              setState(() {
                _items = updatedItems;
              });
            },
          ),
        ),
      ),
    );
  }
}
