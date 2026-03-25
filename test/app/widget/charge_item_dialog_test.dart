@Tags(['widget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/l10n/app_localizations.dart';
import 'package:schedule_note_app/models/charge_item.dart';
import 'package:schedule_note_app/widgets/dialogs/charge_item_dialog.dart';

Widget _buildLocalizedApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'TW'),
    home: home,
  );
}

class _ChargeItemDialogHost extends StatefulWidget {
  final ChargeItem existingItem;

  const _ChargeItemDialogHost({required this.existingItem});

  @override
  State<_ChargeItemDialogHost> createState() => _ChargeItemDialogHostState();
}

class _ChargeItemDialogHostState extends State<_ChargeItemDialogHost> {
  ChargeItem? _savedItem;

  Future<void> _openDialog() async {
    final result = await showDialog<ChargeItem>(
      context: context,
      builder: (context) => ChargeItemDialog(existingItem: widget.existingItem),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _savedItem = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(onPressed: _openDialog, child: const Text('Open')),
          if (_savedItem != null)
            Text(
              'saved:${_savedItem!.itemPrice}:${_savedItem!.receivedAmount}:${_savedItem!.paidItems.length}:${_savedItem!.isPaid}',
            ),
        ],
      ),
    );
  }
}

void main() {
  final existingItem = ChargeItem(
    id: 'charge-item-1',
    recordUuid: 'record-1',
    eventId: 'event-1',
    itemName: 'Consultation',
    itemPrice: 1000,
    receivedAmount: 250,
    paidItems: [
      ChargeItemPayment(
        id: 'payment-1',
        amount: 250,
        paidDate: DateTime(2026, 3, 20),
      ),
    ],
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('編輯待收款項'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  }

  group('ChargeItemDialog charge item editing', () {
    testWidgets(
      'CHARGE-ITEM-WIDGET-001: editing keeps existing paid entries instead of resetting them',
      (tester) async {
        await tester.pumpWidget(
          _buildLocalizedApp(_ChargeItemDialogHost(existingItem: existingItem)),
        );

        await openDialog(tester);

        await tester.enterText(find.byType(TextFormField).at(1), '1200');
        await tester.tap(find.text('儲存'));
        await tester.pumpAndSettle();

        expect(find.text('saved:1200:250:1:false'), findsOneWidget);
      },
    );

    testWidgets(
      'CHARGE-ITEM-WIDGET-002: editing rejects cost lower than the existing paid total',
      (tester) async {
        await tester.pumpWidget(
          _buildLocalizedApp(_ChargeItemDialogHost(existingItem: existingItem)),
        );

        await openDialog(tester);

        await tester.enterText(find.byType(TextFormField).at(1), '200');
        await tester.tap(find.text('儲存'));
        await tester.pump();

        expect(find.text('費用不可低於已付總額'), findsOneWidget);
        expect(find.text('編輯待收款項'), findsOneWidget);
        expect(find.textContaining('saved:'), findsNothing);
      },
    );
  });
}
